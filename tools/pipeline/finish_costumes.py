"""Derive garment maps from the authored 413games costume UVs and Quaternius skin atlas."""
from pathlib import Path
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
    def surface(sz,base):
     rng=np.random.default_rng(829); y,x=np.mgrid[:sz[1],:sz[0]]
     grain=rng.normal(0,2.1,(sz[1],sz[0]))+1.5*np.sin(x*.8)+1.2*np.sin(y*.94)
     return Image.fromarray(np.uint8(np.clip(np.array(base)[None,None,:]+grain[:,:,None],0,255)))
    im=surface((160,320),(195,155,91));d=ImageDraw.Draw(im)
    ink=(133,49,33)
    for path in [[(31,48),(51,22),(64,41),(77,15)],[(73,46),(90,18),(109,39),(123,25)],
     [(80,30),(77,93),(95,78),(96,50)],[(38,91),(61,78),(81,90),(114,69)],[(68,92),(86,128),(59,141),(42,111)],
     [(87,99),(98,128),(115,111)],[(50,153),(89,141),(113,151),(96,170),(59,170),(46,185)],
     [(82,126),(76,177),(98,209),(63,238),(61,207)],[(50,195),(100,172)],[(43,215),(104,190)],[(64,240),(84,266),(111,241)]]:
     d.line(path,fill=ink,width=5,joint='curve')
    d.rectangle((54,273,103,304),outline=ink,width=3)
    d.line([(63,278),(63,299),(92,299),(92,280),(77,280),(77,294)],fill=ink,width=3)
    im.save(OUT/'ward_paper.png')
    im=surface((256,256),(52,61,60));d=ImageDraw.Draw(im)
    for inset,col,w in [(5,(152,124,77),4),(12,(112,90,62),3),(25,(173,143,91),2)]:
     d.rectangle((inset,inset,255-inset,255-inset),outline=col,width=w)
    for a in range(30,235,18):
     for y in [15,233]:d.arc((a-3,y-4,a+9,y+6),0,273,fill=(170,137,80),width=2)
    for x in [33,61,183]:
     d.arc((x,84+(x%2)*7,x+42,106+(x%2)*7),175,350,fill=(146,138,104),width=3)
    for yy in [185,195,205,215]:
     for x in range(21,225,22):d.arc((x,yy-7,x+28,yy+9),170,345,fill=(103,131,126),width=3)
    # Heron in flight, long neck, bent wing and trailing legs.
    d.polygon([(54,72),(95,97),(136,112),(158,106),(145,121),(117,129),(96,120),(73,101)],fill=(204,191,151))
    d.polygon([(101,119),(95,138),(74,163),(68,177),(91,169),(112,150),(134,126)],fill=(179,168,131))
    for k in range(6):
     d.line([(63+k*5,81+k*3),(109+k*4,111+k*2)],fill=(91,94,86),width=2)
     d.line([(79+k*3,162+k%2*3),(108+k*4,130+k%2*2)],fill=(82,89,85),width=2)
    d.line([(143,117),(161,112),(174,96),(176,86),(184,78),(192,81)],fill=(211,193,152),width=6)
    d.polygon([(187,79),(213,85),(190,85)],fill=(159,117,71))
    d.line([(113,126),(81,137),(51,142)],fill=(171,133,74),width=2);d.line([(120,126),(85,143),(55,150)],fill=(171,133,74),width=2)
    im.save(OUT/'rank_badge.png')

if __name__=='__main__':
    for kind in ['base','moon']:coat_atlas(kind)
    moon_hat()
    printed_panels()
    source=ROOT/'assets/models/characters/male_long_T_Superhero_Male_Dark.png'
    im=Image.open(source).convert('RGB')
    washed=ImageOps.colorize(ImageOps.grayscale(im),black=(32,41,36),white=(200,201,177),mid=(123,136,117),midpoint=116)
    toned=Image.blend(washed,ImageEnhance.Color(im).enhance(.14),.14)
    toned.resize((768,768),Image.Resampling.LANCZOS).save(OUT/'weathered_skin.jpg',quality=90,optimize=True)
