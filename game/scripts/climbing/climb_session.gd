class_name ClimbSession
extends RefCounted
## 등반 상태와 고정 틱 1회(판정). play_test에서 분리한 순수 로직이며 노드·입력·그리기를 모른다.
## 호출 측은 InputRouter 명령을 apply_input으로 넣고, 매 물리 틱 step()을 한 번 부른다.
## 안내 문구는 messages에 쌓이고 호출 측이 읽은 뒤 비운다.

var route: RouteDef
var body: BodyState
var rules := ClimbRules.new()  # 지지·피로·유예 규칙(RouteBot과 공유, docs/04 §4·§7)
## limb -> {state, key, pos(실제 말단), grab(잡은 점), req(요청 목표), cand, flag, contact}
var limbs := {}
var falling := false
var fall_reason := ""
var fall_ticks := 0
var goal_ticks := 0
var clears := 0
var falls := 0
var messages: Array[String] = []
var last_phase := -1
var _hint_cooldown := 0
var _last_hint := &""


func _init(p_route: RouteDef) -> void:
	route = p_route
	reset()


func reset() -> void:
	body = BodyState.new(route.start_pelvis, route.start_angle)
	limbs.clear()
	for limb in PoseSolver.LIMBS:
		var key: String = route.start_slots[limb]
		var p := route.slot_pos(key)
		limbs[limb] = {"state": "Attached", "key": key, "pos": p, "grab": p, "req": p, "cand": {}, "flag": p,
			"contact": GripCheck.contact_for(key, route.slots, limb, p)}
	rules.contact_meta = _contact_meta()
	rules.reset(body, attached(), {}, false)
	goal_ticks = 0
	falling = false
	fall_reason = ""


## 붙은(Attached/Armed) 팔다리의 잡은 점.
func attached() -> Dictionary:
	var d := {}
	for limb in limbs:
		if limbs[limb].state == "Attached" or limbs[limb].state == "Armed":
			d[limb] = limbs[limb].grab
	return d


## 붙은 팔다리의 접점 정보 (limb → ContactInfo). 뗀 팔다리는 포함하지 않는다.
func _contact_meta() -> Dictionary:
	var d := {}
	for limb in limbs:
		var l: Dictionary = limbs[limb]
		if l.state in ["Attached", "Armed"] and l.get("contact") != null:
			d[limb] = l.contact
	return d


## 슬롯 키 → [{limb, interval}] (손은 접촉 구간, 발은 ZERO)
func occupied() -> Dictionary:
	var d := {}
	for limb in limbs:
		var l: Dictionary = limbs[limb]
		if l.state in ["Attached", "Armed"]:
			var iv := Vector2.ZERO
			if PoseSolver.is_hand(limb):
				iv = HoldArea.hand_interval(route.slots[l.key], l.grab)
			if not d.has(l.key):
				d[l.key] = []
			d[l.key].append({"limb": limb, "interval": iv})
	return d


func is_dragging() -> bool:
	for limb in limbs:
		if limbs[limb].state == "Dragging":
			return true
	return false


# ---------- 입력 ----------

## InputRouter 명령({type, limb, delta})을 적용한다.
func apply_input(cmds: Array) -> void:
	for c in cmds:
		var l: Dictionary = limbs[c.limb]
		match c.type:
			"arm":
				l.state = "Armed"
			"disarm":
				if l.state == "Armed":
					l.state = "Attached"
			"detach":
				l.state = "Dragging"
				l.contact = null
				l.req = l.pos
			"move":
				l.req = _clamp_to_reach(c.limb, l.req, l.req + c.delta)
			"release":
				_try_grab(c.limb)
			"cancel":
				if l.state == "Armed":
					l.state = "Attached"
				elif l.state == "Dragging":
					l.state = "Free"


## v0.5: 최대 반경만이 아니라 최소 거리·방향 영역을 연속적으로 적용(docs/04 H02/H03/H06).
func _clamp_to_reach(limb: StringName, previous: Vector2, p: Vector2) -> Vector2:
	return PoseSolver.clamp_endpoint(body.pos, body.angle, limb, previous, p, body.yaw)


## 실제 말단 기준 잡기 후보(GripCheck, 히스테리시스는 직전에 보여준 후보 기준).
func _candidate(limb: StringName) -> Dictionary:
	var l: Dictionary = limbs[limb]
	return GripCheck.candidate(route.slots, limb, l.pos, body.pos, body.angle, attached(), occupied(), l.cand.get("key", ""), body.yaw)


func _try_grab(limb: StringName) -> void:
	var l: Dictionary = limbs[limb]
	var cand := _candidate(limb)
	l.cand = {}
	if cand.is_empty():
		var reason := GripCheck.reject_reason(route.slots, limb, l.pos, l.req, body.pos, body.angle, attached(), occupied(), rules.feet_eligible, body.yaw)
		var text := GripCheck.message(reason, limb)
		if not text.is_empty():
			messages.append(text)
		# 균형 발 예고가 있었고 놓는 순간에도 조건을 통과하면 그 위치를 유지(25 MV06)
		if not PoseSolver.is_hand(limb) and rules.flag_ready.has(limb):
			l.state = "Flag"
			l.flag = l.pos
			messages.append("균형 발로 두었어요")
		else:
			l.state = "Free"
		return
	_attach(limb, cand.key, cand.point, GripCheck.contact_for(cand.key, route.slots, limb, cand.point))


func _attach(limb: StringName, key: String, point: Vector2, contact: ContactInfo) -> void:
	var l: Dictionary = limbs[limb]
	l.state = "Attached"
	l.key = key
	l.grab = point
	l.pos = point
	l.contact = contact


## 검증 후 붙인다(기술 실행기용). 검증은 슬롯 존재와 PoseSolver.can_reach뿐이다.
## 종류·점유·영역 판정은 호출 측이 GripCheck로 먼저 해야 한다. 실패하면 false.
func grab(limb: StringName, key: String, point: Vector2, contact: ContactInfo) -> bool:
	if not route.slots.has(key) or not PoseSolver.can_reach(body.pos, body.angle, limb, point, body.yaw):
		return false
	limbs[limb].cand = {}
	_attach(limb, key, point, contact)
	return true


# ---------- 고정 틱 ----------

## 고정 틱 1회. 반환: "" / "fall:<이유>" / "clear" / "unresolved" / "respawn"(추락 연출이 끝나 다시 시작).
func step() -> String:
	if falling:
		return _fall_tick()
	_move_endpoints()
	var att := attached()
	var endpoints := {}
	var moving := false
	var intents := {}
	var hints := {}
	var flag_probe := []
	var occ := occupied()
	for limb in limbs:
		var l: Dictionary = limbs[limb]
		if att.has(limb):
			continue
		endpoints[limb] = l.pos
		if l.state != "Dragging":
			continue
		moving = true
		intents[limb] = l.req
		l.cand = _candidate(limb)
		var aim := GripCheck.aimed_slot(route.slots, l.req)
		if PoseSolver.is_hand(limb):
			var other := &"RH" if limb == &"LH" else &"LH"
			var other_key: String = limbs[other].key
			if not aim.is_empty() and occ.has(other_key) and other_key.get_base_dir() == aim.get_base_dir():
				hints[limb] = MoveClassifier.HAND_MATCH
		else:
			if not aim.is_empty() and occ.has(aim) and occ[aim][0].limb != limb and not PoseSolver.is_hand(occ[aim][0].limb):
				hints[limb] = MoveClassifier.FOOT_SWAP
			if l.cand.is_empty():
				flag_probe.append(limb)
	rules.contact_meta = _contact_meta()
	var outcome := rules.tick(body, att, endpoints, _on_platform(att), moving, intents, hints, flag_probe)
	_drag_hints(att, occ)
	for hand in rules.slipped:
		limbs[hand].state = "Free"
		limbs[hand].contact = null
		messages.append("손이 미끄러졌어요")
	if rules.phase != last_phase:
		if rules.phase == ClimbRules.Phase.REBALANCING:
			messages.append("균형이 무너지고 있어요")
		elif rules.phase == ClimbRules.Phase.STRAINED and last_phase == ClimbRules.Phase.STABLE:
			messages.append("남은 손발로 버티기 힘들어요")
		last_phase = rules.phase
	match outcome:
		"NO_SUPPORT", "BALANCE_LOST":
			_start_fall(outcome)
			return "fall:" + outcome
		"UNRESOLVED":
			return "unresolved"
	return _goal_tick()


func _move_endpoints() -> void:
	for limb in limbs:
		var l: Dictionary = limbs[limb]
		if l.state in ["Attached", "Armed"]:
			l.pos = l.grab
			continue
		var target: Vector2 = l.req
		if l.state == "Flag":
			target = l.flag
		elif l.state == "Free":
			var side := -1.0 if limb in [&"LH", &"LF"] else 1.0
			target = body.pos + (Vector2(0.35 * side, 0.18) if PoseSolver.is_hand(limb) else Vector2(0.25 * side, -0.70))
		var prev: Vector2 = l.pos
		target = _clamp_to_reach(limb, prev, target)
		l.pos = _clamp_to_reach(limb, prev, l.pos.move_toward(target, 2.5 * Tuning.DT))


## 드래그 중 경계에 막혀 후보가 없을 때 이유를 한 번 안내(반복 쿨다운 20틱, docs/05)
func _drag_hints(att: Dictionary, occ: Dictionary) -> void:
	_hint_cooldown = maxi(_hint_cooldown - 1, 0)
	if _hint_cooldown > 0:
		return
	for limb in limbs:
		var l: Dictionary = limbs[limb]
		if l.state != "Dragging" or not l.cand.is_empty():
			continue
		var reason := GripCheck.reject_reason(route.slots, limb, l.pos, l.req, body.pos, body.angle, att, occ, rules.feet_eligible, body.yaw)
		if reason in [GripCheck.JOINT_LIMIT, GripCheck.NEED_WEIGHT_SHIFT, GripCheck.OUT_OF_REACH, GripCheck.OCCUPIED, GripCheck.TYPE_MISMATCH] and reason != _last_hint:
			messages.append(GripCheck.message(reason, limb))
			_last_hint = reason
			_hint_cooldown = 20
			return
	_last_hint = &""


func _on_platform(att: Dictionary) -> bool:
	if not (att.has(&"LF") and att.has(&"RF")) or rules.feet_eligible.size() < 2:
		return false
	for p in route.platforms:
		if p.foot_slot_keys.has(limbs[&"LF"].key) and p.foot_slot_keys.has(limbs[&"RF"].key):
			var a: Vector2 = att[&"LF"]
			var b: Vector2 = att[&"RF"]
			return body.pos.x >= minf(a.x, b.x) - 0.10 and body.pos.x <= maxf(a.x, b.x) + 0.10
	return false


func _goal_tick() -> String:
	var held := 0
	for limb in [&"LH", &"RH"]:
		if limbs[limb].state in ["Attached", "Armed"] and route.goal_slots.has(limbs[limb].key):
			held += 1
	goal_ticks = goal_ticks + 1 if held == 2 and rules.balance_confirmed() else 0  # 균형 확인 뒤에만(docs/15)
	if goal_ticks >= Tuning.GOAL_DWELL_TICKS:
		clears += 1
		reset()
		return "clear"
	return ""


func _start_fall(reason: String) -> void:
	falls += 1
	falling = true
	fall_reason = reason
	fall_ticks = 0
	for limb in limbs:
		limbs[limb].state = "Free"


func _fall_tick() -> String:
	fall_ticks += 1
	body.vel.y -= 9.8 * Tuning.DT
	body.pos += body.vel * Tuning.DT
	for limb in limbs:
		limbs[limb].pos += body.vel * Tuning.DT
	if fall_ticks >= 60 or body.pos.y < route.fail_line_y:
		reset()
		return "respawn"
	return ""
