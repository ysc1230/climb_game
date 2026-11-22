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
8. 착장(CFG outfit, 남성 기본 = TRIPO_CHAR=male_base): 몸 위에 Blender로 옷을 만들고 덮인 몸 면은 지운다(docs/56).
참고 그림은 그림자·주름 없이 단색 + 외곽선으로(구운 음영이 엉덩이 얼룩이 된다, docs/37 §7).
"""
import bpy, math, os
import numpy as np
from mathutils import Vector

REPO = os.path.expanduser("~/Projects/climb_game")
CHAR = os.environ.get("TRIPO_CHAR", "male")
# landmarks: 정규화 높이(발바닥 0, 키 1)에서 잰 값. shoulder = 팔 중심선 높이, ankle = 발목 관절 높이, knee = 무릎 높이,
# tip = 손끝 |x|, crotch = 가랑이 높이. chalk: 정규화 좌표(x 오른쪽, y 앞, z 위)로 초크백 정점 판별.
CFGS = {
    # 남성 v2(2026-11-13, task a621f6bb, art_source/character/male)
    "male": {"src": "art_source/character/male/climber_male_v2_base.glb", "out": "game/art/characters/climber_male.glb",
             "mesh": "P_body_male", "tex": "climber_male_color",
             "landmarks": {"shoulder": 0.762, "ankle": 0.03, "knee": 0.245, "tip": 0.409, "crotch": 0.405},
             "crotch_lift": 0.05,
             "chalk": lambda x, y, z: 0.46 < z < 0.55 and (x > 0.093 or (x > 0.06 and y < -0.06))},
    # 여성 단발(2026-11-15, main temp/characters/female_bob_v1 기본 생성본, art_source/character/female). 초크백은 오른쪽 허리 뒤
    "female": {"src": "art_source/character/female/climber_female_base.glb", "out": "game/art/characters/climber_female.glb",
               "mesh": "P_body_female", "tex": "climber_female_color",
               "landmarks": {"shoulder": 0.776, "ankle": 0.06, "knee": 0.27, "tip": 0.398, "crotch": 0.47,
                             "wrist": 0.29, "knuckle": 0.35},
               "finger_len": 0.058,
               "crotch_lift": 0.0,
               "chalk": lambda x, y, z: 0.43 < z < 0.57 and (x > 0.088 or (x > 0.06 and y < -0.06)),
               # 갈아입는 옷(2026-11-16, main temp/characters/wardrobe_v1 fitted_wip): 원본과 같은 정규화 좌표(발바닥 z 0)라
               # 원본 몸과 같은 변환·다리·팔 맞추기·가중치를 준다. (id, 파일, 겉으로 띄우는 거리 m)
               "garments": [("top_mint_tee", "top_mint_tee.glb", 0.012), ("top_coral_long", "top_coral_long.glb", 0.012),
                            ("pants_charcoal", "pants_charcoal.glb", 0.012), ("pants_olive_crop", "pants_olive_crop.glb", 0.012),
                            ("shoes_gray_pair", "shoes_gray_pair.glb", 0.010), ("shoes_teal_pair", "shoes_teal_pair.glb", 0.010)],
               "garment_dir": "art_source/character/female/wardrobe",
               # 몸에 붙은 옷 나누기: 같은 원본의 파츠 분리본(main temp/characters/female_bob_v1/climber_female_parts_wip.glb)에서
               # 면마다 가장 가까운 파츠로 나눈다. 옷을 입으면 그 부위를 숨긴다(비침 방지). 바지는 7부 밑단 높이에서 위·아래로.
               "regions": {"src": "art_source/character/female/climber_female_parts.glb",
                           "map": {"Shirt": "top", "Pants": "pants", "Shoe_L": "shoes", "Shoe_R": "shoes"},
                           "hem_from": "pants_olive_crop", "prefix": "P_female_"}},
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
    # 애니 남성(2026-11-22, 사용자 기본 그림 정면·왼쪽·뒤 3장 → Tripo v3.1 multiview, pbr 끔, 30크레딧,
    # art_source/character/anime_male, tools/tripo_multiview.py). 가랑이는 다리 사이 틈이 시작하는 높이(무릎이 붙어 있어 가운데 최저점은 무릎).
    # 얼굴이 뭉개지지 않게 삼각형·텍스처를 더 쓴다. 옆모습 그림의 앞으로 뻗은 주먹이 오른 아래팔에 회색 얼룩으로 찍혀 피부색으로 덮는다(skin_clean).
    "anime_male": {"src": "art_source/character/anime_male/tripo_v1/model.glb", "out": "game/art/characters/climber_anime_male.glb",
                   "mesh": "P_body_anime_male", "tex": "climber_anime_male_color",
                   "landmarks": {"shoulder": 0.75, "ankle": 0.075, "knee": 0.25, "tip": 0.50, "crotch": 0.40,
                                 "wrist": 0.394, "knuckle": 0.453},
                   "finger_len": 0.058,
                   "crotch_lift": 0.0,
                   "tris": 24000, "tex_size": 2048,
                   "skin_clean": (0.45, 0.80),
                   "chalk": lambda x, y, z: 0.47 < z < 0.585 and (x > 0.095 or (x > 0.055 and y < -0.06))},
    # 대머리(2026-11-23 v2, 사용자 그림 정면·왼쪽·뒤·오른쪽 4장 → Tripo v3.1 multiview, pbr 끔, 30크레딧, task a93037be,
    # art_source/character/bald, docs/55). 속옷만 입은 맨몸(옷은 나중에 이 몸 위에 맞춰 만든다), 초크백 없음.
    # 가랑이는 속옷 아랫단 가운데(허벅지 안쪽은 0.45까지 붙어 있음). 손목은 팔이 가장 가는 곳, 손가락 뿌리는 손이 얇아지기 시작하는 곳.
    # elbow: 위팔과 아래팔 사이 잘록한 곳. 그림의 위팔이 게임 위팔(0.35m)보다 짧아 팔꿈치를 게임 팔꿈치에 맞춘다(fit_arms).
    # armpit: 팔 아랫면이 몸통 옆선과 만나는 높이. 그 아래 몸통 옆(등·옆구리)은 팔을 따르지 않는다(어깨 가시 방지, weights_for).
    "bald": {"src": "art_source/character/bald/tripo_v2/model.glb", "out": "game/art/characters/climber_bald.glb",
             "mesh": "P_body_bald", "tex": "climber_bald_color",
             "landmarks": {"shoulder": 0.807, "ankle": 0.06, "knee": 0.31, "tip": 0.502, "crotch": 0.50,
                           "wrist": 0.365, "knuckle": 0.462, "elbow": 0.235, "armpit": 0.765},
             "finger_len": 0.058,
             "crotch_lift": 0.0,
             "tris": 24000, "tex_size": 2048,
             # 피부 채도: Tripo 텍스처 (0.984, 0.667, 0.404)가 그림 (0.975, 0.71, 0.53)보다 진해 ×0.78(색상은 같음)
             "saturation": 0.78},
}
# 남성 기본 착장(2026-11-23, docs/56): 대머리 v2 몸 + 머리카락·흰 티·청바지·암벽화·초크백(build_outfit). 몸 메시는 덮인 곳을 지운 P_body_male.
CFGS["male_base"] = dict(CFGS["bald"], out="game/art/characters/climber_male_base.glb", mesh="P_body_male", tex="climber_male_color",
                         outfit=True)
CFG = CFGS[CHAR]
LM = CFG["landmarks"]
SRC = os.path.join(REPO, CFG["src"])
OUT = os.environ.get("TRIPO_OUT", os.path.join(REPO, CFG["out"]))
TRIS = CFG.get("tris", 12000)
TEX = CFG.get("tex_size", 1024)

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
# 겨드랑이 높이(놓은 뒤, m). 있으면 그 아래 몸통 옆은 팔 늘리기·팔 가중치에서 뺀다(2026-11-23 대머리 어깨 가시).
ARMPIT = m_z(LM["armpit"]) if "armpit" in LM else None


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


RAW_ZMIN = [0.0]   # 원본 메시의 가져온 그대로 z 최솟값(옷 좌표 맞추기용)


def place():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    ob = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
    RAW_ZMIN[0] = min((ob.matrix_world @ Vector(c)).z for c in ob.bound_box)
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
        if "elbow" in LM:   # 그림 팔꿈치를 게임 팔꿈치(SH_X+ARM_U)에: 위팔·아래팔을 따로 늘리거나 줄여 굽는 곳이 맞게
            src.insert(1, LM["elbow"] * SCALE)
            dst.insert(1, SH_X + ARM_U)
    else:
        src, dst = [ARM_X0, tip], [ARM_X0, TIP]
    n = len(ob.data.vertices)
    co = np.empty(n * 3)
    ob.data.vertices.foreach_get("co", co)
    co = co.reshape(n, 3)
    ax, z = np.abs(co[:, 0]), co[:, 2]
    low = SH_Z - 0.19 if ARMPIT is None else ARMPIT - 0.01   # 겨드랑이를 쟀으면 그 아래 몸통 옆은 그대로
    band = np.clip((z - low) / 0.04, 0, 1) * np.clip(((SH_Z + 0.12) - z) / 0.04, 0, 1)
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
        if ax < 0.22 and ARMPIT is not None:
            # 겨드랑이 아래 몸통 옆(등·옆구리)은 몸통 가중치, 위(어깨세모근)만 위팔로 섞는다. 예전 규칙은 |x|만 봐서
            # 몸통 옆이 SH_Z − 0.15 위에서 갑자기 위팔을 따라가 팔을 들면 어깨 뒤가 가시처럼 찢어졌다.
            t = ramp(ax, 0.13, 0.22) * ramp(z, ARMPIT - 0.01, ARMPIT + 0.05)
            for k, val in torso_weights(z).items():
                w[k] = w.get(k, 0.0) + val * (1.0 - t)
            w["upperarm_" + s] = w.get("upperarm_" + s, 0.0) + t
        elif ax < 0.22:
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
    return torso_weights(z)


def torso_weights(z):
    """몸통: 골반 → 척추 → 가슴(높이)."""
    w = {}
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


def clean_skin(ob, img, x0, x1):
    """팔(|x| x0~x1, 맞춘 뒤 좌표) 면들의 UV 삼각형 안에서 피부보다 많이 어두운 화소를 그 부위 피부색(중앙값)으로 덮는다.
    참고 그림의 그림자·앞으로 뻗은 주먹 같은 것이 팔 텍스처에 얼룩으로 찍힌 것을 지운다."""
    me = ob.data
    uv = me.uv_layers.active.data
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(h, w, 4)
    mask = np.zeros((h, w), dtype=bool)
    co = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    for p in me.polygons:
        ax = np.abs(co[list(p.vertices), 0])
        if ax.min() < x0 or ax.max() > x1:
            continue
        t = np.array([uv[li].uv[:] for li in p.loop_indices]) * (w, h)
        for k in range(1, len(t) - 1):
            a, b, c = t[0], t[k], t[k + 1]
            lo = np.floor(np.minimum(np.minimum(a, b), c)).astype(int)
            hi = np.ceil(np.maximum(np.maximum(a, b), c)).astype(int)
            lo, hi = np.clip(lo, 0, (w - 1, h - 1)), np.clip(hi, 0, (w - 1, h - 1))
            gx, gy = np.meshgrid(np.arange(lo[0], hi[0] + 1) + 0.5, np.arange(lo[1], hi[1] + 1) + 0.5)
            d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
            if abs(d) < 1e-9:
                continue
            l1 = ((b[1] - c[1]) * (gx - c[0]) + (c[0] - b[0]) * (gy - c[1])) / d
            l2 = ((c[1] - a[1]) * (gx - c[0]) + (a[0] - c[0]) * (gy - c[1])) / d
            inside = (l1 >= -0.02) & (l2 >= -0.02) & (1 - l1 - l2 >= -0.02)
            mask[lo[1]:hi[1] + 1, lo[0]:hi[0] + 1] |= inside
    if not mask.any():
        print("SKIN_CLEAN: 팔 면 없음")
        return
    rgb = px[..., :3]
    lum = rgb @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    skin = np.median(rgb[mask], axis=0)
    dark = mask & (lum < 0.75 * float(skin @ np.array([0.299, 0.587, 0.114])))
    rgb[dark] = skin
    px[..., :3] = rgb
    img.pixels.foreach_set(px.ravel())
    print("SKIN_CLEAN: 팔 화소 %d개 중 어두운 %d개를 피부색 %s로" % (int(mask.sum()), int(dark.sum()), np.round(skin, 3)))


def desaturate(img, k):
    """채도만 k배(밝기·색상 그대로: 각 채널 = 최댓값 − (최댓값 − 채널) × k). Tripo 텍스처가 그림보다 진할 때 그림에 맞춘다."""
    n = img.size[0] * img.size[1]
    px = np.empty(n * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(n, 4)
    mx = px[:, :3].max(1, keepdims=True)
    px[:, :3] = mx - (mx - px[:, :3]) * k
    img.pixels.foreach_set(px.ravel())
    img.update()
    print("SATURATION: ×%.2f" % k)


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
    if "skin_clean" in CFG:
        clean_skin(ob, img, *CFG["skin_clean"])
    if "saturation" in CFG:
        desaturate(img, CFG["saturation"])
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


GARMENT_TRIS = 3500
GARMENT_TEX = 512


def garment(gid, path, push):
    """갈아입는 옷 하나: 정규화 좌표(발바닥 z 0) → 원본 몸과 같은 놓기(원본 z 최솟값 기준) → 줄이기 → 다리·팔 맞추기 →
    법선 방향으로 push만큼 띄우기(원본 몸의 옷 위에 입힘) → 재질(텍스처 512) → P_<id>. 가중치는 skin_garment가 위치로 준다."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    g = [o for o in new if o.type == "MESH" and o.name != "Icosphere" and len(o.data.vertices) > 100][0]
    mw = g.matrix_world.copy()
    g.parent = None
    g.matrix_world = mw
    for o in new:
        if o != g:
            bpy.data.objects.remove(o)
    for m in list(g.modifiers):
        g.modifiers.remove(m)
    g.vertex_groups.clear()
    bpy.ops.object.select_all(action="DESELECT")
    g.select_set(True)
    bpy.context.view_layer.objects.active = g
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    from mathutils import Matrix
    zmin = min(v.co.z for v in g.data.vertices)
    M = Matrix.Translation((0, 0, SOLE - SCALE * RAW_ZMIN[0])) @ Matrix.Scale(SCALE, 4) @ Matrix.Rotation(math.radians(90), 4, "Z") @ Matrix.Translation((0, 0, RAW_ZMIN[0]))
    g.data.transform(M)
    print("GARMENT %s: 원래 z 최솟값 %.3f, 삼각형 %d" % (gid, zmin, sum(len(p.vertices) - 2 for p in g.data.polygons)))
    tris = sum(len(p.vertices) - 2 for p in g.data.polygons)
    if tris > GARMENT_TRIS:
        mod = g.modifiers.new("dec", "DECIMATE")
        mod.ratio = GARMENT_TRIS / tris
        bpy.ops.object.modifier_apply(modifier=mod.name)
    fit_legs(g)
    fit_arms(g)
    g.data.update()
    if gid.startswith("shoes"):   # 한 켤레가 한 메시: 두 발 사이를 잇는 면(가운데 |x| < 0.035)을 지운다
        import bmesh
        bm = bmesh.new()
        bm.from_mesh(g.data)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if abs(v.co.x) < 0.035], context="VERTS")
        bm.to_mesh(g.data)
        bm.free()
        g.data.update()
    n = len(g.data.vertices)
    co = np.empty(n * 3)
    nr = np.empty(n * 3)
    g.data.vertices.foreach_get("co", co)
    g.data.vertices.foreach_get("normal", nr)
    g.data.vertices.foreach_set("co", co + nr * push)
    g.data.update()
    img = None
    for m in g.data.materials:
        if m and m.node_tree:
            for nd in m.node_tree.nodes:
                if nd.type == "TEX_IMAGE" and nd.image:
                    img = nd.image
    mat = bpy.data.materials.new("M_" + gid)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 1.0
    if img is not None:
        img.scale(GARMENT_TEX, GARMENT_TEX)
        img.name = "tex_" + gid
        tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = img
        mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    g.data.materials.clear()
    g.data.materials.append(mat)
    for p in g.data.polygons:
        p.use_smooth = True
    g.name = g.data.name = "P_" + gid
    return g


def split_regions(ob, clothes):
    """몸에 붙은 옷을 따로 메시로(CFG regions). 분리본 파츠를 옷과 같은 변환으로 놓고, 몸의 면마다 가장 가까운 파츠 면으로
    부위를 정해 떼어 낸다: <prefix>top, <prefix>pants_up / pants_low(7부 밑단 + 0.03 아래), <prefix>shoes. 나머지는 몸에 남는다."""
    R = CFG.get("regions")
    if not R:
        return []
    from mathutils import Matrix
    from mathutils.kdtree import KDTree
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(REPO, R["src"]))
    new = [o for o in bpy.data.objects if o not in before]
    M = Matrix.Translation((0, 0, SOLE - SCALE * RAW_ZMIN[0])) @ Matrix.Scale(SCALE, 4) @ Matrix.Rotation(math.radians(90), 4, "Z") @ Matrix.Translation((0, 0, RAW_ZMIN[0]))
    pts, labels = [], []
    for o in new:
        if o.type != "MESH" or o.name not in R["map"] and o.name.split(".")[0] not in ["Skin", "Hair", "Belt", "ChalkBag"]:
            continue
        lab = R["map"].get(o.name.split(".")[0], "body")
        tmp = o.data.copy()
        tmp.transform(M @ o.matrix_world)
        for p in tmp.polygons:
            pts.append(p.center.copy())
            labels.append(lab)
        bpy.data.meshes.remove(tmp)
    for o in new:
        bpy.data.objects.remove(o)
    # 분리본 면 중심도 다리·팔 맞추기를 거친다
    arr = np.array([[p.x, p.y, p.z] for p in pts])
    arr[:, 2] = leg_map(arr[:, 2])
    kd = KDTree(len(arr))
    for i, c in enumerate(arr):
        kd.insert(Vector(c), i)
    kd.balance()
    hem = min((g.matrix_world @ v.co).z for g in clothes if g.name == "P_" + R["hem_from"] for v in g.data.vertices) + 0.03
    lab_of = []
    for p in ob.data.polygons:
        _, i, _ = kd.find(p.center)
        lab = labels[i]
        if lab == "pants":
            lab = "pants_low" if p.center.z < hem else "pants_up"
        lab_of.append(lab)
    out = []
    for lab in ["top", "pants_up", "pants_low", "shoes"]:
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="DESELECT")
        bpy.ops.object.mode_set(mode="OBJECT")
        n = 0
        for p, l in zip(ob.data.polygons, lab_of):
            p.select = (l == lab)
            n += int(p.select)
        if n == 0:
            continue
        before = set(bpy.data.objects)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.separate(type="SELECTED")
        bpy.ops.object.mode_set(mode="OBJECT")
        part = [o for o in bpy.data.objects if o not in before][0]
        part.name = part.data.name = R["prefix"] + lab
        lab_of = [l for l in lab_of if l != lab]
        out.append(part)
        print("REGION %s: 면 %d" % (part.name, n))
    return out


def skin_garment(g, rig):
    g.parent = rig
    mod = g.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    groups = {b.name: g.vertex_groups.new(name=b.name) for b in rig.data.bones}
    for v in g.data.vertices:
        w = weights_for(v.co)
        tot = sum(w.values())
        for name, val in w.items():
            if val / tot > 0.001:
                groups[name].add([v.index], val / tot, "REPLACE")


# ---------- 남성 기본 착장(2026-11-23, docs/56) ----------
# CFG outfit: 대머리 v2 몸 위에 Blender로 머리카락·흰 티·청바지·암벽화·초크백을 만든다(Tripo·OpenAI 생성 없음).
# 티·청바지는 몸 면을 복사해(가중치 그대로) 천처럼 매끈하게 한 뒤 띄우고, 암벽화는 발의 볼록 껍질, 머리카락·초크백은 새 모양.
# 옷이 덮는 몸 면은 지운다(큰 자세에서 피부가 옷을 뚫고 나오지 않게). 아래 높이·위치는 대머리 v2 몸에서 잰 값(게임 좌표, m).
import bmesh
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

# 색(sRGB). 텍스처 한 장(32px, 8px 칸)에 모아 UV로 고른다. 텍스처 캐릭터와 같은 조명(toon texture_light/π)을 받게.
OUTFIT_COLORS = {
    "tee": (0.94, 0.94, 0.92), "jeans": (0.30, 0.43, 0.62), "shoe_upper": (0.66, 0.66, 0.65), "shoe_rubber": (0.17, 0.17, 0.18),
    "hair": (0.29, 0.20, 0.14), "chalk": (0.56, 0.56, 0.57), "belt": (0.30, 0.30, 0.31), "inside": (0.10, 0.10, 0.10),
}
TEE_HEM, TEE_SLEEVE = 0.06, 0.34              # 티 아랫단 높이, 소매 끝 |x|
JEANS_TOP_FRONT, JEANS_TOP_BACK, JEANS_HEM = 0.10, 0.115, -0.845
SHOE_TOP = -0.835                             # 암벽화 발목 둘레 높이(발바닥 −0.915에서 8cm)
NECK_AXIS = Vector((0.0, -0.05))              # 목 중심(x, y)
HEAD_C = Vector((0.0, -0.04, 0.70))           # 머리카락 광선 중심(머리 안)
CHALK_C, CHALK_R, CHALK_Z = Vector((0.0, -0.192)), 0.046, (0.012, 0.135)
BELT_Z, BELT_OFF = (0.114, 0.130), 0.004


def pal_uv(key):
    i = list(OUTFIT_COLORS).index(key)
    return ((i % 4) + 0.5) / 4, ((i // 4) + 0.5) / 4


def outfit_material():
    img = bpy.data.images.new("tex_outfit", 32, 32)
    px = np.ones((32, 32, 4), dtype=np.float32)
    for i, c in enumerate(OUTFIT_COLORS.values()):
        cx, cy = i % 4, i // 4
        px[cy * 8:(cy + 1) * 8, cx * 8:(cx + 1) * 8, :3] = c
    img.pixels.foreach_set(px.ravel())
    img.update()
    img.pack()
    mat = bpy.data.materials.new("M_outfit")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 1.0
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def cut(bm, f):
    """bm을 f(co) = 0인 면으로 자른다(모서리를 나누고 면 안을 잇는다). 나눈 정점은 UV·가중치가 섞여 들어간다."""
    val = {v: f(v.co) for v in bm.verts}
    new = set()
    for e in list(bm.edges):
        a, b = e.verts
        fa, fb = val[a], val[b]
        if (fa < 0.0) != (fb < 0.0) and fa != fb:
            t = fa / (fa - fb)
            pa, pb = a.co.copy(), b.co.copy()
            _, nv = bmesh.utils.edge_split(e, a, t)
            nv.co = pa.lerp(pb, t)
            val[nv] = 0.0
            new.add(nv)
    for fc in list(bm.faces):
        vs = [v for v in fc.verts if v in new]
        if len(vs) == 2 and bm.edges.get(vs) is None:
            bmesh.ops.connect_verts(bm, verts=vs)
    bmesh.ops.triangulate(bm, faces=[fc for fc in bm.faces if len(fc.verts) > 3])


def region_object(body, rig, name, fields, inside):
    """몸 면 중 inside(면 중심)인 것을 복사해 새 메시로(가중치·윤곽선 굵기 그대로). fields로 먼저 잘라 경계가 깔끔하다."""
    bm = bmesh.new()
    bm.from_mesh(body.data)
    for f in fields:
        cut(bm, f)
    bmesh.ops.delete(bm, geom=[fc for fc in bm.faces if not inside(fc.calc_center_median())], context="FACES")
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.003)
    return bm_object(bm, name, body, rig)


def bm_object(bm, name, body, rig):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    for g in body.vertex_groups:
        ob.vertex_groups.new(name=g.name)
    ob.parent = rig
    ob.modifiers.new("Armature", "ARMATURE").object = rig
    for p in me.polygons:
        p.use_smooth = True
    return ob


def coords(me):
    co = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co)
    return co.reshape(-1, 3)


def normals(me, smooth=4):
    """정점 법선을 이웃과 smooth번 평균(가는 삼각형 법선이 튀어 띄울 때 가시가 생기지 않게)."""
    me.update()
    n = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("normal", n)
    n = n.reshape(-1, 3)
    ev = np.empty(len(me.edges) * 2, dtype=np.int64)
    me.edges.foreach_get("vertices", ev)
    ev = ev.reshape(-1, 2)
    for _ in range(smooth):
        acc = n.copy()
        np.add.at(acc, ev[:, 0], n[ev[:, 1]])
        np.add.at(acc, ev[:, 1], n[ev[:, 0]])
        n = acc / np.maximum(np.linalg.norm(acc, axis=1, keepdims=True), 1e-9)
    return n


def boundary_mask(me):
    le = np.empty(len(me.loops), dtype=np.int64)
    me.loops.foreach_get("edge_index", le)
    once = np.bincount(le, minlength=len(me.edges)) == 1
    ev = np.empty(len(me.edges) * 2, dtype=np.int64)
    me.edges.foreach_get("vertices", ev)
    m = np.zeros(len(me.vertices), dtype=bool)
    m[ev.reshape(-1, 2)[once].ravel()] = True
    return m


def taubin(me, iters, pin):
    """줄지 않는 매끈하게(Taubin λ|μ). 몸의 근육·뼈 굴곡을 지워 천처럼. pin 정점은 그대로."""
    co = coords(me)
    ev = np.empty(len(me.edges) * 2, dtype=np.int64)
    me.edges.foreach_get("vertices", ev)
    ev = ev.reshape(-1, 2)
    deg = np.maximum(np.bincount(ev.ravel(), minlength=len(co)), 1)[:, None]
    for _ in range(iters):
        for lam in (0.5, -0.53):
            acc = np.zeros_like(co)
            np.add.at(acc, ev[:, 0], co[ev[:, 1]])
            np.add.at(acc, ev[:, 1], co[ev[:, 0]])
            d = acc / deg - co
            d[pin] = 0.0
            co += lam * d
    me.vertices.foreach_set("co", co.ravel())
    me.update()


def envelope(me, bvh, iters, pin, mask=None):
    """천처럼: 라플라스로 매끈하게 하되 몸 안으로는 못 들어가게(가장 가까운 몸 면 바깥에 둔다). 볼록한 곳은 몸에 붙고
    오목한 곳(복근·등 골·무릎 뒤)은 메워진다. mask(0~1)로 겨드랑이·가랑이는 덜(물갈퀴처럼 메워지지 않게)."""
    co = coords(me)
    ev = np.empty(len(me.edges) * 2, dtype=np.int64)
    me.edges.foreach_get("vertices", ev)
    ev = ev.reshape(-1, 2)
    deg = np.maximum(np.bincount(ev.ravel(), minlength=len(co)), 1)[:, None]
    k = np.full(len(co), 0.5) if mask is None else 0.5 * mask
    k[pin] = 0.0
    for _ in range(iters):
        acc = np.zeros_like(co)
        np.add.at(acc, ev[:, 0], co[ev[:, 1]])
        np.add.at(acc, ev[:, 1], co[ev[:, 0]])
        co += k[:, None] * (acc / deg - co)
        for i in np.nonzero(k > 0)[0]:
            q, nq, _, _ = bvh.find_nearest(Vector(co[i]))
            if q is not None:
                sd = (Vector(co[i]) - q).dot(nq)
                if sd < 0.0:
                    co[i] -= sd * np.array(nq)
    me.vertices.foreach_set("co", co.ravel())
    me.update()


def inflate(ob, off):
    """법선 방향으로 off(정점 위치 배열 → 거리 배열)만큼 띄운다. 띄운 거리를 돌려준다(가장자리 테두리용)."""
    me = ob.data
    co, n = coords(me), normals(me)
    d = off(co)
    me.vertices.foreach_set("co", (co + n * d[:, None]).ravel())
    me.update()
    return d


def rim(ob, depth):
    """열린 가장자리를 몸 쪽(법선 반대)으로 depth[정점]만큼 접어 넣어 천 두께처럼 보이게(가장자리 틈 가리기)."""
    me = ob.data
    n = normals(me)
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    key = lambda c: (round(c.x, 6), round(c.y, 6), round(c.z, 6))
    src = {key(v.co): v.index for v in bm.verts if v.is_boundary}
    old = set(bm.verts)
    bmesh.ops.extrude_edge_only(bm, edges=[e for e in bm.edges if e.is_boundary])
    for v in bm.verts:
        if v not in old:
            i = src.get(key(v.co))
            if i is not None:
                v.co = v.co - Vector(n[i]) * depth[i]
    bm.to_mesh(me)
    bm.free()
    me.update()


def paint(ob, key_of_face):
    """면마다 색 칸(UV)을 준다. key_of_face(면) → OUTFIT_COLORS 키."""
    me = ob.data
    uv = me.uv_layers.active or me.uv_layers.new(name="UVMap")
    for p in me.polygons:
        u, v = pal_uv(key_of_face(p))
        for li in p.loop_indices:
            uv.data[li].uv = (u, v)


def ensure_col(ob, w=1.0):
    me = ob.data
    if "Col" not in me.color_attributes:
        a = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
        cols = np.ones((len(me.vertices), 4), dtype=np.float32)
        cols[:, :3] = w
        a.data.foreach_set("color", cols.ravel())
    me.color_attributes.active_color = me.color_attributes["Col"]


def set_weights(ob, fn):
    """새로 만든 물체(머리카락·초크백): fn(co) → {뼈: 가중치}."""
    for v in ob.data.vertices:
        w = fn(v.co)
        tot = sum(w.values())
        for k, val in w.items():
            ob.vertex_groups[k].add([v.index], val / tot, "REPLACE")


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


# --- 흰 티 ---
def collar_z(p):
    th = math.atan2(p.x - NECK_AXIS.x, p.y - NECK_AXIS.y)   # 0 = 앞
    return 0.574 - 0.02 * math.cos(th) - 0.009 * math.cos(2 * th)


def neck_skin(p):
    """목·머리(티 밖): 목 축에서 0.12 안이고 목둘레선 위."""
    r = math.hypot(p.x - NECK_AXIS.x, p.y - NECK_AXIS.y)
    return p.z > collar_z(p) and (r < 0.12 or p.z > 0.6)


def in_tee(p):
    return p.z > TEE_HEM and abs(p.x) < TEE_SLEEVE and not neck_skin(p)


def tee(body, rig, bvh):
    fields = [lambda c: c.z - TEE_HEM, lambda c: abs(c.x) - TEE_SLEEVE,
              lambda c: (c.z - collar_z(c)) if math.hypot(c.x - NECK_AXIS.x, c.y - NECK_AXIS.y) < 0.12 and c.z < 0.62 else -1.0]
    ob = region_object(body, rig, "P_top_white_tee", fields, in_tee)
    co = coords(ob.data)
    armpit = np.hypot(np.abs(co[:, 0]) - 0.165, co[:, 2] - ARMPIT)
    envelope(ob.data, bvh, 40, boundary_mask(ob.data), np.clip(armpit / 0.07, 0.15, 1.0))

    def off(co):
        hem = 0.012 * smoothstep(TEE_HEM + 0.10, TEE_HEM, co[:, 2])          # 아랫단 퍼짐
        sleeve = 0.010 * smoothstep(TEE_SLEEVE - 0.10, TEE_SLEEVE, np.abs(co[:, 0]))   # 소매 퍼짐
        return 0.009 + hem + sleeve
    d = inflate(ob, off)
    rim(ob, d * 0.9)
    paint(ob, lambda p: "tee")
    return ob


# --- 청바지 ---
def jeans_top(p):
    return JEANS_TOP_BACK + (JEANS_TOP_FRONT - JEANS_TOP_BACK) * min(1.0, max(0.0, (p.y + 0.12) / 0.18))


def in_jeans(p):
    return JEANS_HEM < p.z < jeans_top(p) and abs(p.x) < 0.30


def jeans(body, rig, bvh):
    ob = region_object(body, rig, "P_pants_jeans", [lambda c: c.z - JEANS_HEM, lambda c: c.z - jeans_top(c)], in_jeans)
    co = coords(ob.data)
    crotch = np.hypot(co[:, 0], co[:, 2] - CROTCH_APEX)
    envelope(ob.data, bvh, 30, boundary_mask(ob.data), np.clip(crotch / 0.07, 0.15, 1.0))

    def off(co):
        flare = 0.012 * smoothstep(-0.45, JEANS_HEM, co[:, 2])               # 무릎 아래로 곧게 퍼짐
        waist = 0.003 * smoothstep(0.02, 0.09, co[:, 2])                     # 허리(티 안)는 티보다 안쪽
        return 0.007 + flare - waist
    d = inflate(ob, off)
    rim(ob, d * 0.9)
    paint(ob, lambda p: "jeans")
    return ob


# --- 암벽화(벨크로 두 줄, 글자·로고 없음) ---
def in_shoe(p):
    return p.z < SHOE_TOP


def copy_weights(ob, body, near):
    """ob 정점마다 가장 가까운 몸 정점(near(co)가 참인 것 중)의 가중치를 그대로 쓴다."""
    bv = [v for v in body.data.vertices if near(v.co)]
    kd = KDTree(len(bv))
    for i, v in enumerate(bv):
        kd.insert(v.co, i)
    kd.balance()
    names = [g.name for g in body.vertex_groups]
    for v in ob.data.vertices:
        _, i, _ = kd.find(v.co)
        for g in bv[i].groups:
            ob.vertex_groups[names[g.group]].add([v.index], g.weight, "REPLACE")


def shoes(body, rig):
    bm = bmesh.new()
    for s in (-1, 1):   # 발마다 볼록 껍질(발가락·발바닥 아치를 덮는 신발 모양)
        hb = bmesh.new()
        for v in body.data.vertices:
            if v.co.z < SHOE_TOP + 0.012 and v.co.x * s > 0.02:
                hb.verts.new(v.co)
        res = bmesh.ops.convex_hull(hb, input=hb.verts[:])
        drop = {g for g in res["geom_interior"] + res["geom_unused"] if isinstance(g, bmesh.types.BMVert)}
        bmesh.ops.delete(hb, geom=list(drop), context="VERTS")
        tmp = bpy.data.meshes.new("hull")
        hb.to_mesh(tmp)
        hb.free()
        bm.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
    ob = bm_object(bm, "P_shoes_velcro", body, rig)
    ob.modifiers.clear()
    rm = ob.modifiers.new("remesh", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = 0.011
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier=rm.name)
    taubin(ob.data, 4, np.zeros(len(ob.data.vertices), dtype=bool))
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    cut(bm, lambda c: c.z - SHOE_TOP)
    bmesh.ops.delete(bm, geom=[fc for fc in bm.faces if fc.calc_center_median().z > SHOE_TOP], context="FACES")
    bm.to_mesh(ob.data)
    bm.free()
    for p in ob.data.polygons:
        p.use_smooth = True
    copy_weights(ob, body, lambda c: c.z < SHOE_TOP + 0.04)
    ob.modifiers.new("Armature", "ARMATURE").object = rig
    d = inflate(ob, lambda co: np.full(len(co), 0.003))
    rim(ob, d + 0.004)
    me = ob.data
    co = coords(me)
    feet = {}
    for s in (-1, 1):
        f = co[co[:, 0] * s > 0]
        feet[s] = (f[:, 2].min(), f[:, 1].min(), f[:, 1].max())

    def hu(c):
        sole, heel, toe = feet[1 if c.x > 0 else -1]
        return c.z - sole, (c.y - heel) / (toe - heel)

    def rand(u):
        return 0.018 + 0.030 * float(smoothstep(0.70, 1.0, u)) + 0.030 * float(smoothstep(0.40, 0.0, u))
    STRAPS = ((0.40, 0.51), (0.56, 0.67))   # 벨크로 띠(발 길이 비율)
    bm = bmesh.new()
    bm.from_mesh(me)
    cut(bm, lambda c: hu(c)[0] - rand(hu(c)[1]))
    for a, b in STRAPS:
        for t in (a, b):
            cut(bm, lambda c, t=t: hu(c)[1] - t)
    bm.to_mesh(me)
    bm.free()

    def key(p):
        h, u = hu(p.center)
        if h < rand(u) or p.normal.z < -0.6:
            return "shoe_rubber"
        if any(a < u < b for a, b in STRAPS) and h > 0.03:
            return "shoe_rubber"
        return "shoe_upper"
    paint(ob, key)
    return ob


# --- 머리카락(첨부 그림: 둥근 바가지 머리, 앞머리 눈썹까지, 귀 보임) ---
def hem_z(th_deg):
    a = abs(th_deg)
    return float(np.interp(a, [0, 45, 70, 95, 120, 150, 180], [0.731, 0.731, 0.716, 0.710, 0.692, 0.664, 0.652]))


def hem_off(th_deg):
    a = abs(th_deg)
    return float(np.interp(a, [0, 40, 70, 100, 180], [0.013, 0.015, 0.022, 0.027, 0.023]))


def zig(th_deg):
    """앞머리·뒷머리 끝 뾰족한 다발(삼각파, 아래로)."""
    a = abs(th_deg)
    amp = float(np.interp(a, [0, 55, 75, 120, 150, 180], [0.016, 0.016, 0.004, 0.0, 0.008, 0.008]))
    per = 14.0 if a < 90 else 16.0
    t = (th_deg / per) % 1.0
    return amp * (1.0 - abs(2.0 * t - 1.0))


def hair(body, rig):
    me0 = body.data
    bvh = BVHTree.FromPolygons([v.co.copy() for v in me0.vertices], [p.vertices[:] for p in me0.polygons])
    NT, NR = 144, 14

    def direc(th, al):
        return Vector((math.sin(al) * math.sin(th), math.sin(al) * math.cos(th), math.cos(al)))

    def hit(th, al):
        d = direc(th, al)
        loc, _, _, _ = bvh.ray_cast(HEAD_C, d, 0.4)
        return loc, d

    def alpha_for(th, z):
        lo, hi = 0.3, 2.6
        for _ in range(30):
            mid = (lo + hi) / 2
            if hit(th, mid)[0].z > z:
                lo = mid
            else:
                hi = mid
        return (lo + hi) / 2
    bm = bmesh.new()
    rows = []
    inner = []
    for j in range(NT):
        th = 2 * math.pi * j / NT
        td = math.degrees(th) if th <= math.pi else math.degrees(th) - 360
        a_base = alpha_for(th, hem_z(td))
        a_zig = alpha_for(th, hem_z(td) - zig(td))
        col = []
        for i in range(1, NR + 1):
            s = i / NR
            al = a_base * s if i < NR else a_zig
            p, d = hit(th, al)
            off = 0.030 + (hem_off(td) - 0.030) * float(smoothstep(0.55, 1.0, s))
            col.append(bm.verts.new(p + d * off))
        rows.append(col)
        p, d = hit(th, a_zig)
        inner.append(bm.verts.new(p + d * 0.002))
    top_p, _ = hit(0.0, 0.0)
    top = bm.verts.new(top_p + Vector((0, 0, 0.030)))
    faces = []
    for j in range(NT):
        k = (j + 1) % NT
        faces.append(("dome", bm.faces.new((top, rows[j][0], rows[k][0]))))
        for i in range(NR - 1):
            faces.append(("dome", bm.faces.new((rows[j][i], rows[j][i + 1], rows[k][i + 1], rows[k][i]))))
        faces.append(("rim", bm.faces.new((rows[j][-1], inner[j], inner[k], rows[k][-1]))))
    bm.normal_update()
    for kind, fc in faces:
        c = fc.calc_center_median()
        r = c - HEAD_C
        if kind == "dome":
            want = r
        else:   # 끝 테두리: 자오선 아래쪽
            th = math.atan2(r.x, r.y)
            al = math.acos(max(-1.0, min(1.0, r.normalized().z)))
            want = Vector((math.cos(al) * math.sin(th), math.cos(al) * math.cos(th), -math.sin(al)))
        if fc.normal.dot(want) < 0:
            fc.normal_flip()
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    ob = bm_object(bm, "P_hair_bowl", body, rig)
    set_weights(ob, lambda c: {"head": 1.0})
    paint(ob, lambda p: "hair")
    ensure_col(ob)
    return ob


# --- 초크백(회색, 허리띠) ---
def chalk(body, rig, top):
    """top: 티(띠는 티 위에 BELT_OFF 띄운다)."""
    me0 = top.data
    bvh = BVHTree.FromPolygons([v.co.copy() for v in me0.vertices], [p.vertices[:] for p in me0.polygons])
    bm = bmesh.new()
    N = 24
    # 몸통 + 바닥: 반지름(높이 비율) — 아래는 둥글게
    prof = [(0.0, 0.0), (0.012, 0.6), (0.025, 0.88), (0.045, 1.0), (CHALK_Z[1] - CHALK_Z[0] - 0.014, 1.0), (CHALK_Z[1] - CHALK_Z[0], 1.06)]
    ringv = []
    for h, k in prof:
        ring = []
        for j in range(N):
            a = 2 * math.pi * j / N
            ring.append(bm.verts.new((CHALK_C.x + CHALK_R * k * math.sin(a), CHALK_C.y + CHALK_R * k * math.cos(a) * 0.80, CHALK_Z[0] + h)))
        ringv.append(ring)
    # 입구 안쪽 벽 + 바닥(어둡게)
    in_top = [bm.verts.new((v.co.x - (v.co.x - CHALK_C.x) * 0.12, v.co.y - (v.co.y - CHALK_C.y) * 0.12, v.co.z)) for v in ringv[-1]]
    in_bot = [bm.verts.new((v.co.x, v.co.y, v.co.z - 0.016)) for v in in_top]
    faces = []
    bottom = bm.verts.new((CHALK_C.x, CHALK_C.y, CHALK_Z[0]))
    for j in range(N):
        k = (j + 1) % N
        faces.append(("chalk", bm.faces.new((bottom, ringv[1][k], ringv[1][j]))))
        for i in range(1, len(prof) - 1):
            faces.append(("chalk", bm.faces.new((ringv[i][j], ringv[i][k], ringv[i + 1][k], ringv[i + 1][j]))))
        faces.append(("chalk", bm.faces.new((ringv[-1][j], ringv[-1][k], in_top[k], in_top[j]))))
        faces.append(("inside", bm.faces.new((in_top[j], in_top[k], in_bot[k], in_bot[j]))))
    faces.append(("inside", bm.faces.new(in_bot)))
    # 허리띠: 몸에서 수평 광선으로 둘레를 재 BELT_OFF 띄운 띠
    NB = 48
    belt = []
    for z in BELT_Z:
        ring = []
        for j in range(NB):
            a = 2 * math.pi * j / NB
            d = Vector((math.sin(a), math.cos(a), 0.0))
            o = Vector((0.0, -0.03, z))
            loc, _, _, _ = bvh.ray_cast(o, d, 0.4)
            ring.append(bm.verts.new(loc + d * BELT_OFF))
        belt.append(ring)
    for j in range(NB):
        k = (j + 1) % NB
        faces.append(("belt", bm.faces.new((belt[0][j], belt[0][k], belt[1][k], belt[1][j]))))
    # 가방 고리(허리띠가 가방 뒤 고리를 지난다): 띠 뒤에서 가방 앞까지 작은 상자
    yb = belt[0][NB // 2].co.y
    y0, y1 = yb + 0.003, CHALK_C.y + CHALK_R * 0.80 - 0.004
    z0, z1 = BELT_Z[0] - 0.003, BELT_Z[1] + 0.003
    box = [bm.verts.new((x, y, z)) for x in (-0.016, 0.016) for y in (y0, y1) for z in (z0, z1)]
    for q in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (1, 5, 7, 3), (0, 2, 6, 4)):
        faces.append(("loop", bm.faces.new([box[i] for i in q])))
    bm.normal_update()
    for key, fc in faces:
        c = fc.calc_center_median()
        if key == "belt":
            want = Vector((c.x, c.y + 0.03, 0.0))
        elif key == "loop":
            want = c - Vector((0.0, (y0 + y1) / 2, (z0 + z1) / 2))
        elif fc.verts[0] in in_top or fc.verts[0] in in_bot:
            want = Vector((CHALK_C.x - c.x, CHALK_C.y - c.y, 0.0)) if len(fc.verts) == 4 else Vector((0, 0, 1))
        else:
            want = c - Vector((CHALK_C.x, CHALK_C.y, CHALK_Z[0] + 0.06))
        if fc.normal.dot(want) < 0:
            fc.normal_flip()
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    ob = bm_object(bm, "P_chalk_gray", body, rig)
    set_weights(ob, lambda c: torso_weights(c.z) if abs(c.y + 0.03) < 0.2 and abs(c.z - sum(BELT_Z) / 2) < 0.012 and math.hypot(c.x - CHALK_C.x, (c.y - CHALK_C.y) / 0.80) > CHALK_R * 1.2 else {"pelvis": 1.0})

    def key(p):
        c = p.center
        if abs(c.x) < 0.017 and y1 - 0.001 < c.y < y0 + 0.001 and z0 - 0.001 < c.z < z1 + 0.001:
            return "belt"
        if abs(c.z - sum(BELT_Z) / 2) < 0.0085 and math.hypot(c.x - CHALK_C.x, (c.y - CHALK_C.y) / 0.80) > CHALK_R * 1.15:
            return "belt"
        rr = math.hypot(c.x - CHALK_C.x, (c.y - CHALK_C.y) / 0.80)
        if c.z > CHALK_Z[1] - 0.02 and rr < CHALK_R * 0.99 and (p.normal.z > 0.5 or rr < CHALK_R * 0.97):
            return "inside"
        return "chalk"
    paint(ob, key)
    ensure_col(ob)
    return ob


def trim_body(body, regions):
    """옷이 덮는 몸 면을 지운다. regions = [(안인가(점), margin)]: 옷마다 그 옷 경계에서 margin보다 안쪽인 면만
    (가장자리 아래 몸은 남겨 틈으로 뒤가 비치지 않게)."""
    me = body.data
    le = np.empty(len(me.loops), dtype=np.int64)
    me.loops.foreach_get("edge_index", le)
    ln = np.empty(len(me.polygons), dtype=np.int64)
    me.polygons.foreach_get("loop_total", ln)
    face_of_loop = np.repeat(np.arange(len(me.polygons)), ln)
    ev = np.empty(len(me.edges) * 2, dtype=np.int64)
    me.edges.foreach_get("vertices", ev)
    ev = ev.reshape(-1, 2)
    centers = [p.center.copy() for p in me.polygons]
    kill = np.zeros(len(me.polygons), dtype=bool)
    for inside_fn, margin in regions:
        inside = np.array([inside_fn(c) for c in centers])
        ins_e = np.zeros(len(me.edges), dtype=np.int64)
        out_e = np.zeros(len(me.edges), dtype=np.int64)
        np.add.at(ins_e, le, inside[face_of_loop])
        np.add.at(out_e, le, ~inside[face_of_loop])
        bverts = np.unique(ev[(ins_e > 0) & (out_e > 0)].ravel())
        kd = KDTree(len(bverts))
        for i, vi in enumerate(bverts):
            kd.insert(me.vertices[vi].co, i)
        kd.balance()
        for fi in np.nonzero(inside)[0]:
            if kd.find(centers[fi])[2] > margin:
                kill[fi] = True
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[bm.faces[i] for i in np.nonzero(kill)[0]], context="FACES")
    bm.to_mesh(me)
    bm.free()
    print("TRIM: 몸 면 %d개 지움(덮인 곳), 남은 삼각형 %d" % (int(kill.sum()), len(me.polygons)))


def build_outfit(body, rig):
    mat = outfit_material()
    me0 = body.data
    bvh = BVHTree.FromPolygons([v.co.copy() for v in me0.vertices], [p.vertices[:] for p in me0.polygons])
    t = tee(body, rig, bvh)
    parts = [hair(body, rig), t, jeans(body, rig, bvh), shoes(body, rig), chalk(body, rig, t)]
    for ob in parts:
        ob.data.materials.clear()
        ob.data.materials.append(mat)
        ensure_col(ob)
        print("OUTFIT %s: 삼각형 %d" % (ob.name, sum(len(p.vertices) - 2 for p in ob.data.polygons)))
    trim_body(body, [(in_tee, 0.03), (in_jeans, 0.03), (in_shoe, 0.02)])
    return parts


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
    clothes = []
    for gid, fname, push in CFG.get("garments", []):
        g = garment(gid, os.path.join(REPO, CFG["garment_dir"], fname), push)
        skin_garment(g, rig)
        clothes.append(g)
    clothes += split_regions(ob, clothes)
    if CFG.get("outfit"):
        clothes += build_outfit(ob, rig)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    for g in clothes:
        g.select_set(True)
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
