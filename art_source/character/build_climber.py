"""등반자 캐릭터 CH02 생성 스크립트 (Blender 5.x 배경 실행).
실행: blender -b --python art_source/character/build_climber.py

CH02(2026-11-07 사용자 캐릭터 시트): 갈색 곱슬 머리, 흰 반팔 티, 푸른 청바지, 검은 벨트,
오른쪽 뒤 회색 초크백, 회색 벨크로 클라이밍화. 얼굴 표정 4종(FX_face_*)은 별도 메시로 내보내
play_3d가 상황에 맞게 하나만 보인다(평온·힘씀·기쁨·놀람).

- 뼈 길이·관절 위치는 docs/04 좌표·크기 계약을 따른다(골반=원점, 팔 0.40/0.38, 다리 0.52/0.48,
  어깨 골반 기준 X±0.20·높이 0.55, 고관절 X±0.14). 뼈 이름·계층은 CH01과 같다(RigPose.BONES).
- Blender 축: X 오른쪽, Z 위, +Y = 벽 방향(캐릭터 앞). glTF/Godot에서는 등이 +Z(카메라)를 향한다.
- 몸은 관절 그래프에 Skin 모디파이어를 씌운 하나의 메시, 의상 구역은 머티리얼 이름(M_*)으로 나눈다.
- 결과: game/art/characters/climber.glb
"""
import bpy, bmesh, math, os, random
from mathutils import Vector

REPO = os.path.expanduser("~/Projects/climb_game")
OUT_GLB = os.path.join(REPO, "game/art/characters/climber.glb")

ARM_UP, ARM_LO, LEG_UP, LEG_LO = 0.40, 0.38, 0.52, 0.48
SH_X, SH_Z, HIP_X = 0.20, 0.55, 0.14
HEAD_R = 0.135
HEAD_C = Vector((0, 0.015, 0.815))

# 캐릭터 시트 팔레트(play_3d.CHARACTER_COLORS와 같은 값)
PALETTE = {
    "M_hair": "6b4129", "M_skin": "e8b48e", "M_shirt": "f1ebe0", "M_pants": "4f6b9e",
    "M_belt": "3a393b", "M_buckle": "8c8c8c", "M_chalk": "7a7472", "M_chalk_rim": "4a4645",
    "M_shoe": "a39c94", "M_strap": "c4beb5", "M_rubber": "3d3a38",
    "M_face_eye": "2a1d18", "M_face_hi": "ffffff", "M_face_mouth": "8a3a34", "M_face_brow": "4a2c1c",
    "M_face_cheek": "f29a8a", "M_face_teeth": "fbf7f0",
}


def hexcol(h):
    return tuple((int(h[i:i + 2], 16) / 255) ** 2.2 for i in (0, 2, 4)) + (1.0,)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = hexcol(PALETTE[name])
    bsdf.inputs["Roughness"].default_value = 1.0
    m.diffuse_color = hexcol(PALETTE[name])
    return m


def new_obj(name, bm, mat):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    me.materials.append(material(mat))
    return ob


# ---------- 관절 ----------
def joints():
    J = {"pelvis": Vector((0, 0, 0)), "spine": Vector((0, 0, 0.22)), "chest": Vector((0, 0.01, 0.44)),
         "neck": Vector((0, 0.01, 0.63)), "head": Vector((0, 0.01, 0.80)), "head_top": Vector((0, 0.01, 0.94))}
    for s, sx in (("L", -1), ("R", 1)):
        arm_dir = Vector((sx * math.cos(math.radians(25)), 0, -math.sin(math.radians(25))))
        sh = Vector((sx * SH_X, 0.0, SH_Z))
        J["shoulder_" + s] = sh
        J["elbow_" + s] = sh + arm_dir * ARM_UP
        J["wrist_" + s] = J["elbow_" + s] + arm_dir * ARM_LO
        J["hand_" + s] = J["wrist_" + s] + arm_dir * 0.09
        hip = Vector((sx * HIP_X, 0, 0))
        leg = Vector((sx * math.sin(math.radians(4)), 0, -math.cos(math.radians(4))))
        J["hip_" + s] = hip
        J["knee_" + s] = hip + leg * LEG_UP
        J["ankle_" + s] = J["knee_" + s] + leg * LEG_LO
        J["toe_" + s] = J["ankle_" + s] + Vector((0, 0.15, -0.05))
    return J


EDGES = [("pelvis", "spine"), ("spine", "chest"), ("chest", "neck"), ("neck", "head"),
         ("chest", "shoulder_L"), ("chest", "shoulder_R"), ("pelvis", "hip_L"), ("pelvis", "hip_R")]
for s in "LR":
    EDGES += [("shoulder_" + s, "elbow_" + s), ("elbow_" + s, "wrist_" + s), ("wrist_" + s, "hand_" + s),
              ("hip_" + s, "knee_" + s), ("knee_" + s, "ankle_" + s), ("ankle_" + s, "toe_" + s)]

# (X, Y) 반지름. 헐렁한 티(가슴·배), 곧은 청바지(무릎·발목이 굵음), 둥근 신발 앞코.
RADII = {"pelvis": (0.165, 0.125), "spine": (0.16, 0.12), "chest": (0.185, 0.125), "neck": (0.055, 0.055),
         "head": (0.05, 0.05), "shoulder": (0.075, 0.075), "elbow": (0.05, 0.05), "wrist": (0.037, 0.035),
         "hand": (0.046, 0.03), "hip": (0.12, 0.12), "knee": (0.085, 0.085), "ankle": (0.08, 0.072),
         "toe": (0.072, 0.056)}


def base(name):
    return name.split("_")[0]


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (a + ab * t - p).length, t


def zone(seg, t, c, J):
    a, b = seg
    if (a, b) == ("pelvis", "spine"):
        return "M_pants" if t < 0.30 else "M_shirt"
    if (a, b) == ("shoulder", "elbow"):
        return "M_shirt" if t < 0.50 else "M_skin"  # 반팔
    if (a, b) == ("chest", "neck") and t < 0.30:
        return "M_shirt"  # 목둘레
    if (a, b) in (("chest", "neck"), ("neck", "head"), ("elbow", "wrist"), ("wrist", "hand")):
        return "M_skin"
    if (a, b) in (("pelvis", "hip"), ("hip", "knee"), ("knee", "ankle")):
        return "M_shoe" if (a, b) == ("knee", "ankle") and t > 0.86 else "M_pants"
    if (a, b) == ("ankle", "toe"):
        return "M_shoe"
    return "M_shirt"


def build_body(J):
    used = [n for n in J if n != "head_top"]
    idx = {n: i for i, n in enumerate(used)}
    mesh = bpy.data.meshes.new("CH02_body")
    mesh.from_pydata([J[n] for n in used], [(idx[a], idx[b]) for a, b in EDGES], [])
    ob = bpy.data.objects.new("CH02_body", mesh)
    bpy.context.collection.objects.link(ob)
    skin = ob.modifiers.new("Skin", "SKIN")
    skin.branch_smoothing = 0.6
    for n, i in idx.items():
        sv = mesh.skin_vertices[0].data[i]
        sv.radius = RADII[base(n)]
        sv.use_root = n == "pelvis"
    ob.modifiers.new("Sub", "SUBSURF").levels = 1
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.modifier_apply(modifier="Skin")
    bpy.ops.object.modifier_apply(modifier="Sub")
    # 티 밑단이 벨트 위로 살짝 부풀고, 청바지 밑단이 신발 위에서 퍼진다.
    for v in mesh.vertices:
        if 0.08 < v.co.z < 0.20:
            v.co.x *= 1.05
            v.co.y *= 1.06
        if -0.87 < v.co.z < -0.80:
            for s, sx in (("L", -1), ("R", 1)):
                if v.co.x * sx > 0:
                    cx = J["ankle_" + s].x
                    v.co.x = cx + (v.co.x - cx) * 1.12
                    v.co.y *= 1.12
    names = ["M_shirt", "M_skin", "M_pants", "M_shoe", "M_rubber"]
    for name in names:
        mesh.materials.append(material(name))
    mi = {n: i for i, n in enumerate(names)}
    for poly in mesh.polygons:
        c = poly.center
        best, best_d, best_t = None, 9.0, 0.0
        for a, b in EDGES:
            d, t = seg_dist(c, J[a], J[b])
            if d < best_d:
                best, best_d, best_t = (base(a), base(b)), d, t
        mat = zone(best, best_t, c, J)
        if mat == "M_shoe":
            s = "L" if c.x < 0 else "R"
            sole = J["ankle_" + s].z - 0.035 - 0.25 * max(0.0, c.y - J["ankle_" + s].y)
            if c.z < sole or (best == ("ankle", "toe") and best_t > 0.82):
                mat = "M_rubber"  # 고무 밑창·앞코
        poly.material_index = mi[mat]
    return ob


# ---------- 머리 ----------
def on_head(u, v, lift=0.003):
    """얼굴 좌표(u 오른쪽, v 위, 머리 중심 기준) → 머리 앞면(+Y) 위 점."""
    r = HEAD_R + lift
    y = math.sqrt(max(r * r - u * u - v * v, 1e-6))
    return HEAD_C + Vector((u, y, v))


def build_head():
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=14, radius=HEAD_R)
    for v in bm.verts:
        v.co += HEAD_C
    head = new_obj("CH02_head", bm, "M_skin")
    # 귀
    parts = [head]
    for sx in (-1, 1):
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=6, radius=0.03)
        for v in bm.verts:
            v.co = Vector((v.co.x * 0.5, v.co.y * 0.8, v.co.z * 1.1)) + HEAD_C + Vector((sx * 0.133, 0.0, -0.01))
        parts.append(new_obj("CH02_ear", bm, "M_skin"))
    return parts


def build_hair(rnd):
    """덥수룩한 갈색 머리: 두피 덮개 + 사방으로 뻗은 뾰족한 다발 + 이마 앞머리."""
    bm = bmesh.new()
    r = HEAD_R + 0.014
    bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=14, radius=r)
    kill = []
    for v in bm.verts:
        s = v.co.y / r  # +1 앞(얼굴), -1 뒤통수
        thr = 0.058 if s > 0.5 else -0.075 + (s + 1.0) / 1.5 * 0.133
        if v.co.z < thr:
            kill.append(v)
    bmesh.ops.delete(bm, geom=kill, context="VERTS")
    for v in bm.verts:
        v.co = Vector((v.co.x * 1.04, v.co.y, v.co.z * 1.05)) + HEAD_C + Vector((0, -0.006, 0.006))
    parts = [new_obj("CH02_hair_cap", bm, "M_hair")]

    def spike(base_pt, direction, radius, depth):
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=5, radius1=radius, radius2=0.0, depth=depth)
        q = direction.normalized().to_track_quat("Z", "Y")
        for v in bm.verts:
            v.co = q @ (v.co + Vector((0, 0, depth * 0.5))) + base_pt
        parts.append(new_obj("CH02_hair_spike", bm, "M_hair"))

    # 정수리·옆·뒤 다발: 피보나치 반구 방향
    n = 26
    for i in range(n):
        z = 1.0 - (i + 0.5) / n * 1.35  # 위(1) → 귀 아래(-0.35)
        rr = math.sqrt(max(0.0, 1 - z * z))
        th = i * math.pi * (3 - math.sqrt(5))
        d = Vector((rr * math.cos(th), rr * math.sin(th), z))
        if d.y > 0.55 and d.z < 0.55:
            continue  # 얼굴 쪽은 비운다
        p = HEAD_C + d * (r * 0.92)
        down = Vector((0, -0.35, -1.0)).normalized()
        tang = (down - d * down.dot(d)).normalized()  # 머리 표면을 따라 아래·뒤로 눕는 방향
        out = (d * 0.55 + tang + Vector((rnd.uniform(-0.3, 0.3), 0, 0))).normalized()
        spike(p, out, rnd.uniform(0.045, 0.06), rnd.uniform(0.05, 0.075))
    # 앞머리: 이마로 내려오는 다발
    for u in (-0.07, -0.035, 0.0, 0.035, 0.07):
        p = HEAD_C + Vector((u * 1.15, 0.095, 0.095))
        out = Vector((u * 2.5 + rnd.uniform(-0.15, 0.15), 0.6, -1.0))
        spike(p, out, rnd.uniform(0.032, 0.04), rnd.uniform(0.05, 0.065))
    return parts


# ---------- 얼굴 ----------
def ribbon(name, pts, width, mat):
    """머리 앞면에 붙인 얇은 띠(눈썹·입선). pts: [(u, v)]."""
    bm = bmesh.new()
    rings = []
    for i, (u, v) in enumerate(pts):
        a = Vector(pts[max(0, i - 1)]); b = Vector(pts[min(len(pts) - 1, i + 1)])
        t = (b - a).normalized()
        nrm = Vector((-t.y, t.x)) * width * 0.5
        ring = []
        for (du, dv) in ((nrm.x, nrm.y), (-nrm.x, -nrm.y)):
            for lift in (0.0045, -0.002):
                ring.append(bm.verts.new(on_head(u + du, v + dv, lift)))
        rings.append(ring)  # [위바깥, 위안, 아래바깥, 아래안]
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        for (p, q) in ((0, 2), (2, 3), (3, 1), (1, 0)):
            bm.faces.new((a[p], a[q], b[q], b[p]))
    bm.faces.new((rings[0][0], rings[0][2], rings[0][3], rings[0][1]))
    bm.faces.new((rings[-1][1], rings[-1][3], rings[-1][2], rings[-1][0]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_obj(name, bm, mat)


def blob(name, u, v, size, mat, lift=0.0):
    """얼굴 면에 붙은 납작한 타원체(눈·입 구멍·볼)."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=6, radius=1.0)
    c = on_head(u, v, lift)
    nrm = (c - HEAD_C).normalized()
    q = nrm.to_track_quat("Y", "Z")
    for vt in bm.verts:
        vt.co = q @ Vector((vt.co.x * size[0], vt.co.y * size[1], vt.co.z * size[2])) + c
    return new_obj(name, bm, mat)


def arc(u0, u1, v_mid, sag, n=7):
    """u0..u1 사이 포물선. sag>0이면 가운데가 아래(웃는 입)."""
    out = []
    for i in range(n):
        t = i / (n - 1)
        u = u0 + (u1 - u0) * t
        out.append((u, v_mid - sag * (1 - (2 * t - 1) ** 2)))
    return out


def brows(name, inner_v, outer_v, arch):
    out = []
    for sx in (-1, 1):
        pts = []
        for i in range(5):
            t = i / 4
            u = sx * (0.022 + 0.042 * t)
            pts.append((u, inner_v + (outer_v - inner_v) * t + arch * math.sin(math.pi * t)))
        out.append(ribbon(name, pts, 0.011, "M_face_brow"))
    return out


def build_face():
    """눈은 늘 보이고, 표정 4종(눈썹·입·볼)은 FX_face_<이름> 하나로 묶는다."""
    eyes = []
    for sx in (-1, 1):
        eyes.append(blob("CH02_eye", sx * 0.047, 0.004, (0.016, 0.006, 0.024), "M_face_eye"))
        eyes.append(blob("CH02_eye_hi", sx * 0.047 + 0.006, 0.013, (0.0045, 0.004, 0.0045), "M_face_hi", 0.004))
    faces = {}
    # 평온: 살짝 웃는 입, 편한 눈썹
    faces["calm"] = brows("FX_face_calm", 0.045, 0.047, 0.006) + [
        ribbon("FX_face_calm", arc(-0.022, 0.022, -0.050, 0.007), 0.008, "M_face_mouth")]
    # 힘씀: 미간으로 내려온 눈썹, 이를 악문 입
    faces["effort"] = brows("FX_face_effort", 0.030, 0.052, 0.0) + [
        blob("FX_face_effort", 0.0, -0.052, (0.030, 0.006, 0.012), "M_face_mouth"),
        ribbon("FX_face_effort", [(-0.024, -0.052), (0.024, -0.052)], 0.007, "M_face_teeth")]
    # 기쁨: 올라간 눈썹, 크게 웃는 입, 볼 홍조
    faces["happy"] = brows("FX_face_happy", 0.053, 0.053, 0.010) + [
        ribbon("FX_face_happy", arc(-0.032, 0.032, -0.044, 0.020, 9), 0.012, "M_face_mouth"),
        blob("FX_face_happy", -0.070, -0.026, (0.016, 0.004, 0.010), "M_face_cheek"),
        blob("FX_face_happy", 0.070, -0.026, (0.016, 0.004, 0.010), "M_face_cheek")]
    # 놀람(떨어질 때): 치켜든 눈썹, 동그란 입
    faces["scared"] = brows("FX_face_scared", 0.066, 0.052, 0.004) + [
        blob("FX_face_scared", 0.0, -0.056, (0.012, 0.006, 0.016), "M_face_mouth")]
    return eyes, faces


# ---------- 벨트·초크백·신발 끈 ----------
def build_belt():
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=False, segments=20, radius1=1.0, radius2=1.0, depth=0.045)
    for v in bm.verts:
        v.co = Vector((v.co.x * 0.172, v.co.y * 0.132, v.co.z + 0.075))
    belt = new_obj("CH02_belt", bm, "M_belt")
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * 0.05, v.co.y * 0.012, v.co.z * 0.036)) + Vector((0, 0.136, 0.075))
    buckle = new_obj("CH02_buckle", bm, "M_buckle")
    return [belt, buckle]


def build_chalk_bag():
    """오른쪽 뒤(+X, -Y) 벨트에 매단 초크백."""
    at = Vector((0.115, -0.165, -0.03))
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=0.058, radius2=0.064, depth=0.13)
    for v in bm.verts:
        v.co = Vector((v.co.x, v.co.y * 0.9, v.co.z)) + at
    bag = new_obj("CH02_chalk", bm, "M_chalk")
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=0.068, radius2=0.068, depth=0.028)
    for v in bm.verts:
        v.co = Vector((v.co.x, v.co.y * 0.9, v.co.z + 0.065)) + at
    rim = new_obj("CH02_chalk_rim", bm, "M_chalk_rim")
    return [bag, rim]


def build_straps(J):
    out = {}
    for s in "LR":
        a, t = J["ankle_" + s], J["toe_" + s]
        parts = []
        for k in (0.25, 0.55):
            p = a + (t - a) * k + Vector((0, 0, 0.045 - 0.03 * k))
            bm = bmesh.new()
            bmesh.ops.create_cube(bm, size=1.0)
            for v in bm.verts:
                v.co = Vector((v.co.x * 0.13, v.co.y * 0.03, v.co.z * 0.012)) + p
            parts.append(new_obj("CH02_strap", bm, "M_strap"))
        out["foot_" + s] = parts
    return out


# ---------- 뼈대 ----------
def build_armature(J):
    arm = bpy.data.armatures.new("CH02_rig")
    rig = bpy.data.objects.new("CH02_rig", arm)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    bones = {}

    def bone(name, head, tail, parent=None):
        b = arm.edit_bones.new(name)
        b.head, b.tail = J[head], J[tail]
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
        bone("hand_" + s, "wrist_" + s, "hand_" + s, "forearm_" + s)
        bone("thigh_" + s, "hip_" + s, "knee_" + s, "pelvis")
        bone("shin_" + s, "knee_" + s, "ankle_" + s, "thigh_" + s)
        bone("foot_" + s, "ankle_" + s, "toe_" + s, "shin_" + s)
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


def rigid(ob, bone_name):
    g = ob.vertex_groups.new(name=bone_name)
    g.add([v.index for v in ob.data.vertices], 1.0, "REPLACE")


def join(obs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for ob in obs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    bpy.ops.object.join()
    obs[0].name = name
    obs[0].data.name = name
    return obs[0]


def attach(ob, rig):
    ob.parent = rig
    mod = ob.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    for p in ob.data.polygons:
        p.use_smooth = False


def main():
    rnd = random.Random(11)
    reset()
    J = joints()
    body = build_body(J)
    rig = build_armature(J)
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    extras = []
    eyes, faces = build_face()
    for ob in build_head() + build_hair(rnd) + eyes:
        rigid(ob, "head")
        extras.append(ob)
    for ob in build_belt() + build_chalk_bag():
        rigid(ob, "pelvis")
        extras.append(ob)
    for bone_name, obs in build_straps(J).items():
        for ob in obs:
            rigid(ob, bone_name)
            extras.append(ob)
    climber = join([body] + extras, "CH02_climber")
    exported = [climber, rig]
    for key, obs in faces.items():
        for ob in obs:
            rigid(ob, "head")
        fx = join(obs, "FX_face_" + key)
        attach(fx, rig)
        exported.append(fx)
    tris = sum(len(p.vertices) - 2 for ob in exported if ob.type == "MESH" for p in ob.data.polygons)
    os.makedirs(os.path.dirname(OUT_GLB), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for ob in exported:
        ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", use_selection=True,
                              export_animations=False, export_yup=True)
    if os.environ.get("CH_BLEND"):
        bpy.ops.wm.save_as_mainfile(filepath=os.environ["CH_BLEND"])
    return f"CH02 생성: 삼각형 {tris}, 뼈 {len(rig.data.bones)}, 표정 {len(faces)}, 내보냄 {OUT_GLB}"


print(main())
