"""Bake the motionless upper-body pose seen down the title street.

Reuses the gameplay walker, Quaternius skin and the fitted long coat. Only
visible skin, shoes and cloth are kept. Vertex colours carry the distant dye
and features, so opening the title does not load combat skeletons or animations.
"""
from pathlib import Path

import numpy as np
from PIL import Image

from folk_mesh import Surface, Writer, linear, read_glb, unpack

ROOT = Path(__file__).resolve().parents[2]
FOLK = ROOT / 'assets/models/folk'
CAST = ROOT / 'assets/models/characters'


def paint_texture(path, uv):
    with Image.open(path) as image:
        srgb = np.asarray(image.convert('RGB'), dtype=float) / 255.
    h, w = srgb.shape[:2]
    color = srgb[(uv[:, 1].clip(0, 1)*(h-1)).astype(int),
                 (uv[:, 0].clip(0, 1)*(w-1)).astype(int)]
    return np.where(color < .04045, color/12.92, ((color+.055)/1.055)**2.4)


def posed(doc, blob, attrs, points):
    joints = unpack(doc, blob, attrs['JOINTS_0'])
    weights = unpack(doc, blob, attrs['WEIGHTS_0'])
    weights = weights / np.maximum(weights.sum(axis=1, keepdims=True), 1e-6)
    bones = [doc['nodes'][j]['name'] for j in doc['skins'][0]['joints']]
    arm = np.array([name.startswith(('upperarm', 'lowerarm', 'hand', 'index',
                                     'middle', 'ring', 'pinky', 'thumb')) for name in bones])
    amount = (arm[joints]*weights).sum(axis=1)
    x, y, z = points.T
    side = np.sign(x)
    forward = abs(x) - .177
    lifted = np.column_stack((side*(.177-(z+.045)), y-.095*forward, -.045+forward))
    return points + (lifted-points)*amount[:, None]


def add_piece(parts, doc, blob, primitive, name, clothing):
    attrs = primitive['attributes']
    points = unpack(doc, blob, attrs['POSITION'])
    uv = unpack(doc, blob, attrs['TEXCOORD_0']) if 'TEXCOORD_0' in attrs else None
    faces = unpack(doc, blob, primitive['indices']).reshape(-1, 3)
    if clothing:
        colors = dict(Robe='253349', Pants='20252c', Shoes='45392f', Binding='485367')
        tint = linear(colors[name])*unpack(doc, blob, attrs['COLOR_0'])[:, :3]
    elif name == 'MI_Superhero_Male':
        exposed = (points[:, 1] > 1.541) | ((abs(points[:, 0]) > .697) & (points[:, 1] > 1.19))
        faces = faces[np.any(exposed[faces], axis=1)]
        tint = paint_texture(FOLK/'weathered_skin.jpg', uv)
    elif name.startswith('MI_Hair'):
        tint = paint_texture(CAST/'male_long_T_Hair_1_BaseColor.png', uv)*linear('726453')
    elif name == 'MI_Eyes':
        tint = paint_texture(CAST/'male_long_T_Eye_Brown.png', uv)
    else:
        return
    points = posed(doc, blob, attrs, points)
    # Cluster at 6 mm: keep the mouth profile and separated fingertips. Discard
    # triangles that collapse, retain original winding, and recompute smooth normals.
    groups = np.zeros(len(faces), dtype=int)
    # The robe hides the hip joints. Put each trouser cuff and shoe on its old
    # animated knee pivot so it still kicks forward on the hopping title loop.
    if clothing and name in ('Pants', 'Shoes', 'Binding'):
        centers = points[faces].mean(axis=1)
        below = centers[:, 1] < .40
        groups[below] = np.where(centers[below, 0] < 0, 1, 2)
    for index, target in enumerate(parts):
        face_set = faces[groups == index]
        if len(face_set):
            store_geometry(target, points, tint, face_set, .003 if name == 'Binding' else .006)


def store_geometry(target, points, tint, faces, cell_size):
    kept, references = np.unique(faces, return_inverse=True)
    _, cells = np.unique(np.rint(points[kept]/cell_size).astype(int), axis=0, return_inverse=True)
    count = np.bincount(cells)
    def means(values):
        return np.array([np.bincount(cells, weights=col)/count for col in values[kept].T]).T
    vertices, colors = means(points), means(tint)
    indices = cells[references].reshape(-1, 3)
    valid = (indices[:,0]!=indices[:,1]) & (indices[:,1]!=indices[:,2]) & (indices[:,0]!=indices[:,2])
    offset = len(target.pts)
    for v, c in zip(vertices, colors):
        target.vertex(v, [0., 0.], c)
    target.faces.extend(map(tuple, indices[valid]+offset))


def bake():
    parts = [Surface() for _ in range(3)]
    for file, clothing in [(CAST/'male_long.glb', False), (FOLK/'coat_male_long.glb', True)]:
        doc, blob = read_glb(file)
        for mesh in doc['meshes']:
            for primitive in mesh['primitives']:
                mat = doc['materials'][primitive['material']]['name']
                add_piece(parts, doc, blob, primitive, mat, clothing)
    writer = Writer()
    dye = writer.material('Slate mourning coat', .9)
    for name, part in zip(('StreetFigure','LeftFoot','RightFoot'), parts):
        writer.add(name, [(dye, part)])
    writer.save(FOLK/'title_walker.glb')


if __name__ == '__main__':
    bake()
