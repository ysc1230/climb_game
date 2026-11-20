# 홀드 메시 생성기 v3(Blender 배경 실행). docs/32 홀드 디자인, 작업 4 §4.2(종류마다 모양이 확실히 다름).
# 실행: blender -b --python tools/holds/make_holds.py
# 출력: game/art/holds/holds.glb
# 단위는 m(실제 크기). X = 잡는 방향(길이), Y = 위, Z = 벽에서 나온 깊이(Z=0이 벽면).
# 재질 슬롯: 0 몸체, 1 윗날(손가락이 걸리는 면·디딤 면), 2 어두운 면(볼트 머리·저그 속·포켓 구멍).
# 이름: <종류>_<번호> — jug_0~2, crimp_0~2, sloper_0~1, pinch_0~1, pocket_0~1, foot_chip_0~2, foot_big_0~1, goal_0.
# 실루엣: 저그 = 위가 깊게 파인 콩(어두운 속), 크림프 = 얇고 긴 날, 슬로퍼 = 낮고 둥근 덩어리(넓은 밝은 윗면),
# 핀치 = 휜 바나나 갈비, 포켓 = 둥근 덩어리에 큰 구멍, 작은 발판 = 각진 칩, 큰 발판 = 넓적한 턱.
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


def prism(bm, profile, length, segs, end_scale, rnd, jitter=0.1, crown=0.0, dark_edges=(), bend=0.0):
    """단면(Y, Z) 프로필을 X로 밀어 만든 선반형. 양 끝은 end_scale까지 오므린다. crown: 위 날 가운데 볼록.
    dark_edges: 어두운 재질(2)로 칠할 프로필 변 번호(저그 속). bend: 양 끝을 이만큼 올려 휘게(핀치 바나나)."""
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
            x = (u - 0.5) * length
            ring.append(bm.verts.new((x, yy + bend * (2.0 * (u - 0.5)) ** 2, max(0.0, (z + jz) * taper))))
        rings.append(ring)
    n = len(profile)
    for i in range(segs):
        for k in range(n):
            f = bm.faces.new((rings[i][k], rings[i][(k + 1) % n], rings[i + 1][(k + 1) % n], rings[i + 1][k]))
            if k in dark_edges and 0 < i < segs - 1:
                f.material_index = 2
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


def surface_z(bm, x, y, r):
    """(x, y) 근처(반경 r) 꼭짓점 중 가장 앞(Z 최대). 볼트 머리를 겉면에 얹는다."""
    zs = [v.co.z for v in bm.verts if (v.co.x - x) ** 2 + (v.co.y - y) ** 2 < r * r]
    return max(zs) if zs else max(v.co.z for v in bm.verts)


def bolt(bm, x, y, r):
    """육각 볼트 머리(참고 그림): 겉면 위 어두운 육각."""
    z = surface_z(bm, x, y, r * 3.0)
    disk = bmesh.ops.create_circle(bm, cap_ends=True, radius=r, segments=6)
    for v in disk["verts"]:
        v.co = Vector((x + v.co.x, y + v.co.y, z + 0.002))
    for f in bm.faces:
        if all(v in disk["verts"] for v in f.verts):
            f.material_index = 2


def hollow(bm, center, radius, depth, squash=1.0):
    """둥근 구멍(포켓)·파인 속: center 근처 앞쪽 꼭짓점을 안으로 밀고 그 면을 어둡게. squash < 1이면 옆으로 긴 구멍."""
    for v in bm.verts:
        d = math.sqrt(((v.co.x - center.x) * squash) ** 2 + (v.co.y - center.y) ** 2)
        if d < radius and v.co.z > center.z * 0.5:
            v.co.z -= depth * (1.0 - (d / radius) ** 2)
    for f in bm.faces:
        c = f.calc_center_median()
        if math.sqrt(((c.x - center.x) * squash) ** 2 + (c.y - center.y) ** 2) < radius * 0.8 and c.z > center.z * 0.3:
            f.material_index = 2


def paint_lip(bm, min_up=0.45, min_y_frac=0.25, band=0.72):
    """손가락이 걸리는 날을 윗날 재질로: 위를 향한 면 + 정면에서 보이는 윗부분 띠(카메라가 벽을 정면으로 봄).
    볼트·구멍 면(2)은 그대로. band: 높이의 이 비율 위쪽에서 앞을 향한 면을 띠로 칠한다."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ys = [v.co.y for v in bm.verts]
    lo, hi = min(ys), max(ys)
    cut = lo + (hi - lo) * min_y_frac
    top = lo + (hi - lo) * band
    for f in bm.faces:
        if f.material_index == 2:
            continue
        c = f.calc_center_median()
        up = f.normal.y > min_up and c.y > cut
        front_band = c.y > top and f.normal.z > 0.25 and f.normal.y > -0.1
        f.material_index = 1 if (up or front_band) else 0


def bend_verts(bm, k, half_len):
    """X 양 끝을 k만큼 올려(음수면 내려) 휘게: y += k·(x/half_len)²."""
    for v in bm.verts:
        v.co.y += k * (v.co.x / half_len) ** 2


def finish(name, bm, kind, smooth=False):
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
        p.use_smooth = smooth and p.material_index != 2
    return obj


def blob(bm, size, rnd, jitter=0.06, subdiv=3):
    """둥근 덩어리(저그·슬로퍼·포켓·핀치 몸체): 매끈한 구를 늘리고 낮은 주파수로 살짝 울퉁불퉁하게, 벽 뒤는 누른다."""
    res = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=0.5)
    ph = [rnd.uniform(0, 6.28) for _ in range(3)]
    for v in res["verts"]:
        c = v.co
        wob = 1.0 + jitter * (math.sin(3.1 * c.x * 2 + ph[0]) * math.sin(2.3 * c.y * 2 + ph[1]) + 0.5 * math.sin(4.7 * c.z * 2 + ph[2]))
        v.co = Vector((c.x * size[0] * wob, c.y * size[1] * wob, max(0.0, c.z * size[2] * 2.0 * wob)))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)


def jug(name, rnd, scale=1.0, kind="hand", variant=0):
    """저그: 콩 모양 덩어리 위쪽 앞에 깊게 파인 어두운 속(정면에서 보이는 손잡이 구멍), 그 위 밝은 날."""
    bm = bmesh.new()
    s = scale
    blob(bm, ([0.15, 0.13, 0.17][variant] * s, [0.068, 0.072, 0.064][variant] * s, 0.055 * s), rnd, 0.08, 4)
    bend_verts(bm, [0.012, -0.010, 0.018][variant] * s, 0.08 * s)
    ys = [v.co.y for v in bm.verts]
    zmax = max(v.co.z for v in bm.verts)
    hollow(bm, Vector((0.0, max(ys) - 0.02 * s, zmax)), 0.024 * s, 0.035 * s, [0.42, 0.5, 0.38][variant])
    paint_lip(bm, 0.5, 0.6, 0.86)
    bolt(bm, 0.0, min(ys) + 0.022 * s, 0.006 * s)
    return finish(name, bm, kind, True)


def crimp(name, rnd, length=0.10, variant=0):
    """크림프: 얇고 긴 날. 위 띠만 밝다."""
    bm = bmesh.new()
    h = [0.016, 0.013, 0.019][variant]
    prof = [(-h, 0.0), (-h * 0.8, 0.014), (h * 0.4, 0.024), (h, 0.022), (h * 0.9, 0.0)]
    prism(bm, prof, length, 6, [0.6, 0.45, 0.7][variant], rnd, 0.05, bend=[0.0, 0.006, -0.004][variant])
    paint_lip(bm, 0.5, 0.45)
    bolt(bm, 0.0, -h * 0.2, 0.004)
    return finish(name, bm, "hand")


def sloper(name, rnd, scale=1.0, variant=0):
    """슬로퍼: 낮고 둥근 덩어리, 날 없이 넓은 밝은 윗면."""
    bm = bmesh.new()
    blob(bm, ([0.17, 0.15][variant] * scale, [0.10, 0.11][variant] * scale, 0.042 * scale), rnd, 0.06, 3)
    paint_lip(bm, 0.25, 0.4)
    bolt(bm, 0.0, -0.02 * scale, 0.006 * scale)
    return finish(name, bm, "hand", True)


def pinch(name, rnd, variant=0):
    """핀치: 휜 바나나 갈비. 좁고 앞으로 높이 솟아 양쪽에서 집는다."""
    bm = bmesh.new()
    blob(bm, ([0.13, 0.11][variant], 0.034, 0.06), rnd, 0.04)
    bend_verts(bm, [0.04, -0.035][variant], [0.065, 0.055][variant])
    paint_lip(bm, 0.55, 0.5, 0.75)
    bolt(bm, 0.0, 0.0, 0.005)
    return finish(name, bm, "hand", True)


def pocket(name, rnd, variant=0):
    """포켓: 둥근 덩어리 앞에 큰 구멍(도넛)."""
    bm = bmesh.new()
    blob(bm, ([0.09, 0.08][variant], [0.08, 0.075][variant], 0.05), rnd, 0.05)
    zmax = max(v.co.z for v in bm.verts)
    hollow(bm, Vector((0.0, 0.006, zmax)), [0.03, 0.028][variant], 0.035, [1.0, 0.8][variant])
    paint_lip(bm, 0.55, 0.65)
    bolt(bm, 0.0, -0.028, 0.005)
    return finish(name, bm, "hand", True)


def foot_chip(name, rnd, variant=0):
    """작은 발판: 각진 칩."""
    bm = bmesh.new()
    rock(bm, [(0.06, 0.042, 0.032), (0.07, 0.038, 0.03), (0.055, 0.046, 0.036)][variant], rnd, 0.25)
    paint_lip(bm, 0.45, 0.4)
    bolt(bm, 0.0, -0.004, 0.004)
    return finish(name, bm, "foot")


def foot_big(name, rnd, variant=0):
    """큰 발판: 넓적한 턱(평평한 윗면)."""
    bm = bmesh.new()
    prof = [(-0.026, 0.0), (-0.020, 0.030), (0.014, 0.040), (0.026, 0.036), (0.024, 0.0)]
    prism(bm, prof, [0.12, 0.10][variant], 5, 0.55, rnd, 0.12, crown=0.004)
    paint_lip(bm, 0.45, 0.3)
    bolt(bm, 0.0, -0.006, 0.005)
    return finish(name, bm, "foot")


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    r = random.Random(7)
    for v in range(3):
        jug("jug_%d" % v, r, 1.0, "hand", v)
        crimp("crimp_%d" % v, r, [0.10, 0.085, 0.11][v], v)
        foot_chip("foot_chip_%d" % v, r, v)
    for v in range(2):
        sloper("sloper_%d" % v, r, 1.0, v)
        pinch("pinch_%d" % v, r, v)
        pocket("pocket_%d" % v, r, v)
        foot_big("foot_big_%d" % v, r, v)
    jug("goal_0", r, 1.6, "goal", 0)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_apply=True, export_yup=False)  # 축 그대로(X 길이, Y 위, Z 깊이)
    print("WROTE", os.path.abspath(OUT))


main()
