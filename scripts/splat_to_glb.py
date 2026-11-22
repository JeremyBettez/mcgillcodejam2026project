"""Turn an IDOL Gaussian-splat avatar (.ply) into a rigged GLB the game can
animate like an AniGen friend.

    relay/.venv/Scripts/python scripts/splat_to_glb.py "<in.ply>" godot/demo/resident_demo.glb [--points]

Default: a smooth skinned MESH. The splat is blurred into a 3D density field,
its surface is extracted with marching cubes (skimage), small floating bits
are dropped, the result is simplified to ~MESH_TRIANGLES (fast_simplification)
and coloured per vertex from a blurred colour field. Smooth normals included.
The mesh is textured: the splat is painted from four sides (front, back, left,
right) into one 2:1 atlas, and each triangle takes texture coordinates from the
view it faces most directly, so faces and clothing keep far more detail than
per-vertex colours and sides don't streak (--no-texture for vertex colours).
With --points: the older point-cloud version (one coloured dot per splat).
Needs (tooling only, in relay/.venv): scikit-image==0.26.0, scipy==1.18.1,
fast-simplification==0.2.0.

What it does:
- Reads the splat (x, y, z, normals, f_dc colour, opacity, scale, rotation),
  keeps fairly opaque splats and thins them to ~POINTS points.
- Turns the figure upright and facing -Z (IDOL's output is upside down, facing
  +X); a 180 deg turn plus a 90 deg turn, so nothing is mirrored.
- Builds a skeleton from the body's shape, laid out like AniGen's (pelvis root;
  two 4-bone legs; spine -> chest; two 4-bone arms off the chest; neck -> head)
  so the game's procedural gait finds legs, arms, spine and neck by structure.
- Skins each point to its nearest bone segment (blended with the second
  nearest near joints) and writes a GLB with a POINTS primitive, vertex colours
  (COLOR_0) and JOINTS_0 / WEIGHTS_0. No textures, no triangles.
The game draws POINTS meshes with distance-scaled dots (glb_loader.gd).
"""

import json
import struct
import sys

import numpy as np

POINTS = 90000
MESH_TRIANGLES = 9000 # phone budget for a friend
VOXEL = 0.005 # density grid cell, in splat units (the body is ~1 unit tall)
BLUR = 1.0 # density blur, in voxels (small, so arms near the body stay separate)
TEXTURE_SIZE = 1024 # atlas height; width is 2x (front, back, left, right side by side)
MIN_OPACITY = 0.7
SEED = 7


def read_splat(path):
    raw = open(path, 'rb').read()
    end = raw.index(b'end_header\n') + len(b'end_header\n')
    header = raw[:end].decode('ascii', 'replace').splitlines()
    names = [line.split()[-1] for line in header if line.startswith('property')]
    data = np.frombuffer(raw[end:], dtype='<f4').reshape(-1, len(names))
    col = {n: i for i, n in enumerate(names)}
    pos = data[:, [col['x'], col['y'], col['z']]].astype(np.float64)
    rgb = 0.5 + 0.28209479 * data[:, [col['f_dc_0'], col['f_dc_1'], col['f_dc_2']]]
    opacity = 1.0 / (1.0 + np.exp(-data[:, col['opacity']]))
    return pos, rgb.clip(0.0, 1.0), opacity


def orient(pos):
    """Upside down, facing +X -> upright, facing -Z (180 deg about X, then 90 deg about Y)."""
    x, y, z = pos.T
    return np.stack([-z, -y, -x], axis=1)


def drop_speckles(pos, rgb, cell=0.02, limit=0.22):
    """Drop splats whose colour is far from the average of their 2 cm
    neighbourhood (stray bright/odd blobs that read as speckles)."""
    keys = np.floor(pos / cell).astype(np.int64)
    _, inverse, counts = np.unique(keys, axis=0, return_inverse=True, return_counts=True)
    inverse = inverse.ravel()
    mean = np.stack([np.bincount(inverse, rgb[:, c]) for c in range(3)], 1) / counts[:, None]
    off = np.linalg.norm(rgb - mean[inverse], axis=1)
    keep = (off < limit) | (counts[inverse] < 3)
    return pos[keep], rgb[keep]


def build_skeleton(p):
    """Skeleton from the body's shape. Works for T-poses and A-poses: each arm
    runs from the top of the torso's side to the farthest hand point, wherever
    that is. Returns (joints, height, info) where info has the body centre,
    torso half-width and each arm's shoulder and hand-tip positions."""
    ymin, ymax = np.percentile(p[:, 1], [0.1, 99.9])
    h = ymax - ymin
    legs = p[p[:, 1] < ymin + 0.4 * h]
    cx = float(np.median(legs[:, 0])) # legs are symmetric; arms may not be
    torso = p[(p[:, 1] > ymin + 0.55 * h) & (p[:, 1] < ymin + 0.75 * h)]
    cz = float(np.median(torso[:, 2]))
    leg_x = {s: np.median(legs[(legs[:, 0] - cx) * s > 0][:, 0]) for s in (-1, 1)}
    waist = p[(p[:, 1] > ymin + 0.56 * h) & (p[:, 1] < ymin + 0.62 * h)]
    torso_half = float(np.percentile(np.abs(waist[:, 0] - cx), 90))
    shoulder_y = ymin + 0.80 * h
    arms = {}
    for s in (-1, 1):
        shoulder = np.array([cx + s * torso_half * 0.9, shoulder_y, cz])
        side = p[((p[:, 0] - cx) * s > torso_half * 1.1) & (p[:, 1] > ymin + 0.3 * h)]
        if len(side):
            tip = side[np.argmax((side[:, 0] - cx) * s)].copy() # hand = farthest out sideways
            tip[2] = float(np.median(side[:, 2]))
        else:
            tip = shoulder + np.array([s * 0.3 * h, -0.3 * h, 0.0])
        arms[s] = (shoulder, tip)
    info = {'cx': cx, 'torso_half': torso_half, 'arms': arms, 'ymin': ymin}

    def at(x, y_frac, z=cz):
        return np.array([x, ymin + y_frac * h, z])

    joints = []  # (name, parent index, world position)

    def add(name, parent, pos):
        joints.append((name, parent, np.asarray(pos, dtype=np.float64)))
        return len(joints) - 1

    pelvis = add('pelvis', -1, at(cx, 0.53))
    for s, side in ((-1, 'r'), (1, 'l')):
        hip = add(f'hip_{side}', pelvis, at(leg_x[s], 0.50))
        knee = add(f'knee_{side}', hip, at(leg_x[s], 0.28))
        ankle = add(f'ankle_{side}', knee, at(leg_x[s], 0.05))
        add(f'toe_{side}', ankle, at(leg_x[s], 0.01, cz - 0.06 * h))
    spine = add('spine', pelvis, at(cx, 0.64))
    chest = add('chest', spine, at(cx, 0.76))
    for s, side in ((-1, 'r'), (1, 'l')):
        shoulder, tip = arms[s]
        clav = add(f'clavicle_{side}', chest, np.array([cx + s * 0.04 * h, shoulder[1], cz]))
        sho = add(f'shoulder_{side}', clav, shoulder)
        elb = add(f'elbow_{side}', sho, shoulder + 0.48 * (tip - shoulder))
        add(f'wrist_{side}', elb, shoulder + 0.86 * (tip - shoulder))
    neck = add('neck', chest, at(cx, 0.84))
    add('head', neck, at(cx, 0.92))
    return joints, h, info


def bone_segments(joints, h):
    """One segment per joint: from it to its first child (leaves get a short stub)."""
    segs = []
    for i, (name, _parent, pos) in enumerate(joints):
        kids = [j for j, (_n, par, _p) in enumerate(joints) if par == i]
        if kids:
            end = joints[kids[0]][2]
        elif name == 'head':
            end = pos + np.array([0, 0.09 * h, 0])
        elif name.startswith('wrist'):
            end = pos + (pos - joints[joints[i][1]][2]) * 0.6
        else:
            end = pos + np.array([0, 0, -0.03 * h])
        segs.append((pos, end))
    return segs


def skin(points, joints, h, info):
    segs = bone_segments(joints, h)
    dist = np.empty((len(points), len(segs)))
    for k, (a, b) in enumerate(segs):
        ab = b - a
        t = np.clip(((points - a) @ ab) / max(ab @ ab, 1e-9), 0.0, 1.0)
        dist[:, k] = np.linalg.norm(points - (a + t[:, None] * ab), axis=1)
    # Sleeves and arms: anything out past the torso's sides belongs to that
    # side's arm bones only, so lowering the arms doesn't tear the sleeves off.
    names = [n for n, _p, _q in joints]
    cx, torso_half = info['cx'], info['torso_half']
    nearest = np.argmin(dist, axis=1)
    lower_body = [k for k, n in enumerate(names) if n == 'pelvis' or n.split('_')[0] in ('hip', 'knee', 'ankle', 'toe')]
    near_legs = np.isin(nearest, lower_body)
    for side, sign in (('r', -1), ('l', 1)):
        shoulder, tip = info['arms'][sign]
        # The arm's zone: out past the torso, between hand and shoulder height.
        low, high = min(shoulder[1], tip[1]) - 0.04 * h, max(shoulder[1], tip[1]) + 0.08 * h
        out = ((points[:, 0] - cx) * sign > torso_half * 0.95) & (points[:, 1] > low) & (points[:, 1] < high) & ~near_legs
        arm = [names.index(f'{b}_{side}') for b in ('shoulder', 'elbow', 'wrist')]
        others = [k for k in range(len(segs)) if k not in arm]
        dist[np.ix_(out, others)] = np.inf
        # ...and the torso never follows the arms (no chest chunks stretching
        # up with a raised arm).
        inside = np.abs(points[:, 0] - cx) <= torso_half * 0.75
        dist[np.ix_(inside, arm)] = np.inf
    order = np.argsort(dist, axis=1)[:, :2]
    d1 = np.take_along_axis(dist, order[:, :1], 1)[:, 0]
    d2 = np.take_along_axis(dist, order[:, 1:2], 1)[:, 0]
    w1 = 1.0 / (d1 + 1e-3) ** 2
    w2 = np.where(d2 < d1 * 2.5, 1.0 / (d2 + 1e-3) ** 2, 0.0)
    total = w1 + w2
    joints4 = np.zeros((len(points), 4), np.uint8)
    weights4 = np.zeros((len(points), 4), np.float32)
    joints4[:, 0], joints4[:, 1] = order[:, 0], order[:, 1]
    weights4[:, 0], weights4[:, 1] = w1 / total, w2 / total
    return joints4, weights4


def make_mesh(pos, rgb):
    """Splat centres -> smooth closed surface: (vertices, faces, normals, colours)."""
    from scipy import ndimage
    from skimage import measure
    import fast_simplification

    lo = pos.min(0) - 6 * VOXEL
    hi = pos.max(0) + 6 * VOXEL
    shape = np.ceil((hi - lo) / VOXEL).astype(int) + 1
    idx = np.floor((pos - lo) / VOXEL).astype(int)
    flat = np.ravel_multi_index(idx.T, shape)
    size = int(np.prod(shape))
    density = np.bincount(flat, minlength=size).astype(np.float32).reshape(shape)
    colour = np.stack([np.bincount(flat, rgb[:, c], minlength=size).reshape(shape) for c in range(3)])
    density = ndimage.gaussian_filter(density, BLUR)
    colour = np.stack([ndimage.gaussian_filter(colour[c].astype(np.float32), BLUR * 0.7) for c in range(3)])
    weight = ndimage.gaussian_filter(np.bincount(flat, minlength=size).astype(np.float32).reshape(shape), BLUR * 0.7)
    # Surface level: a fraction of the typical density right at the splats.
    level = 0.25 * float(np.median(density[tuple(idx.T)]))
    # Keep only the big connected body (drops stray floating bits).
    labels, count = ndimage.label(density > level)
    if count > 1:
        sizes = ndimage.sum(np.ones_like(labels), labels, range(1, count + 1))
        density[labels != (1 + int(np.argmax(sizes)))] = 0.0
    verts, faces, _normals, _values = measure.marching_cubes(density, level, spacing=(VOXEL, VOXEL, VOXEL))
    verts = verts + lo
    print(f'marching cubes: {len(faces)} triangles')
    if len(faces) > MESH_TRIANGLES:
        verts, faces = fast_simplification.simplify(verts.astype(np.float32), faces.astype(np.int32),
                                                    target_reduction=1.0 - MESH_TRIANGLES / len(faces))
    verts = verts.astype(np.float64)
    # Smooth vertex normals (area weighted). marching_cubes on skimage winds
    # triangles so their normals point *into* the higher density; flip them out.
    tri = verts[faces]
    face_n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    normals = np.zeros_like(verts)
    for k in range(3):
        np.add.at(normals, faces[:, k], face_n)
    centre = verts.mean(0)
    if np.mean(np.sum(normals * (verts - centre), 1)) < 0:
        faces = faces[:, ::-1]
        normals = -normals
    normals /= np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-9)
    # Colour per vertex from the blurred colour field, sampled just inside the skin.
    coords = ((verts - normals * VOXEL - lo) / VOXEL).T
    w = ndimage.map_coordinates(weight, coords, order=1)
    cols = np.stack([ndimage.map_coordinates(colour[c], coords, order=1) for c in range(3)], 1)
    cols = (cols / np.maximum(w[:, None], 1e-6)).clip(0.0, 1.0)
    return verts, faces.astype(np.uint32), normals, cols


def paint_view(pos, rgb, axis, toward, box, width, height):
    """Orthographic picture of the splat seen along `axis` (0 = X, 2 = Z) from
    the `toward` side (-1 = from the negative side): the picture's horizontal
    is the other horizontal axis. Nearest splat wins per pixel, each splat
    covers a small footprint, then holes are filled from their neighbours."""
    (umin, ymin), (umax, ymax) = box
    across = 2 if axis == 0 else 0
    px = ((pos[:, across] - umin) / (umax - umin) * (width - 1)).round().astype(int)
    py = ((ymax - pos[:, 1]) / (ymax - ymin) * (height - 1)).round().astype(int)
    depth = pos[:, axis] * (1 if toward < 0 else -1) # smaller = nearer the viewer
    order = np.argsort(-depth) # far first, so nearer splats overwrite them
    img = np.zeros((height, width, 3), np.float32)
    zbuf = np.full((height, width), np.inf, np.float32)
    filled = np.zeros((height, width), bool)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            x = np.clip(px[order] + dx, 0, width - 1)
            y = np.clip(py[order] + dy, 0, height - 1)
            d = depth[order] + (0.002 if (dx or dy) else 0.0) # centre pixel beats neighbours' spill
            nearer = d < zbuf[y, x]
            # Later (nearer) writes win where several splats land on one pixel.
            img[y[nearer], x[nearer]] = rgb[order][nearer]
            zbuf[y[nearer], x[nearer]] = d[nearer]
            filled[y[nearer], x[nearer]] = True
    # Grow colours into the small gaps that remain (and a little past the edge,
    # so texture filtering at the silhouette never pulls in black).
    for _ in range(12):
        if filled.all():
            break
        acc = np.zeros_like(img)
        cnt = np.zeros((height, width), np.float32)
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            shifted = np.roll(np.roll(filled, dy, 0), dx, 1)
            acc += np.roll(np.roll(img, dy, 0), dx, 1) * shifted[..., None]
            cnt += shifted
        grow = ~filled & (cnt > 0)
        img[grow] = acc[grow] / cnt[grow][:, None]
        filled |= grow
    return img


def bake_texture(pos, rgb, verts, faces, normals):
    """Give each triangle the view (front/back/left/right) it faces most
    directly, lay the four views side by side in one atlas (widths in
    proportion to the body), set UVs and paint the views. Returns
    (verts, faces, normals, uvs, source_vertex_index, png_bytes)."""
    import io
    from PIL import Image

    pad = 0.02
    lo, hi = verts.min(0) - pad, verts.max(0) + pad
    tri = verts[faces]
    face_n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    # View per face: 0 front (-Z), 1 back (+Z), 2 left (-X), 3 right (+X).
    z_dominant = np.abs(face_n[:, 2]) >= np.abs(face_n[:, 0])
    view = np.where(z_dominant, np.where(face_n[:, 2] < 0, 0, 1), np.where(face_n[:, 0] < 0, 2, 3))
    # Atlas columns: front and back are as wide as the body, sides as deep.
    spans = [hi[0] - lo[0], hi[0] - lo[0], hi[2] - lo[2], hi[2] - lo[2]]
    total = sum(spans)
    width = TEXTURE_SIZE * 2
    px_w = [max(8, int(width * sp / total)) for sp in spans]
    px_w[0] += width - sum(px_w) # rounding slack goes to the front view
    starts = np.cumsum([0] + px_w[:-1])
    # One vertex copy per (vertex, view) so views never share a vertex.
    keys = faces.astype(np.int64) * 4 + view[:, None]
    unique, inverse = np.unique(keys.reshape(-1), return_inverse=True)
    new_faces = inverse.reshape(faces.shape).astype(np.uint32)
    source = unique // 4
    vview = unique % 4
    nv = verts[source]
    across = np.where(vview < 2, nv[:, 0], nv[:, 2])
    amin = np.where(vview < 2, lo[0], lo[2])
    span = np.where(vview < 2, hi[0] - lo[0], hi[2] - lo[2])
    u = (starts[vview] + (across - amin) / span * (np.array(px_w)[vview] - 1) + 0.5) / width
    v = (hi[1] - nv[:, 1]) / (hi[1] - lo[1])
    uvs = np.stack([u, v], 1).astype(np.float32)
    boxes = [((lo[0], lo[1]), (hi[0], hi[1]))] * 2 + [((lo[2], lo[1]), (hi[2], hi[1]))] * 2
    views = [(2, -1), (2, 1), (0, -1), (0, 1)]
    atlas = np.concatenate([paint_view(pos, rgb, ax, tw, boxes[i], px_w[i], TEXTURE_SIZE)
                            for i, (ax, tw) in enumerate(views)], 1)
    buf = io.BytesIO()
    Image.fromarray((atlas.clip(0, 1) * 255).round().astype(np.uint8)).save(buf, 'PNG', optimize=True)
    return verts[source], new_faces, normals[source], uvs, source, buf.getvalue()


def cut_bridges(faces, joints, joints4):
    """Drop triangles that join an arm to the body somewhere other than the
    shoulder (e.g. a hand that was touching the hip in the scan): when the arm
    moves they would stretch into webs. Only tiny contact patches go missing."""
    names = [n for n, _p, _q in joints]
    primary = joints4[:, 0].astype(int)
    keep = np.ones(len(faces), bool)
    for side in ('r', 'l'):
        arm = [names.index(f'{b}_{side}') for b in ('shoulder', 'elbow', 'wrist')]
        lower_arm = arm[1:]
        allowed = set(arm) | {names.index(f'clavicle_{side}'), names.index('chest')}
        bones = primary[faces]
        has_lower = np.isin(bones, lower_arm).any(1)
        has_shoulder = np.isin(bones, arm[:1]).any(1)
        lower_ok = np.isin(bones, arm).all(1) # forearm/hand only touch their own arm
        upper_ok = np.isin(bones, list(allowed)).all(1)
        keep &= ~(has_lower & ~lower_ok) & ~(has_shoulder & ~upper_ok)
    print(f'cut {int((~keep).sum())} bridging triangles')
    return faces[keep]


def write_glb(path, points, colors, joints, joints4, weights4, faces=None, normals=None, uvs=None, png=None):
    blobs, views, accessors = [], [], []

    def add_view(data, target=None):
        offset = sum(len(b) for b in blobs)
        blob = data.tobytes()
        blob += b'\0' * ((4 - len(blob) % 4) % 4)
        blobs.append(blob)
        view = {'buffer': 0, 'byteOffset': offset, 'byteLength': len(data.tobytes())}
        if target:
            view['target'] = target
        views.append(view)
        return len(views) - 1

    def add_accessor(data, comp, kind, normalized=False, minmax=False, target=34962):
        acc = {'bufferView': add_view(data, target), 'componentType': comp, 'count': len(data), 'type': kind}
        if normalized:
            acc['normalized'] = True
        if minmax:
            acc['min'] = data.min(0).tolist()
            acc['max'] = data.max(0).tolist()
        accessors.append(acc)
        return len(accessors) - 1

    pos_acc = add_accessor(points.astype(np.float32), 5126, 'VEC3', minmax=True)
    extra = {}
    if normals is not None:
        extra['NORMAL'] = add_accessor(normals.astype(np.float32), 5126, 'VEC3')
    if uvs is not None:
        extra['TEXCOORD_0'] = add_accessor(uvs, 5126, 'VEC2')
    col_acc = None
    if colors is not None:
        rgba = np.concatenate([(colors * 255).round().astype(np.uint8), np.full((len(colors), 1), 255, np.uint8)], 1)
        col_acc = add_accessor(rgba, 5121, 'VEC4', normalized=True)
    jnt_acc = add_accessor(joints4, 5121, 'VEC4')
    wgt_acc = add_accessor(weights4, 5126, 'VEC4')
    ibm = np.stack([np.array([[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [-p[0], -p[1], -p[2], 1]], np.float32)
                    for _n, _par, p in joints]).reshape(len(joints), 16)
    ibm_acc = add_accessor(ibm, 5126, 'MAT4', target=None)

    nodes = []
    for i, (name, parent, pos) in enumerate(joints):
        local = pos - (joints[parent][2] if parent >= 0 else 0)
        kids = [j for j, (_n, par, _p) in enumerate(joints) if par == i]
        node = {'name': name, 'translation': [float(v) for v in local]}
        if kids:
            node['children'] = kids
        nodes.append(node)
    mesh_node = len(nodes)
    nodes.append({'name': 'Avatar', 'mesh': 0, 'skin': 0})
    attributes = {'POSITION': pos_acc, 'JOINTS_0': jnt_acc, 'WEIGHTS_0': wgt_acc, **extra}
    if col_acc is not None:
        attributes['COLOR_0'] = col_acc
    primitive = {'mode': 0 if faces is None else 4, 'attributes': attributes}
    material = {'name': 'Skin', 'pbrMetallicRoughness': {'baseColorFactor': [1, 1, 1, 1],
                                                         'metallicFactor': 0.0, 'roughnessFactor': 0.9}}
    textures = {}
    if png is not None:
        image_view = add_view(np.frombuffer(png, np.uint8))
        material['pbrMetallicRoughness']['baseColorTexture'] = {'index': 0}
        textures = {
            'images': [{'bufferView': image_view, 'mimeType': 'image/png'}],
            'samplers': [{'magFilter': 9729, 'minFilter': 9987, 'wrapS': 33071, 'wrapT': 33071}],
            'textures': [{'source': 0, 'sampler': 0}],
        }
    if faces is not None:
        primitive['indices'] = add_accessor(faces.reshape(-1), 5125, 'SCALAR', target=34963)
        primitive['material'] = 0
    gltf = {
        'asset': {'version': '2.0', 'generator': 'photo-town splat_to_glb.py'},
        'scene': 0,
        'scenes': [{'nodes': [0, mesh_node]}],
        'nodes': nodes,
        'meshes': [{'name': 'Avatar', 'primitives': [primitive]}],
        'materials': [material],
        **textures,
        'skins': [{'joints': list(range(len(joints))), 'inverseBindMatrices': ibm_acc, 'skeleton': 0}],
        'accessors': accessors,
        'bufferViews': views,
        'buffers': [{'byteLength': sum(len(b) for b in blobs)}],
    }
    js = json.dumps(gltf, separators=(',', ':')).encode()
    js += b' ' * ((4 - len(js) % 4) % 4)
    binary = b''.join(blobs)
    with open(path, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(binary)))
        f.write(struct.pack('<II', len(js), 0x4E4F534A) + js)
        f.write(struct.pack('<II', len(binary), 0x004E4942) + binary)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if len(args) != 2:
        sys.exit('Usage: python scripts/splat_to_glb.py <in.ply> <out.glb> [--points]')
    sys.argv[1:3] = args
    pos, rgb, opacity = read_splat(sys.argv[1])
    keep = opacity > MIN_OPACITY
    pos, rgb = orient(pos[keep]), rgb[keep]
    before = len(pos)
    pos, rgb = drop_speckles(pos, rgb)
    print(f'dropped {before - len(pos)} speckle splats')
    if '--points' not in sys.argv:
        joints, h, info = build_skeleton(pos)
        verts, faces, normals, cols = make_mesh(pos, rgb)
        joints4, weights4 = skin(verts, joints, h, info)
        faces = cut_bridges(faces, joints, joints4)
        if '--no-texture' in sys.argv:
            write_glb(sys.argv[2], verts, cols, joints, joints4, weights4, faces, normals)
        else:
            verts, faces, normals, uvs, source, png = bake_texture(pos, rgb, verts, faces, normals)
            write_glb(sys.argv[2], verts, None, joints, joints4[source], weights4[source], faces, normals, uvs, png)
            print(f'texture: {TEXTURE_SIZE * 2}x{TEXTURE_SIZE}, {len(png) // 1024} KB')
        print(f'mesh: {len(verts)} vertices, {len(faces)} triangles, {len(joints)} joints -> {sys.argv[2]}')
        return
    rng = np.random.default_rng(SEED)
    pick = rng.choice(len(pos), size=min(POINTS, len(pos)), replace=False)
    pos, rgb = pos[pick], rgb[pick]
    joints, h, info = build_skeleton(pos)
    joints4, weights4 = skin(pos, joints, h, info)
    write_glb(sys.argv[2], pos, rgb, joints, joints4, weights4)
    print(f'{len(pos)} points, {len(joints)} joints, height {h:.3f} -> {sys.argv[2]}')


if __name__ == '__main__':
    main()
