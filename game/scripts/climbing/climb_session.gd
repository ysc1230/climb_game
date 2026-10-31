class_name ClimbSession
extends RefCounted
## 등반 상태와 고정 틱 1회(판정). play_test에서 분리한 순수 로직이며 노드·입력·그리기를 모른다.
## 호출 측은 InputRouter 명령을 apply_input으로 넣고, 매 물리 틱 step()을 한 번 부른다.
## 안내 문구는 messages에 쌓이고 호출 측이 읽은 뒤 비운다.

var route: RouteDef
var body: BodyState
var rules := ClimbRules.new()  # 지지·피로·유예 규칙(RouteBot과 공유, docs/04 §4·§7)
## limb -> {state, key, pos(실제 말단), grab(잡은 점), req(요청 목표), cand, flag, flag_depth(플래그 변형의 깊이 힌트, 표현용), contact}
var limbs := {}
var falling := false
var fall_reason := ""
var fall_ticks := 0
var goal_ticks := 0
var clears := 0
var falls := 0
var messages: Array[String] = []
var last_phase := -1
var runner := TechniqueRunner.new()  # 기술 실행기(docs/27). 한 번에 하나
## 확정된 틱의 기술 이벤트 {tick, type, id, side, key, quality, reason}(09 v0.6, 능력치에 쓰지 않음). 최근 200개.
var technique_log: Array = []
var tick_count := 0
## 기술 고르는 중(docs/27 §6, 15 v0.6 TechniqueSelect). true인 동안 step()은 아무것도 바꾸지 않는다.
var selecting := false
const TECHNIQUE_LOG_MAX := 200
const DEADPOINT_TICKS := 9              # 04 §10.5: 0.15초 안에 잡기 판정
const DEADPOINT_SPEED := 5.0            # 말단 따라가기 속도(2.5) × 2
const DEADPOINT_STAMINA_COST := 10.0    # 버틴 손 피로 즉시 −10
## 실행 중인 데드포인트 {limb, key, point, bonus, ticks}. 비면 없음. 손은 "Deadpoint" 상태로 날아가고 끝나면 붙거나(성공) 추락(실패)한다.
var deadpoint := {}
var _last_rise_tick := -1000  # 골반이 DEADPOINT_RISE_SPEED 이상으로 올라간 마지막 틱
var _hint_cooldown := 0
var _last_hint := &""


func _init(p_route: RouteDef) -> void:
	route = p_route
	reset()


func reset() -> void:
	runner.cancel(self, &"reset")
	body = BodyState.new(route.start_pelvis, route.start_angle)
	limbs.clear()
	for limb in PoseSolver.LIMBS:
		var key: String = route.start_slots[limb]
		var p := route.slot_pos(key)
		limbs[limb] = {"state": "Attached", "key": key, "pos": p, "grab": p, "req": p, "cand": {}, "flag": p, "flag_depth": 0.0,
			"contact": GripCheck.contact_for(key, route.slots, limb, p)}
	rules.contact_meta = _contact_meta()
	rules.reset(body, attached(), {}, false)
	goal_ticks = 0
	falling = false
	fall_reason = ""
	deadpoint = {}
	_last_rise_tick = -1000


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


# ---------- 기술 선택(시간 정지) ----------

## 선택을 연다. 드래그 중인 손발이 있거나 추락 중이면 false.
## 눌러 둔 채(Armed) 손발은 Attached로 돌린다. 패드 터치 정리(router.cancel_all)는 호출 측이 한다.
func open_select() -> bool:
	if falling or is_dragging():
		return false
	for limb in limbs:
		if limbs[limb].state == "Armed":
			limbs[limb].state = "Attached"
	selecting = true
	return true


func close_select() -> void:
	selecting = false


## 선택 중 고른 기술을 시작한다. 판단은 지금 스냅숏으로 다시 한다(선택 중 상태 불변).
## 성공하면 &""를 돌려주고 같은 틱부터 시간이 다시 흐른다. 실패하면 이유 ID이며 선택은 유지된다.
func choose(tech_id: StringName, side: StringName, key: String = "", point: Vector2 = Vector2.INF) -> StringName:
	var reason := runner.start(self, tech_id, side, key, point)
	if reason == &"":
		selecting = false
	return reason


# ---------- 입력 ----------

## 데드포인트 창(04 §10.5): 골반이 올라가는 중이거나, 그런 상승이 끝난 뒤 0.25초 이내.
func deadpoint_window() -> bool:
	return body.vel.y >= TechniqueJudge.DEADPOINT_RISE_SPEED or tick_count - _last_rise_tick <= TechniqueJudge.DEADPOINT_GRACE_TICKS


## 지금 도달 보너스(m). drag_speed: 손가락 속도(m/s, 월드). 버튼 흐름은 1을 넣는다(= 0.05).
func deadpoint_bonus(drag_speed: float) -> float:
	return TechniqueJudge.deadpoint_bonus(body.vel.y, drag_speed)


## InputRouter 명령({type, limb, delta, speed})을 적용한다.
func apply_input(cmds: Array) -> void:
	for c in cmds:
		var l: Dictionary = limbs[c.limb]
		if l.state == "Deadpoint":
			continue  # 날아가는 중인 손은 0.15초 동안 입력을 받지 않는다
		# 패드 조작과 실행 중 기술(27 §6 5): 휴식은 어떤 패드 조작이든 끝, 그 외는 기술이 쓰는 손발을 누르면 취소
		if not runner.active.is_empty():
			if runner.active.id == TechniqueJudge.T_REST:
				runner.finish(self)
			elif c.type in ["arm", "detach"] and runner.uses(c.limb):
				runner.cancel(self)
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
				_try_grab(c.limb, float(c.get("speed", 0.0)))
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


func _try_grab(limb: StringName, speed: float = 0.0) -> void:
	var l: Dictionary = limbs[limb]
	if l.state != "Dragging":
		return  # 끌고 있지 않은 손발(붙어 있거나 날아가는 중)의 release는 잡기를 만들지 않는다
	var cand := _candidate(limb)
	l.cand = {}
	if cand.is_empty():
		# 정적 후보가 없을 때만 데드포인트(창이 열려 있고 빠르게 놓은 손). 정지 상태의 빠른 드래그는 일반 Free(27 §13 TA04)
		if PoseSolver.is_hand(limb) and speed >= TechniqueJudge.DEADPOINT_MIN_SPEED and deadpoint_window() and _start_pad_deadpoint(limb, speed):
			return
		var reason := GripCheck.reject_reason(route.slots, limb, l.pos, l.req, body.pos, body.angle, attached(), occupied(), rules.feet_eligible, body.yaw)
		var text := GripCheck.message(reason, limb)
		if not text.is_empty():
			messages.append(text)
		# 균형 발 예고가 있었고 놓는 순간에도 조건을 통과하면 그 위치를 유지(25 MV06)
		if not PoseSolver.is_hand(limb) and rules.flag_ready.has(limb):
			l.state = "Flag"
			l.flag = l.pos
			l.flag_depth = 0.0
			messages.append("균형 발로 두었어요")
		else:
			l.state = "Free"
		return
	_attach(limb, cand.key, cand.point, GripCheck.contact_for(cand.key, route.slots, limb, cand.point))


## 패드로 놓은 손의 데드포인트 시도. 노린 홀드(요청 목표 근처)가 보너스 범위 + 여유 안에 있으면 던진다.
## 범위 안/밖과 무관하게 던진 뒤의 성패는 받기 판정이 정한다(놓치면 DEADPOINT_MISS).
func _start_pad_deadpoint(limb: StringName, speed: float) -> bool:
	var l: Dictionary = limbs[limb]
	var snap := ClimbSnapshot.from_session(self)
	if TechniqueJudge.deadpoint_hand_reason(snap, limb) != "":
		return false
	var bonus := deadpoint_bonus(speed)
	var joint := PoseSolver.joint_position(body.pos, body.angle, limb, body.yaw)
	var limit := TechniqueJudge.deadpoint_far(limb, body.yaw) + bonus + TechniqueJudge.DEADPOINT_AIM_MARGIN
	var aim: Vector2 = l.req
	var occ := occupied()
	var best := {}
	var best_d := GripCheck.AIM_RADIUS
	for key in route.slots:
		var slot: Dictionary = route.slots[key]
		if not slot.allowed.has(limb) or not slot.has("hand_area") or aim.distance_to(slot.pos) >= best_d:
			continue
		var pt := GripCheck.contact_point(slot, limb, aim, occ.get(key, []), INF)
		if pt.is_empty() or joint.distance_to(pt.point) > limit:
			continue
		if not PoseSolver.direction_ok(body.pos, body.angle, limb, pt.point, body.yaw):
			continue  # 방향 영역은 완화하지 않는다: 일반 Free로 처리
		best = {"key": key, "point": pt.point}
		best_d = aim.distance_to(slot.pos)
	if best.is_empty():
		return false
	start_deadpoint(limb, best.key, best.point, bonus)
	return true


## 데드포인트 시작(패드·기술 버튼 공통). 손을 떼어 "Deadpoint" 상태로 두고 목표로 날린다.
func start_deadpoint(limb: StringName, key: String, point: Vector2, bonus: float) -> void:
	var l: Dictionary = limbs[limb]
	l.state = "Deadpoint"
	l.contact = null
	l.cand = {}
	l.req = point
	deadpoint = {"limb": limb, "key": key, "point": point, "bonus": bonus, "ticks": 0}


## 한 틱: 손을 2배 속도로 옮기다 후보 반경에 닿으면(또는 9틱이 지나면) 받기 판정. 놓쳤으면 true.
func _tick_deadpoint() -> bool:
	if deadpoint.is_empty():
		return false
	var dp := deadpoint
	var limb: StringName = dp.limb
	var l: Dictionary = limbs[limb]
	dp.ticks += 1
	l.pos = (l.pos as Vector2).move_toward(dp.point, DEADPOINT_SPEED * Tuning.DT)
	var arrived: bool = (l.pos as Vector2).distance_to(dp.point) <= GripCheck.radius_of(limb)
	if not arrived and dp.ticks < DEADPOINT_TICKS:
		return false
	deadpoint = {}
	if arrived and TechniqueJudge.deadpoint_catch(ClimbSnapshot.from_session(self), limb, dp.key, dp.point, dp.bonus).ok:
		_attach(limb, dp.key, dp.point, TechniqueJudge.contact_for(route, TechniqueJudge.T_DEADPOINT, limb, dp.key, dp.point))
		var holder := TechniqueJudge.other_of(limb)
		rules.stamina[holder] = maxf(float(rules.stamina[holder]) - DEADPOINT_STAMINA_COST, 0.0)
		return false
	l.state = "Free"
	return true


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
	if selecting:
		return ""  # 기술 고르는 중: 틱·피로·카운터·몸통·말단 모두 멈춘다
	tick_count += 1
	if falling:
		return _fall_tick()
	_log_event(runner.tick(self))
	if _tick_deadpoint():
		if not runner.active.is_empty() and runner.active.id == TechniqueJudge.T_DEADPOINT:
			runner.fail(self, TechniqueJudge.DEADPOINT_MISS)
		_start_fall("DEADPOINT_MISS")
		return "fall:DEADPOINT_MISS"
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
	var outcome := rules.tick(body, att, endpoints, on_platform(att), moving, intents, hints, flag_probe)
	if body.vel.y >= TechniqueJudge.DEADPOINT_RISE_SPEED:
		_last_rise_tick = tick_count
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
		if l.state == "Deadpoint":
			continue  # _tick_deadpoint가 옮긴다
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
		if l.state != "Dragging" or not l.cand.is_empty() or runner.uses(limb):
			continue
		var reason := GripCheck.reject_reason(route.slots, limb, l.pos, l.req, body.pos, body.angle, att, occ, rules.feet_eligible, body.yaw)
		if reason in [GripCheck.JOINT_LIMIT, GripCheck.NEED_WEIGHT_SHIFT, GripCheck.OUT_OF_REACH, GripCheck.OCCUPIED, GripCheck.TYPE_MISMATCH] and reason != _last_hint:
			messages.append(GripCheck.message(reason, limb))
			_last_hint = reason
			_hint_cooldown = 20
			return
	_last_hint = &""


func on_platform(att: Dictionary) -> bool:
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
	runner.cancel(self, &"fall")
	_log_event(runner.tick(self))
	falls += 1
	deadpoint = {}
	falling = true
	fall_reason = reason
	fall_ticks = 0
	for limb in limbs:
		limbs[limb].state = "Free"


## 확정된 틱의 기술 이벤트를 기록한다. 실패는 이유 문구를 안내한다.
func _log_event(ev: Dictionary) -> void:
	if ev.is_empty():
		return
	technique_log.append({"tick": tick_count, "type": ev.type, "id": ev.id, "side": ev.side, "key": ev.key, "quality": ev.quality, "reason": ev.reason})
	if technique_log.size() > TECHNIQUE_LOG_MAX:
		technique_log.pop_front()
	if ev.type == TechniqueRunner.FAILED:
		var text := TechniqueJudge.text_for(ev.reason)
		if not text.is_empty():
			messages.append(text)


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
