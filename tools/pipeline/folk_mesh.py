"""Small glTF writer for authored rings, panels and skinned costume pieces (Y up, +Z front)."""
import json
import math
import struct
from pathlib import Path

import numpy as np


def linear(rgb):
    x = np.array(list(bytes.fromhex(rgb.lstrip("#")))) / 255.0
    return np.where(x < .04045, x / 12.92, ((x + .055) / 1.055) ** 2.4)


def unit(v):
    return v / max(1e-9, np.linalg.norm(v))


class Surface:
    def __init__(self):
        self.pts, self.uv, self.tint, self.faces = [], [], [], []

    def vertex(self, p, uv, color):
        self.pts.append(np.array(p))
        self.uv.append(uv)
        self.tint.append(color)
        return len(self.pts) - 1

    def face(self, a, b, c, outside):
        cross = np.cross(self.pts[b] - self.pts[a], self.pts[c] - self.pts[a])
        if np.dot(cross, outside) < 0:
            b, c = c, b
        self.faces.append((a, b, c))

    def rings(self, sections, colors, sides=28, warp=None):
        """Sections are center and two oriented radius vectors. Warp shapes individual folds."""
        prev = []
        for k, (c, u, v) in enumerate(sections):
            c,u,v = map(np.asarray, (c,u,v))
            row = []
            for i in range(sides+1):
                theta = 2 * math.pi * (i % sides) / sides
                d = u * math.cos(theta) + v * math.sin(theta)
                if warp:
                    d *= warp(theta,k)
                shade = colors(theta,k) if callable(colors) else colors
                row.append(self.vertex(c+d, [i/sides, k/(len(sections)-1)], shade))
                if prev and i:
                    hint = d + self.pts[row[-2]] - c
                    self.face(prev[i-1],prev[i],row[i],hint)
                    self.face(prev[i-1],row[i],row[i-1],hint)
            prev = row

    def tube(self, points, radii, color, sides=9, flat=1.0):
        points = np.asarray(points,float)
        sections = []
        for i,(p,r) in enumerate(zip(points,radii)):
            axis = unit(points[min(i+1,len(points)-1)] - points[max(i-1,0)])
            ref = np.array([1.,0.,0.]) if abs(axis[0]) < .85 else np.array([0.,0.,1.])
            u = unit(ref - axis * np.dot(axis,ref))
            sections.append((p,u*r,unit(np.cross(axis,u))*r*flat))
        self.rings(sections,color,sides)

    def ball(self, center, scale, color, sides=16, rows=10):
        sec=[]
        for i in range(rows+1):
            a = np.pi * i/rows
            r=max(.001,np.sin(a))
            sec.append((np.array(center)+[0,-np.cos(a)*scale[1],0], [scale[0]*r,0,0],[0,0,scale[2]*r]))
        self.rings(sec,color,sides)

    def normals(self):
        pts = np.asarray(self.pts)
        tri = np.asarray(self.faces)
        n = np.cross(pts[tri[:,1]]-pts[tri[:,0]],pts[tri[:,2]]-pts[tri[:,0]])
        normals=np.zeros_like(pts,dtype=float)
        for col in tri.T:
            np.add.at(normals,col,n)
        # UV seams and ring endpoints have duplicate vertices at the same spatial position.
        _,inverse = np.unique(np.round(pts,6),axis=0,return_inverse=True)
        smooth=np.zeros((inverse.max()+1,3))
        np.add.at(smooth,inverse,normals)
        normals=smooth[inverse]
        return normals/np.maximum(np.linalg.norm(normals,axis=1)[:,None],1e-12)


class Writer:
    def __init__(self):
        self.doc={"asset":{"version":"2.0","generator":"JieYuLu model workshop"},
                  "scene":0,"scenes":[{"nodes":[]}],"nodes":[],"meshes":[],"materials":[],
                  "buffers":[{"byteLength":0}],"bufferViews":[],"accessors":[]}
        self.binary=bytearray()

    def material(self,name,rough=.85,metal=0,emission=None):
        m={"name":name,"pbrMetallicRoughness":{"baseColorFactor":[1,1,1,1],"roughnessFactor":rough,"metallicFactor":metal}}
        if emission: m["emissiveFactor"]=emission
        self.doc["materials"].append(m)
        return len(self.doc["materials"])-1

    def acc(self,data,dtype,kind,limits=False):
        a=np.asarray(data,dtype=dtype)
        padding=-len(self.binary)%4
        self.binary.extend(b'\0'*padding)
        self.doc["bufferViews"].append({"buffer":0,"byteOffset":len(self.binary),"byteLength":a.nbytes})
        self.binary.extend(a.tobytes())
        acc={"bufferView":len(self.doc['bufferViews'])-1,"componentType":{"<f4":5126,"<u2":5123,"<u4":5125}[dtype],
             "count":len(a),"type":kind}
        if limits: acc.update(min=a.min(axis=0).tolist(),max=a.max(axis=0).tolist())
        self.doc["accessors"].append(acc)
        return len(self.doc["accessors"])-1

    def add(self,name,parts,skin=None):
        primitives=[]
        for index,s in parts:
            if not s.faces: continue
            attrs={'POSITION': self.acc(s.pts,'<f4','VEC3',True),'NORMAL':self.acc(s.normals(),'<f4','VEC3'),
                   'TEXCOORD_0':self.acc(s.uv,'<f4','VEC2'),'COLOR_0':self.acc(s.tint,'<f4','VEC3')}
            if skin:
                joints,weights=skin(s.pts)
                attrs['JOINTS_0']=self.acc(joints,'<u2','VEC4')
                attrs['WEIGHTS_0']=self.acc(weights,'<f4','VEC4')
            primitives.append({"material":index,"attributes":attrs,"indices":self.acc(np.ravel(s.faces),'<u2','SCALAR')})
        self.doc['nodes'].append({'name':name,'mesh':len(self.doc['meshes'])})
        if skin:self.doc['nodes'][-1]['skin']=0
        self.doc['meshes'].append({'name':name,'primitives':primitives})
        self.doc['scenes'][0]['nodes'].append(len(self.doc['nodes'])-1)

    def save(self,path):
        self.doc["buffers"][0]["byteLength"]=len(self.binary)
        j=json.dumps(self.doc,separators=(',',':')).encode()
        j+=b' '*(-len(j)%4)
        b=bytes(self.binary)+b'\0'*(-len(self.binary)%4)
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_bytes(struct.pack('<4sIIII',b'glTF',2,28+len(j)+len(b),len(j),0x4e4f534a)+j+
                         struct.pack('<II',len(b),0x004e4942)+b)

def read_glb(path):
    raw=path.read_bytes()
    n=struct.unpack_from('<I',raw,12)[0]
    return json.loads(raw[20:20+n]),raw[28+n:]

def unpack(doc,buf,aid):
    ac=doc['accessors'][aid]
    v=doc['bufferViews'][ac['bufferView']]
    dtype=np.dtype({5126:'<f4',5123:'<u2',5121:'u1',5125:'<u4'}[ac['componentType']])
    dim={'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16,'SCALAR':1}[ac['type']]
    return np.ndarray((ac['count'],dim),dtype=dtype,buffer=buf,offset=v.get('byteOffset',0)+ac.get('byteOffset',0),strides=(v.get('byteStride',dim*dtype.itemsize),dtype.itemsize)).copy()
