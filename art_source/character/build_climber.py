"""등반자 캐릭터 CH01 생성 스크립트 (Blender 5.x, MCP execute_code 또는 Blender 텍스트 에디터에서 실행).

- 뼈 길이·관절 위치는 docs/04 좌표·크기 계약을 따른다(골반=원점, 팔 0.40/0.38, 다리 0.52/0.48,
  어깨 골반 기준 X±0.20·높이 0.55, 고관절 X±0.14).
- Blender 축: X 오른쪽, Z 위, +Y = 벽 방향(캐릭터 앞). glTF/Godot에서는 등이 +Z(카메라)를 향한다.
- 몸은 관절 그래프에 Skin 모디파이어를 씌워 하나로 이어진 메시로 만든다.
- 의상 구역은 머티리얼 이름(M_*)으로 나눈다. Godot에서 이름으로 툰 셰이더를 붙인다.
- 결과: game/art/characters/climber.glb, 미리보기 art_source/character/preview_*.png
"""
import bpy, bmesh, math, os
from mathutils import Vector

REPO = os.path.expanduser("~/Projects/climb_game")
OUT_GLB = os.path.join(REPO, "game/art/characters/climber.glb")

ARM_UP, ARM_LO, LEG_UP, LEG_LO = 0.40, 0.38, 0.52, 0.48
SH_X, SH_Z, HIP_X = 0.20, 0.55, 0.14

PALETTE = {  # docs/22 토큰
    "M_shirt": "4f6a68", "M_skin": "b98a6a", "M_shorts": "6e5a48", "M_bandage": "c7b79b",
    "M_shoe": "7e4a3e", "M_hair": "3b2e26", "M_pack": "6b5240", "M_bandana": "985448",
}


def hexcol(h):
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)) + (1.0,)


def reset():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.armatures, bpy.data.materials):
        for d in list(coll):
            if d.users == 0:
                coll.remove(d)


def material(name):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = hexcol(PALETTE[name])
    bsdf.inputs["Roughness"].default_value = 1.0
    m.diffuse_color = hexcol(PALETTE[name])
    return m


# ---------- 관절 ----------
def joints():
    J = {"pelvis": Vector((0, 0, 0)), "spine": Vector((0, 0, 0.22)), "chest": Vector((0, 0.01, 0.44)),
         "neck": Vector((0, 0.01, 0.63)), "head": Vector((0, 0.01, 0.80)), "head_top": Vector((0, 0.01, 0.94))}
    arm_dir = {"L": Vector((-math.cos(math.radians(25)), 0, -math.sin(math.radians(25)))),
               "R": Vector((math.cos(math.radians(25)), 0, -math.sin(math.radians(25))))}
    for s, sx in (("L", -1), ("R", 1)):
        sh = Vector((sx * SH_X, 0.0, SH_Z))
        J["shoulder_" + s] = sh
        J["elbow_" + s] = sh + arm_dir[s] * ARM_UP
        J["wrist_" + s] = J["elbow_" + s] + arm_dir[s] * ARM_LO
        J["hand_" + s] = J["wrist_" + s] + arm_dir[s] * 0.09
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

RADII = {"pelvis": (0.17, 0.13), "spine": (0.155, 0.12), "chest": (0.19, 0.13), "neck": (0.055, 0.055),
         "head": (0.06, 0.06), "shoulder": (0.078, 0.078), "elbow": (0.056, 0.056), "wrist": (0.042, 0.04),
         "hand": (0.05, 0.034), "hip": (0.115, 0.115), "knee": (0.074, 0.074), "ankle": (0.055, 0.06),
         "toe": (0.06, 0.045)}

# 면 중심이 가장 가까운 관절 구간 → 의상 구역
ZONE = {("pelvis", "spine"): "M_shirt", ("spine", "chest"): "M_shirt", ("chest", "neck"): "M_skin", ("neck", "head"): "M_skin",
        ("chest", "shoulder"): "M_shirt", ("pelvis", "hip"): "M_shorts", ("shoulder", "elbow"): "M_shirt",
        ("elbow", "wrist"): "M_skin", ("wrist", "hand"): "M_skin", ("hip", "knee"): "M_shorts",
        ("knee", "ankle"): "M_bandage", ("ankle", "toe"): "M_shoe"}


def base(name):
    return name.split("_")[0]


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (a + ab * t - p).length, t


def build_body(J):
    names = list(J.keys())
    used = [n for n in names if n != "head_top"]
    idx = {n: i for i, n in enumerate(used)}
    mesh = bpy.data.meshes.new("CH01_body")
    mesh.from_pydata([J[n] for n in used], [(idx[a], idx[b]) for a, b in EDGES], [])
    ob = bpy.data.objects.new("CH01_body", mesh)
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
    # 반바지 끝단을 무릎 위에서 넓혀 옷처럼 보이게, 상의 끝을 살짝 부풀림
    for v in mesh.vertices:
        if -0.42 < v.co.z < -0.30:
            v.co.x *= 1.06
            v.co.y *= 1.08
    for name in PALETTE:
        mesh.materials.append(material(name))
    mat_index = {m.name: i for i, m in enumerate(mesh.materials)}
    for poly in mesh.polygons:
        c = poly.center
        best, best_d = None, 9.0
        for a, b in EDGES:
            d, t = seg_dist(c, J[a], J[b])
            if d < best_d:
                best, best_d = (base(a), base(b)), d
        mat = ZONE.get(best, "M_shirt")
        # 소매: 위팔 바깥 절반은 피부(반팔), 무릎 위 붕대 시작 경계
        poly.material_index = mat_index[mat]
    return ob


def build_head(J):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=10, radius=0.115, location=J["head"])
    head = bpy.context.active_object
    head.name = "CH01_head"
    head.scale = (0.92, 1.0, 1.08)
    head.data.materials.append(material("M_hair"))
    bpy.ops.mesh.primitive_torus_add(major_radius=0.112, minor_radius=0.022, location=J["head"] + Vector((0, 0, 0.03)))
    band = bpy.context.active_object
    band.name = "CH01_bandana"
    band.rotation_euler = (math.radians(8), 0, 0)
    band.data.materials.append(material("M_bandana"))
    # 뒤로 늘어진 매듭
    bpy.ops.mesh.primitive_cone_add(vertices=5, radius1=0.035, depth=0.12, location=J["head"] + Vector((0, -0.12, 0.0)))
    tail = bpy.context.active_object
    tail.name = "CH01_bandana_tail"
    tail.rotation_euler = (math.radians(-60), 0, 0)
    tail.data.materials.append(material("M_bandana"))
    return [head, band, tail]


def build_pack(J):
    bpy.ops.mesh.primitive_cube_add(size=1, location=J["chest"] + Vector((0, -0.19, -0.08)))
    pack = bpy.context.active_object
    pack.name = "CH01_pack"
    pack.scale = (0.30, 0.13, 0.36)
    bpy.ops.object.transform_apply(scale=True)
    bev = pack.modifiers.new("Bevel", "BEVEL")
    bev.width = 0.03
    bev.segments = 2
    bpy.ops.object.modifier_apply(modifier="Bevel")
    pack.data.materials.append(material("M_pack"))
    # 어깨끈
    parts = [pack]
    for sx in (-1, 1):
        bpy.ops.mesh.primitive_cube_add(size=1, location=Vector((sx * 0.11, -0.02, 0.47)))
        strap = bpy.context.active_object
        strap.scale = (0.035, 0.25, 0.02)
        strap.rotation_euler = (math.radians(70), 0, 0)
        bpy.ops.object.transform_apply(scale=True, rotation=True)
        strap.data.materials.append(material("M_pack"))
        parts.append(strap)
    return parts


def build_armature(J):
    arm = bpy.data.armatures.new("CH01_rig")
    rig = bpy.data.objects.new("CH01_rig", arm)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    bones = {}

    def bone(name, head, tail, parent=None):
        b = arm.edit_bones.new(name)
        b.head, b.tail = J[head] if isinstance(head, str) else head, J[tail] if isinstance(tail, str) else tail
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


def rigid_group(ob, bone_name):
    g = ob.vertex_groups.new(name=bone_name)
    g.add([v.index for v in ob.data.vertices], 1.0, "REPLACE")


def main():
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
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
    for ob in build_head(J):
        rigid_group(ob, "head")
        extras.append(ob)
    for ob in build_pack(J):
        rigid_group(ob, "chest")
        extras.append(ob)
    bpy.ops.object.select_all(action="DESELECT")
    for ob in extras:
        ob.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    body.name = "CH01_climber"
    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    os.makedirs(os.path.dirname(OUT_GLB), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    rig.select_set(True)
    bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", use_selection=True,
                              export_animations=False, export_yup=True)
    return f"CH01 생성: 삼각형 {tris}, 뼈 {len(rig.data.bones)}, 내보냄 {OUT_GLB}"


result = main()
print(result)
