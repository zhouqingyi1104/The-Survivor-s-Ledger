"""Smooth anatomical union for the yard dog's coat, sampled once when authoring the GLB."""
import numpy as np
from PIL import Image, ImageDraw
from folk_mesh import Surface,linear

def coat_mesh():
    step=.025
    axes=[np.arange(a,b,step) for a,b in [(-.24,.25),(-.045,.87),(-.56,.555)]]
    grid=np.stack(np.meshgrid(*axes,indexing='ij'),axis=-1)
    field=np.full(grid.shape[:-1],10.)
    def join(d,w):
        nonlocal field
        h=np.maximum(w-np.abs(field-d),0)/w
        field=np.minimum(field,d)-h*h*w*.25
    def egg(center,radii,w=.026):
        p=grid-center; r=np.array(radii)
        k=np.linalg.norm(p/r,axis=-1)
        d=(k-1)*np.linalg.norm(p/r,axis=-1)/np.maximum(np.linalg.norm(p/(r*r),axis=-1),1e-8)
        d=np.where(k<.002,-min(radii),d)
        join(d,w)
    def limb(points,radii,w):
        for a,b,r0,r1 in zip(points,points[1:],radii,radii[1:]):
            a,b=np.asarray(a),np.asarray(b);v=b-a
            t=np.clip(np.sum((grid-a)*v,axis=-1)/np.dot(v,v),0,1)
            dist=np.linalg.norm(grid-a-t[:,:,:,None]*v,axis=-1)-(r0+(r1-r0)*t)
            join(dist,w)
    egg((0,.410,.092),(.149,.160,.218))
    egg((0,.404,-.159),(.132,.120,.215))
    egg((0,.410,-.241),(.145,.141,.118))
    limb([(0,.425,.147),(0,.492,.224),(.008,.574,.277),(.01,.616,.286)],[.119,.104,.087,.070],.054)
    egg((.01,.640,.295),(.098,.098,.100),.031)
    egg((.01,.627,.359),(.082,.070,.093),.030)
    egg((.01,.603,.428),(.054,.037,.085),.023)
    egg((.01,.580,.402),(.049,.026,.078),.017)
    for sign in [-1,1]:
        x=sign*.095; lead=.034*sign
        limb([(x,.400,.164+lead),(x,.314,.159+lead),(x,.236,.131+lead),(x,.149,.151+lead),(x,.064,.174+lead)],
             [.071,.053,.039,.028,.023],.031)
        egg((x,.384,-.231+lead),(.067,.103,.089),.032)
        limb([(x,.38,-.237+lead),(x,.300,-.180+lead),(x,.256,-.159+lead),(x,.137,-.254+lead),(x,.066,-.224+lead)],
             [.067,.055,.042,.024,.021],.031)
        for z in [.175+lead,-.224+lead]:
            egg((x,.040,z+.018),(.039,.032,.057),.019)
            for toe in [-1,0,1]:
                egg((x+.020*toe,.029,z+.045-.006*abs(toe)),(.019,.020,.026),.007)
    limb([(0,.441,-.290),(.014,.469,-.357),(.034,.519,-.427),(.046,.581,-.460),(.057,.627,-.450),
          (.060,.660,-.432),(.057,.680,-.394),(.044,.667,-.344)],
         [.052,.054,.049,.043,.037,.033,.025,.009],.022)
    # Six tetrahedra per grid cell, matched diagonals on shared faces. Vertices on a shared
    # edge are reused so normals follow muscle volume rather than the voxel resolution.
    corners=np.array([[0,0,0],[1,0,0],[1,1,0],[0,1,0],[0,0,1],[1,0,1],[1,1,1],[0,1,1]])
    tets=[(0,1,2,6),(0,2,3,6),(0,3,7,6),(0,7,4,6),(0,4,5,6),(0,5,1,6)]
    offsets=[field[a:a+len(axes[0])-1,b:b+len(axes[1])-1,c:c+len(axes[2])-1] for a,b,c in corners]
    cells=np.argwhere((np.min(offsets,axis=0)<0)&(np.max(offsets,axis=0)>0))
    surface=Surface();edges={}; tan=linear('b68a5f');cream=linear('dfcbac');sable=linear('574233')
    def color(p):
        x,y,z=p
        upper=np.clip((y-.385)*5.4,0,1)*np.clip((.327-z)*5.8,0,1)
        below=np.clip((.388-y)*4.9,0,1)
        cheeks=np.exp(-((y-.612)/.101)**2)*np.clip((z-.31)*5.8,0,.8)
        chest=np.exp(-((z-.259)/.08)**2)*np.clip((.57-y)*4.4,0,.78)
        belly=max(.79*below,.91*cheeks,chest)
        return (tan*(1-upper)+sable*upper)*(1-belly)+cream*belly
    for cell in cells:
        ijk=corners+cell
        coord=grid[tuple(ijk.T)]
        val=field[tuple(ijk.T)]
        flat=np.ravel_multi_index(ijk.T,field.shape)
        def at(a,b):
            key=tuple(sorted((flat[a],flat[b])))
            if key not in edges:
                p=coord[a]+(coord[b]-coord[a])*(val[a]/(val[a]-val[b]))
                edges[key]=surface.vertex(p,[p[2]*2.7,p[1]*2.7+.2*p[0]],color(p))
            return edges[key]
        for tet in tets:
            inside=[c for c in tet if val[c]<0];outside=[c for c in tet if val[c]>=0]
            if not (inside and outside):continue
            n=np.mean(coord[outside],axis=0)-np.mean(coord[inside],axis=0)
            if len(inside)==2:
                i,j=inside;k,l=outside
                a,b,c,d=at(i,k),at(i,l),at(j,l),at(j,k)
                surface.face(a,b,c,n);surface.face(a,c,d,n)
            else:
                if len(outside)==1:inside,outside=outside,inside
                a,b,c=[at(inside[0],q) for q in outside]
                surface.face(a,b,c,n)
    return surface

def coat_texture(out):
    size=256; rng=np.random.default_rng(981);im=Image.new('L',(size,size),231);draw=ImageDraw.Draw(im)
    for i in range(6300):
        x,y=rng.integers(-8,size,2);n=rng.uniform(3,11);c=int(rng.integers(185,255))
        for dx in [0,size] if x<1 else [0]:
            for dy in [0,-size] if y>size-12 else [0]:
                draw.line((x+dx,y+dy,x+dx+n*.25,y+dy+n),fill=c,width=1)
    im.save(out/'guard_hair.png')
