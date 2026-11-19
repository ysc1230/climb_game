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
## 멈춤 플래그(docs/superpowers/specs/2026-11-19-1-feel-design.md §1.1·§1.2). 기본 끔 = 지금 동작.
## hold_on_clear: 완등 틱에 reset 대신 탑 자세로 멈춘다. hold_on_fall: 낙하 끝(respawn 조건)에 reset 대신 "landed"를 돌려주고 멈춘다.
## 멈춘 동안(halted != &"") step은 "", apply_input은 무시. reset()이 푼다.
var hold_on_clear := false
var hold_on_fall := false
var halted: StringName = &""
var messages: Array[String] = []
var last_phase := -1
var runner := TechniqueRunner.new()  # 기술 실행기(docs/27). 한 번에 하나
## 확정된 틱의 기술 이벤트(09 v0.6, 능력치에 쓰지 않음). 최근 200개.
## 모든 이벤트에 tick과 seq(세션 수명 동안 1부터 단조 증가, reset/reset_to에도 되돌리지 않음)가 붙는다.
## 로그는 최근 TECHNIQUE_LOG_MAX개만 남으므로 소비자(튜토리얼 실행기)는 seq > 마지막으로 본 seq로 새 이벤트를 고른다.
## 기술 실행기: {type, id, side, key, quality, reason}. 패드 손 잡기: {type: "pad_grip", limb, key, mode}(28 §4.3).
## 패드 기술(28 §7.4·튜토리얼 판정): {type: "move", label}(확정 라벨이 MOVE_EVENT_LABELS로 바뀔 때 1회),
## {type: "grab", limb, key, quality}(패드·기술로 붙을 때마다), {type: "flag", limb}(패드 균형 발이 될 때),
## {type: "pad_foot_swap", limb, key}, {type: "fall", reason}(추락 시작), {type: "miss", limb, reason}(놓았는데 못 잡음).
var technique_log: Array = []
var event_seq := 0  # 마지막으로 기록한 이벤트의 seq
## 검증기 전용 금지 플래그(키 StringName → true, 28 §7.4). 플레이 코드는 설정하지 않는다(비면 영향 없음).
## &"high_step": 고관절−0.20m 이상 발 후보 거부 + StandUp 선호 끔, &"cross": 반대 손 X를 넘는 손 후보 거부,
## &"flag": 균형 발 상태를 만들지 않음, &"match": 반대 손이 잡은 홀드 거부, &"foot_swap": 패드 풋스왑 끔,
## &"lock_off": LockOff 선호 대신 뻗기 선호(0.60), &"grip_auto": 잡기 방향 자동 선택 끔(grip_modes[0]).
var forbid := {}
const MOVE_EVENT_LABELS := [MoveClassifier.HIGH_STEP, MoveClassifier.STAND_UP, MoveClassifier.CROSS_REACH, MoveClassifier.HAND_MATCH, MoveClassifier.LOCK_OFF]
var _last_move_label: StringName = MoveClassifier.REST
var tick_count := 0
## 기술 고르는 중(docs/27 §6, 15 v0.6 TechniqueSelect). true인 동안 step()은 아무것도 바꾸지 않는다.
var selecting := false
const TECHNIQUE_LOG_MAX := 200
var _hint_cooldown := 0
var _last_hint := &""


func _init(p_route: RouteDef) -> void:
	route = p_route
	reset()


func reset() -> void:
	halted = &""
	_reset_pose(route.start_pelvis, route.start_angle, route.start_slots)


## 주어진 자세로 다시 시작한다(튜토리얼 단계 시작용). pose는 RouteDef.start_pose와 같은 형식
## {pelvis: [x, y], angle, slots: {limb: key}, stamina?: {LH, RH}}. slots에 없는 팔다리는 Free(쉬는 위치)로 둔다.
## 기술 로그와 seq는 이어진다.
func reset_to(pose: Dictionary) -> void:
	halted = &""
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
	rules.body_goal = Vector2(NAN, NAN)
	_body_dragging = false
	dyno = {}
	_dyno_relief = 0
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
	selecting = false
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
	if falling or is_dragging():
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


# ---------- 몸통 끌기(docs/03 v0.9) ----------

var _body_dragging := false
var _body_anchor := Vector2.ZERO
var _body_offset := Vector2.ZERO


## 패드 사이 가운데 영역 끌기: 누른 순간의 골반을 기준으로 끈 만큼(최대 BODY_GOAL_MAX) 골반 목표를 옮긴다.
## 손을 떼도 목표는 남고(그 자리에 머묾), 다른 팔다리를 움직이기 시작하면 지운다. 판정(도달·관절·힘 균형)은 그대로다.
func _body_input(c: Dictionary) -> void:
	match str(c.type):
		"body_start":
			_body_dragging = true
			_body_anchor = body.pos
			_body_offset = Vector2.ZERO
			rules.body_goal = body.pos
		"body_move":
			if _body_dragging:
				_body_offset = (_body_offset + (c.delta as Vector2)).limit_length(Tuning.BODY_GOAL_MAX)
				rules.body_goal = _body_anchor + _body_offset
		"body_end":
			_body_dragging = false


## 몸통 끌기 중인가(화면 화살표용).
func body_dragging() -> bool:
	return _body_dragging


# ---------- 입력 ----------

## InputRouter 명령({type, limb, delta, speed})을 적용한다. release의 speed는 쓰지 않는다(데드포인트 제거).
func apply_input(cmds: Array) -> void:
	if halted != &"":
		return
	for c in cmds:
		if c.type in ["dyno_start", "dyno_move", "dyno_end", "dyno_cancel"]:
			_dyno_input(c)
			continue
		if dyno.get("phase", "") == "flight":
			if c.type in ["arm", "detach"] and PoseSolver.is_hand(c.limb):
				_dyno_catch(c.limb)
			continue  # 날아가는 동안 다른 조작은 받지 않는다
		if dyno.get("phase", "") == "hang" and c.type == "detach" and PoseSolver.is_hand(c.limb) and _dyno_catch(c.limb):
			continue
		if dyno.get("phase", "") == "charge":
			continue  # 준비하는 동안 손발은 그대로
		if c.type in ["body_start", "body_move", "body_end"]:
			_body_input(c)
			continue
		if c.type in ["arm", "detach"] and not _body_dragging:
			rules.body_goal = Vector2(NAN, NAN)  # 다른 팔다리를 움직이기 시작하면 자동 자세로 돌아간다
		var l: Dictionary = limbs[c.limb]
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


func _try_grab(limb: StringName) -> void:
	var l: Dictionary = limbs[limb]
	if l.state != "Dragging":
		return  # 끌고 있지 않은 손발(붙어 있는)의 release는 잡기를 만들지 않는다
	var cand := _candidate(limb)
	l.cand = {}
	if cand.is_empty():
		if not PoseSolver.is_hand(limb) and not forbid.has(&"foot_swap") and _try_pad_foot_swap(limb):
			return
		if forbid.is_empty() and _try_slot_swap(limb):
			return
		var reason := GripCheck.reject_reason(route.slots, limb, l.pos, l.req, body.pos, body.angle, attached(), occupied(), rules.feet_eligible, body.yaw)
		var text := GripCheck.message(reason, limb)
		if not text.is_empty():
			messages.append(text)
		_log_event({"type": "miss", "limb": limb, "reason": reason})  # 놓았는데 못 잡음(기술 수업의 "먼저 그냥 해 보기" 단계, docs/47)
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


## 다른 손발이 잡거나 밟고 있는 홀드에 손발을 놓으면(2026-11-10 사용자 규칙): 그 손발을 떼어 들어온 손발이 잡고,
## 뗀 손발은 균형이 가장 좋은 허공 위치(flag_cost 최소)에 둔다(Flag 상태: 그 자리를 유지하며 다시 끌 수 있음).
## 같은 종류(손↔손, 발↔발)만. 합손 가능한 파란 홀드는 이 길로 오지 않는다(후보가 이미 있음). 못 잡으면 되돌리고 false.
func _try_slot_swap(limb: StringName) -> bool:
	var l: Dictionary = limbs[limb]
	var key := GripCheck.aimed_slot(route.slots, l.req)
	if key.is_empty() or not route.slots[key].allowed.has(limb):
		return false
	var occ: StringName = &""
	for o in limbs:
		if o != limb and PoseSolver.is_hand(o) == PoseSolver.is_hand(limb) and limbs[o].state in ["Attached", "Armed"] and limbs[o].key == key:
			occ = o
	if occ == &"":
		return false
	var o: Dictionary = limbs[occ]
	var saved := {"state": o.state, "contact": o.contact}
	o.state = "Flag"
	o.contact = null
	var cand := _candidate(limb)
	if cand.is_empty() or cand.key != key:
		o.state = saved.state
		o.contact = saved.contact
		return false
	var contact := GripCheck.contact_for_pose(cand.key, route.slots, limb, cand.point, body.pos, body.angle, body.yaw, attached(), _contact_meta(), _endpoints(), forbid.has(&"grip_auto"))
	_attach(limb, cand.key, cand.point, contact)
	o.flag = _best_air_point(occ)
	o.flag_depth = 0.0
	o.req = o.flag
	messages.append("%s 자리를 내주고 균형 잡는 곳에 두었어요" % ("손이" if PoseSolver.is_hand(occ) else "발이"))
	_log_event({"type": "slot_swap", "limb": limb, "freed": occ, "key": key})
	return true


## 떠 있는 limb을 둘 허공 위치: 관절 둘레 후보 중 지금 붙은 손발로 버틸 때 균형 비용(flag_cost)이 가장 작은 곳.
func _best_air_point(limb: StringName) -> Vector2:
	var att := attached()
	var joint := PoseSolver.joint_position(body.pos, body.angle, limb, body.yaw)
	var reach := PoseSolver.reach_of(limb)
	var eps := _endpoints()
	for a in att:
		eps.erase(a)
	var best: Vector2 = limbs[limb].pos
	var best_c := INF
	var feet := PoseSolver.supporting_feet(body.pos, body.angle, att, rules.feet_eligible, body.yaw)
	# 자연스러운 범위만: 발은 고관절 아래쪽 부채꼴, 손은 어깨 옆·위 부채꼴(관절이 무리하게 꺾이는 곳에 두지 않게), 쉬는 위치도 후보
	var side := PoseSolver.side_sign(limb)
	var dirs: Array[Vector2] = []
	for i in 7:
		var t := deg_to_rad(-15.0 + 25.0 * i)  # 몸 바깥쪽 −15°~135°
		dirs.append(Vector2(side * sin(t), cos(t)) if PoseSolver.is_hand(limb) else Vector2(side * sin(t * 0.5), -cos(t * 0.5)))
	var cands: Array[Vector2] = [body.pos + _rest_offset(limb)]
	for dir in dirs:
		for f in [0.7, 0.85]:
			cands.append(joint + dir * reach.y * f)
	for raw in cands:
		if true:
			var p := _clamp_to_reach(limb, limbs[limb].pos, raw)
			eps[limb] = p
			var c := ClimbRules.flag_cost(rules.evaluate(body.pos, body.angle, att, eps, on_platform(att), feet, body.yaw))
			if c < best_c - 0.0001:
				best_c = c
				best = p
	return best


## 붙어 있는 limb을 지금 떼면 어떻게 되나(예고 경고, 2026-11-09). 몸은 그대로 둔 채 그 접점만 뺀 힘 계산.
## &"" 버틸 수 있음, &"GRACE" 버틸 손·플랫폼이 없음, &"FORCE" 힘 균형이 깨짐, &"BARN_DOOR" 몸이 문처럼 돌아감.
## 떼고 나면 몸이 지지 쪽으로 저절로 옮겨 가 회복할 수도 있다(REBALANCING) — 예고는 "위험할 수 있음"이다.
func release_risk(limb: StringName) -> StringName:
	var att := attached()
	if not att.has(limb):
		return &""
	att.erase(limb)
	var eps := _endpoints()
	for l in att:
		eps.erase(l)
	var platform := on_platform(att)
	if rules._eligible_hand_count(body.pos, body.angle, att, body.yaw) == 0 and not ClimbRules.platform_holds(platform, att):
		return &"GRACE"
	var feet := PoseSolver.supporting_feet(body.pos, body.angle, att, rules.feet_eligible, body.yaw)
	var r := rules.evaluate(body.pos, body.angle, att, eps, platform, feet, body.yaw)
	if r.status != SupportSolver.Status.FEASIBLE:
		return &"FORCE"
	if ClimbRules.barn_exceeded(r):
		return &"BARN_DOOR"
	return &""


## 지금 자세를 reset_to 형식으로(되돌리기용). 붙은 손발의 슬롯만 담고 떠 있는 손발은 쉬는 위치로 돌아간다.
func current_pose() -> Dictionary:
	var slots := {}
	for limb in limbs:
		if limbs[limb].state in ["Attached", "Armed"]:
			slots[limb] = limbs[limb].key
	return {"pelvis": [body.pos.x, body.pos.y], "angle": body.angle, "slots": slots, "stamina": rules.stamina.duplicate()}


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
	if pt.is_empty() or (l.pos as Vector2).distance_to(pt.point) > GripCheck.radius_for(foot, route.slots[key]):
		return false
	if not forbid.is_empty() and _forbidden_target(key, pt.point, foot):
		return false  # 검증기 금지(high_step): 높은 발 자리로 바꿔 딛기도 우회로가 되지 않게 거부
	if not TechniqueJudge.evaluate_target(snap, TechniqueJudge.T_FOOT_SWAP, foot, key, pt.point).ok:
		return false
	l.cand = {}
	_attach(foot, key, pt.point, TechniqueJudge.contact_for(route, TechniqueJudge.T_FOOT_SWAP, foot, key, pt.point))
	limbs[other].state = "Flag"  # 뗀 발은 균형이 가장 좋은 허공에(2026-11-10 사용자 규칙, _try_slot_swap과 같음)
	limbs[other].contact = null
	limbs[other].flag = _best_air_point(other)
	limbs[other].flag_depth = 0.0
	limbs[other].req = limbs[other].flag
	messages.append("발을 바꿔 딛었어요")
	_log_event({"type": "pad_foot_swap", "limb": foot, "key": key})
	return true


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
	if halted != &"":
		return ""
	if selecting:
		return ""  # 기술 고르는 중: 틱·피로·카운터·몸통·말단 모두 멈춘다
	tick_count += 1
	if falling:
		return _fall_tick()
	if dyno.get("phase", "") == "flight":
		return _dyno_tick()
	rules.drain_scale = Tuning.DYNO_RELIEF_SCALE if _dyno_relief > 0 else 1.0
	_dyno_relief = maxi(0, _dyno_relief - 1)
	if dyno.get("phase", "") == "hang":
		rules.imbalance_ticks = 0  # 잡은 직후 버티는 시간(DYNO_HANG_TICKS): 균형·지지 카운터를 세지 않는다
		rules.unsupported_ticks = 0
		dyno.ticks = int(dyno.ticks) - 1
		if dyno.has("anchor"):  # 날던 방향으로 흔들리다 줄어든다(감쇠 진동, 2026-11-18 사용자)
			dyno.t = float(dyno.t) + Tuning.DT
			var t: float = dyno.t
			var fade := pow(0.5, t / 0.35)
			rules.body_goal = (dyno.anchor as Vector2) + Vector2(float(dyno.amp) * cos(TAU * Tuning.DYNO_SWAY_HZ * t) * fade, -0.03 * absf(sin(TAU * Tuning.DYNO_SWAY_HZ * t)) * fade)
		if int(dyno.ticks) <= 0:
			if dyno.has("anchor") and not _body_dragging:
				rules.body_goal = Vector2(NAN, NAN)
			dyno = {}
	_log_event(runner.tick(self))
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
	_log_move_label()
	_drag_hints(att, occ)
	for hand in rules.slipped:
		limbs[hand].state = "Free"
		limbs[hand].contact = null
		messages.append("손이 미끄러졌어요")
	if rules.phase != last_phase and dyno.get("phase", "") == "hang":
		last_phase = rules.phase  # 다이노로 잡은 직후 버티는 1초에는 균형 문구를 띄우지 않는다
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
		if hold_on_clear:
			halted = &"clear"
		else:
			reset()
		return "clear"
	return ""


func _start_fall(reason: String) -> void:
	runner.cancel(self, &"fall")
	_log_event(runner.tick(self))
	_log_event({"type": "fall", "reason": reason})
	falls += 1
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
		if hold_on_fall:
			halted = &"fall"
			return "landed"
		reset()
		return "respawn"
	return ""


# ---------- 균형 보기(docs/49) ----------

## 화면용 균형 정보: {com(무게중심), feet: [{limb, pos(딛은 점), share(그 발의 몫 0.65~1)}], state: "ok"/"strain"/"danger"}.
## state는 손 힘 규칙과 같다: ok = 발 몫 합 ≥ REST_FOOT_SUPPORT이고 안정(가만히 있으면 손 힘이 참), danger = 균형 회복 중·지지 없음.
func balance_view() -> Dictionary:
	var feet := []
	var att := attached()
	for f in [PoseSolver.LF, PoseSolver.RF]:
		if att.has(f) and rules.loaded_feet.has(f):
			var w := ClimbRules.foot_weight(body.pos, body.angle, body.yaw, f, att[f])
			feet.append({"limb": f, "pos": att[f], "share": (1.0 - Tuning.FOOT_LOAD_BLEND) + Tuning.FOOT_LOAD_BLEND * w})
	var ph := rules.phase
	var state := "danger" if ph == ClimbRules.Phase.REBALANCING or ph == ClimbRules.Phase.GRACE else \
		("ok" if rules.foot_support >= Tuning.REST_FOOT_SUPPORT - 0.0001 and ph == ClimbRules.Phase.STABLE else "strain")
	return {"com": rules.last.get("com", body.pos), "feet": feet, "state": state}


## 손발마다 받치는 몸무게 몫(합 = 1). 힘 계산의 접점 힘 크기를 합으로 나눈 비율(옆으로 서로 상쇄되는 성분이 있어
## 크기 합이 1BW를 넘을 수 있으므로). 붙지 않았거나 하중이 없으면 0.
func limb_loads() -> Dictionary:
	var out := {}
	var loads: Dictionary = rules.last.get("loads", {})
	var total := 0.0
	for limb in limbs:
		if attached().has(limb):
			total += float(loads.get(limb, 0.0))
	for limb in limbs:
		out[limb] = float(loads.get(limb, 0.0)) / total if attached().has(limb) and total > 0.0001 else 0.0
	return out


# ---------- 다이노(Tuning.DYNO_*, docs/45) ----------

## {} / {phase: "charge", anchor, drag(끈 벡터, 월드)}
## / {phase: "flight", reach(닿는 손홀드 키 목록), aim: {hand: 키}, start_y, window(남은 틱), window_used, window_ticks}
## / {phase: "hang", ticks}(잡은 직후 1초: 균형을 잃어도 버팀, 다른 손 패드를 누르면 닿는 손홀드를 잡음)
var dyno := {}
var _dyno_relief := 0
const _UP := Vector2(0.0, 1.0)  # 월드 위(_UP은 화면 위라 −y)


func dyno_flying() -> bool:
	return dyno.get("phase", "") == "flight"


## 느린 화면 중이면 남은 비율(0~1), 아니면 -1.
func dyno_slow_left() -> float:
	if not dyno_flying() or int(dyno.window) <= 0:
		return -1.0
	return float(dyno.window) / float(dyno.window_ticks)


## 날아가는 동안 손마다 팔을 뻗어 닿은 손홀드 키(없으면 빈 문자열). 그 손 패드를 누르면 잡는다.
func dyno_aim() -> Dictionary:
	return dyno.get("aim", {}) if dyno_flying() else {}


## 준비 중이면 {reach(그 궤적에서 팔이 닿는 손홀드 키, 높은 순), cost, quality, ready}, 아니면 {}.
func dyno_preview() -> Dictionary:
	if dyno.get("phase", "") != "charge":
		return {}
	var ready := (dyno.drag as Vector2).length() >= Tuning.DYNO_DRAG_MIN
	return {"reach": _dyno_reachable(_dyno_velocity()) if ready else [], "cost": lerpf(Tuning.DYNO_COST_MIN, Tuning.DYNO_COST_MAX, _dyno_t()),
		"quality": dyno_quality(), "ready": ready}


func _dyno_t() -> float:
	return clampf(((dyno.drag as Vector2).length() - Tuning.DYNO_DRAG_MIN) / (Tuning.DYNO_DRAG_MAX - Tuning.DYNO_DRAG_MIN), 0.0, 1.0)


func _top_hand_y() -> float:
	var top := body.pos.y
	for hand in [PoseSolver.LH, PoseSolver.RH]:
		if limbs[hand].state in ["Attached", "Armed"]:
			top = maxf(top, (limbs[hand].grab as Vector2).y)
	return top


## 홀드 품질 0~1: 붙은 손홀드는 반폭/0.10, 발판은 반폭/0.06(최대 1, 정상은 1). 손·발 평균의 평균.
func dyno_quality() -> float:
	var qh := []
	var qf := []
	for limb in attached():
		var key: String = limbs[limb].key
		var slot: Dictionary = route.slots[key]
		var hw := float(slot.hand_area.half_width) if slot.has("hand_area") else (GripCheck.foot_half_width(slot) if not route.goal_slots.has(key) else 0.13)
		if PoseSolver.is_hand(limb):
			qh.append(clampf(hw / 0.10, 0.0, 1.0))
		else:
			qf.append(clampf(hw / 0.06, 0.0, 1.0))
	var avg := func(a: Array) -> float:
		return 0.0 if a.is_empty() else a.reduce(func(x, y): return x + y, 0.0) / a.size()
	return 0.5 * avg.call(qh) + 0.5 * avg.call(qf)


## 끈 길이·방향과 홀드 품질로 정한 처음 속도. 방향 = 끈 반대(새총), 위에서 좌우 DYNO_MAX_ANGLE까지.
## 속력 = 똑바로 위로 뛸 때 꼭대기 골반이 "다리를 쭉 편 골반 + 덤"에 닿는 속력(지금 골반에서).
func _dyno_velocity() -> Vector2:
	var drag: Vector2 = dyno.drag
	var dir := -drag.normalized() if drag.length() > 0.001 else _UP
	var ang := clampf(_UP.angle_to(dir), -deg_to_rad(Tuning.DYNO_MAX_ANGLE), deg_to_rad(Tuning.DYNO_MAX_ANGLE))
	dir = _UP.rotated(ang)
	var feet := []
	for limb in [PoseSolver.LF, PoseSolver.RF]:
		if limbs[limb].state in ["Attached", "Armed"]:
			feet.append((limbs[limb].grab as Vector2).y)
	var foot_y: float = feet.reduce(func(x, y): return x + y, 0.0) / feet.size() if not feet.is_empty() else body.pos.y - PoseSolver.reach_of(PoseSolver.LF).y
	var q := dyno_quality()
	var extra := lerpf(Tuning.DYNO_EXTRA_MIN, Tuning.DYNO_EXTRA_MAX, _dyno_t()) * q - Tuning.DYNO_BAD_DROP * (1.0 - q)
	var apex := foot_y + PoseSolver.reach_of(PoseSolver.LF).y - Tuning.HIP_OFFSET.y + extra
	return dir * sqrt(2.0 * 9.8 * maxf(0.05, apex - body.pos.y))


## 처음 속도 v로 뛸 때 팔(DYNO_REACH)이 닿는 손홀드(정상 포함). 지금 가장 높은 손보다 0.05m 넘게 높은 것, 높은 순.
func _dyno_reachable(v: Vector2) -> Array:
	var arm := PoseSolver.reach_of(PoseSolver.LH).y * Tuning.DYNO_REACH
	var top := _top_hand_y()
	var p := body.pos
	var vel := v
	var found := {}
	for i in 240:
		vel.y -= 9.8 * Tuning.DT
		p += vel * Tuning.DT
		for hand in [PoseSolver.LH, PoseSolver.RH]:
			var sh := PoseSolver.joint_position(p, 0.0, hand)
			for key in route.slots:
				if found.has(key):
					continue
				var slot: Dictionary = route.slots[key]
				if not slot.has("hand_area") and not route.goal_slots.has(key):
					continue
				var hp := route.slot_pos(key)
				if hp.y > top + 0.05 and sh.distance_to(hp) <= arm:
					found[key] = hp.y
		if vel.y < 0.0 and p.y < body.pos.y - Tuning.DYNO_MISS_DROP:
			break
	var keys := found.keys()
	keys.sort_custom(func(a, b): return found[a] > found[b])
	return keys


func _dyno_input(c: Dictionary) -> void:
	match str(c.type):
		"dyno_start":
			if falling or selecting or not dyno.is_empty():
				return
			var hands := 0
			var feet := 0
			for limb in attached():
				if PoseSolver.is_hand(limb):
					hands += 1
				else:
					feet += 1
			if hands == 0 or feet == 0:
				messages.append("다이노는 손과 발이 붙어 있을 때 할 수 있어요")
				return
			runner.cancel(self)
			_body_dragging = false
			dyno = {"phase": "charge", "anchor": body.pos, "drag": Vector2.ZERO}
			rules.body_goal = body.pos
		"dyno_move":
			if dyno.get("phase", "") == "charge":
				dyno.drag = ((dyno.drag as Vector2) + (c.delta as Vector2)).limit_length(Tuning.DYNO_DRAG_MAX)
				rules.body_goal = (dyno.anchor as Vector2) + (dyno.drag as Vector2) * (Tuning.DYNO_CROUCH / Tuning.DYNO_DRAG_MAX)
		"dyno_end":
			if dyno.get("phase", "") != "charge":
				return
			if (dyno.drag as Vector2).length() < Tuning.DYNO_DRAG_MIN:
				dyno = {}
				rules.body_goal = Vector2(NAN, NAN)
				messages.append("더 길게 끌어야 다이노해요")
				return
			_dyno_launch()
		"dyno_cancel":
			if dyno.get("phase", "") == "charge":
				dyno = {}
				rules.body_goal = Vector2(NAN, NAN)
				messages.append("다이노를 취소했어요")


func _dyno_launch() -> void:
	var v := _dyno_velocity()
	var reach := _dyno_reachable(v)
	var cost := lerpf(Tuning.DYNO_COST_MIN, Tuning.DYNO_COST_MAX, _dyno_t())
	for hand in [PoseSolver.LH, PoseSolver.RH]:
		rules.stamina[hand] = maxf(0.0, float(rules.stamina[hand]) - cost)
	for limb in limbs:
		var l: Dictionary = limbs[limb]
		l.state = "Free"
		l.contact = null
		l.cand = {}
	body.vel = v
	body.ang_vel = 0.0
	body.angle = 0.0  # 날아가는 동안 몸은 곧게(표시한 닿는 홀드 계산과 같은 자세)
	body.yaw = 0.0
	rules.body_goal = Vector2(NAN, NAN)
	dyno = {"phase": "flight", "reach": reach, "aim": {}, "start_y": body.pos.y, "window": 0, "window_used": false, "window_ticks": 1}
	_dyno_place_limbs()
	_log_event({"type": "dyno", "vel": v, "cost": cost, "reach": reach})


## 날아가는 동안 손발 위치. 손: 팔이 닿는(DYNO_REACH) 표시된 손홀드 중 가장 높은 것으로 뻗고(aim),
## 없으면 그중 가장 높은 홀드 쪽으로(없으면 뛰는 방향으로) 쭉 뻗는다. 두 손은 같은 홀드를 겨누지 않는다(정상 두 칸은 다른 홀드로 침).
## 발은 늘어뜨린다.
func _dyno_place_limbs() -> void:
	var arm := PoseSolver.reach_of(PoseSolver.LH).y * Tuning.DYNO_REACH
	var reach: Array = dyno.reach
	var aim := {}
	for hand in [PoseSolver.LH, PoseSolver.RH]:
		var sh := PoseSolver.joint_position(body.pos, body.angle, hand, body.yaw)
		var key := ""
		for k in reach:  # 높은 순: 이 손이 닿는 가장 높은 홀드(두 손이 같은 홀드를 겨눌 수 있다 — 누른 손이 잡는다)
			if sh.distance_to(route.slot_pos(k)) <= arm:
				key = k
				break
		aim[hand] = key
		var to: Vector2
		if not key.is_empty():
			to = route.slot_pos(key)
		elif not reach.is_empty():
			to = route.slot_pos(reach[0])
		else:
			to = sh + (body.vel.normalized() if body.vel.length() > 0.1 else _UP)
		var p: Vector2 = sh + (to - sh).limit_length(arm) if not key.is_empty() else sh + (to - sh).normalized() * arm
		limbs[hand].pos = p
		limbs[hand].req = p
	for foot in [PoseSolver.LF, PoseSolver.RF]:
		limbs[foot].pos = body.pos + _rest_offset(foot)
		limbs[foot].req = limbs[foot].pos
	dyno.aim = aim


func _dyno_tick() -> String:
	var slow := int(dyno.window) > 0
	var dt := Tuning.DT * (Tuning.DYNO_SLOW if slow else 1.0)
	body.vel.y -= 9.8 * dt
	body.pos += body.vel * dt
	_dyno_place_limbs()
	if slow:
		dyno.window = int(dyno.window) - 1
	elif not dyno.window_used and not (dyno.reach as Array).is_empty():
		for hand in dyno.aim:
			var key: String = dyno.aim[hand]
			if key != dyno.reach[0]:
				continue  # 느린 화면은 표시한 가장 높은 홀드(굵은 고리)에 손이 닿을 때
			var hw := float(route.slots[key].hand_area.half_width) if route.slots[key].has("hand_area") else 0.13
			var win := lerpf(Tuning.DYNO_WINDOW_MIN, Tuning.DYNO_WINDOW_MAX, clampf((hw - 0.03) / 0.10, 0.0, 1.0))
			dyno.window_ticks = maxi(1, roundi(win * Tuning.TICK_HZ))
			dyno.window = dyno.window_ticks
			dyno.window_used = true
			break
	if not slow and body.vel.y < 0.0 and body.pos.y < float(dyno.start_y) - Tuning.DYNO_MISS_DROP:
		dyno = {}
		_start_fall("DYNO_MISS")
		return "fall:DYNO_MISS"
	return ""


## 손 패드를 눌렀을 때 그 손이 잡는다(2026-11-18 사용자: "누른 버튼의 손으로"). 날아가는 중: 그 손이 겨눈 홀드, 없으면 그 어깨에서
## 팔 길이 + DYNO_CATCH_SLACK 안의 가장 높은 표시 홀드(다른 손이 잡은 것 제외). 잡으면 두 발은 닿는 홀드를 딛고, 날던 방향으로
## 몸이 흔들리다 멈춘다(hang 동안 골반 목표를 흔든다). hang 중(두 번째 손)이면 지금 몸에서 닿는 가장 가까운 손홀드. 없으면 false.
func _dyno_catch(hand: StringName) -> bool:
	if limbs[hand].state in ["Attached", "Armed"]:
		return false
	var key := ""
	if dyno.phase == "flight":
		key = dyno.aim.get(hand, "")
		if key.is_empty():
			var sh := PoseSolver.joint_position(body.pos, body.angle, hand, body.yaw)
			var lim := PoseSolver.reach_of(hand).y * Tuning.DYNO_REACH + Tuning.DYNO_CATCH_SLACK
			for k in dyno.reach:
				if not _held_keys().has(k) and sh.distance_to(route.slot_pos(k)) <= lim:
					key = k
					break
	else:
		# 두 번째 손: 뛰며 표시한 홀드 중 팔 길이 + 여유 안의 가장 높은 것(모자라면 몸을 그만큼 끌어올림),
		# 없으면 지금 닿는 손홀드 중 가장 높은 것
		var sh := PoseSolver.joint_position(body.pos, body.angle, hand, body.yaw)
		var arm := PoseSolver.reach_of(hand).y * Tuning.DYNO_REACH
		for k in dyno.get("reach", []):
			var kp := route.slot_pos(k)
			if not _held_keys().has(k) and sh.distance_to(kp) <= arm + Tuning.DYNO_CATCH_SLACK:
				key = k
				if sh.distance_to(kp) > arm:
					var pull: Vector2 = (kp - sh) - (kp - sh).normalized() * arm
					body.pos += pull
					if dyno.has("anchor"):
						dyno.anchor = (dyno.anchor as Vector2) + pull
				break
		if key.is_empty():
			key = _highest_reachable_hand(hand)
	if key.is_empty():
		return false
	var point := route.slot_pos(key)
	if dyno.phase == "flight":
		var v := body.vel
		var sh2 := PoseSolver.joint_position(body.pos, body.angle, hand, body.yaw)
		var arm := PoseSolver.reach_of(hand).y * Tuning.DYNO_REACH
		if sh2.distance_to(point) > arm:  # 여유로 잡은 경우: 팔이 닿게 몸을 끌어당긴다
			body.pos += (point - sh2) - (point - sh2).normalized() * arm
		body.vel = Vector2.ZERO
		_dyno_place_limbs()
		_dyno_attach(hand, key, point)
		for foot in [PoseSolver.LF, PoseSolver.RF]:
			var f := _nearest_reachable(foot, _held_keys(), false)
			if not f.is_empty():
				_dyno_attach(foot, f, route.slot_pos(f))
		var amp := clampf(v.x * Tuning.DYNO_SWAY, -0.15, 0.15) + 0.05 * PoseSolver.side_sign(hand)
		dyno = {"phase": "hang", "ticks": Tuning.DYNO_HANG_TICKS, "anchor": body.pos, "amp": amp, "t": 0.0, "reach": dyno.reach}
		_dyno_relief = Tuning.DYNO_RELIEF_TICKS
	else:
		_dyno_attach(hand, key, point)
	return true


func _dyno_attach(limb: StringName, key: String, point: Vector2) -> void:
	var contact := GripCheck.contact_for_pose(key, route.slots, limb, point, body.pos, body.angle, body.yaw, attached(), _contact_meta(), _endpoints(), forbid.has(&"grip_auto"))
	_attach(limb, key, point, contact)
	_log_event({"type": "dyno_catch", "limb": limb, "key": key})


## 지금 몸에서 hand가 닿는(can_reach) 손홀드·정상 중 가장 높은 것(잡힌 것 제외). 없으면 "".
func _highest_reachable_hand(hand: StringName) -> String:
	var best := ""
	var best_y := -INF
	for key in route.slots:
		var slot: Dictionary = route.slots[key]
		if _held_keys().has(key) or (not slot.has("hand_area") and not route.goal_slots.has(key)):
			continue
		var p := route.slot_pos(key)
		if p.y > best_y and PoseSolver.can_reach(body.pos, body.angle, hand, p, body.yaw):
			best = key
			best_y = p.y
	return best


func _held_keys() -> Dictionary:
	var out := {}
	for limb in attached():
		out[limbs[limb].key] = true
	return out


## limb이 지금 몸에서 닿는(PoseSolver.can_reach) 가장 가까운 슬롯. 손은 손홀드·정상만, 발은 정상이 아닌 모든 홀드(docs/38) 중
## 고관절보다 0.05m 넘게 낮은 것. used의 슬롯은 건너뛴다.
func _nearest_reachable(limb: StringName, used: Dictionary, hand: bool) -> String:
	var joint := PoseSolver.joint_position(body.pos, body.angle, limb, body.yaw)
	var best := ""
	var best_d := INF
	for key in route.slots:
		if used.has(key):
			continue
		var slot: Dictionary = route.slots[key]
		var goal := route.goal_slots.has(key)
		if hand and not slot.has("hand_area") and not goal:
			continue
		var p := route.slot_pos(key)
		if not hand and (goal or p.y > joint.y - 0.05):
			continue
		if not PoseSolver.can_reach(body.pos, body.angle, limb, p, body.yaw):
			continue
		var d := (limbs[limb].pos as Vector2).distance_to(p)
		if d < best_d:
			best = key
			best_d = d
	return best
