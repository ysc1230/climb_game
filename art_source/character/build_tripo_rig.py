"""Tripo 기본 캐릭터 → 게임용 리깅 모델(docs/36, 2026-11-11).
실행: blender -b --python art_source/character/build_tripo_rig.py   (여성: TRIPO_CHAR=female 앞에 붙임)
입력: art_source/character/male|female/*_base.glb(Tripo v3.1, 약 146만 삼각형, T자, 키 1.0, 앞 +X)
출력: game/art/characters/climber_tripo.glb / climber_tripo_female.glb(약 1만 2천 삼각형, 뼈 17 + 손가락 2 + 엉덩이 보조 2, 색 텍스처 1024)

1. 놓기: Z +90°(앞 +X → +Y, build_climber 규약), 키 1.99m, 발바닥 z = −0.835(골반 관절 = 원점). 실측은 docs/36 §1.1.
2. 줄이기: 같은 위치 정점 붙이기(UV 경계 틈 방지) → Decimate(접기) → TRIS 삼각형. UV 유지.
3. 뼈대: RigPose.BONES 17개 + finger_L/R(손 아래). 판정 몸(Tuning)과 같은 길이:
   위팔 0.20, 팔꿈치→손 접점(손가락 뿌리) 0.35, 손가락 0.07(hand 0.035 + finger 0.035), 허벅지 0.41, 정강이 0.375, 발 0.135.
   T자 기준 자세(팔 수평). 팔 중심선은 모델 실측(y −0.03).
4. 가중치: Blender 자동 가중치는 Tripo 메시에서 자주 실패하므로 부위·위치로 직접 준다(관절 경계는 선형으로 섞음).
   팔은 어깨에서 거리로(어깨 → 팔꿈치 → 손바닥은 아래팔에 고정 → 손가락 뿌리 → 손가락 끝), 다리·몸통은 높이로,
   머리카락·머리는 head, 초크백은 pelvis 고정. 정점당 뼈 2개 이하(가랑이 가운데만 4개 이하).
   엉덩이(docs/37 4단계, 2026-11-12): 골반↔허벅지 사이는 보조 뼈 hiphelp_L/R(엉덩이 관절, 게임이 골반과 허벅지
   회전의 중간으로 돌림)를 거쳐 pelvis → hiphelp → thigh로 잇는다. 두 뼈만 섞으면 다리를 90° 들 때 사이 정점이
   안으로 접힌다. 가운데 선 가까운 가랑이(|x| < 0.07, z > −0.20)는 골반 쪽에 더 남겨 다리를 들어도 가랑이 꼭짓점이
   가운데에 있게 한다(전에는 꼭짓점이 허벅지를 따라 옆으로 끌려가 Y자가 사라졌다).
5. 재질: 색 텍스처만(2048 → 1024), 금속 0. ORM·노멀은 쓰지 않는다(게임은 툰 셰이더).
6. 엉덩이·바지(docs/37 §7, 2026-11-12): Tripo 원본은 밑위가 길어 다리 관절이 엉덩이 아래에 있고,
   텍스처에 구운 음영이 엉덩이 아래·가운데·가랑이에 진하게 몰려 엉덩이가 주머니 아래에서 시작하는 것처럼 보였다.
   - 다리 관절 올리기: 다리 뼈(허벅지)는 판정 고관절(z 0)보다 HIP_RAISE 위(뒷주머니 가운데)에서 시작하고 그만큼 길다
     (게임 LimbIK.HIP_RAISE와 같은 값). 다리가 엉덩이에서 돌아 갈라지는 점이 주머니 바로 아래에 온다(사용자 참고 그림).
     골반↔허벅지 가중치 구간도 HIP_RAISE만큼 위로 옮긴다. 허리·바지 바깥 선은 그대로.
   - lift_crotch: 원본 가랑이는 올린 다리 관절보다 17cm 아래라, 다리를 들면 가랑이 천이 늘어진 조각처럼 남는다.
     다리 안쪽만 가랑이를 CROTCH_LIFT 올려 엉덩이 바로 아래에서 갈라지게 한다.
   - delight_pants: 바지 영역(UV) 텍스처에서 큰 음영(흐린 밝기)을 바지 평균 쪽으로 펴고, 가는 진한 주름선도 조금 누그러뜨린다.
     주머니·솔기 같은 무늬는 남는다. 게임은 툰 셰이더가 명암을 따로 주므로 구운 음영이 겹치면 지나치게 어둡다.
"""
import bpy, math, os
import numpy as np
from mathutils import Vector

REPO = os.path.expanduser("~/Projects/climb_game")
# 캐릭터(TRIPO_CHAR): male(기본) / female(2026-11-12 추가). 값이 없는 항목은 남성 값.
CHAR = os.environ.get("TRIPO_CHAR", "male")
CFG = {
    # 남성 v2(2026-11-13, task a621f6bb): 바지·셔츠 그림자를 지운 참고 그림(art_source/character/male)으로 다시 만든 모델.
    # 실측(정규화 높이): 팔 중심선 0.762, 발목 관절 0.03, 가랑이 0.405, 무릎 0.245, 손끝 ±0.409, 초크백 오른쪽 뒤 허리.
    # ×1.9877(키 1.99m). 가랑이를 7cm 올려 엉덩이 바로 아래에서 갈라지게 한다(docs/37 §7).
    "male": {"src": "art_source/character/male/climber_male_v2_base.glb", "out": "game/art/characters/climber_tripo.glb",
             "mesh": "P_body_male", "tex": "climber_tripo_color",
             "scale": 1.9877, "sole": -0.8446, "hip_raise": 0.10, "hip_y": 0.006,
             "knee": (0.116, -0.011, -0.358), "ankle": (0.136, -0.01, -0.785), "arm_y": -0.027,
             "arm_fit": (0.12, 0.813), "crotch_lift": 0.07, "crotch_apex": -0.04, "delight": False,
             "chalk": lambda x, y, z: 0.06 < z < 0.26 and (x > 0.185 or (x > 0.12 and y < -0.12))},
    # 여성: Tripo v3.1(task e606f7d8), 키 1(올림머리 포함). 실측(정규화 높이): 팔 중심선 0.743, 발목 관절 0.045,
    # 가랑이 0.44, 엉덩이 가장 넓은 곳 0.475, 무릎 0.265, 손끝 ±0.434, 초크백 왼쪽 허리(x < −0.095, 0.50~0.60).
    # 어깨(0.67)~발목(−0.785) 1.455m에 맞춰 ×2.0845(키 약 2.08m, 머리 위 올림머리 포함). 팔은 손끝이 0.80에 오게 줄인다.
    "female": {"src": "art_source/character/female/climber_female_base.glb",
               "out": "game/art/characters/climber_tripo_female.glb", "mesh": "P_body_female", "tex": "climber_female_color",
               "scale": 2.0845, "sole": -0.879, "hip_raise": 0.11, "hip_y": 0.03,
               "knee": (0.119, 0.017, -0.326), "ankle": (0.152, 0.015, -0.785), "arm_y": -0.021,
               "arm_fit": (0.12, 0.905), "crotch_lift": 0.0, "delight": False,
               "chalk": lambda x, y, z: 0.17 < z < 0.38 and (x < -0.195 or (x < -0.12 and y < -0.155))},
}[CHAR]
SRC = os.path.join(REPO, CFG["src"])
OUT = os.environ.get("TRIPO_OUT", os.path.join(REPO, CFG["out"]))
TRIS = 12000
TEX = 1024

ARM_U, ARM_L, HAND_A, HAND_B = 0.20, 0.35, 0.035, 0.035
LEG_U, LEG_L, FOOT = 0.41, 0.375, 0.135
SH_X, SH_Z, ARM_Y = 0.18, 0.67, CFG.get("arm_y", -0.03)
HIP_X = 0.10
HIP_RAISE = CFG.get("hip_raise", 0.10)   # 화면 다리 관절을 판정 고관절보다 올리는 높이(게임은 뼈대에서 읽는다)
SPINE, CHEST, NECK, HEAD, HEAD_TOP = 0.27, 0.54, 0.76, 0.84, 1.16
SOLE = CFG.get("sole", -0.835)
SCALE = CFG.get("scale", 1.99)
CROTCH_X = 0.07   # 가랑이 가운데 영역 반폭(골반 쪽에 더 남김)
PANTS_Z = (-0.72, 0.085)   # 바지 높이(신발 위 ~ 벨트 아래)
DELIGHT_SIGMA, DELIGHT_K, DELIGHT_DETAIL = 14, 0.6, 0.25
CROTCH_SHARE = float(os.environ.get("CROTCH_SHARE", "0.04"))   # 가랑이 가운데를 두 다리가 나눠 따르는 반폭
BLEND_BELOW = float(os.environ.get("BLEND_BELOW", "0.07"))   # 골반↔허벅지 잇는 구간이 다리 관절 아래로 내려가는 길이
SHARE_BOTTOM = float(os.environ.get("SHARE_BOTTOM", "0.0"))     # 나눠 따르는 가장 낮은 높이(올린 가랑이 꼭짓점 근처)
# 가랑이 올리기: 다리 안쪽(|x| < CROTCH_IN 전부, CROTCH_OUT까지 줄어듦)의 가랑이 꼭짓점(CROTCH_APEX)을 CROTCH_LIFT 올린다.
# 위(CROTCH_TOP = 다리 관절)·아래(CROTCH_BOTTOM) 끝에서는 0. 바깥 엉덩이 선·허리는 그대로.
CROTCH_LIFT = float(os.environ.get("CROTCH_LIFT", CFG.get("crotch_lift", 0.11)))
CROTCH_APEX, CROTCH_TOP, CROTCH_BOTTOM, CROTCH_IN, CROTCH_OUT = CFG.get("crotch_apex", -0.07), 0.12, -0.36, 0.03, 0.12


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
    if "chalk" in CFG:
        return CFG["chalk"](x, y, z)
    return x > 0.04 and y < -0.11 and -0.14 < z < 0.10


def fit_arms(ob):
    """팔 길이 맞추기(여성): 손끝이 게임 손끝(0.80)에 오게 |x| ≥ x0인 팔 부분을 길이 방향으로만 줄인다.
    팔 높이(0.58~0.76)에서 다 적용하고 위·아래 0.03에 걸쳐 줄여 몸통 옆선과 이어지게 한다."""
    if "arm_fit" not in CFG:
        return
    x0, tip = CFG["arm_fit"]
    k = (SH_X + ARM_U + ARM_L + HAND_A + HAND_B - x0) / (tip - x0)
    n = len(ob.data.vertices)
    co = np.empty(n * 3)
    ob.data.vertices.foreach_get("co", co)
    co = co.reshape(n, 3)
    ax, z = np.abs(co[:, 0]), co[:, 2]
    band = np.clip((z - 0.55) / 0.03, 0, 1) * np.clip((0.79 - z) / 0.03, 0, 1)
    nx = np.where(ax > x0, x0 + (ax - x0) * k, ax)
    co[:, 0] = np.sign(co[:, 0]) * (ax + (nx - ax) * band)
    ob.data.vertices.foreach_set("co", co.ravel())
    ob.data.update()
    print("ARMS: ×%.3f (손끝 %.3f → %.3f)" % (k, tip, x0 + (tip - x0) * k))


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


def joints():
    J = {"pelvis": Vector((0, 0, 0)), "spine": Vector((0, 0, SPINE)), "chest": Vector((0, 0, CHEST)),
         "neck": Vector((0, 0, NECK)), "head": Vector((0, 0, HEAD)), "head_top": Vector((0, 0, HEAD_TOP))}
    for s, sx in (("L", -1), ("R", 1)):
        sh = Vector((sx * SH_X, ARM_Y, SH_Z))
        J["shoulder_" + s] = sh
        J["elbow_" + s] = sh + Vector((sx * ARM_U, 0, 0))
        J["wrist_" + s] = J["elbow_" + s] + Vector((sx * ARM_L, 0, 0))   # 게임의 손 접점 = 손가락 뿌리
        J["finger_" + s] = J["wrist_" + s] + Vector((sx * HAND_A, 0, 0))
        J["hand_" + s] = J["finger_" + s] + Vector((sx * HAND_B, 0, 0))
        hip = Vector((sx * HIP_X, CFG.get("hip_y", -0.02), HIP_RAISE))
        J["hip_" + s] = hip
        if "knee" in CFG:   # 실측 무릎·발목(허벅지+정강이 = 판정 다리 0.785 + HIP_RAISE)
            kx, ky, kz = CFG["knee"]
            fx, fy, fz = CFG["ankle"]
            J["knee_" + s] = Vector((sx * kx, ky, kz))
            J["ankle_" + s] = Vector((sx * fx, fy, fz))
        else:
            leg = Vector((sx * 0.03, 0, -0.785 - HIP_RAISE)).normalized()
            J["knee_" + s] = hip + leg * (LEG_U + HIP_RAISE)
            J["ankle_" + s] = J["knee_" + s] + leg * LEG_L
        J["toe_" + s] = J["ankle_" + s] + Vector((0, 0.125, -0.05)).normalized() * FOOT
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
    if z > 0.79 and ax < 0.26:
        return {"head": 1.0}
    if z > 0.70 and ax < 0.11:
        blend(w, "neck", "head", ramp(z, 0.74, 0.80))
        return w
    # 팔(어깨부터): 어깨 0.15~0.24 가슴↔위팔, 팔꿈치 ±0.04, 손바닥은 아래팔, 손가락 뿌리·끝
    if ax > 0.15 and z > 0.55:
        if ax < 0.24:
            blend(w, "chest", "upperarm_" + s, ramp(ax, 0.15, 0.24))
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
        knee = CFG["knee"][2] if "knee" in CFG else -LEG_U
        ankle = CFG["ankle"][2] if "ankle" in CFG else -(LEG_U + LEG_L)
        if z > -0.22:
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
        blend(w, "pelvis", "spine", ramp(z, 0.08, 0.20))
    else:
        blend(w, "spine", "chest", ramp(z, 0.36, 0.48))
    return w


def skin(ob, rig):
    ob.parent = rig
    mod = ob.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    groups = {}
    for b in rig.data.bones:
        groups[b.name] = ob.vertex_groups.new(name=b.name)
    for v in ob.data.vertices:
        w = {"pelvis": 1.0} if is_chalk(*orig(v)) else weights_for(v.co)   # 초크백 판별은 원래 모양으로
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
    if CFG.get("delight", True):
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
    decimate(ob)
    remember(ob)
    lift_crotch(ob)
    fit_arms(ob)
    material(ob)
    ob.name = CFG["mesh"]
    ob.data.name = CFG["mesh"]
    for p in ob.data.polygons:
        p.use_smooth = True
    outline_mask(ob)
    J = joints()
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
    print("TRIPO_RIG: 삼각형 %d, 뼈 %d, 출력 %s (%.0fKB)" % (tris, len(rig.data.bones), OUT, os.path.getsize(OUT) / 1024))


main()
