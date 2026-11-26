class_name ReachMarker
extends RefCounted
## 끄는 손발의 잡힐 자리 표시와 손 그림 맞추기(docs/superpowers/specs/2026-11-19-1-feel-design.md §1.5). 표현 전용.
## 2026-11-19 확인: 판정 점과 손 그림은 거의 같은 자리였다. 어긋나 보이는 이유는 잡기 여유(HAND_CANDIDATE_RADIUS 0.17m)로
## 손이 홀드에서 10~17cm 떨어져 있어도(그림자가 홀드에 걸칠 때) 잡힐 후보가 되기 때문. 그래서 후보가 생기면
## 손 그림을 후보 점 쪽으로 끌어당겨(display_point) "손이 홀드 위에 있을 때 잡힌다"로 보이게 한다.

const NEAR := 0.15          # 이 거리 안에서 떠 있는 손발을 벽 쪽으로 붙인다(m)
const SNAP_RATE := 12.0     # 손 그림이 목표 점으로 따라가는 빠르기(1/초, 지수)


static func lift_scale(dist_to_slot: float) -> float:
	return clampf(dist_to_slot / NEAR, 0.0, 1.0)


## 그 손발이 허용되고 비어 있는 슬롯 중 가장 가까운 거리(없으면 INF).
static func nearest_slot_dist(route: RouteDef, limb: StringName, p: Vector2, occupied: Dictionary) -> float:
	var best := INF
	for key in route.slots:
		var sl: Dictionary = route.slots[key]
		if not sl.allowed.has(limb) or occupied.has(key):
			continue
		best = minf(best, p.distance_to(sl.pos))
	return best


## 잡기 안내(2026-11-27 사용자 "손으로 홀드를 잡을 때 어딜 잡아야 잘잡았는지 보이지않아 … 초록 주황 빨강 색으로 가이드"):
## 끄는 손이 노리는 홀드와 그 단계. GOOD 지금 놓으면 잘 잡힘(가운데 쪽·편한 방향), OK 잡히지만 가장자리이거나 불편한 방향
## (개스턴·언더), BAD 노리지만 그 손으로는 못 잡음(방향·거리). 노리는 홀드가 없거나 손이 아니면 {}.
enum Guide { GOOD, OK, BAD }
const GUIDE_COLORS := [Color("7cc443"), Color("ffa53a"), Color("ff5a4a")]
const GUIDE_GOOD_Q := 0.7


static func grip_guide(s, limb: StringName) -> Dictionary:
	var l: Dictionary = s.limbs[limb]
	if l.state != "Dragging" or not PoseSolver.is_hand(limb):
		return {}
	if not l.cand.is_empty():
		var c := GripCheck.contact_for(l.cand.key, s.route.slots, limb, l.cand.point, s.body.pos, s.body.angle, s.body.yaw)
		var good: bool = float(l.cand.quality) >= GUIDE_GOOD_Q and c.grip_kind in [&"", &"pull", &"sidepull"]
		return {"key": l.cand.key, "level": Guide.GOOD if good else Guide.OK}
	var aim := GripCheck.aimed_slot(s.route.slots, l.req)
	if aim != "" and (s.route.slots[aim].has("hand_area") or s.route.goal_slots.has(aim)):
		return {"key": aim, "level": Guide.BAD}
	return {}


## 고리를 그릴 점: 잡힐 후보가 있으면 후보 점, 없으면 판정 점.
static func ring_point(l: Dictionary) -> Vector2:
	var c: Dictionary = l.get("cand", {})
	return c.point if not c.is_empty() else l.pos


## 손 그림 위치를 한 프레임 진행한다(prev → ring_point로 지수 접근).
static func display_point(prev: Vector2, l: Dictionary, dt: float) -> Vector2:
	return prev.lerp(ring_point(l), 1.0 - exp(-SNAP_RATE * dt))
