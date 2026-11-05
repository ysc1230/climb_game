# 홀드 메시 생성기 v2(Blender 배경 실행). docs/32 홀드 디자인.
# 실행: blender -b --python tools/holds/make_holds.py
# 출력: game/art/holds/holds.glb
# 단위는 m(실제 크기). X = 잡는 방향(길이), Y = 위, Z = 벽에서 나온 깊이(Z=0이 벽면).
# 재질 슬롯: 0 몸체, 1 윗날(손가락이 걸리는 면·디딤 면), 2 볼트 구멍.
# 이름: hs_* 작은 손홀드, hm_* 중간, hl_* 큰 손홀드, f_* 발판, goal.
import bpy
import bmesh
import math
import random
import os
from mathutils import Vector

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "game", "art", "holds", "holds.glb")

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


def prism(bm, profile, length, segs, end_scale, rnd, jitter=0.1, crown=0.0):
    """단면(Y, Z) 프로필을 X로 밀어 만든 선반형. 양 끝은 end_scale까지 오므린다. crown: 위 날 가운데 볼록."""
    rings = []
    for i in range(segs + 1):
        u = i / segs
        arc = math.sin(math.pi * u)
        taper = end_scale + (1.0 - end_scale) * arc ** 0.7
        ring = []
        for (y, z) in profile:
            inner = 0 < i < segs
            jy = rnd.uniform(-jitter, jitter) * 0.02 if inner else 0.0
            jz = rnd.uniform(-jitter, jitter) * z if inner else 0.0
            yy = (y + jy) * (0.45 + 0.55 * taper) + (crown * arc if y > 0 else 0.0)
            ring.append(bm.verts.new(((u - 0.5) * length, yy, max(0.0, (z + jz) * taper))))
        rings.append(ring)
    n = len(profile)
    for i in range(segs):
        for k in range(n):
            bm.faces.new((rings[i][k], rings[i][(k + 1) % n], rings[i + 1][(k + 1) % n], rings[i + 1][k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])


def rock(bm, size, rnd, jitter=0.18, subdiv=1):
    """각진 돌기: 정이십면체를 크기대로 늘리고 꼭짓점을 흔든 뒤 벽 뒤(Z<0)는 벽면으로 누른다."""
    res = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=0.5)
    for v in res["verts"]:
        d = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2] * 2.0))
        d *= 1.0 + rnd.uniform(-jitter, jitter)
        d.z = max(0.0, d.z)
        v.co = d
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.002)


def dome(bm, size, rnd, flat_top=0.0):
    """슬로퍼: 낮은 반구. flat_top이 크면 윗면이 넓게 눌린다."""
    res = bmesh.ops.create_uvsphere(bm, u_segments=9, v_segments=6, radius=0.5)
    for v in res["verts"]:
        z = max(0.0, v.co.z) * 2.0
        if z > 1.0 - flat_top:
            z = 1.0 - flat_top + (z - (1.0 - flat_top)) * 0.3
        v.co = Vector((v.co.x * size[0] * (1 + rnd.uniform(-0.06, 0.06)), v.co.y * size[1] + 0.15 * size[1] * z, z * size[2]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.002)


def pocket_hole(bm, center, radius, depth):
    """앞면 위쪽에 구멍(포켓): 가장 가까운 면을 안쪽으로 파고 볼트색으로."""
    best = min(bm.faces, key=lambda f: (f.calc_center_median() - center).length)
    bmesh.ops.inset_individual(bm, faces=[best], thickness=radius * 0.35, depth=-depth)
    best.material_index = 2


def bolt(bm, at, r):
    disk = bmesh.ops.create_circle(bm, cap_ends=True, radius=r, segments=8)
    for v in disk["verts"]:
        v.co = Vector((at.x + v.co.x, at.y + v.co.y, at.z + 0.002))
    for f in bm.faces:
        if all(v in disk["verts"] for v in f.verts):
            f.material_index = 2


def paint_lip(bm, min_up=0.45, min_y_frac=0.25):
    """위를 향한 면(손가락이 걸리는 날·디딤 면)을 윗날 재질로. 볼트·구멍 면은 그대로."""
    ys = [v.co.y for v in bm.verts]
    lo, hi = min(ys), max(ys)
    cut = lo + (hi - lo) * min_y_frac
    for f in bm.faces:
        if f.material_index == 2:
            continue
        c = f.calc_center_median()
        f.material_index = 1 if (f.normal.y > min_up and c.y > cut) else 0


def finish(name, bm, kind):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    for slot in ("_body", "_lip"):
        me.materials.append(material(kind + slot))
    me.materials.append(material("bolt"))
    for p in me.polygons:
        p.use_smooth = False
    return obj


def crimp(name, rnd, length=0.10):
    bm = bmesh.new()
    prof = [(-0.018, 0.0), (-0.012, 0.022), (0.010, 0.034), (0.018, 0.030), (0.016, 0.0)]
    prism(bm, prof, length, 5, 0.55, rnd, 0.06)
    paint_lip(bm, 0.5, 0.4)
    return finish(name, bm, "hand")


def edge(name, rnd, length=0.12):
    bm = bmesh.new()
    prof = [(-0.026, 0.0), (-0.020, 0.030), (0.006, 0.046), (0.024, 0.044), (0.028, 0.026), (0.016, 0.018), (0.022, 0.0)]
    prism(bm, prof, length, 6, 0.4, rnd, 0.1, crown=0.006)
    paint_lip(bm)
    return finish(name, bm, "hand")


def pinch(name, rnd):
    """세로 갈비: 좁고 높은 날(양쪽에서 집는다)."""
    bm = bmesh.new()
    rock(bm, (0.045, 0.11, 0.05), rnd, 0.12)
    paint_lip(bm, 0.55, 0.6)
    return finish(name, bm, "hand")


def pocket(name, rnd):
    bm = bmesh.new()
    rock(bm, (0.09, 0.07, 0.05), rnd, 0.12)
    pocket_hole(bm, Vector((0.0, 0.012, 0.05)), 0.02, 0.012)
    paint_lip(bm, 0.55, 0.55)
    return finish(name, bm, "hand")


def nub(name, rnd):
    bm = bmesh.new()
    rock(bm, (0.075, 0.06, 0.045), rnd, 0.22)
    paint_lip(bm, 0.5, 0.45)
    return finish(name, bm, "hand")


def jug(name, rnd, scale=1.0, kind="hand"):
    """저그: 위쪽이 안으로 깊게 파인 손잡이(C자 단면)."""
    bm = bmesh.new()
    s = scale
    prof = [(-0.045 * s, 0.0), (-0.036 * s, 0.050 * s), (0.000, 0.080 * s), (0.032 * s, 0.088 * s),
            (0.045 * s, 0.070 * s), (0.026 * s, 0.050 * s), (0.016 * s, 0.030 * s), (0.034 * s, 0.0)]
    prism(bm, prof, 0.15 * s, 7, 0.35, rnd, 0.12, crown=0.010 * s)
    paint_lip(bm)
    bolt(bm, Vector((0.0, -0.012 * s, 0.072 * s)), 0.006 * s)
    return finish(name, bm, kind)


def sloper(name, rnd, scale=1.0):
    bm = bmesh.new()
    dome(bm, (0.16 * scale, 0.12 * scale, 0.055 * scale), rnd, flat_top=0.25)
    paint_lip(bm, 0.35, 0.45)
    bolt(bm, Vector((0.0, -0.02 * scale, 0.05 * scale)), 0.006 * scale)
    return finish(name, bm, "hand")


def foot_chip(name, rnd):
    bm = bmesh.new()
    rock(bm, (0.065, 0.045, 0.035), rnd, 0.25)
    paint_lip(bm, 0.45, 0.4)
    return finish(name, bm, "foot")


def foot_edge(name, rnd):
    bm = bmesh.new()
    prof = [(-0.020, 0.0), (-0.012, 0.024), (0.014, 0.032), (0.020, 0.0)]
    prism(bm, prof, 0.085, 4, 0.5, rnd, 0.1)
    paint_lip(bm, 0.5, 0.3)
    return finish(name, bm, "foot")


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    r = random.Random(7)
    crimp("hs_crimp_0", r)
    crimp("hs_crimp_1", r, 0.085)
    edge("hs_edge_0", r)
    edge("hs_edge_1", r, 0.10)
    pinch("hs_pinch_0", r)
    pocket("hs_pocket_0", r)
    nub("hs_nub_0", r)
    nub("hs_nub_1", r)
    jug("hm_jug_0", r, 1.0)
    sloper("hm_sloper_0", r, 1.0)
    jug("hl_jug_0", r, 1.7)
    sloper("hl_sloper_0", r, 1.6)
    foot_chip("f_chip_0", r)
    foot_chip("f_chip_1", r)
    foot_chip("f_chip_2", r)
    foot_edge("f_edge_0", r)
    jug("goal", r, 1.6, "goal")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_apply=True)
    print("WROTE", os.path.abspath(OUT))


main()
