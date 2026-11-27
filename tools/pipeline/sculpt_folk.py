"""Original courtyard dog, headwear, watch lantern and belt satchel. Units are metres."""
import math
from pathlib import Path
import numpy as np
from folk_mesh import Writer,Surface,linear,unit
from sew_characters import upright
from hound_coat import coat_mesh, coat_texture

OUT=Path(__file__).resolve().parents[2]/'assets/models/folk'
def lathe(s,rows,color,sides=36,wave=None):
    upright(s,[(0,y,0,r,rz) for y,r,rz in rows],color,sides,wave)

def hound(w):
    fur,face,collar=Surface(),Surface(),Surface()
    saddle=linear('654630'); tan=linear('b58250'); cream=linear('e1c7a1'); black=linear('302923')
    body=coat_mesh()
    face.ball((.01,.618,.484),(.039,.024,.023),black,24)
    for sign in [-1,1]:
        # Eyes sit in the outward-facing side of the skull, ahead of the cheeks.
        face.ball((.01+sign*.072,.664,.359),(.015,.013,.018),linear('33251e'),16)
        face.ball((.01+sign*.078,.668,.372),(.004,.004,.003),linear('c8bb98'),12)
        face.tube([(.01+sign*.038,.593,.481),(.01+sign*.051,.587,.457),
                   (.01+sign*.055,.588,.423),(.01+sign*.063,.597,.391)],[.002,.003,.003,.001],black,8)
        # Guard-hair outer edge, recessed inner ear and arched tip.
        ear=[(.017+sign*.065,.690,.275),(.017+sign*.074,.722,.267),
             (.017+sign*.082,.765,.263),(.017+sign*.093,.802,.252)]
        fur.rings([(c,[r,0,0],[0,0,d]) for c,r,d in zip(ear,[.049,.041,.025,.002],[.037,.032,.022,.002])],
                  lambda a,k:tan*(1-.19*k)+saddle*.19*k,20)
        inner=[(np.array(c)+[0,0,r],[wth,0,0],[0,0,.002]) for c,r,wth in zip(ear[1:],[.028,.019,.002],[.031,.017,.001])]
        face.rings(inner,linear('8d665c'),14)
    # Flat dyed hide collar with stitched edges, fitted between jaw and chest.
    center=np.array([.007,.548,.254])
    tangent=np.array([0.,-.64,.768])
    normal=np.array([0.,.768,.64])
    pts=np.asarray(body.pts)-center
    along=pts@normal
    cut=pts[(abs(along)<.018)&(np.linalg.norm(pts,axis=1)<.17)]
    angles=np.arctan2(cut@tangent,cut[:,0])
    radii=np.hypot(cut@tangent,cut[:,0])
    sample=np.linspace(0,math.tau,49)
    widths=[]
    for angle in sample:
        distance=np.abs(np.angle(np.exp(1j*(angles-angle))))
        widths.append(np.percentile(radii[distance<.14],83)+.003)
    strap_color=linear('785239')
    for k,height in enumerate([-.012,-.008,.007,.012]):
        for i,(angle,radius) in enumerate(zip(sample,widths)):
            radial=np.array([np.cos(angle),0,0])+np.sin(angle)*tangent
            collar.vertex(center+normal*height+radius*radial,[i/48,k/3],strap_color*(.72 if k in (0,3) else 1.0))
            if k and i:
                j=k*49+i
                collar.face(j-50,j-49,j,radial)
                collar.face(j-50,j,j-1,radial)
    body.pts.extend(fur.pts); body.uv.extend(fur.uv); body.tint.extend(fur.tint)
    start=len(body.pts)-len(fur.pts); body.faces.extend([tuple(start+i for i in tri) for tri in fur.faces])
    w.add('CourtyardHound',[(w.material('Sable short coat',.89),body),(w.material('Muzzle and eyes',.48),face),(w.material('Worn collar',.78),collar)])

def caps(w):
    cloth,band=Surface(),Surface()
    lathe(cloth,[(-.075,.119,.115),(-.058,.135,.127),(.014,.119,.113),(.076,.095,.087),
                 (.104,.076,.066),(.125,.042,.038),(.129,.002,.002)],linear('38414a'),40,
          lambda a,k:1+.035*np.sin(a*6+.26*k))
    lathe(band,[(-.087,.148,.131),(-.08,.157,.142),(-.068,.158,.141),(-.049,.14,.13),(-.046,.136,.126)],linear('292c32'))
    for a in np.arange(6)*math.tau/6:
        band.tube([(np.cos(a)*r,y,np.sin(a)*r*.92) for y,r in [(-.047,.133),(.015,.118),(.077,.095),(.108,.070),(.125,.039)]],
                  [.003]*5,linear('65594c'),8)
    band.ball((0,.139,0),(.022,.02,.022),linear('925244'))
    w.add('OfficialCap',[(w.material('Faded indigo velvet',.92),cloth),(w.material('Welt and bead',.64),band)])
    cloth,band=Surface(),Surface()
    lathe(cloth,[(-.068,.108,.103),(-.050,.123,.114),(.001,.118,.110),(.056,.115,.100),(.088,.102,.088),(.105,.033,.032),(.109,.002,.002)],linear('343333'),36,
          lambda a,k: (abs(np.cos(a))**5+abs(np.sin(a))**5)**(-.20)*(1+.037*np.cos(a*7+k*.2)))
    lathe(band,[(-.068,.117,.115),(-.059,.125,.12),(-.035,.124,.118)],linear('51483f'))
    for s in [-1,1]:
        band.tube([(s*.065,-.047,-.091),(s*.064,-.118,-.113),(s*.080,-.200,-.125)],[.015,.019,.010],linear('433e39'),8,.33)
    w.add('ScholarsCap',[(w.material('Ink-dyed cap'),cloth),(w.material('Folded band'),band)])
    straw,stitch=Surface(),Surface()
    radii=[(.10,.017),(.086,.065),(.058,.119),(.016,.195),(-.03,.271),(-.046,.308),(-.052,.311),(-.057,.299)]
    lathe(straw,[(y,r,r*.98) for y,r in radii],
          lambda a,k:linear('b89a6a')*(.71+.20*np.sin(a*53+k*.9)+.10*np.cos(a*27-k*.6)),144,
          lambda a,k:1+.012*k/7*np.cos(3*a))
    for y,r in [(.027,.175),(-.018,.248),(-.052,.309)]:
        pts=[(np.cos(a)*r,y+.002*np.cos(a*3),np.sin(a)*r*.98) for a in np.linspace(0,math.tau,97)]
        stitch.tube(pts,[.0035]*len(pts),linear('977952'),6)
    w.add('PlaitedRainHat',[(w.material('Split bamboo'),straw),(w.material('Bound straw edge'),stitch)])

def kit(w):
    hoops,shade=Surface(),Surface()
    lathe(shade,[(-.159,.052,.052),(-.145,.075,.075),(-.126,.085,.085),(-.06,.088,.088),(.013,.080,.080),(.029,.052,.052)],linear('f3d39c'),32)
    for y,r in [(-.157,.065),(-.14,.084),(.017,.083),(.029,.065)]:
        lathe(hoops,[(y-.003,r,r),(y+.004,r,r)],linear('604334'),32)
    for a in np.arange(8)*math.tau/8:
        hoops.tube([(np.cos(a)*r,y,np.sin(a)*r) for y,r in [(-.148,.076),(-.12,.086),(-.06,.089),(.012,.081)]],
                   [.004]*4,linear('70543c'),8)
    hoops.tube([(-.057,.027,0),(-.049,.075,0),(-.017,.11,0),(.02,.11,0),(.05,.077,0),(.057,.027,0)],[.004]*6,linear('634a3b'))
    w.add('HandLantern',[(w.material('Waxed bamboo frame',.64),hoops),(w.material('Lit paper',.9,emission=[.67,.32,.08]),shade)])
    hide,trim,brass=Surface(),Surface(),Surface()
    def pocket(y,r,z,depth):
        return ([0,y,z],[r,0,0],[0,0,depth])
    shape=[(-.136,.064,0,.031),(-.126,.101,0,.049),(-.103,.113,0,.062),(.052,.119,0,.061),(.084,.111,0,.049),(.100,.092,-.004,.031)]
    hide.rings([pocket(*p) for p in shape],linear('7c523e'),36,
               lambda a,k:(abs(np.cos(a))**4+abs(np.sin(a))**4)**(-.25))
    xs=np.linspace(-.11,.11,25)
    pts=[(x,.008+.032*(abs(x)/.11)**2,.059*(1-(abs(x)/.127)**6)) for x in xs]
    for i,x in enumerate(xs):
        front=np.sqrt(max(.05,1-(x/.131)**4))
        cross=[(x,.082,-.043*front),(x,.097,-.025*front),(x,.099,.019*front),(x,.081,.057*front),(x,.049,.065*front),pts[i]]
        for k,p in enumerate(cross):
            trim.vertex(p,[i/24,k/5],linear('92654a')*(.81+.12*(k/5)))
            if i and k:
                a=i*6+k;trim.face(a-7,a-1,a,[0,.4 if k<4 else 0,1]);trim.face(a-7,a,a-6,[0,.4 if k<4 else 0,1])
    hide.tube(pts,[.0024]*len(pts),linear('bc9373'),8)
    for x in [-.08,.08]:
        for y in np.arange(-.097,-.015,.015):
            trim.tube([(x,y,.061),(x,y+.007,.062)],[.0013,.0013],linear('b99e76'),6)
    for x in [-.080,.080]:
        # Narrow belt keepers carry the bag behind its brass rings.
        levels=[(x,.097,-.004),(x,.117,-.002),(x*.85,.173,-.020),(x*.69,.216,-.054),(x*.69,.216,-.072)]
        trim.rings([(pos,[.010,0,0],[0,0,.0035]) for pos in levels],linear('6a503e'),8)
        brass.tube([(x-.014,.089,0),(x-.017,.108,0),(x-.01,.117,0),(x+.01,.117,0),(x+.017,.108,0),(x+.014,.089,0)],[.0033]*6,linear('b79860'),8)
    brass.ball((0,.014,.065),(.013,.011,.004),linear('b39661'),16)
    w.add('BeltSatchel',[(w.material('Oiled hide',.73),hide),(w.material('Folded leather',.67),trim),(w.material('Old brass',.34,.65),brass)])

if __name__=='__main__':
    for name,func in [('courtyard_hound',hound),('headwear',caps),('field_gear',kit)]:
        writer=Writer();func(writer);writer.save(OUT/f'{name}.glb')
    coat_texture(OUT)
