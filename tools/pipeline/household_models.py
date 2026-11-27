"""Bake the small hand-built props into one glTF library with a shared PBR atlas.

Run from any directory with Python, NumPy and Pillow. Sizes are in game metres.
The stock forms and woven surfaces are authored here. Sawn timber uses the
project's CC0 brown_planks_09 scan (see docs/03-art-assets.md).
"""
import json
import math
import struct
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/models/household/household.glb"
TAU = math.tau
TILES = ["linen", "hemp", "bark", "split", "end", "wood", "willow", "iron",
         "brass", "sacking", "leaf", "pepper", "garlic", "stone", "paper", "ash"]


def atlas():
    size = 256
    y, x = np.mgrid[:size, :size] / size
    rng = np.random.default_rng(617)
    def noise(scale):
        field = Image.fromarray(rng.integers(0, 255, (scale, scale), dtype="uint8"))
        return np.asarray(field.resize((size, size), Image.Resampling.BICUBIC)) / 255 - 0.5
    grain, broad, fleck = noise(36), noise(6), noise(256)
    twist = np.sin(TAU * (22*x - 6*y))
    # Threads alternately pass over one another. The shallower crossing is shaded.
    warp = np.sin(TAU * 66 * x + 0.4 * grain)
    weft = np.sin(TAU * 35 * y + 0.27 * broad)
    over = np.sin(TAU * x * 33) * np.sin(TAU * y * 17.5) > 0
    linen = np.where(over, 0.64 * warp + 0.2 * weft, 0.33 * warp + 0.5 * weft)
    bark = np.sin(TAU * (x * 12 + 2.3 * broad + 0.38 * grain + 0.27 * np.sin(6 * y)))
    radius = np.sqrt((x - 0.43) ** 2 + ((y - 0.36) * 1.1) ** 2)
    rings = np.sin(TAU * (radius * 24 + 0.38 * broad + 0.16 * grain))
    woodfile = ROOT / "assets/third_party/polyhaven/textures/brown_planks_09/brown_planks_09_diff.jpg"
    with Image.open(woodfile) as src:
        wood = np.asarray(src.convert("L").crop((15, 111, 995, 167)).resize((size,size))) / 255
    wood = wood - wood.mean()
    # base sRGB, relief, roughness, metallic
    samples = [
        ((193,166,122), linen * 0.38 + broad * 0.58 + fleck * 0.41, .96, 0),
        ((175,139,88), twist * 0.38 + fleck * 0.35, .93, 0),
        ((95,74,55), bark * .64 + grain * .82 + fleck * .50, .95, 0),
        ((185,144,96), wood.T * 2.65 + grain * .34, .82, 0),
        ((189,153,110), rings * .53 + grain * .60, .87, 0),
        ((147,109,75), wood * 2.9 + fleck * .15, .66, 0),
        ((181,138,75), .35 * np.sin(TAU * (26 * x + .25 * broad)) + .52 * grain, .77, 0),
        ((101,103,98), .5 * grain + broad + .2 * fleck, .48, .79),
        ((167,130,79), grain * .65 + broad + fleck * .16, .49, .72),
        ((185,166,135), linen * .53 + broad * .55 + fleck * .42, .96, 0),
        ((120,147,93), grain * .45 + broad * .95, .76, 0),
        ((151,62,39), grain * .52 + .52 * np.cos(TAU * (8*x + broad)), .65, 0),
        ((224,209,169), .33 * np.sin(TAU*(14*x + broad)) + grain * .47, .82, 0),
        ((137,143,134), fleck * .60 + grain * .88 + broad * .64, .83, 0),
        ((210,189,143), broad * 1.1 + grain * .50 + fleck * .23, .94, 0),
        ((84,75,66), fleck * .65 + broad + grain, .94, 0)]
    maps = [Image.new("RGB", (size*4,size*4)) for _ in range(3)]
    for i,(base,h,rough,metal) in enumerate(samples):
        lum = np.clip(1.0 + .29 * h, .49, 1.44)
        color = np.array(base) * lum[...,None]
        dy,dx = np.gradient(h)
        norm = np.stack((-dx*.44,dy*.44,np.ones_like(h)),axis=2)
        norm /= np.linalg.norm(norm,axis=2,keepdims=True)
        orm = np.stack((np.ones_like(h), (rough - .09*h).clip(.12,1),
                        np.full_like(h,metal)),axis=2)
        for sheet, pixels in zip(maps, [color,(norm*.5+.5)*255,orm*255]):
            sheet.paste(Image.fromarray(pixels.clip(0,255).astype("uint8")),
                        (size*(i%4),size*(i//4)))
    # Original brush marks on a single printed protective slip. Uneven ink
    # follows the paper fibres, including the edges of the little square seal.
    stamp=Image.new("L",(size,size))
    pen=ImageDraw.Draw(stamp)
    strokes=[[(113,18),(137,26),(145,34)],[(66,58),(79,44),(184,41),(172,61)],
             [(114,69),(92,108),(154,131)],[(146,74),(135,102),(123,115),(84,136)],
             [(65,91),(98,85),(181,81)],[(83,162),(129,153),(163,159),(139,172),(95,177)],
             [(110,181),(132,186),(143,198)],[(82,202),(168,196)]]
    for j,line in enumerate(strokes):
        pen.line(line,fill=225,width=5+j%3,joint="curve")
    pen.rectangle((155,212,190,239),outline=237,width=3)
    for x0 in [164,175,181]:
        pen.line((x0,218,x0+2,232),fill=219,width=2)
    where=(2*size,3*size)
    ink=np.asarray(stamp)/255*(.77+.20*grain+.10*fleck)
    paper=np.array(maps[0].crop((*where,where[0]+size,where[1]+size)))
    red=np.array([119.,48.,32.])
    maps[0].paste(Image.fromarray((paper+(red-paper)*ink[...,None]).astype("uint8")),where)
    # A weathered rice merchant's chop, printed twice around the reused sacking.
    mark = Image.new("L", (size, size))
    pen = ImageDraw.Draw(mark)
    for center in (63, 191):
        pen.rectangle((center - 11, 109, center + 11, 157), outline=145, width=2)
        for line in [[(-7,120),(-3,130)],[(7,119),(3,130)],[(-8,133),(8,132)],
                     [(0,116),(0,151)],[(0,131),(-8,147)],[(1,131),(8,146)]]:
            pen.line([(center + dx, yy) for dx, yy in line], fill=177, width=2)
    tile = (size, 2 * size)
    cloth = np.asarray(maps[0].crop((*tile, tile[0]+size, tile[1]+size)))
    faded = np.asarray(mark)[...,None] / 255 * (.75 + .4*grain + .25*fleck)[...,None]
    maps[0].paste(Image.fromarray((cloth + (np.array([91,68,47])-cloth)*faded).astype("uint8")), tile)
    return maps


def vec(p):
    return np.asarray(p, dtype=float)


def unit(p):
    return p / max(1e-9, np.linalg.norm(p))


def swatch(code):
    rgb = np.array(list(bytes.fromhex(code))) / 255
    # glTF vertex factors multiply the decoded sRGB base map in linear space.
    return np.where(rgb < .04045,rgb/12.92,((rgb+.055)/1.055)**2.4)


WHITE = np.ones(3)


class Model:
    def __init__(self):
        self.attrs = [[],[],[],[]]
        self.indices = []

    def surface(self, grid, tile, tint=WHITE, flip=False, loop=False, planar_uv=None):
        grid = np.asarray(grid)
        rows, cols = grid.shape[:2]
        start = len(self.attrs[0])
        cell = TILES.index(tile)
        for j in range(rows):
            for i in range(cols):
                a = grid[j, (i-1) % (cols-1) if loop else max(0,i-1)]
                b = grid[j, (i+1) % (cols-1) if loop else min(cols-1,i+1)]
                c,d = grid[max(0,j-1),i], grid[min(rows-1,j+1),i]
                norm = unit(np.cross(b-a,d-c))
                uv = planar_uv(grid[j,i]) if planar_uv else [i/(cols-1), 1-j/(rows-1)]
                tex = np.array(uv)*.968+.016
                color = tint(j/(rows-1),i/(cols-1)) if callable(tint) else tint
                for out, val in zip(self.attrs, (grid[j,i], -norm if flip else norm,
                                   (tex + [cell%4,cell//4])/4, color)):
                    out.append(val)
        for j in range(rows-1):
            for i in range(cols-1):
                a=start+j*cols+i
                face = [a,a+1,a+cols,a+1,a+cols+1,a+cols]
                self.indices.extend(face[::-1] if flip else face)

    def loft(self, profile, tile, tint=WHITE, sides=24, shape=None):
        # Each section is (x radius, z radius, centre y). Latitude follows its exact profile.
        points = []
        for row,(rx,rz,h) in enumerate(profile):
            ring=[]
            for i in range(sides+1):
                a=TAU*i/sides
                p = vec([rx*math.cos(a),h,rz*math.sin(a)])
                ring.append(shape(p,a,row) if shape else p)
            points.append(ring)
        self.surface(points,tile,tint,flip=True,loop=True)

    def tube(self, path, radii, tile, tint=WHITE, sides=7):
        path = vec(path)
        if np.isscalar(radii):
            radii = [radii]*len(path)
        first=unit(path[1]-path[0])
        anchor=np.eye(3)[np.argmin(np.abs(first))]
        points=[]
        for j,(p,r) in enumerate(zip(path,radii)):
            tangent=unit(path[min(j+1,len(path)-1)]-path[max(j-1,0)])
            u=unit(anchor-tangent*np.dot(anchor,tangent))
            v=unit(np.cross(tangent,u))
            points.append([p + r * (u*math.cos(TAU*i/sides)+v*math.sin(TAU*i/sides)) for i in range(sides+1)])
        self.surface(points,tile,tint,loop=True)

    def hoop(self, point, rx, rz, radius, tile, tint=WHITE, sides=28):
        path=[vec(point)+[rx*math.cos(TAU*i/sides),0,rz*math.sin(TAU*i/sides)] for i in range(sides+1)]
        self.tube(path,radius,tile,tint,6)

    def block(self, center, size, tile, tint=WHITE, bevel=.008, yaw=0):
        x,y,z=vec(size)/2
        b=min(bevel,x*.36,y*.36,z*.36)
        angle=math.radians(yaw)
        cs,sn=math.cos(angle),math.sin(angle)
        ring=[(-x+b,-z),(x-b,-z),(x,-z+b),(x,z-b),(x-b,z),(-x+b,z),(-x,z-b),(-x,-z+b)]
        contour=[]
        for level,sx,sz in [(-y,.99,.99),(-y+b,1,1),(y-b,1,1),(y,.99,.99)]:
            row=[]
            for u,v in ring:
                a,c=u*sx,v*sz
                row.append(vec(center)+[a*cs+c*sn,level,c*cs-a*sn])
            contour.append(row)
        for i in range(8):
            j=(i+1)%8
            self.surface([[row[j],row[i]] for row in contour],tile,tint)
        for side,flip in [(0,True),(-1,False)]:
            row=np.array([*contour[side],contour[side][0]])
            mid=row.mean(axis=0)
            self.surface([mid+.0005*(row-mid),row],tile,tint,flip=flip,loop=True)


def sack():
    m=Model()
    profile=[(.005,.005,.012),(.14,.115,.015),(.225,.176,.049),(.251,.2,.11),
             (.265,.202,.18),(.253,.19,.238),(.208,.159,.288),(.154,.12,.323),
             (.108,.084,.351),(.052,.046,.379),(.043,.041,.397),(.074,.061,.437),
             (.080,.063,.449),(.061,.049,.444),(.016,.013,.399)]
    def body(p,a,j):
        fold=(.017 * math.cos(9*a+.45*p[1]) + .006*math.sin(5*a)) * min(1.,max(0.,(p[1]-.20)/.11))
        fold+=.006*math.sin(3*a+8*p[1])
        gather=max(0.,p[1]-.205)
        p[0]+=.03*p[1]+.22*gather+fold*math.cos(a)
        p[2]+=fold*math.sin(a) + .014*math.sin(p[1]*10) - .12*gather
        if j in (11,12,13): p[1]+=.014*math.cos(7*a)
        return p
    def color(v,u):
        band = 1-.21 * math.exp(-((v-.32)/.038)**2)
        dirt = .83+.17*min(1,v*4.3)
        return vec([.96,.93,.87])*band*dirt
    m.loft(profile,"sacking",color,32,body)
    for a in (.07,math.pi+.07):
        seam=[body(vec([r*math.cos(a),h,d*math.sin(a)]),a,j) for j,(r,d,h) in enumerate(profile[1:10],1)]
        m.tube(seam,.004,"hemp",swatch("c5b49c"),5)
    for i in range(2):
        m.hoop((.052,.385+i*.011,-.030),.050,.045,.0065,"hemp",swatch("bca17e"))
    m.tube([(.089,.390,-.036),(.123,.379,-.030),(.140,.348,-.01),(.155,.34,.002)], [.007,.006,.006,.003],"hemp")
    # Laid sacks spread sideways under their own weight. Compress the contacted
    # face more strongly than the shoulder, leaving the tied mouth off the floor.
    angle = math.radians(68)
    rotation = np.array([[math.cos(angle), -math.sin(angle), 0],
                         [math.sin(angle), math.cos(angle), 0], [0, 0, 1]])
    transform = np.diag([1.22, .58, .99]) @ rotation
    vertices = np.asarray(m.attrs[0]) @ transform.T
    normals = np.asarray(m.attrs[1]) @ np.linalg.inv(transform)
    vertices -= [(vertices[:,0].max()+vertices[:,0].min()) / 2, vertices[:,1].min(), 0]
    y = vertices[:,1].copy()
    vertices[:,1] = y - .032 * (1-np.exp(-y/.040))
    normals[:,1] /= 1 - .8*np.exp(-y/.040)
    m.attrs[0] = vertices
    m.attrs[1] = normals / np.maximum(1e-8, np.linalg.norm(normals,axis=1))[:,None]
    return m


def billet():
    m=Model()
    angles=np.linspace(.25,4.24,10)
    shape=[[.116*math.cos(a),(0.111+.009*math.sin(3*a))*math.sin(a)] for a in angles]
    shape.extend([[-.031,-.057],[.021,-.025],[.068,-.043]])
    shape=np.array(shape)
    section=[]
    for z,scale in [(-.45,.95),(-.402,.98),(-.19,1),(.145,1.025),(.379,.94),(.438,.91)]:
        section.append(np.array([[x*scale+.007*math.sin(z*5),y*scale+.008*math.sin(z*2),z+.012*math.sin(x*26+y*39)] for x,y in shape]))
    m.surface([ring[:10] for ring in section],"bark")
    for i in range(9,len(shape)):
        j=(i+1)%len(shape)
        m.surface([[ring[i],ring[j]] for ring in section],"bark" if i<9 else "split")
    for end,flip in [(0,False),(-1,True)]:
        ring=np.array([*section[end],section[end][0]])
        mid=ring.mean(axis=0)
        m.surface([mid+(ring-mid)*.003,ring],"end",flip=flip,loop=True,
                  planar_uv=lambda p: [.5 + p[0]/.30, .5 - p[1]/.30])
    return m


def timber():
    m=Model()
    # Square-cut timber has face grain and pale end grain on a single draw surface.
    m.block((0,0,0),(2.02,.163,.196),"wood",swatch("ead0aa"),.014)
    for side in [-1,1]:
        x=side*1.0101
        m.surface([[(x,-.068,-.084),(x,-.068,.084)],
                   [(x,.068,-.084),(x,.068,.084)]],"end",flip=side>0)
    return m


def worktools():
    m=Model()
    m.block((-.24,.061,.11),(.55,.115,.135),"split",swatch("b99a76"),.019,-11)
    m.block((-.23,.122,.11),(.10,.012,.108),"iron",swatch("787c73"),.004,-11)
    m.tube([(-.235,.127,.11),(-.204,.181,.11),(-.186,.209,.11)], [.045,.036,.025],"wood",sides=9)
    m.tube([(.32,.031,.24),(.36,.026,.18),(.49,.022,-.03),(.56,.023,-.13)],
           [.038,.030,.024,.015],"split",swatch("cfb488"),9)
    m.block((.545,.045,-.108),(.18,.078,.077),"iron",swatch("acaeaa"),.014,24)
    # Open tool tray with two chisels, a hone and a few curled plane shavings.
    m.block((.53,.026,-.30),(.55,.047,.26),"wood")
    for s in [-1,1]:
        m.block((.53,.079,-.30+s*.119),(.55,.084,.023),"wood")
        m.block((.53+s*.266,.079,-.30),(.021,.084,.237),"wood")
    for i in range(2):
        z=-.30+i*.051
        m.tube([(.36,.075,z),(.43,.075,z),(.48,.075,z)],[.016,.021,.014],"split")
        m.block((.558,.075,z),(.163,.015,.026),"iron")
    for i in range(4):
        path=[]
        for k in range(15):
            a=k*.47
            p=vec([-.47+.067*i+.026*math.cos(a),.047+.022*math.sin(a),-.12-.003*k-.014*i])
            path.append([p+[-.006,0,0],p+[.006,0,0]])
        m.surface(path,"split",swatch("fae7bf"))
    return m


def brazier():
    m=Model()
    m.loft([(.015,.015,.066),(.165,.165,.073),(.254,.254,.144),(.317,.317,.250),
            (.33,.33,.276),(.331,.331,.292),(.307,.307,.298),(.298,.298,.269),
            (.246,.246,.182),(.081,.081,.111),(.002,.002,.104)],"iron",swatch("aba8a0"),28)
    for side in range(3):
        a=TAU*side/3
        uv=vec([math.cos(a),0,math.sin(a)])
        m.tube([uv*.20+[0,.13,0],uv*.224+[0,.081,0],uv*.247+[0,.018,0]],
               [.025,.025,.034],"iron")
    rng=np.random.default_rng(93)
    for i in range(14):
        a=i*2.40
        rr=.214*math.sqrt(i/13)
        px,pz=rr*math.cos(a),rr*math.sin(a)
        p=vec([px,.19+.018*rng.random(),pz])
        hue=swatch("d75f32") if i%4==0 else swatch("a69b90")
        m.loft([(.03,.029,-.029),(.049,.057,.001),(.046,.050,.026),(.014,.018,.043)],
               "ash" if i%4 else "paper",hue,7,lambda q,a,j:q+p)
    return m


def meat():
    m=Model()
    for i in range(3):
        x=(i-1)*.30
        h=1.37
        m.tube([(x,1.49,0),(x+.013,1.42,.012),(x,1.36,.014)],.009,"hemp")
        for offset,col in [(0,"ab6045"),(.027,"c9a67a")]:
            path=[(x+offset,h,.005),(x+offset*.8,h-.07,.017),(x-.009+offset,h-.17,.016),
                  (x-.022+offset*.9,h-.30,.032),(x+.004+offset*.4,h-.43-.025*i,.044)]
            m.tube(path,[.026,.060,.055,.042,.012] if offset==0 else [.012,.023,.017,.016,.006],
                   "pepper" if offset==0 else "garlic",swatch(col),9)
    return m


def incense():
    m=Model()
    m.loft([(.01,.01,.201),(.08,.077,.209),(.155,.145,.240),(.183,.170,.292),(.177,.164,.337),
            (.153,.145,.351),(.157,.149,.370),(.140,.135,.37),(.139,.130,.343),(.012,.013,.312)],
           "brass",swatch("b5aa8b"),26)
    for i in range(3):
        a=TAU*i/3
        d=vec([math.cos(a),0,math.sin(a)])
        m.tube([d*.104+[0,.235,0],d*.116+[0,.198,0],d*.111+[0,.161,0]],[.018,.015,.020],"brass")
        x=.022*(i-1)
        m.tube([(x,.331,0),(x*1.64,.55+.04*i,.007),(x*1.65,.558+.04*i,.008)],
               [.0035,.0032,.0028],"wood",swatch("857469"),5)
    for side in [-1,1]:
        m.tube([(side*.153,.314,0),(side*.194,.360,0),(side*.208,.386,0),
                (side*.186,.397,0),(side*.173,.384,0)], .010,"brass")
    m.loft([(.105,.090,0),(.117,.105,.016),(.112,.100,.036),(.072,.065,.052),(.073,.067,.141),
            (.137,.115,.150),(.142,.127,.162),(.130,.115,.169)],"wood",swatch("a78264"),12)
    return m


def basket():
    m=Model()
    # Vertical stakes take the load; the continuous horizontal weft alternately
    # crosses behind and in front. A dark inner lining keeps the contents legible.
    m.loft([(.01,.01,.019),(.205,.181,.019),(.224,.195,.042),(.294,.255,.283),(.297,.26,.30)],
           "willow",swatch("75675a"),36)
    for i in range(24):
        a=TAU*i/24
        path=[]
        for j in range(9):
            t=j/8
            rr=.007*math.cos(j*math.pi/2)
            mid=vec([(.223+.078*t+rr)*math.cos(a),.032+.271*t,(.194+.070*t+rr)*math.sin(a)])
            width=vec([-math.sin(a),0,math.cos(a)])*.010
            path.append([mid-width,mid+.004*vec([math.cos(a),0,math.sin(a)]),mid+width])
        m.surface(path,"willow",swatch("d8c294"),flip=True)
    for j in range(9):
        t=j/8
        pos=[]
        for i in range(49):
            a=TAU*i/48
            relief=.011*math.cos(12*a+j*math.pi)
            mid=vec([(.232+.072*t+relief)*math.cos(a),.042+.248*t,(.202+.063*t+relief)*math.sin(a)])
            pos.append([mid-[0,.012,0],mid+.004*vec([math.cos(a),0,math.sin(a)]),mid+[0,.012,0]])
        m.surface(np.transpose(pos,(1,0,2)),"willow",swatch("f1dab1") if j%3 else swatch("cfb58b"),flip=True,loop=True)
    m.hoop((0,.305,0),.303,.265,.016,"hemp",swatch("d6b98b"),40)
    for side in [-1,1]:
        m.tube([(side*.298,.27,-.04),(side*.307,.335,-.037),(side*.306,.351,0),
                (side*.307,.335,.037),(side*.298,.27,.04)],.011,"willow")
    return m


def produce():
    m=Model()
    for i in range(9):
        a=i*2.399
        reach=.16 * math.sqrt(i/8)
        x,z=reach*math.cos(a),reach*.9*math.sin(a)
        h=.31+.025*(1-reach/.16)
        rx,rz=.093,.082
        def bulb(p,_a,_j):
            wobble=1+.06*math.cos(5*_a+i)
            return [x+p[0]*wobble,h+p[1],z+p[2]*wobble]
        m.loft([(.02,.02,-.072),(rx*.78,rz*.8,-.041),(rx,rz,-.005),
                (rx*.82,rz*.8,.033),(.022,.021,.057),(.007,.007,.075)],
               "leaf",swatch("d8dba4") if i%3 else swatch("aeb780"),14,bulb)
        # The leaf veins and cupped margins follow each overlapping head.
        for leaf in range(3):
            ang=a+leaf*2.094
            l=vec([math.cos(ang),0,math.sin(ang)])
            w=vec([-math.sin(ang),0,math.cos(ang)])
            origin=vec([x,h-.042,z])
            m.surface([[origin+l*.04-w*.017,origin+l*.047,origin+l*.04+w*.017],
                       [origin+l*.079-w*.04+[0,.05,0],origin+l*.095+[0,.051,0],origin+l*.079+w*.04+[0,.05,0]],
                       [origin+l*.053-w*.029+[0,.086,0],origin+l*.078+[0,.092,0],origin+l*.053+w*.029+[0,.086,0]]],
                      "leaf",swatch("9eae89"))
    return m


def grain():
    m=Model()
    m.loft([(.001,.001,.29),(.281,.247,.287),(.244,.208,.319),(.179,.157,.343),(.094,.084,.358),(.001,.001,.363)],
           "garlic",swatch("d9cdb3"),36)
    rng=np.random.default_rng(702)
    for _ in range(165):
        a=rng.uniform(0,TAU)
        r=math.sqrt(rng.random())
        x,z=.26*r*math.cos(a),.22*r*math.sin(a)
        h=float(np.interp(.26*r,[0,.094,.179,.244,.282],[.366,.361,.346,.322,.290]))+.0018
        d=vec([math.cos(a),0,math.sin(a)])*.009
        w=vec([-math.sin(a),0,math.cos(a)])*.004
        p=vec([x,h,z])
        m.surface([[p-d-w*.25,p-d+w*.25],[p-w+[0,.003,0],p+w+[0,.003,0]],
                   [p+d-w*.25,p+d+w*.25]],"garlic",swatch("ebd9aa"))
    return m


def produce_string():
    m=Model()
    for string,spacing,count in [(0,.096,9),(.35,.108,6)]:
        cord=[(string+.012*math.sin(j*2),-.035-j*spacing,.012*math.cos(j*1.5)) for j in range(count)]
        m.tube(cord,.010,"hemp",swatch("b7a077"))
        for j,root in enumerate(cord):
            for side in [-1,1] if string else [(-1)**j]:
                root=vec(root)
                if string:
                    def bulb(p,a,_i):
                        p[[0,2]] *= 1+.10*math.cos(a*6)
                        return p+root+[side*.022,-.106,.013]
                    m.loft([(.006,.008,.002),(.043,.040,.014),(.055,.052,.049),
                            (.042,.042,.076),(.015,.015,.101),(.008,.009,.122)],"garlic",WHITE,14,bulb)
                else:
                    path=[root+[0,.028,0],root+[side*.034,-.012,.005],root+[side*.052,-.056,.012],
                          root+[side*.056,-.105,.028],root+[side*.033,-.147,.046],root+[side*.01,-.173,.056]]
                    m.tube(path,[.010,.025,.030,.024,.013,.001],"pepper",swatch("dab6a0") if j%3 else WHITE,9)
                    m.tube([root+[0,.048,0],root+[0,.025,0],root+[side*.022,.005,.001]],[.007,.012,.015],"leaf",swatch("968764"))
    return m


def drying_cloth(index):
    m=Model()
    col=["59748b","dbcdb4","a26854"][index]
    height=[.76,.86,.68][index]
    def vertex(u,v):
        down = v*height
        w = .56*(1-.08*(1-v))
        y = -down-.038*math.sin(math.pi*u)*(1-v) - .014*math.sin(7*u)*v
        x = (u-.5)*w+.022*math.sin(3*v+index)*v
        z = .027*math.cos(15*u+index+v*1.15)+v*.035+.024*math.sin(math.pi*v)
        return [x,y,z]
    m.surface([[vertex(i/16,j/8) for i in range(17)] for j in range(9)],
              "linen",lambda v,u: swatch(col)*(.66 if .07<v<.12 or .87<v<.90 else 1))
    # A short return folds over the rope: show the reverse fabric when seen from behind.
    m.surface([[[p[0],p[1],p[2]-.016] for p in [vertex(i/16,d) for i in range(17)]]
               for d in [0,.03,.095]],"linen",swatch(col)*.81,flip=True)
    return m


def charm():
    m=Model()
    grid=[]
    for j in range(7):
        v=j/6
        row=[]
        for i in range(5):
            u=i/4
            row.append([.185*(u-.5)+.010*math.sin(v*4.7),
                        .373*(v-.5)-.007*(1-v)*math.cos(9*u),
                        .025*math.cos(5.2*v)+.015*(u-.6)**2])
        grid.append(row)
    m.surface(grid,"paper",swatch("e6c98b"))
    return m


def mirror():
    m=Model()
    m.loft([(.038,.038,-.037),(.265,.265,-.03),(.287,.287,-.019),(.306,.306,.003),
            (.299,.299,.020),(.265,.265,.029),(.250,.250,.019)],"brass",swatch("cfc3a3"),8)
    m.hoop((0,.020,0),.230,.230,.013,"brass",swatch("d2c6a3"),36)
    m.loft([(.234,.234,.012),(.222,.222,.032),(.143,.143,.046),(.002,.002,.057)],"brass",swatch("d2d3c1"),36)
    for i in range(8):
        a=i*TAU/8
        mid=vec([math.cos(a)*.257,.031,math.sin(a)*.257])
        tangent=vec([-math.sin(a),0,math.cos(a)])*.024
        for j in range(2):
            at=mid*(1+.032*j)
            m.tube([at-tangent,at+tangent],.0035,"brass",swatch("8e7d65"),5)
    return m


def export(models):
    doc={"asset":{"version":"2.0","generator":"JieYuLu household workshop"},"scene":0,
         "scenes":[{"nodes":list(range(len(models)))}],"nodes":[],"meshes":[],"accessors":[],
         "bufferViews":[],"buffers":[],"images":[],"textures":[]}
    blob=bytearray()
    def view(data):
        blob.extend(b"\x00" * (-len(blob)%4))
        offset=len(blob)
        blob.extend(data)
        doc["bufferViews"].append({"buffer":0,"byteOffset":offset,"byteLength":len(data)})
        return len(doc["bufferViews"])-1
    def accessor(values,dtype,shape):
        arr=np.array(values,dtype=dtype)
        entry={"bufferView":view(arr.tobytes()),"componentType":5126 if dtype=="<f4" else 5125,
               "type":shape,"count":len(arr)}
        if shape=="VEC3":
            entry.update(min=arr.min(axis=0).tolist(),max=arr.max(axis=0).tolist())
        doc["accessors"].append(entry)
        return len(doc["accessors"])-1
    for i,sheet in enumerate(atlas()):
        name=["HouseholdColor","HouseholdRelief","HouseholdORM"][i]
        file=OUT.with_name("household_"+name+".png")
        file.parent.mkdir(parents=True,exist_ok=True)
        sheet.save(file,optimize=True)
        doc["images"].append({"name":name,"uri":file.name})
        doc["textures"].append({"source":i})
    doc["materials"]=[{"name":"Handworked surfaces","doubleSided":True,
                       "pbrMetallicRoughness":{"baseColorTexture":{"index":0},
                                              "metallicRoughnessTexture":{"index":2}},
                       "normalTexture":{"index":1,"scale":.52}}]
    for i,(name,model) in enumerate(models.items()):
        attrs={key:accessor(values,"<f4",shape) for key,values,shape in
               zip(("POSITION","NORMAL","TEXCOORD_0","COLOR_0"),model.attrs,("VEC3","VEC3","VEC2","VEC3"))}
        doc["nodes"].append({"name":name,"mesh":i})
        doc["meshes"].append({"name":name,"primitives":[{"attributes":attrs,"indices":accessor(model.indices,"<u4","SCALAR"),"material":0}]})
    doc["buffers"]=[{"byteLength":len(blob)}]
    packed=json.dumps(doc,separators=(",",":")).encode()
    packed+=b" "*(-len(packed)%4)
    blob.extend(b"\x00"*(-len(blob)%4))
    OUT.parent.mkdir(parents=True,exist_ok=True)
    with OUT.open("wb") as f:
        f.write(struct.pack("<4sIIII",b"glTF",2,28+len(packed)+len(blob),len(packed),0x4e4f534a))
        f.write(packed)
        f.write(struct.pack("<II",len(blob),0x004e4942))
        f.write(blob)


if __name__ == "__main__":
    export({"Sack":sack(),"Billet":billet(),"Timber":timber(),"Basket":basket(),"Cabbages":produce(),
            "Rice":grain(),"Strings":produce_string(),"Worktools":worktools(),"Brazier":brazier(),
            "SmokedMeat":meat(),"Incense":incense(),"Slip":charm(),"Mirror":mirror(),
            **{f"Cloth{i}":drying_cloth(i) for i in range(3)}})
