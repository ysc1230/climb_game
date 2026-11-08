class_name AutoRescue
extends RefCounted
## 자동 도움(2026-11-09 사용자: "위험 게이지를 누르면 최적의 동작으로 알아서 다음 동작으로. 팔·다리 최대 한 번씩.
## 마지막 탑 홀드는 버튼으로 잡지 않게"). 노드 없는 탐색기. 판정과 같은 힘 계산(ClimbRules.evaluate)을 쓴다.
##
## 후보: 손 하나를 옮기기(또는 그대로) × 발 하나를 옮기기(또는 그대로). 떨어져 있던 손발을 다시 붙이는 것도 "옮기기"다.
## - 옮길 수 있는 슬롯: 그 손발이 허용되고, 다른 손발이 쓰지 않고, 목표(goal_slots)가 아니고, 관절에서 닿을 만한 거리.
## - 각 조합마다 골반 자세를 찾고(현재 골반 ±0.2m 격자에서 가능한 시작점 → PoseSolver.find_target),
##   그 자세가 해부학적으로 가능하고(is_valid) 버틸 손(또는 플랫폼)이 있고 힘 균형(FEASIBLE)·문 열림 없음이어야 후보.
## - 점수(작을수록 좋음): 손 하중 비용 + 부담 큼(STRAINED) 벌점 + 옮긴 손발 수 + 골반 이동 거리 − 오른 높이.
##   + 허공에 남는 손발 벌점 − 손·발을 지금보다 높은 홀드로 옮긴 만큼(W_HAND_UP·W_FOOT_UP). 즉 "안전한 자세 중에서 다음 동작으로 한 걸음".

const GRID := [-0.2, -0.1, 0.0, 0.1, 0.2]   # 시작 골반 후보 격자(m)
const NEAR := 0.45       # 후보 슬롯: 관절에서 최대 팔다리 길이 + 이만큼 안(몸이 옮겨 갈 수 있으므로)
const W_STRAIN := 1.0
const W_MOVE := 0.25
const W_SHIFT := 0.8
const W_UP := 0.6
const W_HAND_UP := 1.0   # 손을 지금 가장 높은 손보다 높은 홀드로 옮기면 1m당(다음 동작으로 나아가기)
const W_FOOT_UP := 0.5   # 발을 지금 가장 높은 발보다 높게
const W_FREE_HAND := 0.4 # 끝난 뒤 허공에 남는 손 하나당(한 손으로 매달린 채 끝나지 않게)
const W_FREE_FOOT := 0.15


## 가장 좋은 계획. 없으면 {}.
## {moves: [{limb, key}], slots: {limb: key}(최종 붙은 손발), pelvis: Vector2, angle: float, score: float}
static func plan(s: ClimbSession) -> Dictionary:
	var base := {}
	for limb in s.limbs:
		if s.limbs[limb].state in ["Attached", "Armed"]:
			base[limb] = s.limbs[limb].key
	var hand_opts: Array = [{}]
	var foot_opts: Array = [{}]
	for o in options(s, base):
		(hand_opts if PoseSolver.is_hand(o.limb) else foot_opts).append(o)
	var best := {}
	for h in hand_opts:
		for f in foot_opts:
			var keys := base.duplicate()
			var moves: Array = []
			for m in [h, f]:
				if not m.is_empty():
					keys[m.limb] = m.key
					moves.append(m)
			var r := evaluate(s, keys, moves.size())
			if not r.is_empty():
				r.score -= progress(s, base, moves)
			if not r.is_empty() and (best.is_empty() or r.score < best.score):
				r["moves"] = moves
				best = r
	return best


## 옮긴 손발이 지금 가장 높은 손(발)보다 얼마나 높이 갔나의 가산점.
static func progress(s: ClimbSession, base: Dictionary, moves: Array) -> float:
	var top := {true: -INF, false: -INF}
	for limb in base:
		var hand := PoseSolver.is_hand(limb)
		top[hand] = maxf(top[hand], s.route.slot_pos(base[limb]).y)
	var gain := 0.0
	for m in moves:
		var hand := PoseSolver.is_hand(m.limb)
		var ref: float = top[hand] if top[hand] > -INF else s.body.pos.y + (0.6 if hand else -0.7)
		gain += maxf(0.0, s.route.slot_pos(m.key).y - ref) * (W_HAND_UP if hand else W_FOOT_UP)
	return gain


## 옮길 수 있는 (손발, 슬롯) 후보.
static func options(s: ClimbSession, base: Dictionary) -> Array:
	var out: Array = []
	var body := s.body
	for limb in PoseSolver.LIMBS:
		var joint := PoseSolver.joint_position(body.pos, body.angle, limb, body.yaw)
		var max_r := PoseSolver.reach_of(limb).y + NEAR
		for key in s.route.slots:
			if s.route.goal_slots.has(key) or base.get(limb, "") == key:
				continue
			var slot: Dictionary = s.route.slots[key]
			if not slot.allowed.has(limb) or joint.distance_to(slot.pos) > max_r:
				continue
			var taken := false
			for o in base:
				if o != limb and base[o] == key:
					taken = true
			if not taken:
				out.append({"limb": limb, "key": key})
	return out


## 붙은 손발 keys(limb → 슬롯)로 버틸 수 있는 골반 자세와 점수. 못 버티면 {}.
static func evaluate(s: ClimbSession, keys: Dictionary, move_count: int) -> Dictionary:
	if keys.is_empty():
		return {}
	var att := {}
	for limb in keys:
		att[limb] = s.route.slot_pos(keys[limb])
	var start := Vector2.INF
	var best_d := INF
	for dx in GRID:
		for dy in GRID:
			var p: Vector2 = s.body.pos + Vector2(dx, dy)
			var d := p.distance_to(s.body.pos)
			if d < best_d and PoseSolver.is_valid(p, s.body.angle, att, 0.0):
				start = p
				best_d = d
	if not start.is_finite():
		return {}
	var t := PoseSolver.find_target(start, s.body.angle, att, PoseSolver.supporting_feet(start, s.body.angle, att, [], 0.0))
	var pelvis := Vector2(t.x, t.y)
	var angle := t.z
	if not PoseSolver.is_valid(pelvis, angle, att, 0.0):
		return {}
	var feet := PoseSolver.supporting_feet(pelvis, angle, att, [], 0.0)
	var rules := ClimbRules.new()
	for limb in keys:
		rules.contact_meta[limb] = GripCheck.contact_for(keys[limb], s.route.slots, limb, att[limb])
	rules.feet_eligible = feet
	rules.loaded_feet.assign(feet)
	var platform := _on_platform(s, keys, att, pelvis)
	if rules._eligible_hand_count(pelvis, angle, att, 0.0) == 0 and not platform:
		return {}
	var eps := {}
	for limb in PoseSolver.LIMBS:
		if not att.has(limb):
			eps[limb] = pelvis + ClimbSession._rest_offset(limb)  # reset_to가 떠 있는 손발을 두는 곳
	var r := rules.evaluate(pelvis, angle, att, eps, platform, feet, 0.0)
	if r.status != SupportSolver.Status.FEASIBLE or ClimbRules.barn_exceeded(r):
		return {}
	var score := ClimbRules.balance_cost(r) + move_count * W_MOVE + pelvis.distance_to(s.body.pos) * W_SHIFT \
		- clampf(pelvis.y - s.body.pos.y, -0.3, 0.4) * W_UP
	if SupportSolver.max_u(r) > SupportSolver.STABLE_LOAD_RATIO:
		score += W_STRAIN
	for limb in PoseSolver.LIMBS:
		if not keys.has(limb):
			score += W_FREE_HAND if PoseSolver.is_hand(limb) else W_FREE_FOOT
	return {"slots": keys, "pelvis": pelvis, "angle": angle, "score": score}


static func _on_platform(s: ClimbSession, keys: Dictionary, att: Dictionary, pelvis: Vector2) -> bool:
	if not (keys.has(PoseSolver.LF) and keys.has(PoseSolver.RF)):
		return false
	for p in s.route.platforms:
		if p.foot_slot_keys.has(keys[PoseSolver.LF]) and p.foot_slot_keys.has(keys[PoseSolver.RF]):
			var a: Vector2 = att[PoseSolver.LF]
			var b: Vector2 = att[PoseSolver.RF]
			return pelvis.x >= minf(a.x, b.x) - 0.10 and pelvis.x <= maxf(a.x, b.x) + 0.10
	return false
