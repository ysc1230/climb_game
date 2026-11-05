# 홀드 메시 생성기(Blender 배경 실행). docs/22 아트 방향 + docs/32 홀드 디자인.
# 실행: blender -b --python tools/holds/make_holds.py
# 출력: game/art/holds/holds.glb — 객체 hand_0..2, foot_0..2, goal
# 단위 메시: X = 길이(-0.5..0.5, 잡기 영역 방향), Y = 높이(-0.5..0.5), Z = 벽에서 나온 깊이(0..1).
# 게임이 슬롯마다 (길이, 높이, 깊이)로 늘린다. 재질 슬롯: 0 몸체, 1 윗날(잡는 면), 2 볼트 구멍.
import bpy
import bmesh
import math
import random
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "game", "art", "holds", "holds.glb")

# 단면(Y, Z): 벽(Z=0)에서 시작해 위쪽에 안으로 파인 립(손가락이 걸리는 곳)을 둔다.
HAND_PROFILES = [
    [(-0.50, 0.00), (-0.40, 0.55), (0.02, 0.92), (0.34, 1.00), (0.50, 0.80), (0.30, 0.52), (0.42, 0.00)],  # 저그
    [(-0.50, 0.00), (-0.35, 0.40), (0.10, 0.70), (0.40, 0.78), (0.50, 0.62), (0.36, 0.45), (0.46, 0.00)],  # 에지
    [(-0.50, 0.00), (-0.45, 0.48), (-0.05, 0.86), (0.30, 0.96), (0.50, 0.74), (0.28, 0.60), (0.40, 0.00)],  # 둥근 저그
]
FOOT_PROFILES = [
    [(-0.50, 0.00), (-0.32, 0.62), (0.18, 0.96), (0.50, 0.70), (0.50, 0.00)],
    [(-0.50, 0.00), (-0.20, 0.70), (0.25, 1.00), (0.50, 0.55), (0.48, 0.00)],
    [(-0.50, 0.00), (-0.38, 0.55), (0.10, 0.90), (0.50, 0.78), (0.50, 0.00)],
]
GOAL_PROFILE = [(-0.50, 0.00), (-0.42, 0.62), (0.00, 0.98), (0.32, 1.00), (0.50, 0.82), (0.26, 0.50), (0.38, 0.00)]

COLORS = {
    "hand_body": (0x2B, 0x7A, 0x6F), "hand_lip": (0x8F, 0xD0, 0xBC),
    "foot_body": (0x5E, 0x4C, 0x70), "foot_lip": (0xC4, 0xB0, 0xD6),
    "goal_body": (0xD9, 0xB8, 0x72), "goal_lip": (0xF1, 0xD5, 0x9A),
    "bolt": (0x30, 0x28, 0x20),
}


def srgb(c):
    return tuple((v / 255.0) ** 2.2 for v in c) + (1.0,)


def material(name):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = srgb(COLORS[name])
    m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.9
    return m


def build(name, profile, segments, end_scale, seed, kind):
    rnd = random.Random(seed)
    bm = bmesh.new()
    rings = []
    for i in range(segments + 1):
        u = i / segments
        x = -0.5 + u * 1.0
        # 양 끝으로 갈수록 가늘고 낮게(둥근 끝), 가운데는 살짝 흔들어 손으로 깎은 레진 느낌
        arc = math.sin(math.pi * u)
        taper = end_scale + (1.0 - end_scale) * arc ** 0.7
        ring = []
        for (y, z) in profile:
            jy = rnd.uniform(-0.04, 0.04) if 0 < i < segments else 0.0
            jz = rnd.uniform(-0.08, 0.08) * z if 0 < i < segments else 0.0
            # 정면 실루엣: 위쪽(립)은 가운데가 볼록한 초승달, 양 끝은 둥글게 오므린다(렌즈 모양)
            yy = (y + jy) * (0.35 + 0.65 * taper) + (0.10 * arc if y > 0.15 else -0.04 * arc)
            ring.append(bm.verts.new((x * (0.92 + 0.08 * arc), yy, (z + jz) * taper)))
        rings.append(ring)
    n = len(profile)
    for i in range(segments):
        for k in range(n):
            a, b = rings[i][k], rings[i][(k + 1) % n]
            c, d = rings[i + 1][(k + 1) % n], rings[i + 1][k]
            bm.faces.new((a, b, c, d))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # 윗날: 위·앞을 향한 면 중 위쪽(Y > 0.2)에 있는 면 = 손가락이 걸리는 곳
    for f in bm.faces:
        c = f.calc_center_median()
        nrm = f.normal
        # 정면 카메라에서도 보이게: 윗면 + 앞면의 위쪽 띠(손가락이 걸리는 날)
        top = c.y > 0.2 and nrm.y > 0.25
        front_band = c.y > 0.22 and nrm.z > 0.3
        f.material_index = 1 if (top or front_band) else 0
    # 볼트 구멍: 앞면 가운데 작은 원판(벽 쪽으로 살짝 들어간 짙은 구멍)
    if kind != "foot" or True:
        cz = max(z for (_, z) in profile) * 0.92
        cy = -0.05
        disk = bmesh.ops.create_circle(bm, cap_ends=True, radius=0.055 if kind != "foot" else 0.07, segments=8)
        for v in disk["verts"]:
            co = v.co.copy()
            v.co = (co.x * 0.9, cy + co.y * 1.4, cz + 0.02)
        for f in bm.faces:
            if all(v in disk["verts"] for v in f.verts):
                f.material_index = 2
                if f.normal.z < 0:
                    f.normal_flip()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    prefix = "goal" if kind == "goal" else kind
    me.materials.append(material(prefix + "_body"))
    me.materials.append(material(prefix + "_lip"))
    me.materials.append(material("bolt"))
    for p in me.polygons:
        p.use_smooth = False  # 로우폴리 면이 보이게(툰 셰이더 밴드)
    return obj


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for i, prof in enumerate(HAND_PROFILES):
        build("hand_%d" % i, prof, 8, 0.28, 100 + i, "hand")
    for i, prof in enumerate(FOOT_PROFILES):
        build("foot_%d" % i, prof, 6, 0.22, 200 + i, "foot")
    build("goal", GOAL_PROFILE, 9, 0.35, 300, "goal")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_apply=True)
    print("WROTE", os.path.abspath(OUT))


main()
