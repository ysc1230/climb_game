"""Tripo 기본 캐릭터 → 게임용 리깅 모델(docs/36, 2026-11-11).
실행: blender -b --python art_source/character/tripo/build_tripo_rig.py
입력: art_source/character/tripo/climber_tripo_base.glb(Tripo v3.1, 146만 삼각형, T자, 키 1.0, 앞 +X)
출력: game/art/characters/climber_tripo.glb(약 1만 2천 삼각형, 뼈 17 + 손가락 2 + 엉덩이 보조 2, 색 텍스처 1024)

1. 놓기: Z +90°(앞 +X → +Y, build_climber 규약), 키 1.99m, 발바닥 z = −0.835(골반 관절 = 원점). 실측은 docs/36 §1.1.
2. 줄이기: Decimate(접기) → TRIS 삼각형. UV 유지.
3. 뼈대: RigPose.BONES 17개 + finger_L/R(손 아래). 판정 몸(Tuning)과 같은 길이:
   위팔 0.20, 팔꿈치→손 접점(손가락 뿌리) 0.35, 손가락 0.07(hand 0.035 + finger 0.035), 허벅지 0.41, 정강이 0.375, 발 0.135.
   T자 기준 자세(팔 수평). 팔 중심선은 모델 실측(y −0.03).
4. 가중치: Blender 자동 가중치는 Tripo 메시에서 자주 실패하므로 부위·위치로 직접 준다(관절 경계는 선형으로 섞음).
   팔은 어깨에서 거리로(어깨 → 팔꿈치 → 손바닥은 아래팔에 고정 → 손가락 뿌리 → 손가락 끝), 다리·몸통은 높이로,
   머리카락·머리는 head, 초크백은 pelvis 고정. 정점당 뼈 2개 이하.
   엉덩이(docs/37 4단계, 2026-11-12): 골반↔허벅지 사이는 보조 뼈 hiphelp_L/R(엉덩이 관절, 게임이 골반과 허벅지
   회전의 중간으로 돌림)를 거쳐 pelvis → hiphelp → thigh로 잇는다. 두 뼈만 섞으면 다리를 90° 들 때 사이 정점이
   안으로 접힌다. 가운데 선 가까운 가랑이(|x| < 0.07, z > −0.20)는 골반 쪽에 더 남겨 다리를 들어도 가랑이 꼭짓점이
   가운데에 있게 한다(전에는 꼭짓점이 허벅지를 따라 옆으로 끌려가 Y자가 사라졌다).
5. 재질: 색 텍스처만(2048 → 1024), 금속 0. ORM·노멀은 쓰지 않는다(게임은 툰 셰이더).
"""
import bpy, math, os
from mathutils import Vector

REPO = os.path.expanduser("~/Projects/climb_game")
SRC = os.path.join(REPO, "art_source/character/tripo/climber_tripo_base.glb")
OUT = os.path.join(REPO, "game/art/characters/climber_tripo.glb")
TRIS = 12000
TEX = 1024

ARM_U, ARM_L, HAND_A, HAND_B = 0.20, 0.35, 0.035, 0.035
LEG_U, LEG_L, FOOT = 0.41, 0.375, 0.135
SH_X, SH_Z, ARM_Y = 0.18, 0.67, -0.03
HIP_X = 0.10
SPINE, CHEST, NECK, HEAD, HEAD_TOP = 0.27, 0.54, 0.76, 0.84, 1.16
SOLE = -0.835
CROTCH_X = 0.07   # 가랑이 가운데 영역 반폭(골반 쪽에 더 남김)


def place():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    ob = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
    ob.rotation_mode = "XYZ"
    ob.rotation_euler = (0, 0, math.radians(90))
    ob.scale = (1.99, 1.99, 1.99)
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


def decimate(ob):
    n = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    m = ob.modifiers.new("dec", "DECIMATE")
    m.ratio = TRIS / n
    bpy.ops.object.modifier_apply(modifier="dec")


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
        hip = Vector((sx * HIP_X, -0.02, 0))
        leg = Vector((sx * 0.03, 0, -0.785)).normalized()
        J["hip_" + s] = hip
        J["knee_" + s] = hip + leg * LEG_U
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
    # 초크백(오른쪽 뒤 허리)
    if x > 0.04 and y < -0.11 and -0.14 < z < 0.10:
        return {"pelvis": 1.0}
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
    # 다리: 골반 → 엉덩이 보조 → 허벅지(z 0.04~−0.14, 가운데 가랑이는 골반 쪽에 더), 무릎 ±0.05, 발목(−0.76 위아래)
    if z < 0.04 and ax > 0.005:
        knee = -LEG_U
        ankle = -(LEG_U + LEG_L)
        if z > -0.22:
            t = ramp(-z, -0.04, 0.14)
            t *= 1.0 - 0.5 * (1.0 - ramp(ax, 0.0, CROTCH_X)) * (1.0 - ramp(-z, 0.08, 0.20))
            if t < 0.5:
                blend(w, "pelvis", "hiphelp_" + s, t * 2.0)
            else:
                blend(w, "hiphelp_" + s, "thigh_" + s, t * 2.0 - 1.0)
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
        w = weights_for(v.co)
        tot = sum(w.values())
        for name, val in w.items():
            if val / tot > 0.001:
                groups[name].add([v.index], val / tot, "REPLACE")


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
    img.name = "climber_tripo_color"
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
    decimate(ob)
    material(ob)
    ob.name = "P_body_male"
    ob.data.name = "P_body_male"
    for p in ob.data.polygons:
        p.use_smooth = True
    J = joints()
    rig = armature(J)
    skin(ob, rig)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_animations=False,
                              export_yup=True, export_image_format="JPEG", export_jpeg_quality=88)
    if os.environ.get("TRIPO_BLEND"):
        bpy.ops.wm.save_as_mainfile(filepath=os.environ["TRIPO_BLEND"])
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    print("TRIPO_RIG: 삼각형 %d, 뼈 %d, 출력 %s (%.0fKB)" % (tris, len(rig.data.bones), OUT, os.path.getsize(OUT) / 1024))


main()
