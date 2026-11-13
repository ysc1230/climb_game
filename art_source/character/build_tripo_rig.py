"""Tripo 캐릭터 → 게임용 리깅 모델. 2026-11-13 더미 몸 기준(docs/39)으로 고침.
실행: TRIPO_CHAR=male|female blender -b --python art_source/character/build_tripo_rig.py
입력: CFG의 Tripo 원본 glb(키 1.0으로 정규화된 T자, 앞 +X). 출력: CFG의 game/art/characters/*.glb

게임 몸(더미, docs/39 — Tuning·ClimberPose와 같아야 한다. 골반 관절 = 원점, 위 +Z, 앞 +Y, m):
  어깨 (±0.175, 0.49) · 위팔 0.35 · 팔꿈치→손 접점(손가락 뿌리) 0.38 · 손가락 0.07(hand 0.035 + finger 0.035)
  고관절 (±0.095, 0) · 허벅지 0.41 · 정강이 0.40(발목 −0.81) · 발목→발끝 0.20(앞 0.19, 아래 0.09)
  척추 0.16 · 가슴 0.37 · 목 0.49 · 머리 0.56 · 머리 꼭대기 0.81
원본마다 정규화 높이로 잰 기준점(CFG landmarks: 팔 중심선, 발목 관절, 무릎, 손끝, 가랑이)으로 맞춘다:
1. 놓기: Z +90°(앞 +X → +Y). 어깨~발목(1.30m)이 맞게 크기를 정하고, 어깨가 0.49에 오게 올린다.
2. 줄이기: 같은 위치 정점 붙이기(UV 경계 틈 방지) → Decimate(접기) → TRIS 삼각형. UV 유지.
3. 다리 맞추기: 고관절(0)~발목 사이 높이를 구간별로 옮겨 원본 무릎이 −0.41에 오게 한다(발목은 1에서 맞음).
   가랑이 올리기(crotch_lift, 선택): 다리 안쪽만 가랑이 꼭짓점을 올린다.
4. 팔 맞추기: 손끝이 0.975에 오게 |x| ≥ 0.14인 팔 부분을 길이 방향으로만 늘이거나 줄인다.
5. 뼈대: RigPose.BONES 17개 + finger_L/R + 엉덩이 보조 hiphelp_L/R. 팔·다리 뼈의 앞뒤(y)는 메시에서 잰 중심선.
6. 가중치: 부위·위치로 직접 준다(관절 경계는 선형으로 섞음). 팔은 어깨에서 거리로(손바닥은 아래팔), 다리·몸통은 높이로,
   머리카락·머리는 head, 초크백은 pelvis. 골반 → 엉덩이 보조 → 허벅지로 잇고, 가랑이 가운데는 두 다리가 반씩 따른다.
7. 재질: 색 텍스처만(1024), 금속 0. 윤곽선 굵기(정점 색 R): 엉덩이골·가랑이 가운데는 0(docs/37 §7).
참고 그림은 그림자·주름 없이 단색 + 외곽선으로(구운 음영이 엉덩이 얼룩이 된다, docs/37 §7).
"""
import bpy, math, os
import numpy as np
from mathutils import Vector

REPO = os.path.expanduser("~/Projects/climb_game")
CHAR = os.environ.get("TRIPO_CHAR", "male")
# landmarks: 정규화 높이(발바닥 0, 키 1)에서 잰 값. shoulder = 팔 중심선 높이, ankle = 발목 관절 높이, knee = 무릎 높이,
# tip = 손끝 |x|, crotch = 가랑이 높이. chalk: 정규화 좌표(x 오른쪽, y 앞, z 위)로 초크백 정점 판별.
CFG = {
    # 남성 v2(2026-11-13, task a621f6bb, art_source/character/male)
    "male": {"src": "art_source/character/male/climber_male_v2_base.glb", "out": "game/art/characters/climber_male.glb",
             "mesh": "P_body_male", "tex": "climber_male_color",
             "landmarks": {"shoulder": 0.762, "ankle": 0.03, "knee": 0.245, "tip": 0.409, "crotch": 0.405},
             "crotch_lift": 0.05,
             "chalk": lambda x, y, z: 0.46 < z < 0.55 and (x > 0.093 or (x > 0.06 and y < -0.06))},
    # 여성(2026-11-12, task e606f7d8, art_source/character/female). 초크백은 왼쪽 허리
    "female": {"src": "art_source/character/female/climber_female_base.glb", "out": "game/art/characters/climber_female.glb",
               "mesh": "P_body_female", "tex": "climber_female_color",
               "landmarks": {"shoulder": 0.743, "ankle": 0.045, "knee": 0.265, "tip": 0.434, "crotch": 0.44},
               "crotch_lift": 0.0,
               "chalk": lambda x, y, z: 0.50 < z < 0.60 and (x < -0.094 or (x < -0.06 and y < -0.075))},
    # 매끈한 남성(2026-11-13, main 15f44d9, Tripo P1 task 1f0174d2): game/art/characters/climber_smooth_base.glb.
    # 초크백은 따로 떨어진 덩어리(앞뒤 주머니 두 겹으로 생성됨) → 뒤쪽(y < −0.02)만 남긴다.
    "smooth": {"src": "art_source/character/smooth/climber_smooth_base.glb", "out": "game/art/characters/climber_smooth.glb",
               "mesh": "P_body_smooth", "tex": "climber_smooth_color",
               "landmarks": {"shoulder": 0.775, "ankle": 0.065, "knee": 0.322, "tip": 0.399, "crotch": 0.46,
                             "wrist": 0.300, "knuckle": 0.355},
               # 손(2026-11-13 사용자: "손가락이 왜 이렇게 길어, 절반 길이로"): 팔만 손목까지 늘리고 손바닥은 원래 크기,
               # 손가락은 늘린 길이(약 0.116)의 절반 0.058.
               "finger_len": 0.058,
               "crotch_lift": 0.0,
               "chalk_box": ((0.04, 0.11), (-0.11, 0.06), (0.48, 0.60)),
               "chalk_keep": lambda x, y, z: y < -0.02},
}[CHAR]
LM = CFG["landmarks"]
SRC = os.path.join(REPO, CFG["src"])
OUT = os.environ.get("TRIPO_OUT", os.path.join(REPO, CFG["out"]))
TRIS = 12000
TEX = 1024

# 게임 몸(더미, docs/39)
ARM_U, ARM_L = 0.35, 0.38
HAND_A = HAND_B = CFG.get("finger_len", 0.07) / 2   # 손가락 뿌리 → 손가락 뼈 → 손끝
LEG_U, LEG_L = 0.41, 0.40
SH_X, SH_Z = 0.175, 0.49
HIP_X = 0.095
HIP_RAISE = 0.0
KNEE_Z, ANKLE_Z = -LEG_U, -(LEG_U + LEG_L)
FOOT, TOE_DIR = 0.20, Vector((0, 0.19, -0.09))
SPINE, CHEST, NECK, HEAD, HEAD_TOP = 0.16, 0.37, 0.49, 0.56, 0.81
TIP = SH_X + ARM_U + ARM_L + HAND_A + HAND_B   # 0.975
ARM_X0 = 0.14   # 이보다 바깥(|x|)만 팔 길이 맞추기

SCALE = (SH_Z - ANKLE_Z) / (LM["shoulder"] - LM["ankle"])
SOLE = SH_Z - SCALE * LM["shoulder"]


def m_z(zn):
    """정규화 높이 → 놓은 뒤 높이(m, 다리 맞추기 전)."""
    return SOLE + SCALE * zn


KNEE_SRC = m_z(LM["knee"])


def leg_map(z):
    """다리 맞추기: 고관절(0)~발목 사이에서 원본 무릎(KNEE_SRC)을 KNEE_Z로. 배열·스칼라 모두."""
    return np.where((z < 0.0) & (z > ANKLE_Z), np.interp(z, [ANKLE_Z, KNEE_SRC, 0.0], [ANKLE_Z, KNEE_Z, 0.0]), z)


CROTCH_X = 0.07   # 가랑이 가운데 영역 반폭
PANTS_Z = (ANKLE_Z + 0.05, 0.12)   # 바지 높이(delight용)
DELIGHT_SIGMA, DELIGHT_K, DELIGHT_DETAIL = 14, 0.6, 0.25
CROTCH_SHARE = 0.04   # 가랑이 가운데를 두 다리가 나눠 따르는 반폭
BLEND_BELOW = 0.07    # 골반↔허벅지 잇는 구간이 다리 관절 아래로 내려가는 길이
SHARE_BOTTOM = -0.12  # 나눠 따르는 가장 낮은 높이
CROTCH_LIFT = float(CFG.get("crotch_lift", 0.0))
CROTCH_APEX = float(leg_map(m_z(LM["crotch"])))
CROTCH_TOP, CROTCH_BOTTOM, CROTCH_IN, CROTCH_OUT = 0.12, -0.36, 0.03, 0.12


def place():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    ob = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
    ob.rotation_mode = "XYZ"
    ob.rotation_euler = (0, 0, math.radians(90))
    ob.scale = (SCALE, SCALE, SCALE)
    bpy.context.view_layer.update()
    zmin = min((ob.matrix_world @ Vector(c)).z for c in ob.bound_box)
    ob.location.z = SOLE - zmin
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if ob.parent:
        ob.parent = None
    return ob


def weld(ob):
    """Tripo 원본은 UV 경계마다 정점이 나뉘어 있다(열린 모서리 4만 개). 그대로 줄이면 경계 양쪽이 따로 줄어
    틈이 생기고, 게임에서 그 틈으로 외곽선 껍데기·벽이 검은 점처럼 비친다(docs/37 §7). 같은 위치 정점을 먼저 붙인다.
    UV는 면 모서리(loop)마다 따로 남으므로 텍스처 경계는 그대로다."""
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=1e-5)
    bpy.ops.object.mode_set(mode="OBJECT")


def decimate(ob):
    n = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    m = ob.modifiers.new("dec", "DECIMATE")
    m.ratio = TRIS / n
    bpy.ops.object.modifier_apply(modifier="dec")


def is_chalk(x, y, z):
    """놓은 뒤 좌표(다리·팔 맞추기 전)를 정규화로 되돌려 CFG chalk로 판별. chalk_box를 쓰는 모델은 CHALK 그룹으로(skin)."""
    if "chalk" not in CFG:
        return False
    return CFG["chalk"](x / SCALE, y / SCALE, (z - SOLE) / SCALE)


def split_chalk(ob):
    """초크백이 몸과 떨어진 덩어리인 모델(chalk_box): 상자 안의 작은 연결 성분을 찾아 chalk_keep 밖은 지우고
    정점 그룹 CHALK로 표시한다(skin이 pelvis에 고정). 몸 덩어리는 건드리지 않는다."""
    if "chalk_box" not in CFG:
        return
    import bmesh
    (x0, x1), (y0, y1), (z0, z1) = CFG["chalk_box"]
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.verts.ensure_lookup_table()
    norm = lambda co: (co.x / SCALE, co.y / SCALE, (co.z - SOLE) / SCALE)
    seen, chalk = set(), []
    for v in bm.verts:
        if v.index in seen:
            continue
        comp, st = [], [v]
        seen.add(v.index)
        while st:
            a = st.pop()
            comp.append(a)
            for e in a.link_edges:
                b = e.other_vert(a)
                if b.index not in seen:
                    seen.add(b.index)
                    st.append(b)
        if len(comp) < 2000 and all(x0 <= n[0] <= x1 and y0 <= n[1] <= y1 and z0 <= n[2] <= z1 for n in map(lambda q: norm(q.co), comp)):
            chalk.extend(comp)
    drop = [v for v in chalk if not CFG["chalk_keep"](*norm(v.co))]
    keep_idx = {v.index for v in chalk if v not in drop}
    bmesh.ops.delete(bm, geom=drop, context="VERTS")
    bm.verts.ensure_lookup_table()
    # 지운 뒤 번호가 바뀌므로 좌표로 다시 찾는다
    tag = bm.verts.layers.int.new("chalk_tag")
    for v in bm.verts:
        n = norm(v.co)
        if x0 <= n[0] <= x1 and y0 <= n[1] <= y1 and z0 <= n[2] <= z1 and CFG["chalk_keep"](*n):
            v[tag] = 1
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()
    print("CHALK: 초크백 정점 %d개 중 %d개 지움" % (len(chalk), len(drop)))


def chalk_group(ob):
    """split_chalk가 남긴 표시(chalk_tag)로 CHALK 정점 그룹을 만든다(줄인 뒤 호출). 표시는 몸 덩어리와 이어지지 않은 정점만."""
    if "chalk_box" not in CFG:
        return set()
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.verts.ensure_lookup_table()
    tag = bm.verts.layers.int.get("chalk_tag")
    # 연결 성분으로: 표시된 정점이 과반인 작은 성분 전체
    seen, out = set(), set()
    for v in bm.verts:
        if v.index in seen:
            continue
        comp, st = [], [v]
        seen.add(v.index)
        while st:
            a = st.pop()
            comp.append(a)
            for e in a.link_edges:
                b = e.other_vert(a)
                if b.index not in seen:
                    seen.add(b.index)
                    st.append(b)
        if tag is not None and len(comp) < 2000 and sum(q[tag] for q in comp) * 2 > len(comp):
            out.update(q.index for q in comp)
    bm.free()
    print("CHALK: 골반 고정 정점 %d개" % len(out))
    return out


def fit_legs(ob):
    n = len(ob.data.vertices)
    co = np.empty(n * 3)
    ob.data.vertices.foreach_get("co", co)
    co = co.reshape(n, 3)
    co[:, 2] = leg_map(co[:, 2])
    ob.data.vertices.foreach_set("co", co.ravel())
    ob.data.update()
    print("LEGS: 무릎 %.3f → %.3f" % (KNEE_SRC, KNEE_Z))


def fit_arms(ob):
    """팔 길이 맞추기. 손목·손가락 뿌리를 잰 모델(landmarks wrist·knuckle): 팔(ARM_X0~손목)만 늘리고, 손바닥은 원래 크기로
    손가락 뿌리가 게임 손 접점(SH_X+ARM_U+ARM_L)에 오게, 손가락은 손끝이 TIP에 오게 줄이거나 늘린다(|x| 구간별 선형).
    그 밖의 모델: 손끝이 TIP에 오게 |x| ≥ ARM_X0 전체를 같은 배율로. 팔 높이(어깨 −0.15 ~ +0.08)에서 다 적용하고
    위·아래 0.04에 걸쳐 줄여 몸통 옆선·머리카락과 이어지게 한다."""
    tip = LM["tip"] * SCALE
    contact = SH_X + ARM_U + ARM_L
    if "wrist" in LM:
        wr, kn = LM["wrist"] * SCALE, LM["knuckle"] * SCALE
        w_new = contact - (kn - wr)
        src, dst = [ARM_X0, wr, kn, tip], [ARM_X0, w_new, contact, TIP]
    else:
        src, dst = [ARM_X0, tip], [ARM_X0, TIP]
    n = len(ob.data.vertices)
    co = np.empty(n * 3)
    ob.data.vertices.foreach_get("co", co)
    co = co.reshape(n, 3)
    ax, z = np.abs(co[:, 0]), co[:, 2]
    band = np.clip((z - (SH_Z - 0.19)) / 0.04, 0, 1) * np.clip(((SH_Z + 0.12) - z) / 0.04, 0, 1)
    k_end = (dst[-1] - dst[-2]) / (src[-1] - src[-2])
    nx = np.where(ax > ARM_X0, np.where(ax > tip, dst[-1] + (ax - tip) * k_end, np.interp(ax, src, dst)), ax)
    co[:, 0] = np.sign(co[:, 0]) * (ax + (nx - ax) * band)
    ob.data.vertices.foreach_set("co", co.ravel())
    ob.data.update()
    print("ARMS: |x| %s → %s" % (["%.3f" % v for v in src], ["%.3f" % v for v in dst]))


def centerline_y(ob):
    """팔·다리 뼈 앞뒤 위치: 메시 중심선(위팔 가운데, 허벅지·무릎 높이)의 y 중앙값."""
    n = len(ob.data.vertices)
    co = np.empty(n * 3)
    ob.data.vertices.foreach_get("co", co)
    co = co.reshape(n, 3)
    ax, z = np.abs(co[:, 0]), co[:, 2]
    arm = co[(ax > SH_X + 0.1) & (ax < SH_X + ARM_U + 0.2) & (np.abs(z - SH_Z) < 0.06)]
    leg = co[(ax > 0.03) & (ax < 0.2) & (z < -0.15) & (z > KNEE_Z - 0.1)]
    ay = float((arm[:, 1].min() + arm[:, 1].max()) / 2) if len(arm) else 0.0
    ly = float((leg[:, 1].min() + leg[:, 1].max()) / 2) if len(leg) else 0.0
    print("CENTER: 팔 y %.3f, 다리 y %.3f" % (ay, ly))
    return ay, ly


ORIG = {}   # 정점 번호 → 고치기 전 위치(초크백·바지 판별은 원래 모양으로)


def orig(v):
    return ORIG.get(v.index, v.co)


def remember(ob):
    for v in ob.data.vertices:
        ORIG[v.index] = v.co.copy()


def lift_crotch(ob):
    n = len(ob.data.vertices)
    co = np.empty(n * 3)
    ob.data.vertices.foreach_get("co", co)
    co = co.reshape(n, 3)
    ax, z = np.abs(co[:, 0]), co[:, 2]
    t = np.clip((ax - CROTCH_IN) / (CROTCH_OUT - CROTCH_IN), 0.0, 1.0)
    inner = 1.0 - t * t * (3 - 2 * t)
    up = np.clip((CROTCH_TOP - z) / (CROTCH_TOP - CROTCH_APEX), 0.0, 1.0)
    dn = np.clip((z - CROTCH_BOTTOM) / (CROTCH_APEX - CROTCH_BOTTOM), 0.0, 1.0)
    prof = np.where(z > CROTCH_APEX, np.sin(up * math.pi / 2), np.sin(dn * math.pi / 2))
    lift = CROTCH_LIFT * inner * prof
    co[:, 2] += lift
    ob.data.vertices.foreach_set("co", co.ravel())
    ob.data.update()
    print("CROTCH: 정점 %d개를 위로(최대 %.3f)" % (int((lift > 0.002).sum()), lift.max()))


def _box_blur(a, r, axis):
    c = np.cumsum(np.pad(a, [(r + 1, r) if i == axis else (0, 0) for i in range(a.ndim)], mode="edge"), axis=axis)
    hi = np.take(c, range(2 * r + 1, c.shape[axis]), axis=axis)
    lo = np.take(c, range(0, c.shape[axis] - 2 * r - 1), axis=axis)
    return (hi - lo) / (2 * r + 1)


def _gauss(a, sigma):
    r = max(1, int(round(sigma * 0.87)))   # 상자 흐림 3번 ≈ 가우시안
    for _ in range(3):
        a = _box_blur(_box_blur(a, r, 0), r, 1)
    return a


def pants_mask(ob, size):
    """바지 높이 삼각형(초크백 제외)을 UV에 칠한 0/1 마스크(행 = v, 아래에서 위)."""
    m = np.zeros((size, size), dtype=np.float32)
    uv = ob.data.uv_layers.active.data
    for p in ob.data.polygons:
        vs = [orig(ob.data.vertices[i]) for i in p.vertices]
        if not all(PANTS_Z[0] < v.z < PANTS_Z[1] and not is_chalk(v.x, v.y, v.z) for v in vs):
            continue
        pts = [uv[li].uv for li in p.loop_indices]
        for k in range(1, len(pts) - 1):
            tri = np.array([pts[0], pts[k], pts[k + 1]]) * (size - 1)
            x0, y0 = np.floor(tri.min(0)).astype(int)
            x1, y1 = np.ceil(tri.max(0)).astype(int)
            x0, y0, x1, y1 = max(x0, 0), max(y0, 0), min(x1, size - 1), min(y1, size - 1)
            gx, gy = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
            (ax, ay), (bx, by), (cx, cy) = tri
            d = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
            if abs(d) < 1e-9:
                continue
            l1 = ((by - cy) * (gx - cx) + (cx - bx) * (gy - cy)) / d
            l2 = ((cy - ay) * (gx - cx) + (ax - cx) * (gy - cy)) / d
            inside = (l1 >= -0.02) & (l2 >= -0.02) & (1 - l1 - l2 >= -0.02)
            m[gy[inside], gx[inside]] = 1.0
    return m


def delight_pants(ob, img):
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(h, w, 4)
    rgb = px[:, :, :3]
    lum = rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    m = pants_mask(ob, w)
    mb = _gauss(m, DELIGHT_SIGMA)
    big = _gauss(lum * m, DELIGHT_SIGMA) / np.maximum(mb, 1e-4)
    ref = float(np.median(lum[m > 0.5]))
    gain = (ref / np.maximum(big, 1e-3)) ** DELIGHT_K * (np.maximum(big, 1e-3) / np.maximum(lum, 1e-3)) ** DELIGHT_DETAIL
    gain = np.clip(gain, 0.8, 1.7)
    feather = np.clip(_gauss(m, 1.5) * 2.0 - 0.5, 0.0, 1.0) * m
    gain = 1.0 + (gain - 1.0) * feather
    rgb[:] = np.clip(rgb * gain[:, :, None], 0.0, 1.0)
    img.pixels.foreach_set(px.ravel())
    img.update()
    print("DELIGHT: 바지 %d px, 기준 밝기 %.3f, 이득 %.2f~%.2f" % (int(m.sum()), ref, float(gain[m > 0.5].min()), float(gain[m > 0.5].max())))


def joints(arm_y, leg_y):
    J = {"pelvis": Vector((0, 0, 0)), "spine": Vector((0, 0, SPINE)), "chest": Vector((0, 0, CHEST)),
         "neck": Vector((0, 0, NECK)), "head": Vector((0, 0, HEAD)), "head_top": Vector((0, 0, HEAD_TOP))}
    for s, sx in (("L", -1), ("R", 1)):
        sh = Vector((sx * SH_X, arm_y, SH_Z))
        J["shoulder_" + s] = sh
        J["elbow_" + s] = sh + Vector((sx * ARM_U, 0, 0))
        J["wrist_" + s] = J["elbow_" + s] + Vector((sx * ARM_L, 0, 0))   # 게임의 손 접점 = 손가락 뿌리
        J["finger_" + s] = J["wrist_" + s] + Vector((sx * HAND_A, 0, 0))
        J["hand_" + s] = J["finger_" + s] + Vector((sx * HAND_B, 0, 0))
        J["hip_" + s] = Vector((sx * HIP_X, leg_y, HIP_RAISE))
        J["knee_" + s] = Vector((sx * HIP_X, leg_y, KNEE_Z))
        J["ankle_" + s] = Vector((sx * HIP_X, leg_y, ANKLE_Z))
        J["toe_" + s] = J["ankle_" + s] + TOE_DIR.normalized() * FOOT
    return J


def armature(J):
    arm = bpy.data.armatures.new("ClimberCommonRig")
    rig = bpy.data.objects.new("ClimberCommonRig", arm)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    bones = {}

    def bone(name, head, tail, parent=None):
        b = arm.edit_bones.new(name)
        b.head, b.tail = J[head], J[tail]
        b.roll = 0.0
        if parent:
            b.parent = bones[parent]
        bones[name] = b

    bone("pelvis", "pelvis", "spine")
    bone("spine", "spine", "chest", "pelvis")
    bone("chest", "chest", "neck", "spine")
    bone("neck", "neck", "head", "chest")
    bone("head", "head", "head_top", "neck")
    for s in "LR":
        bone("upperarm_" + s, "shoulder_" + s, "elbow_" + s, "chest")
        bone("forearm_" + s, "elbow_" + s, "wrist_" + s, "upperarm_" + s)
        bone("hand_" + s, "wrist_" + s, "finger_" + s, "forearm_" + s)
        bone("finger_" + s, "finger_" + s, "hand_" + s, "hand_" + s)
    for s in "LR":
        bone("thigh_" + s, "hip_" + s, "knee_" + s, "pelvis")
        bone("shin_" + s, "knee_" + s, "ankle_" + s, "thigh_" + s)
        bone("foot_" + s, "ankle_" + s, "toe_" + s, "shin_" + s)
    for s in "LR":
        J["hiphelp_end_" + s] = J["hip_" + s] + (J["knee_" + s] - J["hip_" + s]) * 0.4
        bone("hiphelp_" + s, "hip_" + s, "hiphelp_end_" + s, "pelvis")
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


def ramp(v, a, b):
    """v가 a에서 b로 갈 때 0 → 1(경계 섞기)."""
    if b == a:
        return 1.0 if v >= a else 0.0
    return max(0.0, min(1.0, (v - a) / (b - a)))


def blend(w, lo_bone, hi_bone, t):
    w[lo_bone] = w.get(lo_bone, 0.0) + (1.0 - t)
    w[hi_bone] = w.get(hi_bone, 0.0) + t


def weights_for(p):
    x, y, z = p.x, p.y, p.z
    ax = abs(x)
    s = "L" if x < 0 else "R"
    w = {}
    # 머리·머리카락
    if z > HEAD - 0.01 and ax < 0.26:
        return {"head": 1.0}
    if z > NECK - 0.04 and ax < 0.07:
        blend(w, "neck", "head", ramp(z, HEAD - 0.03, HEAD + 0.02))
        return w
    # 팔(어깨부터): 어깨 0.13~0.22 가슴↔위팔, 팔꿈치 ±0.04, 손바닥은 아래팔, 손가락 뿌리·끝
    if ax > 0.13 and z > SH_Z - 0.15:
        if ax < 0.22:
            blend(w, "chest", "upperarm_" + s, ramp(ax, 0.13, 0.22))
        elif ax < SH_X + ARM_U + 0.04:
            blend(w, "upperarm_" + s, "forearm_" + s, ramp(ax, SH_X + ARM_U - 0.04, SH_X + ARM_U + 0.04))
        elif ax < SH_X + ARM_U + ARM_L:
            w["forearm_" + s] = 1.0
        elif ax < SH_X + ARM_U + ARM_L + HAND_A:
            blend(w, "forearm_" + s, "hand_" + s, ramp(ax, SH_X + ARM_U + ARM_L - 0.008, SH_X + ARM_U + ARM_L + 0.008))
        else:
            blend(w, "hand_" + s, "finger_" + s, ramp(ax, SH_X + ARM_U + ARM_L + HAND_A - 0.006, SH_X + ARM_U + ARM_L + HAND_A + 0.006))
        return w
    # 다리: 골반 → 엉덩이 보조 → 허벅지(다리 관절 기준 +0.04~−BLEND_BELOW), 무릎 ±0.05, 발목.
    # 가랑이 가운데(|x| < CROTCH_SHARE, 관절 아래)는 왼·오른 다리를 x에 따라 나눠 따른다(가운데 = 반반):
    # 한쪽 다리를 들면 가랑이 천이 절반만큼 같이 올라가 늘어진 조각이 남지 않는다.
    if z < 0.04 + HIP_RAISE and (ax > 0.005 or z < HIP_RAISE - 0.02):
        knee = KNEE_Z
        ankle = ANKLE_Z
        if z > KNEE_Z / 2:
            t = ramp(HIP_RAISE - z, -0.04, BLEND_BELOW)
            share = CROTCH_SHARE > 0.0 and SHARE_BOTTOM < z < HIP_RAISE
            fr = 0.5 + 0.5 * max(-1.0, min(1.0, x / CROTCH_SHARE)) if share else (1.0 if x > 0 else 0.0)
            for side, f in (("R", fr), ("L", 1.0 - fr)):
                if f <= 0.0:
                    continue
                part = {}
                if t < 0.5:
                    blend(part, "pelvis", "hiphelp_" + side, t * 2.0)
                else:
                    blend(part, "hiphelp_" + side, "thigh_" + side, t * 2.0 - 1.0)
                for k, val in part.items():
                    w[k] = w.get(k, 0.0) + val * f
        elif z > knee - 0.05:
            blend(w, "thigh_" + s, "shin_" + s, ramp(-z, -knee - 0.05, -knee + 0.05))
        elif z > ankle + 0.03:
            w["shin_" + s] = 1.0
        else:
            blend(w, "shin_" + s, "foot_" + s, ramp(-z, -ankle - 0.03, -ankle + 0.01))
        return w
    # 몸통: 골반 → 척추 → 가슴(높이)
    if z < (SPINE + CHEST) / 2:
        blend(w, "pelvis", "spine", ramp(z, SPINE - 0.08, SPINE + 0.04))
    else:
        blend(w, "spine", "chest", ramp(z, CHEST - 0.09, CHEST + 0.03))
    return w


CHALK_IDX = set()


def skin(ob, rig):
    ob.parent = rig
    mod = ob.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    groups = {}
    for b in rig.data.bones:
        groups[b.name] = ob.vertex_groups.new(name=b.name)
    for v in ob.data.vertices:
        w = {"pelvis": 1.0} if (v.index in CHALK_IDX or is_chalk(*orig(v))) else weights_for(v.co)   # 초크백 판별은 원래 모양으로
        tot = sum(w.values())
        for name, val in w.items():
            if val / tot > 0.001:
                groups[name].add([v.index], val / tot, "REPLACE")


def outline_mask(ob):
    """윤곽선 굵기(정점 색 R, 0~1, docs/37 §7): 엉덩이골·가랑이(가운데 |x| < 0.03 전부, 0.08까지 줄어듦,
    다리 관절 위 0.15 ~ 가랑이 아래 0.12)는 0. 뒤집은 껍데기 윤곽선이 움푹한 골 사이로 비쳐 검은 선이 생기기 때문.
    게임 외곽선 셰이더가 use_vertex_width일 때 곱한다."""
    n = len(ob.data.vertices)
    co = np.empty(n * 3)
    ob.data.vertices.foreach_get("co", co)
    co = co.reshape(n, 3)
    ax, z = np.abs(co[:, 0]), co[:, 2]
    side = np.clip((ax - 0.03) / 0.05, 0, 1)
    top, bot = HIP_RAISE + 0.15, CROTCH_APEX + CROTCH_LIFT - 0.12
    vert = 1.0 - np.clip((top - z) / 0.04, 0, 1) * np.clip((z - bot) / 0.04, 0, 1)
    wv = np.maximum(side, vert)
    attr = ob.data.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    cols = np.ones((n, 4), dtype=np.float32)
    cols[:, 0] = cols[:, 1] = cols[:, 2] = wv
    attr.data.foreach_set("color", cols.ravel())
    ob.data.color_attributes.active_color = attr
    print("OUTLINE: 윤곽선 줄인 정점 %d개" % int((wv < 0.99).sum()))


def material(ob):
    img = None
    for m in ob.data.materials:
        if m and m.node_tree:
            for n in m.node_tree.nodes:
                if n.type == "TEX_IMAGE" and n.image and "Color" in n.image.name:
                    img = n.image
    if img is None:
        for m in ob.data.materials:
            for n in m.node_tree.nodes:
                if n.type == "TEX_IMAGE" and n.image:
                    img = n.image
                    break
    img.scale(TEX, TEX)
    if CFG.get("delight", False):
        delight_pants(ob, img)
    img.name = CFG["tex"]
    mat = bpy.data.materials.new("M_body_main")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 1.0
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    ob.data.materials.clear()
    ob.data.materials.append(mat)


def main():
    ob = place()
    weld(ob)
    split_chalk(ob)
    decimate(ob)
    CHALK_IDX.update(chalk_group(ob))
    remember(ob)
    fit_legs(ob)
    lift_crotch(ob)
    fit_arms(ob)
    material(ob)
    ob.name = CFG["mesh"]
    ob.data.name = CFG["mesh"]
    for p in ob.data.polygons:
        p.use_smooth = True
    outline_mask(ob)
    J = joints(*centerline_y(ob))
    rig = armature(J)
    skin(ob, rig)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_animations=False,
                              export_yup=True, export_image_format="JPEG", export_jpeg_quality=88,
                              export_vertex_color="ACTIVE")
    if os.environ.get("TRIPO_BLEND"):
        bpy.ops.wm.save_as_mainfile(filepath=os.environ["TRIPO_BLEND"])
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    print("TRIPO_RIG: ×%.4f 키 %.3fm, 삼각형 %d, 뼈 %d, 출력 %s (%.0fKB)" % (SCALE, SCALE, tris, len(rig.data.bones), OUT, os.path.getsize(OUT) / 1024))


main()
