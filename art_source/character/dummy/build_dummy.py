"""더미 캐릭터 → 게임 모델(docs/39, 2026-11-13).
실행: blender -b --python art_source/character/dummy/build_dummy.py
입력: art_source/character/dummy/reference_climber.glb(사용자 더미: 뼈 17 + 뼈마다 타원 덩어리, 키 1.71m, 앞 +Y)
출력: game/art/characters/climber_dummy.glb

- 더미의 뼈대를 게임 규격으로 다시 놓는다: 손 뼈는 손 접점(손가락 뿌리 = 손목 + 0.09)에서 시작, 손가락 뼈 0.035,
  발 뼈는 발목 → 발끝(앞 0.19, 아래 0.09), 엉덩이 보조 뼈(hiphelp)는 고관절에. 덩어리(*_shell)가 아닌 메시는 버린다.
- 덩어리는 그 뼈에 고정(가중치 1). 손 덩어리는 손가락 뿌리 안쪽(손바닥)은 아래팔, 바깥은 손, 그 바깥 0.035부터 손가락.
- 재질 하나(M_body_main, 연회색). 덩어리를 한 메시(P_body_dummy)로 합친다.
"""
import bpy, os
from mathutils import Vector

REPO = os.path.expanduser("~/Projects/climb_game")
SRC = os.path.join(REPO, "art_source/character/dummy/reference_climber.glb")
OUT = os.path.join(REPO, "game/art/characters/climber_dummy.glb")

PALM, FINGER_A, FINGER_B = 0.09, 0.035, 0.035   # 손목→손가락 뿌리, 손가락 뿌리→손가락 뼈, 손가락 뼈→손끝


def joints(src_rig):
    b = {bn.name: (src_rig.matrix_world @ bn.head_local) for bn in src_rig.data.bones}
    J = {k: b[v] for k, v in {"pelvis": "pelvis", "spine": "spine", "chest": "chest", "neck": "neck", "head": "head"}.items()}
    J["head_top"] = Vector((0, 0, 0.81))
    for s, sx in (("L", -1), ("R", 1)):
        J["shoulder_" + s] = b["upperarm_" + s]
        J["elbow_" + s] = b["forearm_" + s]
        wrist = b["hand_" + s]
        J["wrist_" + s] = wrist + Vector((sx * PALM, 0, 0))            # 게임 손 접점 = 손가락 뿌리
        J["finger_" + s] = J["wrist_" + s] + Vector((sx * FINGER_A, 0, 0))
        J["hand_" + s] = J["finger_" + s] + Vector((sx * FINGER_B, 0, 0))
        J["hip_" + s] = b["thigh_" + s]
        J["knee_" + s] = b["shin_" + s]
        J["ankle_" + s] = b["foot_" + s]
        J["toe_" + s] = J["ankle_" + s] + Vector((0, 0.19, -0.09)).normalized() * 0.20
        J["hiphelp_end_" + s] = J["hip_" + s] + (J["knee_" + s] - J["hip_" + s]) * 0.4
    return J


def armature(J):
    arm = bpy.data.armatures.new("ClimberCommonRig")
    rig = bpy.data.objects.new("ClimberCommonRig", arm)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    bones = {}

    def bone(name, head, tail, parent=None):
        e = arm.edit_bones.new(name)
        e.head, e.tail = J[head], J[tail]
        e.roll = 0.0
        if parent:
            e.parent = bones[parent]
        bones[name] = e

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
        bone("hiphelp_" + s, "hip_" + s, "hiphelp_end_" + s, "pelvis")
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


def bone_for(shell, co, J):
    name = shell.replace("_shell", "")
    if name.startswith("hand_"):
        s = name[-1]
        ax = abs(co.x)
        if ax < abs(J["wrist_" + s].x):
            return "forearm_" + s
        return "hand_" + s if ax < abs(J["finger_" + s].x) else "finger_" + s
    return name


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    src_rig = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"][0]
    J = joints(src_rig)
    shells = [o for o in bpy.context.scene.objects if o.type == "MESH" and o.name.endswith("_shell")]
    for o in [o for o in bpy.context.scene.objects if o.type == "MESH" and not o.name.endswith("_shell")]:
        bpy.data.objects.remove(o)   # 불러오기가 만든 뼈 표시용 구 등 덩어리가 아닌 것
    rig = armature(J)
    mat = bpy.data.materials.new("M_body_main")
    mat.diffuse_color = (0.78, 0.78, 0.76, 1.0)
    mat.use_nodes = True
    mat.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = (0.78, 0.78, 0.76, 1.0)
    for o in shells:
        o.data = o.data.copy()
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        for m in list(o.modifiers):
            o.modifiers.remove(m)
        o.vertex_groups.clear()
        o.data.materials.clear()
        o.data.materials.append(mat)
        groups = {}
        for v in o.data.vertices:
            bn = bone_for(o.name, v.co, J)
            if bn not in groups:
                groups[bn] = o.vertex_groups.new(name=bn)
            groups[bn].add([v.index], 1.0, "REPLACE")
    bpy.ops.object.select_all(action="DESELECT")
    for o in shells:
        o.select_set(True)
    bpy.context.view_layer.objects.active = shells[0]
    bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = body.data.name = "P_body_dummy"
    for p in body.data.polygons:
        p.use_smooth = True
    for o in [o for o in bpy.context.scene.objects if o.type == "ARMATURE" and o != rig]:
        bpy.data.objects.remove(o)
    body.parent = rig
    mod = body.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_animations=False, export_yup=True)
    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    print("DUMMY: 삼각형 %d, 뼈 %d, 출력 %s" % (tris, len(rig.data.bones), OUT))


main()
