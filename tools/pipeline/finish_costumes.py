"""Derive garment maps from the authored 413games costume UVs and Quaternius skin atlas."""
from pathlib import Path
import shutil
import subprocess
import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageOps

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/models/folk'
SIZE=1024

def coat_atlas(kind):
    source=next(p for p in (ROOT/'assets/third_party/413games').glob(kind+'-motion-v7*Clothes_Tex.png'))
    original=Image.open(source).convert('RGBA').resize((SIZE,SIZE),Image.Resampling.LANCZOS)
    rgb=np.asarray(original)[:,:,:3].astype(float)
    alpha=original.getchannel('A')
    y,x=np.mgrid[:SIZE,:SIZE]/SIZE
    lum=np.mean(rgb,axis=-1)
    linen=np.clip((lum-152)/64,0,1)
    # Dye varies at a tailor's scale. Weave never overrides the existing lace cutouts.
    warp=np.sin(2*np.pi*(x*231+.19*np.sin(y*61)))*np.cos(2*np.pi*y*197)
    fold=np.sin(2*np.pi*(x*16+.32*np.sin(y*8.1)+.19*np.sin(x*23)))*(.58+.42*np.sin(2*np.pi*x*3.0))
    hem=(np.clip((y-.553)/.24,0,1)*np.clip((.906-y)/.065,0,1))
    wave=np.sin(x*2*np.pi*39+y*5)
    depth=.12*fold*hem+.026*warp+.019*wave
    warmth=np.array([.94,.91,.84]) if kind=='moon' else np.array([.94,.93,.91])
    rgb=rgb*(1+depth[:,:,None])*(1+linen[:,:,None]*(warmth-1))
    albedo=Image.fromarray(np.clip(rgb,0,255).astype('uint8')).convert('RGBA')
    albedo.putalpha(alpha)
    # Embroidered mugwort branches at the outer edges of the apron, confined to the panel.
    paint=Image.new('RGBA',(SIZE,SIZE));brush=ImageDraw.Draw(paint)
    for side in (-1,1):
        root=np.array([.5+side*.079,.738]);tip=np.array([.5+side*.153,.609])
        def stem(t):return root+(tip-root)*t+np.array([side*.013*np.sin(t*np.pi),0])
        line=[tuple((stem(t)*SIZE).astype(int)) for t in np.linspace(0,1,28)]
        brush.line(line,fill=(116,111,83,185),width=2)
        for j,t in enumerate(np.linspace(.1,.92,11)):
            pos=stem(t);spread=(-1)**j*.011
            vector=np.array([side*spread,-.011])*(1.25-.38*t)
            normal=np.array([-vector[1],vector[0]])*.24
            pts=[pos,pos+vector*.5+normal,pos+vector,pos+vector*.5-normal]
            brush.polygon([tuple((p*SIZE).astype(int)) for p in pts],fill=(133+j%3*9,126+j%3*8,92+j%2*12,225))
        for k in range(5):
            pos=stem(.92+k*.012);px,py=(pos*SIZE).astype(int)
            brush.ellipse((px-1,py-1,px+2,py+2),fill=(171,138,82,205))
    albedo=Image.alpha_composite(albedo,paint)
    albedo.putalpha(alpha)
    albedo.save(OUT/(kind+'_tailoring.png'),optimize=True)
    # Fine normals follow the fibre and the broad fabric folds; roughness differs at trim.
    height=warp*.11+fold*hem*2.1
    gy,gx=np.gradient(height)
    norm=np.stack((-gx,gy,np.ones_like(gx)),axis=-1)
    norm/=np.linalg.norm(norm,axis=-1)[:,:,None]
    if kind == 'moon':  # Both costumes share the same weave and UV layout.
        Image.fromarray(((norm+1)*127.5).clip(0,255).astype('uint8')).save(OUT/'moon_tailoring_normal.png')
    rough=np.clip(.68+.19*linen+.055*fold+.04*warp,0,1)
    Image.fromarray((rough*255).astype('uint8')).save(OUT/(kind+'_tailoring_rough.png'))

def moon_hat():
    # The hat is unwrapped by revolution: u runs along the brim, v from crown to edge.
    width,height=1024,512
    y,x=np.mgrid[:height,:width]
    u=x/width;v=y/height
    ring=np.exp(-((v-.827)/.092)**8)
    faded=np.clip(v**2,0,1)
    dye=(.10*np.cos(2*np.pi*(u*14+v*.24))+.035*np.cos(2*np.pi*(u*53-v*7)))
    weave=.03*np.sin(2*np.pi*(u*238+v*19))*np.cos(2*np.pi*v*99)
    col=np.array([66,54,66])*(1+dye[:,:,None]+weave[:,:,None])+faded[:,:,None]*np.array([17,14,13])
    col=col*(1-ring[:,:,None])+(np.array([84,81,91])+dye[:,:,None]*32)*ring[:,:,None]
    image=Image.fromarray(np.uint8(np.clip(col,0,255)));draw=ImageDraw.Draw(image)
    for row,c,w in [(.703,(123,103,94),2),(.725,(155,132,105),2),(.912,(143,116,98),3),(.940,(120,95,87),2)]:
        draw.line((0,int(row*height),width,int(row*height)),fill=c,width=w)
    # Couched braided stems, with one set of buds folded over the other.
    for i in range(-1,24):
        x0=i*width/22
        pts=[]
        for t in np.linspace(0,1,28):
            px=x0+t*width/22;py=height*(.823+.028*np.sin(t*np.pi*2))
            pts.append((px,py))
        draw.line(pts,fill=(161,134,107),width=2)
        for t,sgn in [(.18,-1),(.58,1)]:
            px=x0+t*width/22;py=height*(.823+.028*np.sin(t*np.pi*2))
            draw.polygon([(px,py),(px+2,py+7*sgn),(px+11,py+13*sgn),(px+7,py+4*sgn)],fill=(147,141,143))
        for j in range(3):
            px=x0+j*4+20;py=height*.824-6-j*3
            draw.ellipse((px-1.2,py-1.2,px+1.2,py+1.2),fill=(179,145,101))
    for k in range(0,width,8):
        draw.line([(k,height*.963),(k+4,height*.966)],fill=(173,146,123),width=2)
    image.save(OUT/'moon_hat_brocade.png',optimize=True)


def printed_panels():
    """Bake the two paintings through the same SVG rasterizer used by the game."""
    bundled = ROOT / 'tools/godot/Godot_v4.7.2-stable_win64_console.exe'
    godot = bundled if bundled.is_file() else shutil.which('godot4') or shutil.which('godot')
    if not godot:
        raise RuntimeError('Godot 4 is required to bake costume panels')
    subprocess.run([str(godot), '--headless', '--path', str(ROOT),
                    '--script', 'res://tools/pipeline/bake_costume_panels.gd'], check=True)


if __name__=='__main__':
    for kind in ['base','moon']:coat_atlas(kind)
    moon_hat()
    printed_panels()
    source=ROOT/'assets/models/characters/male_long_T_Superhero_Male_Dark.png'
    im=Image.open(source).convert('RGB')
    washed=ImageOps.colorize(ImageOps.grayscale(im),black=(32,41,36),white=(200,201,177),mid=(123,136,117),midpoint=116)
    toned=Image.blend(washed,ImageEnhance.Color(im).enhance(.14),.14)
    toned.resize((768,768),Image.Resampling.LANCZOS).save(OUT/'weathered_skin.jpg',quality=90,optimize=True)
