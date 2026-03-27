#!/usr/bin/env python3
"""
Generate valid glTF 2.0 binary (.glb) placeholder models.
- JSON chunk padding: 0x20 (space) per spec
- Each item gets a distinct shape / color
"""
import struct, math, os

OUT = "/home/piacere/claude/vrex_server/priv/static/glb"

def pack_f32(*vals):
    return struct.pack(f"<{len(vals)}f", *vals)

def pack_u16(*vals):
    return struct.pack(f"<{len(vals)}H", *vals)

def build_glb(vertices, normals, indices, color):
    """
    vertices : list of (x,y,z)
    normals  : list of (nx,ny,nz)
    indices  : list of int (triangles)
    color    : (r,g,b,a) 0.0-1.0
    """
    # ── バイナリバッファ ──────────────────────────────────
    pos_bytes  = b"".join(pack_f32(*v) for v in vertices)   # VEC3 float32
    norm_bytes = b"".join(pack_f32(*n) for n in normals)
    idx_bytes  = b"".join(pack_u16(i)  for i in indices)
    # uint16 は 4バイトアライン
    if len(idx_bytes) % 4:
        idx_bytes += b"\x00" * (4 - len(idx_bytes) % 4)

    bin_buffer = pos_bytes + norm_bytes + idx_bytes

    pos_bvlen  = len(pos_bytes)
    norm_bvlen = len(norm_bytes)
    idx_bvlen  = len(idx_bytes)
    buf_len    = len(bin_buffer)

    # ── JSON ─────────────────────────────────────────────
    json_str = (
        '{"asset":{"version":"2.0"},'
        '"scene":0,'
        '"scenes":[{"nodes":[0]}],'
        '"nodes":[{"mesh":0}],'
        '"meshes":[{"primitives":[{"attributes":{"POSITION":0,"NORMAL":1},'
        '"indices":2,"material":0,"mode":4}]}],'
        f'"materials":[{{"pbrMetallicRoughness":{{'
        f'"baseColorFactor":[{color[0]},{color[1]},{color[2]},{color[3]}],'
        '"metallicFactor":0.1,"roughnessFactor":0.7}}}}],'
        f'"accessors":['
        f'{{"bufferView":0,"componentType":5126,"count":{len(vertices)},"type":"VEC3"}},'
        f'{{"bufferView":1,"componentType":5126,"count":{len(normals)},"type":"VEC3"}},'
        f'{{"bufferView":2,"componentType":5123,"count":{len(indices)},"type":"SCALAR"}}],'
        f'"bufferViews":['
        f'{{"buffer":0,"byteOffset":0,"byteLength":{pos_bvlen}}},'
        f'{{"buffer":0,"byteOffset":{pos_bvlen},"byteLength":{norm_bvlen}}},'
        f'{{"buffer":0,"byteOffset":{pos_bvlen+norm_bvlen},"byteLength":{idx_bvlen}}}],'
        f'"buffers":[{{"byteLength":{buf_len}}}]}}'
    )
    json_bytes = json_str.encode("utf-8")
    # 4バイトアライン: spec は 0x20(space) でパディング
    pad = (4 - len(json_bytes) % 4) % 4
    json_bytes += b"\x20" * pad

    # ── GLBヘッダ + chunks ────────────────────────────────
    total = 12 + 8 + len(json_bytes) + 8 + len(bin_buffer)
    header     = struct.pack("<4sII", b"glTF", 2, total)
    json_chunk = struct.pack("<II", len(json_bytes), 0x4E4F534A) + json_bytes
    bin_chunk  = struct.pack("<II", len(bin_buffer),  0x004E4942) + bin_buffer

    return header + json_chunk + bin_chunk


# ── プリミティブ生成ヘルパー ─────────────────────────────

def box(sx, sy, sz):
    """軸平行ボックス (sx,sy,sz=半径)"""
    # 各面に4頂点・4法線、時計回りインデックス
    faces = [
        # +X
        ([ (sx,-sy,-sz),(sx, sy,-sz),(sx, sy, sz),(sx,-sy, sz)], ( 1, 0, 0)),
        # -X
        ([(-sx,-sy, sz),(-sx, sy, sz),(-sx, sy,-sz),(-sx,-sy,-sz)], (-1, 0, 0)),
        # +Y
        ([(-sx, sy,-sz),(-sx, sy, sz),( sx, sy, sz),( sx, sy,-sz)], ( 0, 1, 0)),
        # -Y
        ([(-sx,-sy, sz),(-sx,-sy,-sz),( sx,-sy,-sz),( sx,-sy, sz)], ( 0,-1, 0)),
        # +Z
        ([(-sx,-sy, sz),( sx,-sy, sz),( sx, sy, sz),(-sx, sy, sz)], ( 0, 0, 1)),
        # -Z
        ([( sx,-sy,-sz),(-sx,-sy,-sz),(-sx, sy,-sz),( sx, sy,-sz)], ( 0, 0,-1)),
    ]
    verts, norms, idxs = [], [], []
    for pts, n in faces:
        base = len(verts)
        verts += pts
        norms += [n] * 4
        idxs  += [base, base+1, base+2, base, base+2, base+3]
    return verts, norms, idxs

def cylinder(r, h, seg=16):
    """円柱 (r=半径, h=高さ, seg=分割数)"""
    verts, norms, idxs = [], [], []
    # 側面
    for i in range(seg):
        a0 = 2*math.pi * i / seg
        a1 = 2*math.pi * (i+1) / seg
        x0,z0 = r*math.cos(a0), r*math.sin(a0)
        x1,z1 = r*math.cos(a1), r*math.sin(a1)
        base = len(verts)
        verts += [(x0,-h,z0),(x1,-h,z1),(x1,h,z1),(x0,h,z0)]
        nx0,nz0 = math.cos(a0), math.sin(a0)
        nx1,nz1 = math.cos(a1), math.sin(a1)
        norms += [(nx0,0,nz0),(nx1,0,nz1),(nx1,0,nz1),(nx0,0,nz0)]
        idxs  += [base,base+1,base+2,base,base+2,base+3]
    # 上下キャップ
    for sign, ny in [(1, 1), (-1, -1)]:
        base = len(verts)
        # 中心
        verts.append((0, sign*h, 0)); norms.append((0, ny, 0))
        for i in range(seg):
            a = 2*math.pi * i / seg
            verts.append((r*math.cos(a), sign*h, r*math.sin(a)))
            norms.append((0, ny, 0))
        for i in range(seg):
            if ny > 0:
                idxs += [base, base+1+i, base+1+(i+1)%seg]
            else:
                idxs += [base, base+1+(i+1)%seg, base+1+i]
    return verts, norms, idxs

def cone(r, h, seg=12):
    """円錐"""
    verts, norms, idxs = [], [], []
    slope = r / math.sqrt(r*r + h*h)
    vslope = h / math.sqrt(r*r + h*h)
    for i in range(seg):
        a0 = 2*math.pi * i / seg
        a1 = 2*math.pi * (i+1) / seg
        x0,z0 = r*math.cos(a0), r*math.sin(a0)
        x1,z1 = r*math.cos(a1), r*math.sin(a1)
        base = len(verts)
        verts += [(0, h, 0), (x0, 0, z0), (x1, 0, z1)]
        norms += [(math.cos(a0)*vslope, slope, math.sin(a0)*vslope),
                  (math.cos(a0)*vslope, slope, math.sin(a0)*vslope),
                  (math.cos(a1)*vslope, slope, math.sin(a1)*vslope)]
        idxs  += [base, base+1, base+2]
    # 底面
    base = len(verts)
    verts.append((0, 0, 0)); norms.append((0,-1,0))
    for i in range(seg):
        a = 2*math.pi * i / seg
        verts.append((r*math.cos(a), 0, r*math.sin(a))); norms.append((0,-1,0))
    for i in range(seg):
        idxs += [base, base+1+(i+1)%seg, base+1+i]
    return verts, norms, idxs

def sphere(r, lat=10, lon=16):
    """球"""
    verts, norms, idxs = [], [], []
    for i in range(lat+1):
        phi = math.pi * i / lat - math.pi/2
        for j in range(lon+1):
            theta = 2*math.pi * j / lon
            x = math.cos(phi)*math.cos(theta)
            y = math.sin(phi)
            z = math.cos(phi)*math.sin(theta)
            verts.append((r*x, r*y, r*z))
            norms.append((x, y, z))
    for i in range(lat):
        for j in range(lon):
            a = i*(lon+1)+j
            idxs += [a, a+1, a+lon+1, a+1, a+lon+2, a+lon+1]
    return verts, norms, idxs

def torus(R, r, seg=20, tube=12):
    """トーラス"""
    verts, norms, idxs = [], [], []
    for i in range(seg+1):
        phi = 2*math.pi * i / seg
        cx, cz = R*math.cos(phi), R*math.sin(phi)
        for j in range(tube+1):
            theta = 2*math.pi * j / tube
            x = (R + r*math.cos(theta))*math.cos(phi)
            y = r*math.sin(theta)
            z = (R + r*math.cos(theta))*math.sin(phi)
            nx = math.cos(theta)*math.cos(phi)
            ny = math.sin(theta)
            nz = math.cos(theta)*math.sin(phi)
            verts.append((x,y,z)); norms.append((nx,ny,nz))
    for i in range(seg):
        for j in range(tube):
            a = i*(tube+1)+j
            idxs += [a, a+1, a+tube+1, a+1, a+tube+2, a+tube+1]
    return verts, norms, idxs

def pyramid(base, height):
    """四角錐"""
    h = (0, height, 0)
    pts = [(-base,-base/4,-base),(base,-base/4,-base),(base,-base/4,base),(-base,-base/4,base)]
    verts, norms, idxs = [], [], []
    # 側面 4面
    for i in range(4):
        p0 = pts[i]; p1 = pts[(i+1)%4]
        base_i = len(verts)
        verts += [h, p0, p1]
        # 法線
        ax,ay,az = p0[0]-h[0], p0[1]-h[1], p0[2]-h[2]
        bx,by,bz = p1[0]-h[0], p1[1]-h[1], p1[2]-h[2]
        nx,ny,nz = ay*bz-az*by, az*bx-ax*bz, ax*by-ay*bx
        l = math.sqrt(nx*nx+ny*ny+nz*nz)
        norms += [(nx/l,ny/l,nz/l)]*3
        idxs  += [base_i, base_i+1, base_i+2]
    # 底面
    base_i = len(verts)
    for p in pts: verts.append(p); norms.append((0,-1,0))
    idxs += [base_i, base_i+2, base_i+1, base_i, base_i+3, base_i+2]
    return verts, norms, idxs

def combine(*shapes):
    verts, norms, idxs = [], [], []
    for v, n, i in shapes:
        offset = len(verts)
        verts += v; norms += n
        idxs  += [x+offset for x in i]
    return verts, norms, idxs

# ── アイテム定義 ─────────────────────────────────────────────────────
# (ファイル名, shape関数呼び出し, RGBA色)

ITEMS = [
    # 自然系
    ("campfire",        combine(cylinder(0.3,0.1), cone(0.25,0.6)),     (0.9,0.3,0.05,1.0)),
    ("palm_tree",       combine(cylinder(0.08,0.8), cone(0.5,0.4)),     (0.2,0.6,0.1,1.0)),
    ("sakura_tree",     combine(cylinder(0.07,0.7), sphere(0.45)),       (0.98,0.7,0.8,1.0)),
    ("snowman",         combine(sphere(0.3), sphere(0.22), sphere(0.15)),(0.95,0.95,1.0,1.0)),
    ("koi_fish",        combine(sphere(0.25), cone(0.15,0.3)),           (1.0,0.4,0.1,1.0)),

    # 建築・家具系
    ("throne",          combine(box(0.3,0.5,0.25), box(0.3,0.1,0.05)),  (0.7,0.5,0.1,1.0)),
    ("altar",           combine(box(0.5,0.15,0.5), box(0.3,0.3,0.3)),   (0.5,0.4,0.7,1.0)),
    ("engawa",          combine(box(0.8,0.06,0.35)),                     (0.6,0.4,0.2,1.0)),
    ("stage",           combine(box(0.9,0.12,0.6)),                      (0.4,0.3,0.2,1.0)),
    ("observation_deck",combine(box(0.7,0.08,0.7), cylinder(0.04,0.5)), (0.4,0.5,0.6,1.0)),
    ("old_well",        combine(cylinder(0.3,0.3), cylinder(0.32,0.02)), (0.5,0.45,0.35,1.0)),
    ("stone_lantern",   combine(box(0.15,0.4,0.15), box(0.2,0.1,0.2)),  (0.55,0.55,0.5,1.0)),
    ("default_floor",   combine(box(1.0,0.02,1.0)),                      (0.4,0.4,0.4,1.0)),

    # 機器・道具系
    ("scoreboard",      combine(box(0.6,0.4,0.04), box(0.05,0.5,0.05)), (0.15,0.15,0.2,1.0)),
    ("info_board",      combine(box(0.5,0.35,0.03), box(0.04,0.45,0.04)),(0.3,0.4,0.6,1.0)),
    ("music_player",    combine(box(0.25,0.2,0.12), cylinder(0.1,0.01)), (0.2,0.2,0.3,1.0)),
    ("speaker",         combine(box(0.2,0.3,0.15), cone(0.12,0.05)),    (0.15,0.15,0.15,1.0)),
    ("control_console", combine(box(0.5,0.3,0.25), box(0.4,0.05,0.2)),  (0.1,0.2,0.15,1.0)),
    ("spacesuit_rack",  combine(box(0.25,0.5,0.15), box(0.35,0.02,0.2)),(0.7,0.7,0.75,1.0)),
    ("earth_window",    combine(box(0.5,0.5,0.04), sphere(0.3)),        (0.2,0.4,0.8,1.0)),
    ("start_button",    combine(box(0.2,0.08,0.2), cylinder(0.08,0.05)),(0.9,0.1,0.1,1.0)),

    # 武器・道具
    ("weapon_rack",     combine(box(0.5,0.4,0.08), box(0.02,0.4,0.02)), (0.4,0.3,0.2,1.0)),
    ("scroll_shelf",    combine(box(0.45,0.35,0.1), cylinder(0.04,0.3)), (0.6,0.5,0.3,1.0)),
    ("target",          combine(torus(0.3,0.04), cylinder(0.04,0.3)),    (0.9,0.2,0.2,1.0)),
    ("training_log",    combine(cylinder(0.2,0.4)),                      (0.5,0.35,0.2,1.0)),

    # ファンタジー系
    ("glowing_orb",     combine(sphere(0.25)),                           (0.4,0.8,1.0,1.0)),
    ("magic_mirror",    combine(box(0.35,0.5,0.04), box(0.4,0.55,0.02)),(0.7,0.5,0.9,1.0)),
    ("teleport_gate",   combine(torus(0.45,0.06), cylinder(0.04,0.5)),  (0.3,0.9,0.9,1.0)),
    ("goal_gate",       combine(box(0.5,0.04,0.04), box(0.04,0.5,0.04)),(0.9,0.8,0.1,1.0)),
    ("spotlight",       combine(cylinder(0.1,0.2), cone(0.18,0.3)),     (0.8,0.8,0.4,1.0)),
    ("mountain_stele",  combine(box(0.15,0.6,0.08)),                     (0.5,0.5,0.45,1.0)),
    ("item_box",        combine(box(0.3,0.3,0.3)),                       (0.7,0.6,0.1,1.0)),
    ("wall_painting",   combine(box(0.5,0.4,0.02), box(0.48,0.38,0.01)),(0.8,0.6,0.3,1.0)),
]

for fname, (verts, norms, idxs), color in ITEMS:
    glb = build_glb(verts, norms, idxs, color)
    path = os.path.join(OUT, f"{fname}.glb")
    with open(path, "wb") as f:
        f.write(glb)
    print(f"  {fname}.glb  ({len(glb)}B, {len(verts)}verts, {len(idxs)//3}tris)")

print(f"\n合計 {len(ITEMS)} ファイル生成完了")
