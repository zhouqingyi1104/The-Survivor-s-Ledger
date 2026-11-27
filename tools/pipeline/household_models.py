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
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/models/household/household.glb"
TAU = math.tau
TILES = ["linen", "hemp", "bark", "split", "end", "wood", "willow", "iron",
         "brass", "sacking", "leaf", "pepper", "garlic", "stone", "paper", "ash",
         "cut_meat", "smoked_rind", "rice", "leaf_heart"]
ATLAS_COLUMNS = 4
ATLAS_ROWS = math.ceil(len(TILES) / ATLAS_COLUMNS)


def atlas():
    size = 256
    y, x = np.mgrid[:size, :size] / size
    rng = np.random.default_rng(617)
    def noise(scale):
        field = Image.fromarray(rng.integers(0, 255, (scale, scale), dtype="uint8"))
        return np.asarray(field.resize((size, size), Image.Resampling.BICUBIC)) / 255 - 0.5
    grain, broad = noise(36), noise(6)
    twist = np.sin(TAU * (22*x - 6*y))
    # Threads alternately pass over one another. The shallower crossing is shaded.
    warp = np.sin(TAU * 66 * x + 0.4 * grain)
    weft = np.sin(TAU * 35 * y + 0.27 * broad)
    over = np.sin(TAU * x * 33) * np.sin(TAU * y * 17.5) > 0
    linen = np.where(over, 0.64 * warp + 0.2 * weft, 0.33 * warp + 0.5 * weft)
    barkfile = ROOT / "assets/third_party/polyhaven/models/dead_tree_trunk/textures/dead_tree_trunk_diff_1k.jpg"
    with Image.open(barkfile) as scan:
        bark = np.asarray(scan.convert("L").crop((55, 502, 310, 964)).resize((size, size), Image.Resampling.LANCZOS)) / 255
    bark = bark - bark.mean()
    dx, dy = x - .35, y - .55
    radius = np.hypot(dx + .035 * broad, 1.12 * dy)
    season = radius * 18 + .25 * np.sin(17 * radius) + .24 * broad
    latewood = np.maximum(0, np.cos(TAU * season))**4
    split = np.exp(-((dy + .42 * dx + .009 * np.sin(19 * dx)) / .008)**2) * np.clip(dx * 6, 0, 1)
    rings = .12 - latewood * (.22 + .13 * grain) - .7 * split + .20 * broad
    woodfile = ROOT / "assets/third_party/polyhaven/textures/brown_planks_09/brown_planks_09_diff.jpg"
    with Image.open(woodfile) as src:
        wood = np.asarray(src.convert("L").crop((15, 111, 995, 167)).resize((size,size))) / 255
    wood = wood - wood.mean()
    # base sRGB, relief, roughness, metallic
    samples = [
        ((193,166,122), linen * .16 + broad * .28, .96, 0),
        ((175,139,88), twist * .20 + broad * .18, .93, 0),
        ((97,79,62), bark * 4.4, .94, 0),
        ((190,153,111), wood.T * 1.95 + grain * .14, .85, 0),
        ((184,149,109), rings, .91, 0),
        ((147,109,75), wood * 2.45, .72, 0),
        ((181,138,75), .20 * np.sin(TAU * (26 * x + .25 * broad)) + .20 * grain, .81, 0),
        ((101,103,98), .15 * grain + broad * .48, .56, .76),
        ((167,130,79), .12 * grain + broad * .55, .54, .72),
        ((188,166,129), linen * .18 + broad * .28 + grain * .09, .96, 0),
        ((135,156,96), grain * .14 + broad * .34, .80, 0),
        ((151,62,39), grain * .18 + .22 * np.cos(TAU * (8*x + broad)), .70, 0),
        ((224,209,169), .15 * np.sin(TAU*(14*x + broad)) + grain * .14, .84, 0),
        ((137,143,134), grain * .36 + broad * .58, .89, 0),
        ((235,208,147), .11 * broad, .94, 0),
        ((84,75,66), .52 * broad + .21 * grain, .94, 0),
        ((143,81,62), .38*broad+.09*grain, .72, 0),
        ((116,74,49), .62*broad+.27*grain, .84, 0),
        ((218,201,161), .35*broad+.08*grain, .88, 0),
        ((168,187,120), .23*broad+.09*grain, .78, 0)]
    maps = [Image.new("RGB", (size*ATLAS_COLUMNS,size*ATLAS_ROWS)) for _ in range(3)]
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
    def tint_tile(name, rgb, coverage):
        index = TILES.index(name)
        x0, y0 = size*(index%ATLAS_COLUMNS), size*(index//ATLAS_COLUMNS)
        original = np.asarray(maps[0].crop((x0, y0, x0+size, y0+size)))
        alpha = coverage.clip(0, 1)[...,None]
        maps[0].paste(Image.fromarray((original*(1-alpha)+np.array(rgb)*alpha).astype("uint8")), (x0,y0))

    # Raised midrib and alternating secondary veins belong to each real leaf.
    stem = .5 + .044*np.sin(4*y)
    span = np.abs(x - stem)
    midrib = np.exp(-(span/(.019+.049*y))**2)
    branches = np.zeros_like(x)
    for j in range(1,6):
        line = .16*j - span*(.58+.13*y) - .20*span**2 + .018*np.sin(6*x+j)
        branches = np.maximum(branches, np.exp(-((y-line)/.014)**2) * np.exp(-span*2.5))
    tint_tile("leaf", (219,222,163), .70*midrib + .34*branches + .12*y)
    # Fat partitions taper into the cut. The skin turns around its outer edge.
    lean_edge = .68 + .07*np.sin(6*y+.7) + .055*broad
    fat = np.clip((x-lean_edge)*18,0,1)
    marble = np.exp(-((x-.18-.70*y+.08*np.sin(6*y)+.02*grain)/(.018+.026*y))**2)
    tint_tile("cut_meat", (208,171,125), .83*fat+.69*marble)
    tint_tile("cut_meat", (117,71,42), np.clip((x-.92-.03*np.sin(8*y))*35,0,1))
    # The hanging slip is twice as tall as its square atlas cell. Set real type at
    # the physical aspect ratio before packing it into the cell.
    origin = (2 * size, 3 * size)
    paper = maps[0].crop((*origin, origin[0] + size, origin[1] + size)).resize((256, 512))
    pen = ImageDraw.Draw(paper)
    face = str(ROOT / "assets/fonts/LXGWWenKai-Regular.ttf")
    brush = ImageFont.truetype(face, 168)
    for glyph, y in [("安", 55), ("宅", 224)]:
        pen.text((128, y), glyph, font=brush, fill=(127, 48, 33), anchor="mt",
                 stroke_width=1, stroke_fill=(127, 48, 33))
    pen.line([(44, 43), (116, 42), (213, 43)], fill=(175, 109, 66), width=2)
    pen.rounded_rectangle((152, 406, 200, 457), radius=3, fill=(149, 63, 43))
    pen.text((176, 414), "平", font=ImageFont.truetype(face, 35), fill=(238, 206, 145), anchor="mt")
    maps[0].paste(paper.resize((size, size), Image.Resampling.LANCZOS), origin)
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
    faded = np.asarray(mark)[...,None] / 255 * (.71 + .35*broad + .16*grain)[...,None]
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
                                   (tex + [cell%ATLAS_COLUMNS,cell//ATLAS_COLUMNS])/[ATLAS_COLUMNS,ATLAS_ROWS], color)):
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
    # A short rib end, belly strip and cheek hang from separate loops. The rind
    # and fat follow the cut face rather than a second cylinder running beside it.
    for i, (x, length, width, lean) in enumerate([(-.32,.35,.084,-.15), (0,.48,.067,.12), (.32,.31,.096,-.06)]):
        m.tube([(x-.018,1.49,0),(x+.012,1.50,0),(x+.018,1.43,.016),
                (x,1.38,.022),(x-.020,1.43,.016),(x-.018,1.49,0)], .0065, "hemp")
        profile = [(0,.35),(.12,.80),(.29,1),(.52,.90),(.79,.75),(1,.44)]
        rows = []
        for t, spread in profile:
            mid = x + lean*length*t + .015*math.sin(t*5+i)
            h = 1.39-length*t
            w = width*spread
            depth = .025 + .012*math.sin(t*math.pi)
            rows.append([vec([mid + a*w, h + .014*a*math.sin(t*4+i),
                              depth*(1 - .16*a*a) + .011*math.sin(4*t+i)]) for a in (-1,-.57,.46,.70,1)])
        m.surface(rows,"cut_meat",swatch("eadaca"))
        back = [[v-[0,0,.047] for v in row] for row in rows]
        m.surface(back,"smoked_rind",flip=True)
        for edge in (0,-1):
            m.surface([[row[edge],rear[edge]] for row,rear in zip(rows,back)],
                      "smoked_rind",flip=edge==0)
        for end in (0,-1):
            m.surface([rows[end],back[end]],"cut_meat",swatch("c8ad93"),flip=end==0)
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
    heads=[(-.122,-.092,.30,.83),(.085,-.093,.31,.97),(-.143,.083,.30,.91),
           (.092,.078,.31,1.0),(-.029,.003,.35,1.06)]
    for i,(cx,cz,base,scale) in enumerate(heads):
        origin=vec([cx,base,cz])
        def heart(point,angle,row):
            return origin + point*scale
        m.loft([(.019,.021,-.065),(.065,.060,-.034),(.078,.072,.013),
                (.065,.061,.056),(.031,.029,.089),(.002,.002,.096)],
               "leaf_heart",swatch("dfdfb9"),20,heart)
        for leaf in range(12):
            angle=i*.71 + leaf*2.399
            outward=vec([math.cos(angle),0,math.sin(angle)])
            side=vec([-math.sin(angle),0,math.cos(angle)])
            outer=1.0-leaf/12
            grid=[]
            for t, width, reach, rise in [(0,.009,.019,-.059),(.22,.029,.059,-.042),
                                         (.48,.044,.087,-.003),(.70,.051,.079,.045),
                                         (.85,.043,.059,.072),(.95,.026,.034,.086),(1,.006,.012,.094)]:
                row=[]
                for u in [-1,-.69,-.32,0,.32,.69,1]:
                    curl=abs(u)**1.65
                    tip=t*t*t
                    radial=reach*(.90+.24*outer) - .034*curl + .054*outer**2*tip
                    y=rise - .014*curl + .007*math.sin(6*t+leaf+2*u)*curl - .032*outer**2*tip
                    row.append(origin+scale*(radial*outward+(width*u+.021*tip)*side+[0,y,0]))
                grid.append(row)
            def leaf_colour(v,u):
                green=swatch("b6c692")*outer + swatch("e7e5b5")*(1-outer)
                return green*(.86+.14*v)
            m.surface(grid,"leaf",leaf_colour)
    return m


def grain():
    m=Model()
    m.loft([(.001,.001,.29),(.281,.247,.287),(.244,.208,.319),(.179,.157,.343),(.094,.084,.358),(.001,.001,.363)],
           "rice",swatch("e9deca"),36)
    rng=np.random.default_rng(702)
    for _ in range(225):
        a=rng.uniform(0,TAU)
        r=math.sqrt(rng.random())
        x,z=.26*r*math.cos(a),.22*r*math.sin(a)
        h=float(np.interp(.26*r,[0,.094,.179,.244,.282],[.366,.361,.346,.322,.290]))+.0018
        tilt=rng.uniform(0,TAU)
        d=vec([math.cos(tilt),0,math.sin(tilt)])*.008
        w=vec([-math.sin(tilt),0,math.cos(tilt)])*.0035
        p=vec([x,h,z])
        m.surface([[p-d-w*.25,p-d+w*.25],[p-w+[0,.003,0],p+w+[0,.003,0]],
                   [p+d-w*.25,p+d+w*.25]],"rice",swatch("f8edda"))
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
