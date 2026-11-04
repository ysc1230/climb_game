class_name ClimbSession
extends RefCounted
## 등반 상태와 고정 틱 1회(판정). play_test에서 분리한 순수 로직이며 노드·입력·그리기를 모른다.
## 호출 측은 InputRouter 명령을 apply_input으로 넣고, 매 물리 틱 step()을 한 번 부른다.
## 안내 문구는 messages에 쌓이고 호출 측이 읽은 뒤 비운다.

var route: RouteDef
var body: BodyState
var rules := ClimbRules.new()  # 지지·피로·유예 규칙(RouteBot과 공유, docs/04 §4·§7)
## limb -> {state, key, pos(실제 말단), grab(잡은 점), req(요청 목표), cand, flag, flag_depth(균형 발의 깊이 힌트, 표현용), contact}
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
## 확정된 틱의 기술 이벤트(09 v0.6, 능력치에 쓰지 않음). 최근 200개.
## 모든 이벤트에 tick과 seq(세션 수명 동안 1부터 단조 증가, reset/reset_to에도 되돌리지 않음)가 붙는다.
## 로그는 최근 TECHNIQUE_LOG_MAX개만 남으므로 소비자(튜토리얼 실행기)는 seq > 마지막으로 본 seq로 새 이벤트를 고른다.
## 기술 실행기: {type, id, side, key, quality, reason}. 패드 손 잡기: {type: "pad_grip", limb, key, mode}(28 §4.3).
## 패드 기술(28 §7.4·튜토리얼 판정): {type: "move", label}(확정 라벨이 MOVE_EVENT_LABELS로 바뀔 때 1회),
## {type: "grab", limb, key, quality}(패드·기술로 붙을 때마다), {type: "flag", limb}(패드 균형 발이 될 때),
## {type: "pad_foot_swap", limb, key}, {type: "pad_deadpoint", limb, key, ok}(받기 판정 결과), {type: "fall", reason}(추락 시작).
var technique_log: Array = []
var event_seq := 0  # 마지막으로 기록한 이벤트의 seq
## 검증기 전용 금지 플래그(키 StringName → true, 28 §7.4). 플레이 코드는 설정하지 않는다(비면 영향 없음).
## &"high_step": 고관절−0.20m 이상 발 후보 거부 + StandUp 선호 끔, &"cross": 반대 손 X를 넘는 손 후보 거부,
## &"flag": 균형 발 상태를 만들지 않음, &"match": 반대 손이 잡은 홀드 거부, &"foot_swap": 패드 풋스왑 끔,
## &"lock_off": LockOff 선호 대신 뻗기 선호(0.60), &"grip_auto": 잡기 방향 자동 선택 끔(grip_modes[0]), &"deadpoint": 도달 보너스 0.
var forbid := {}
const MOVE_EVENT_LABELS := [MoveClassifier.HIGH_STEP, MoveClassifier.STAND_UP, MoveClassifier.CROSS_REACH, MoveClassifier.HAND_MATCH, MoveClassifier.LOCK_OFF]
var _last_move_label: StringName = MoveClassifier.REST
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
	_reset_pose(route.start_pelvis, route.start_angle, route.start_slots)


## 주어진 자세로 다시 시작한다(튜토리얼 단계 시작용). pose는 RouteDef.start_pose와 같은 형식
## {pelvis: [x, y], angle, slots: {limb: key}, stamina?: {LH, RH}}. slots에 없는 팔다리는 Free(쉬는 위치)로 둔다.
## 기술 로그와 seq는 이어진다.
func reset_to(pose: Dictionary) -> void:
	var pv = pose.get("pelvis", route.start_pelvis)
	var pelvis: Vector2 = pv if pv is Vector2 else Vector2(pv[0], pv[1])
	var src: Dictionary = pose.get("slots", {})
	var slots := {}
	for limb in PoseSolver.LIMBS:
		if src.has(limb):
			slots[limb] = src[limb]
		elif src.has(String(limb)):
			slots[limb] = src[String(limb)]
	_reset_pose(pelvis, float(pose.get("angle", 0.0)), slots)
	var st: Dictionary = pose.get("stamina", {})
	for hand in [PoseSolver.LH, PoseSolver.RH]:
		if st.has(hand):
			rules.stamina[hand] = float(st[hand])
		elif st.has(String(hand)):
			rules.stamina[hand] = float(st[String(hand)])


func _reset_pose(pelvis: Vector2, angle: float, slots: Dictionary) -> void:
	runner.cancel(self, &"reset")
	body = BodyState.new(pelvis, angle)
	limbs.clear()
	for limb in PoseSolver.LIMBS:
		if not slots.has(limb):
			var rest := body.pos + _rest_offset(limb)
			limbs[limb] = {"state": "Free", "key": "", "pos": rest, "grab": rest, "req": rest, "cand": {}, "flag": rest, "flag_depth": 0.0, "contact": null}
			continue
		var key: String = slots[limb]
		var p := route.slot_pos(key)
		limbs[limb] = {"state": "Attached", "key": key, "pos": p, "grab": p, "req": p, "cand": {}, "flag": p, "flag_depth": 0.0,
			"contact": GripCheck.contact_for(key, route.slots, limb, p)}
	rules.contact_meta = _contact_meta()
	rules.reset(body, attached(), {}, false)
	goal_ticks = 0
	falling = false
	fall_reason = ""
	deadpoint = {}
	selecting = false
	_last_rise_tick = -1000
	_last_move_label = MoveClassifier.REST  # 새 시작: 다음 틱의 확정 기술 라벨을 다시 한 번 기록한다


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
	if falling or is_dragging() or not deadpoint.is_empty():
		return false
	for limb in limbs:
		if limbs[limb].state == "Armed":
			limbs[limb].state = "Attached"
	selecting = true
	return true


## 실행 중 기술을 버튼으로 끝낸다("풀기", 27 §6 5, §10 드롭니). 실행 중이 아니면 false.
func cancel_technique() -> bool:
	if runner.active.is_empty():
		return false
	runner.cancel(self)
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

## 데드포인트 창(04 §10.5, docs/31): 발로 일어서는 중(StandUp, 상승 ≥ 0.05)이거나 상승 ≥ 0.20이면 열리고,
## 그런 상승이 끝난 뒤 0.4초까지 열려 있다. 손을 뻗을 때 몸이 따라 조금 오르는 것만으로는 열리지 않는다.
func deadpoint_window() -> bool:
	return _rising() or tick_count - _last_rise_tick <= TechniqueJudge.DEADPOINT_GRACE_TICKS


func _rising() -> bool:
	if body.vel.y >= TechniqueJudge.DEADPOINT_RISE_SPEED:
		return true
	return rules.moves.label == MoveClassifier.STAND_UP and body.vel.y >= TechniqueJudge.DEADPOINT_STANDUP_RISE


## 지금 도달 보너스(m). drag_speed: 손가락 속도(m/s, 월드). 검증기 금지(&"deadpoint")면 0.
func deadpoint_bonus(drag_speed: float) -> float:
	if forbid.has(&"deadpoint"):
		return 0.0
	return TechniqueJudge.deadpoint_bonus(body.vel.y, drag_speed)


## InputRouter 명령({type, limb, delta, speed})을 적용한다.
func apply_input(cmds: Array) -> void:
	for c in cmds:
		var l: Dictionary = limbs[c.limb]
		if l.state == "Deadpoint":
			continue  # 날아가는 중인 손은 0.15초 동안 입력을 받지 않는다
		# 패드 조작과 실행 중 기술(27 §6 5): 기술이 쓰는 발을 누르면 취소
		if c.type in ["arm", "detach"] and runner.uses(c.limb):
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
	var reject := Callable() if forbid.is_empty() else _forbidden_target.bind(limb)
	return GripCheck.candidate(route.slots, limb, l.pos, body.pos, body.angle, attached(), occupied(), l.cand.get("key", ""), body.yaw, reject)


## 검증기 금지 플래그로 거부하는 잡기 목표인가(28 §7.4). 금지가 비면 항상 false.
func _forbidden_target(key: String, point: Vector2, limb: StringName) -> bool:
	if PoseSolver.is_hand(limb):
		var o: Dictionary = limbs[TechniqueJudge.other_of(limb)]
		if not (o.state in ["Attached", "Armed"]):
			return false
		var ox: float = (o.grab as Vector2).x
		if forbid.has(&"cross") and ((limb == PoseSolver.LH and point.x > ox) or (limb == PoseSolver.RH and point.x < ox)):
			return true
		return forbid.has(&"match") and key.get_base_dir() == String(o.key).get_base_dir()
	if forbid.has(&"high_step"):
		var hip := PoseSolver.joint_position(body.pos, body.angle, limb, body.yaw)
		return point.y >= hip.y - Tuning.HIGH_STEP_BELOW_HIP
	return false


func _try_grab(limb: StringName, speed: float = 0.0) -> void:
	var l: Dictionary = limbs[limb]
	if l.state != "Dragging":
		return  # 끌고 있지 않은 손발(붙어 있거나 날아가는 중)의 release는 잡기를 만들지 않는다
	var cand := _candidate(limb)
	l.cand = {}
	# 데드포인트(v6, docs/31): 창이 열려 있고 빠르게 놓은 손은 겨눈 홀드가 정적 후보와 다르면 그 홀드로 던진다.
	# 겨눈 홀드가 정적 후보와 같으면 그냥 잡는다. 정지 상태의 빠른 드래그는 창이 닫혀 있어 일반 처리(27 §13 TA04).
	if PoseSolver.is_hand(limb) and speed >= TechniqueJudge.DEADPOINT_MIN_SPEED and deadpoint_window() and _start_pad_deadpoint(limb, speed, cand):
		return
	if cand.is_empty():
		if not PoseSolver.is_hand(limb) and not forbid.has(&"foot_swap") and _try_pad_foot_swap(limb):
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
			_log_event({"type": "flag", "limb": limb})
		else:
			l.state = "Free"
		return
	var contact := GripCheck.contact_for_pose(cand.key, route.slots, limb, cand.point, body.pos, body.angle, body.yaw, attached(), _contact_meta(), _endpoints(), forbid.has(&"grip_auto"))
	_attach(limb, cand.key, cand.point, contact)
	if PoseSolver.is_hand(limb):
		_log_event({"type": "pad_grip", "limb": limb, "key": cand.key, "mode": contact.mode})  # 28 §4.3 5: 튜토리얼 판정용


## 네 팔다리의 실제 말단 위치.
func _endpoints() -> Dictionary:
	var d := {}
	for limb in limbs:
		d[limb] = limbs[limb].pos
	return d


## 패드로 끈 발을 반대 발이 딛은 발판에 놓으면 풋스왑(Ruling 14): 판단기의 풋스왑 판단(T_FOOT_SWAP)을 통과하면
## 들어온 발이 붙고 반대 발은 같은 틱에 풀린다. 못 하면 false(일반 거부 경로로).
func _try_pad_foot_swap(foot: StringName) -> bool:
	var l: Dictionary = limbs[foot]
	var other := TechniqueJudge.other_of(foot)
	var key := GripCheck.aimed_slot(route.slots, l.req)
	if key.is_empty() or not attached().has(other) or limbs[other].key != key or not route.slots[key].allowed.has(foot):
		return false
	var snap := ClimbSnapshot.from_session(self)
	if not TechniqueJudge.slot_filter(snap, TechniqueJudge.T_FOOT_SWAP, foot, key):
		return false
	var pt := TechniqueJudge.point_for(snap, TechniqueJudge.T_FOOT_SWAP, foot, key, l.req)
	if pt.is_empty() or (l.pos as Vector2).distance_to(pt.point) > GripCheck.radius_of(foot):
		return false
	if not forbid.is_empty() and _forbidden_target(key, pt.point, foot):
		return false  # 검증기 금지(high_step): 높은 발 자리로 바꿔 딛기도 우회로가 되지 않게 거부
	if not TechniqueJudge.evaluate_target(snap, TechniqueJudge.T_FOOT_SWAP, foot, key, pt.point).ok:
		return false
	l.cand = {}
	_attach(foot, key, pt.point, TechniqueJudge.contact_for(route, TechniqueJudge.T_FOOT_SWAP, foot, key, pt.point))
	limbs[other].state = "Free"
	limbs[other].contact = null
	messages.append("발을 바꿔 딛었어요")
	_log_event({"type": "pad_foot_swap", "limb": foot, "key": key})
	return true


## 패드로 놓은 손의 데드포인트 시도. 노린 홀드(요청 목표 근처)가 보너스 범위 + 여유 안에 있으면 던진다.
## 범위 안/밖과 무관하게 던진 뒤의 성패는 받기 판정이 정한다(놓치면 DEADPOINT_MISS).
func _start_pad_deadpoint(limb: StringName, speed: float, cand: Dictionary = {}) -> bool:
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
		if not forbid.is_empty() and _forbidden_target(key, pt.point, limb):
			continue
		best = {"key": key, "point": pt.point}
		best_d = aim.distance_to(slot.pos)
	if best.is_empty() or (not cand.is_empty() and best.key == cand.key):
		return false
	start_deadpoint(limb, best.key, best.point, bonus)
	return true


## 데드포인트 시작(패드 빠른 놓기). 손을 떼어 "Deadpoint" 상태로 두고 목표로 날린다.
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
	var follow := {}
	if arrived and TechniqueJudge.deadpoint_catch(ClimbSnapshot.from_session(self), limb, dp.key, dp.point, dp.bonus).ok:
		follow = _deadpoint_follow_pose(limb, dp.point)
	if not follow.is_empty():
		# 손이 먼저 닿고 몸이 탄력으로 따라간다(v6): 모든 접점이 성립하는 가까운 자세로 골반을 옮긴다
		body.pos = follow.pos
		body.angle = follow.angle
		for f in follow.cut:
			limbs[f].state = "Free"
			limbs[f].contact = null
			limbs[f].cand = {}
		if not follow.cut.is_empty():
			messages.append("발이 벽에서 떨어졌어요")
			_log_event({"type": "feet_cut", "limbs": follow.cut})
		_attach(limb, dp.key, dp.point, TechniqueJudge.contact_for(route, TechniqueJudge.T_DEADPOINT, limb, dp.key, dp.point))
		var holder := TechniqueJudge.other_of(limb)
		rules.stamina[holder] = Fatigue.apply(float(rules.stamina[holder]), -DEADPOINT_STAMINA_COST, 1.0, rules.fatigue_disabled)  # 보조 모드는 감소 없음
		_log_event({"type": "pad_deadpoint", "limb": limb, "key": dp.key, "ok": true})
		return false
	l.state = "Free"
	_log_event({"type": "pad_deadpoint", "limb": limb, "key": dp.key, "ok": false})
	return true


## 데드포인트로 받은 뒤 몸이 따라갈 자세(docs/31). 새 접점을 더한 접점들이 성립(PoseSolver.is_valid)하고
## 지금 골반에서 DEADPOINT_FOLLOW_MAX 안인 자세를 찾는다. 발을 모두 유지한 자세가 없으면 발을 떼어 본다
## (다이나믹하게 잡으면 발이 벽에서 떨어진다: 풋컷). 반환 {pos, angle, cut: 뗄 발 배열}, 손으로도 안 되면 {}(놓침).
func _deadpoint_follow_pose(limb: StringName, point: Vector2) -> Dictionary:
	var base := attached()
	base[limb] = point
	var feet_on: Array = [PoseSolver.LF, PoseSolver.RF].filter(func(f): return base.has(f))
	var options: Array = [[]]
	for f in feet_on:
		options.append([f])
	if feet_on.size() == 2:
		options.append(feet_on.duplicate())
	for cut in options:
		var with_new := base.duplicate()
		for f in cut:
			with_new.erase(f)
		var pose := _valid_pose_near(with_new)
		if not pose.is_empty():
			pose.cut = cut
			return pose
	return {}


## 접점 att가 모두 성립하는 가장 가까운 자세(지금 자세 우선). 골반은 DEADPOINT_FOLLOW_MAX 반경을 0.025m 격자로,
## 몸통 각은 지금 ±10°를 5° 간격으로 본다. PoseSolver.find_target은 성립하지 않는 자세에서 시작하면 움직이지
## 않아서(받는 순간이 그렇다) 여기서는 직접 찾는다. 받을 때 한 번만 부른다. 없으면 {}.
func _valid_pose_near(att: Dictionary) -> Dictionary:
	if PoseSolver.is_valid(body.pos, body.angle, att, body.yaw):
		return {"pos": body.pos, "angle": body.angle}
	var step := 0.025
	var n := int(TechniqueJudge.DEADPOINT_FOLLOW_MAX / step)
	var best := {}
	var best_d := INF
	for ix in range(-n, n + 1):
		for iy in range(-n, n + 1):
			var off := Vector2(ix, iy) * step
			var d := off.length()
			if d > TechniqueJudge.DEADPOINT_FOLLOW_MAX or d >= best_d:
				continue
			for da in [0.0, -5.0, 5.0, -10.0, 10.0]:
				var a: float = body.angle + da
				if PoseSolver.is_valid(body.pos + off, a, att, body.yaw):
					best = {"pos": body.pos + off, "angle": a}
					best_d = d
					break
	return best


func _attach(limb: StringName, key: String, point: Vector2, contact: ContactInfo) -> void:
	var l: Dictionary = limbs[limb]
	l.state = "Attached"
	l.key = key
	l.grab = point
	l.pos = point
	l.contact = contact
	_log_event({"type": "grab", "limb": limb, "key": key, "quality": contact.quality if contact != null else 1.0})


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
	rules.forbid = forbid
	var outcome := rules.tick(body, att, endpoints, on_platform(att), moving, intents, hints, flag_probe)
	if _rising():
		_last_rise_tick = tick_count
	_log_move_label()
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
			target = body.pos + _rest_offset(limb)
		var prev: Vector2 = l.pos
		target = _clamp_to_reach(limb, prev, target)
		l.pos = _clamp_to_reach(limb, prev, l.pos.move_toward(target, 2.5 * Tuning.DT))


## 쉬는(Free) 손발의 골반 기준 목표 위치.
static func _rest_offset(limb: StringName) -> Vector2:
	var side := -1.0 if limb in [&"LH", &"LF"] else 1.0
	return Vector2(0.35 * side, 0.18) if PoseSolver.is_hand(limb) else Vector2(0.25 * side, -0.70)


## 확정 무브 라벨이 바뀌어 기술 라벨(MOVE_EVENT_LABELS)이 되면 move 이벤트를 한 번 남긴다.
func _log_move_label() -> void:
	var lbl: StringName = rules.moves.label
	if lbl == _last_move_label:
		return
	_last_move_label = lbl
	if lbl in MOVE_EVENT_LABELS:
		_log_event({"type": "move", "label": lbl})


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
	_log_event({"type": "fall", "reason": reason})
	falls += 1
	deadpoint = {}
	falling = true
	fall_reason = reason
	fall_ticks = 0
	for limb in limbs:
		limbs[limb].state = "Free"


## 확정된 틱의 기술 이벤트를 기록한다. 이벤트의 키를 그대로 두고 tick과 seq를 더한다(형식 자유, type은 필수).
## 실패는 이유 문구를 안내한다.
func _log_event(ev: Dictionary) -> void:
	if ev.is_empty():
		return
	var entry := ev.duplicate()
	entry["tick"] = tick_count
	event_seq += 1
	entry["seq"] = event_seq
	technique_log.append(entry)
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
