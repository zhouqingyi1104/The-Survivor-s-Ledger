"""Fit period tunics to the same four Quaternius skeletons used by character.gd.

The bone palette is kept in original Godot skin order. Solid sleeves overlap the
torso at the armhole and end inside the original wrists. No faces are deleted
from the player's licensed source models.
"""
import json
from pathlib import Path
import numpy as np
from PIL import Image
from folk_mesh import Writer,Surface,read_glb,unpack

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/models/folk'
WHITE=np.ones(3)

def gray(value):
    return WHITE*value

def upright(s,rows,color,sides=36,warp=None):
    s.rings([([x,y,z],[rx,0,0],[0,0,rz]) for x,y,z,rx,rz in rows],color,sides,warp)

def panel(s,a,b,w,color,offset=.0):
    # Draw a strip of binding on the cloth. The two edges follow the same front depth.
    edges=[]
    for i,(p,q) in enumerate(zip(a,b)):
        v=[]
        for j,pt in enumerate((p,q)):
            v.append(s.vertex(np.array(pt)+[0,0,offset],[j*w,i*.22],color))
        if edges:
            s.face(edges[0],edges[1],v[1],[0,0,1]); s.face(edges[0],v[1],v[0],[0,0,1])
        edges=v

def make_garment(body):
    female=body.startswith('female')
    long=body.endswith('long')
    dx=.94 if female else 1.
    dy=.947 if female else 1.
    main,shade,leather,edge=(Surface() for _ in range(4))
    # A single garment from neck to hem: shoulder fall, bloused waist, wider lower skirt.
    low=.19 if long else .73
    body_rows=[(low, .333 if long else .242, .248 if long else .181),
               (low+.025,.332 if long else .241,.247 if long else .183),
               ((low+.86)/2,.294 if long else .235,.217 if long else .18),
               (.856,.225,.177),(.964,.210,.160),(1.04,.186,.145),
               (1.105,.189,.138),(1.18,.203,.145),(1.30,.223,.158),
               (1.40,.232,.156),(1.455,.226,.142),(1.50,.207,.121),
               (1.528,.152,.109),(1.55,.086,.082),(1.565,.078,.076)]
    def folds(a,k):
        spread=(.066 if long else .033)*(1-min(1,max(0,body_rows[k][0]-.30)/.8))
        return 1+(spread+.014)*np.cos(a*10+body_rows[k][0]*.9)+spread*.41*np.sin(a*7-.5)
    def cloth(a,k):
        return gray(.79+.18*(.5+.5*np.cos(a*10+body_rows[k][0]*.9))+.03*np.sin(a*4+k*.28))
    upright(main,[(0,y,-.016 if y<1.43 else -.044,rx,rz) for y,rx,rz in body_rows],cloth,48,folds)
    # Solid collar closes the original gap between exposed neck and the torso mesh.
    upright(edge,[(0,1.538,-.048,.099,.093),(0,1.568,-.048,.089,.084),
                  (0,1.583,-.048,.081,.078),(0,1.583,-.048,.070,.068)],gray(.48),36)
    # Cross collar turns from the nape to the waist and continues into the side seam.
    # Compute its depth on the same elliptical section as the shell.
    def front(x,y):
        ry=np.interp(y,[r[0] for r in body_rows],[r[1] for r in body_rows])
        rz=np.interp(y,[r[0] for r in body_rows],[r[2] for r in body_rows])
        cz=-.016 if y<1.43 else -.044
        return [x,y,cz+rz*np.sqrt(max(.05,1-(x/ry)**2))+.013]
    for path,thick in [([(-.061,1.566),(-.055,1.513),(-.026,1.431),(.008,1.367),(.063,1.295),(.112,1.232),(.150,1.16),(.162,1.093)],.033),
                       ([(.053,1.558),(.054,1.506),(.042,1.449),(.010,1.391),(-.004,1.367)],.026)]:
        panel(edge,[front(x-thick/2,y) for x,y in path],[front(x+thick/2,y) for x,y in path],.15,gray(.52))
    # Weighted sleeves run along the unposed arms, with material sag on the undersides.
    for side in (-1,1):
        sleeve=[(.070,1.423,.090,.101),(.133,1.441,.113,.132),(.198,1.446,.125,.127),(.245,1.446,.121,.127),
                (.318,1.442,.121,.120),(.39,1.433,.117,.118),(.458,1.433,.114,.113),
                (.532,1.437,.110,.110),(.617,1.445,.103,.099),(.692,1.444,.100,.094),
                (.714,1.444,.099,.094),(.714,1.444,.085,.082),(.701,1.444,.061,.061),(.681,1.445,.036,.038),(.680,1.445,.001,.001)]
        def cuff(rows):
            return [([side*x,y,-.047],[0,ry,0],[0,0,rz]) for x,y,ry,rz in rows]
        main.rings(cuff(sleeve),lambda a,k:gray(.82+.15*(.5+.5*np.sin(5*a+k*.18))),32,
                   lambda a,k:1+.032*np.sin(6*a+k*.21))
        edge.rings(cuff([(.659,1.445,.103,.101),(.667,1.445,.105,.102),(.708,1.444,.104,.099),
                         (.717,1.444,.101,.096)]),gray(.53),32)
        # A dark facing turns the open end of each sleeve back into the wrist.
        # Its inside is visible from the front when the jiangshi raises both arms.
        edge.rings(cuff([(.703,1.444,.097,.093),(.711,1.444,.094,.091),
                         (.697,1.444,.043,.042),(.736,1.443,.034,.036),(.753,1.443,.030,.031)]),
                   gray(.29),32)
        # Trousers taper into cloth shoes; the cuff covers the shin as the ankle flexes.
        rows=[(.073,.113,-.072,.071,.073),(.114,.114,-.070,.075,.078),(.154,.116,-.07,.071,.075),
              (.21,.117,-.065,.083,.081),(.355,.129,-.070,.087,.09),(.48,.122,-.04,.088,.089),
              (.58,.116,-.025,.091,.097),(.73,.110,-.021,.112,.122),(.88,.106,-.030,.115,.143),
              (1.0,.10,-.035,.11,.128)]
        rows = [r for r in rows if r[0] <= (.355 if long else .88)]
        upright(shade,[(side*x,y,z,rx,rz) for y,x,z,rx,rz in rows],gray(.92),28,
                lambda a,k:1+.047*np.sin(a*7+k*.28))
        upright(leather,[(side*.115,y,z,rx,rz) for y,z,rx,rz in
                         [(.012,-.014,.076,.150),(.026,-.014,.079,.155),(.056,-.018,.078,.151),
                          (.087,-.037,.072,.128),(.116,-.064,.070,.084),(.184,-.072,.072,.080)]],gray(.85),32)
        upright(edge,[(side*.115,.024,-.014,.08,.156),(side*.115,.035,-.014,.080,.156)],gray(.39),32)
    # A slightly raised woven sash covers the opening where the two front panels overlap.
    upright(edge,[(0,1.031,-.015,.196,.153),(0,1.04,-.015,.199,.154),
                  (0,1.083,-.015,.198,.154),(0,1.096,-.015,.196,.153)],gray(.40),40)
    # All four shapes use the source skin without copying the 16 MB character or its maps.
    writer=Writer()
    raw=next((ROOT/'assets/third_party/quaternius/raw').rglob('Superhero_'+('Female' if female else 'Male')+'_FullBody.gltf'))
    rd=json.loads(raw.read_text());rb=(raw.parent/rd['buffers'][0]['uri']).read_bytes()
    ref=max(rd['meshes'],key=lambda m:rd['accessors'][m['primitives'][0]['attributes']['POSITION']]['count'])['primitives'][0]['attributes']
    xyz=unpack(rd,rb,ref['POSITION'])
    old,ob=read_glb(ROOT/'assets/models/characters'/f'{body}.glb')
    old_skin=old['skins'][0]; a=old_skin['inverseBindMatrices']
    joint_names=[old['nodes'][n]['name'] for n in old_skin['joints']]
    mapping=np.array([joint_names.index(rd['nodes'][n]['name']) for n in rd['skins'][0]['joints']])
    joints=mapping[unpack(rd,rb,ref['JOINTS_0'])]
    weights=unpack(rd,rb,ref['WEIGHTS_0'])
    if weights.dtype.kind!='f':weights=weights/np.iinfo(weights.dtype).max
    # Use mostly soft nearest weights at moving joints. The skirt below the hips follows both thighs.
    def fit(points):
        fitting_skirt = long and points is main.pts
        result=[]
        for start in range(0,len(points),48):
            p=np.asarray(points[start:start+48])
            d=np.sum((p[:,None,:]-xyz[None,:,:])**2,axis=-1)
            idx=np.argpartition(d,8,axis=1)[:,:8]
            for v,ids,dist in zip(p,idx,np.take_along_axis(d,idx,axis=1)):
                ws=1/(dist+.00015)
                accum=np.bincount(joints[ids].ravel(),weights=(weights[ids]*ws[:,None]).ravel(),minlength=len(joint_names))
                if fitting_skirt and v[1]<.84:
                    # The hem hangs from the pelvis with a little thigh motion, not the nearest shin.
                    accum[:]=0
                    accum[1]=.67
                    left=np.clip(.5+v[0]/.46,0,1)
                    accum[joint_names.index('thigh_l')]=.33*left
                    accum[joint_names.index('thigh_r')]=.33*(1-left)
                top=np.argsort(accum)[-4:][::-1]
                result.append((top,accum[top]/accum[top].sum()))
        return zip(*result)
    node_map={n:i for i,n in enumerate(old_skin['joints'])}
    skin_nodes=[]
    for n in old_skin['joints']:
        node={k:v for k,v in old['nodes'][n].items() if k in ('name','translation','rotation','scale','matrix')}
        children=[node_map[c] for c in old['nodes'][n].get('children',[]) if c in node_map]
        if children:node['children']=children
        skin_nodes.append(node)
    writer.doc['nodes']=skin_nodes
    writer.doc['scenes'][0]['nodes']=[0]
    writer.doc['skins']=[{'joints':list(range(len(skin_nodes))),'skeleton':0,'inverseBindMatrices':writer.acc(unpack(old,ob,a),'<f4','MAT4')}]
    for s in (main,shade,leather,edge):
        s.pts=[p*np.array([dx,dy,dx]) for p in s.pts]
    attrs=[(writer.material(n),s) for n,s in [('Robe',main),('Pants',shade),('Shoes',leather),('Binding',edge)]]
    writer.add('TailoredCoat',attrs,fit)
    writer.save(OUT/f'coat_{body}.glb')

def weave():
    # Periodic interlocked yarns with broad dye variation. All maps are authored together.
    size=512; y,x=np.mgrid[0:size,0:size]/size; rng=np.random.default_rng(413)
    w=2*np.pi*(x*42+.11*np.sin(2*np.pi*y*3)); h=2*np.pi*(y*41+.10*np.sin(2*np.pi*x*4))
    over=(np.cos(w*.5)*np.cos(h*.5))*.55+.5
    relief=(np.cos(w)*over+np.cos(h)*(1-over))*.62
    mottle=.32*np.sin(2*np.pi*(4*x+y))+.18*np.sin(2*np.pi*(2*y-x))+.12*np.cos(2*np.pi*(3*x-5*y))
    val=np.clip(228+11*relief+7*mottle+rng.normal(0,1.4,(size,size)),0,255).astype('uint8')
    Image.fromarray(val).save(OUT/'dyed_weave.png')
    gx=(np.roll(relief,-1,1)-np.roll(relief,1,1))*.65; gy=(np.roll(relief,-1,0)-np.roll(relief,1,0))*.65
    normal=np.stack((-gx,gy,np.ones_like(gx)),axis=-1); normal/=np.linalg.norm(normal,axis=-1)[:,:,None]
    Image.fromarray(((normal*.5+.5)*255).astype('uint8')).save(OUT/'dyed_weave_normal.png')

if __name__=='__main__':
    for sex in ['male','female']:
        for cut in ['long','short']:make_garment(sex+'_'+cut)
    weave()
