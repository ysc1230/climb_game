class_name HoldSpacing
extends RefCounted
## 홀드 간격 규칙(2026-11-15 사용자: "홀드 간 거리가 지금의 V0처럼 붙어 있으면 안 돼. 적어도 홀드 크기만큼은 떨어져 있어야 해").
## 홀드는 화면에 보이는 크기의 타원(메시 가로·세로 × 보이는 배율 hold_view_scale × 무작위 최대 1.05, 홀드 방향으로 회전)으로 본다.
## 다른 홀드(hold_id가 다름) 두 개를 잇는 방향 u에서: 가장자리 사이 = 중심 거리 − r_a(u) − r_b(u) ≥ max(2·r_a(u), 2·r_b(u)).
## 즉 두 홀드 사이에 그 방향으로 잰 큰 홀드 하나가 더 들어갈 만큼 비어 있어야 한다. 같은 홀드의 슬롯끼리(정상 두 칸)는 보지 않는다.

const JITTER := 1.05
const P3 := preload("res://scenes/play_3d.gd")
static var _meshes := {}


## 슬롯의 보이는 타원 반지름(가로, 세로)과 회전각.
static func ellipse(route: RouteDef, key: String) -> Dictionary:
	var slot: Dictionary = route.slots[key]
	var is_goal: bool = route.goal_slots.has(key)
	var mesh := _mesh(P3.hold_variant(key, slot, is_goal))
	var s := P3.hold_view_scale(slot, mesh, is_goal) * JITTER
	var size := mesh.get_aabb().size
	var ang := 0.0
	if slot.has("hand_area"):
		ang = Vector2(slot.hand_area.dir).angle()
	elif slot.has("foot_area") and slot.foot_area.has("up"):
		ang = Vector2(slot.foot_area.up).angle() - PI / 2.0
	return {"a": size.x * s / 2.0, "b": size.y * s / 2.0, "ang": ang}


## 타원 중심에서 방향 u로 가장자리까지 거리.
static func radius(e: Dictionary, u: Vector2) -> float:
	var v := u.rotated(-float(e.ang))
	return 1.0 / sqrt(pow(v.x / float(e.a), 2) + pow(v.y / float(e.b), 2))


## 규칙을 어기는 홀드 쌍마다 한 줄. 빈 배열이면 통과.
static func violations(route: RouteDef) -> PackedStringArray:
	var out: PackedStringArray = []
	var keys: Array = route.slots.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var a: String = keys[i]
			var b: String = keys[j]
			if a.get_slice("/", 1) == b.get_slice("/", 1):
				continue
			var pa: Vector2 = route.slot_pos(a)
			var pb: Vector2 = route.slot_pos(b)
			var u := (pb - pa).normalized()
			var ra := radius(ellipse(route, a), u)
			var rb := radius(ellipse(route, b), u)
			var gap := pa.distance_to(pb) - ra - rb
			var need := 2.0 * maxf(ra, rb)
			if gap < need - 0.0005:
				out.append("%s ↔ %s 간격 %.3fm < %.3fm" % [a.get_slice("/", 1), b.get_slice("/", 1), gap, need])
	return out


static func _mesh(name: String) -> Mesh:
	if _meshes.is_empty():
		var root: Node = load("res://art/holds/holds.glb").instantiate()
		for n in root.find_children("*", "MeshInstance3D", true, false):
			_meshes[String(n.name)] = (n as MeshInstance3D).mesh
		root.free()
	return _meshes[name]
