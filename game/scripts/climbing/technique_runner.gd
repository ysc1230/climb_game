class_name TechniqueRunner
extends RefCounted
## 기술 실행기(docs/27 §6 4·5단계, §10, §11). 한 번에 하나의 기술만 실행한다. 노드 의존 없음.
## 세션의 step()이 rules.tick 전에 tick(session)을 부른다. 손발 이동은 세션의 Dragging 경로(req = 목표점)를 쓰고
## 체중 이동(Shift)은 세션의 의도 비용(intents)이 맡는다. 도착하면 session.grab으로 기술의 접점 정보와 함께 붙인다.
## 이벤트: {type: started/succeeded/cancelled/failed, id, side, key, quality, reason}. tick이 한 틱에 하나씩 돌려준다.

const STARTED := &"started"
const SUCCEEDED := &"succeeded"
const CANCELLED := &"cancelled"
const FAILED := &"failed"

const MOVE_BUDGET_TICKS := 90      # 27 §11: 체중 이동 후 도달은 1.5초까지
const ARRIVE_EPSILON := 0.02       # 말단이 목표점에 이만큼 가까우면 붙인다
const STAND_MIN_TICKS := 30        # 하이스텝 일어서기 0.5~1초(27 §10)
const STAND_MAX_TICKS := 60
const STAND_STOP_SPEED := 0.03     # 골반 속도가 이보다 작으면 "이동 정지"
const LOCK_OFF_FATIGUE := 1.5

## {id, side, limb, key, point, step, ticks, ...}. 비면 실행 없음.
## step: check(첫 틱 재검사) → move(손발 이동) → stand_up(하이스텝) / hold(록오프·휴식) / yaw(드롭니·아웃사이드 엣지: 취소될 때까지 ψ 유지)
var active := {}
var _events: Array = []


## 기술을 시작한다. 성공 &"", 실패면 이유 ID. 판단은 지금 세션의 스냅숏으로 다시 한다(선택 중 상태 불변, 27 §11).
## 홀드를 쓰는 기술은 key가 필요하다(홀드 자동 선택 없음, TA12). point는 탭 지점(INF면 홀드 중심).
func start(session: ClimbSession, tech_id: StringName, side: StringName, key: String = "", point: Vector2 = Vector2.INF) -> StringName:
	if not active.is_empty():
		return TechniqueJudge.WRONG_PHASE
	var snap := ClimbSnapshot.from_session(session)
	var j := TechniqueJudge.judge(snap, tech_id)
	if not j.has(side):
		return TechniqueJudge.WRONG_PHASE
	if not j[side].available:
		return j[side].reason
	var limb := TechniqueJudge.limb_for(tech_id, side)
	var a := {"id": tech_id, "side": side, "limb": limb, "key": "", "point": Vector2.INF, "quality": NAN,
		"step": &"check", "ticks": 0, "needs_shift": false, "limbs": [limb] if limb != &"" else []}
	if TechniqueJudge.uses_hold(tech_id):
		if key.is_empty():
			return TechniqueJudge.NO_HOLD
		var c := TechniqueJudge.check_hold(snap, tech_id, side, key, point)
		if not c.ok:
			return c.reason
		a.key = key
		a.point = c.point
		a.quality = c.quality
		a.needs_shift = c.needs_shift
		if tech_id == TechniqueJudge.T_MATCH:
			a.other_point = c.other_point
		if tech_id in [TechniqueJudge.T_MATCH, TechniqueJudge.T_FOOT_SWAP]:
			a.limbs.append(TechniqueJudge.other_of(limb))
	if TechniqueJudge.is_flag(tech_id):
		var plan := TechniqueJudge.flag_plan(snap, tech_id, limb)
		if plan.is_empty():
			return TechniqueJudge.LIMB_STATE
		a.point = plan.point
	active = a
	return &""


## 실행 중 기술이 이 팔다리를 쓰는가(그 패드를 누르면 취소, 27 §6 5).
func uses(limb: StringName) -> bool:
	return not active.is_empty() and active.limbs.has(limb)


## 한 틱 진행. 이번 틱 이벤트(없으면 {}).
func tick(session: ClimbSession) -> Dictionary:
	if not active.is_empty():
		match active.step:
			&"check":
				_check_and_begin(session)
			&"move":
				_tick_move(session)
			&"stand_up":
				_tick_stand(session)
			&"hold":
				_tick_hold(session)
			&"yaw":
				_tick_yaw(session)
			&"deadpoint":
				_tick_deadpoint(session)
	return _events.pop_front() if not _events.is_empty() else {}


func cancel(session: ClimbSession, reason: StringName = &"cancelled") -> void:
	if active.is_empty():
		return
	_end(session, CANCELLED, reason)


## 실행 중 기술을 실패로 끝낸다(세션이 판정한 실패 이유를 기록).
func fail(session: ClimbSession, reason: StringName) -> void:
	if not active.is_empty():
		_end(session, FAILED, reason)


## 끝 조건이 "패드 조작"인 기술(휴식)을 정상 종료한다.
func finish(session: ClimbSession) -> void:
	if not active.is_empty():
		_end(session, SUCCEEDED, &"")


# ---------- 단계 ----------

## 실행 첫 틱: 같은 판단을 한 번 더 해 수치 오류만 걸러 낸다(27 §11).
func _check_and_begin(session: ClimbSession) -> void:
	var a := active
	var snap := ClimbSnapshot.from_session(session)
	snap.executing = false
	var j := TechniqueJudge.judge_side(snap, a.id, a.side)
	if not j.available:
		_end(session, FAILED, j.reason)
		return
	if TechniqueJudge.uses_hold(a.id):
		var c := TechniqueJudge.check_hold(snap, a.id, a.side, a.key, a.point)
		if not c.ok:
			_end(session, FAILED, c.reason)
			return
	_push(session, STARTED, &"")
	var rules := session.rules
	match a.id:
		TechniqueJudge.T_REST:
			rules.profile_override = {PoseSolver.LH: Tuning.PREF_ARM_REST, PoseSolver.RH: Tuning.PREF_ARM_REST,
				PoseSolver.LF: Tuning.PREF_LEG_STAND, PoseSolver.RF: Tuning.PREF_LEG_STAND}
			a.step = &"hold"
		TechniqueJudge.T_LOCK_OFF:
			rules.profile_override = {a.limb: TechniqueJudge.LOCK_OFF_PREF}
			rules.fatigue_multiplier = {a.limb: LOCK_OFF_FATIGUE}
			a.other_released = not session.attached().has(TechniqueJudge.other_of(a.limb))
			a.step = &"hold"
		TechniqueJudge.T_DEADPOINT:
			# 손을 떼어 날린다. 이동·받기 판정은 세션이 한다(패드 경로와 같은 로직)
			session.start_deadpoint(a.limb, a.key, a.point, TechniqueJudge.deadpoint_bonus(snap.body.vel.y, 1.0))
			a.step = &"deadpoint"
			a.ticks = 0
		TechniqueJudge.T_DROP_KNEE:
			# 이미 딛은 발: 접점 edge를 drop_knee로, ψ 목표를 그 발 쪽 엉덩이를 벽으로(27 §10)
			var c: ContactInfo = session.limbs[a.limb].contact
			c.edge = &"drop_knee"
			_begin_yaw(session)
		_:
			if a.id in [TechniqueJudge.T_INSIDE_EDGE, TechniqueJudge.T_HIGH_STEP, TechniqueJudge.T_OUTSIDE_EDGE]:
				rules.yaw_target = NAN  # 엉덩이 정면으로
			var l: Dictionary = session.limbs[a.limb]
			l.state = "Dragging"
			l.contact = null
			l.cand = {}
			l.req = a.point
			a.last_d = INF
			a.step = &"move"


## 손발을 목표점으로 옮긴다. 닿으면 붙이고, 1.5초 안에 못 닿으면 실패.
func _tick_move(session: ClimbSession) -> void:
	var a := active
	a.ticks += 1
	var l: Dictionary = session.limbs[a.limb]
	if l.state != "Dragging":
		_end(session, CANCELLED, &"cancelled")
		return
	l.req = a.point
	var d: float = (l.pos as Vector2).distance_to(a.point)
	var progressed: bool = d < float(a.last_d) - 0.0005
	a.last_d = d
	if TechniqueJudge.is_flag(a.id):
		# 플래그: 붙이지 않고 그 자리에 "Flag"로 둔다. 이후 그 발 패드를 누르면 기존 동작으로 끝난다
		if d <= ARRIVE_EPSILON or (not progressed and d <= GripCheck.radius_of(a.limb)):
			l.state = "Flag"
			l.flag = l.pos
			l.flag_depth = TechniqueJudge.flag_depth(a.id)
			_end(session, SUCCEEDED, &"")
			return
	elif d <= GripCheck.radius_of(a.limb) and (d <= ARRIVE_EPSILON or not progressed) and _attach(session):
		if a.id == TechniqueJudge.T_OUTSIDE_EDGE:
			_begin_yaw(session)  # 발이 붙은 뒤 ψ 목표(접점 edge는 contact_for가 outside로 기록)
		elif a.id == TechniqueJudge.T_HIGH_STEP:
			# 일어서기: 골반을 올린 발 위로, 다리 선호 0.86
			session.rules.profile_override = {a.limb: Tuning.PREF_LEG_STAND, TechniqueJudge.other_of(a.limb): Tuning.PREF_LEG_STAND, &"_stand_x": (a.point as Vector2).x}
			a.step = &"stand_up"
			a.ticks = 0
		else:
			_end(session, SUCCEEDED, &"")
		return
	if a.ticks >= MOVE_BUDGET_TICKS:
		l.state = "Free"
		_end(session, FAILED, TechniqueJudge.NEED_WEIGHT_SHIFT if a.needs_shift else TechniqueJudge.JOINT_LIMIT)


## 데드포인트: 세션이 끝낼 때까지 기다린다. 붙었으면 성공(놓친 경우는 세션이 fail로 끝내고 추락한다).
func _tick_deadpoint(session: ClimbSession) -> void:
	var a := active
	a.ticks += 1
	if session.deadpoint.is_empty():
		# 놓친 경우는 세션이 먼저 fail()로 끝내므로 여기까지 오는 것은 성공뿐이다. CANCELLED는 방어용(도달 불가)
		_end(session, SUCCEEDED if session.attached().has(a.limb) else CANCELLED, &"")


## yaw 단계 시작: ψ 목표를 정하고 힘 균형 게이트를 켠다. 기술은 취소될 때까지 유지된다.
func _begin_yaw(session: ClimbSession) -> void:
	var a := active
	session.rules.yaw_target = TechniqueJudge.yaw_for(a.id, a.limb)
	session.rules.yaw_guard = true
	a.step = &"yaw"
	a.ticks = 0


## yaw 유지: 다른 패드 조작에는 영향받지 않는다. 그 발이 붙어 있지 않게 되면(슬립·떼기) 중립으로 복귀하며 취소.
func _tick_yaw(session: ClimbSession) -> void:
	var a := active
	a.ticks += 1
	if not session.attached().has(a.limb):
		_end(session, CANCELLED, &"cancelled")


## 도착한 손발을 붙인다. 풋스왑은 같은 틱에 반대 발을 떼고, 매치는 잡던 손을 반대쪽 절반으로 옮겨 잡는다.
func _attach(session: ClimbSession) -> bool:
	var a := active
	var body := session.body
	var other := TechniqueJudge.other_of(a.limb)
	var att := session.attached()
	att[a.limb] = a.point
	if a.id == TechniqueJudge.T_FOOT_SWAP:
		att.erase(other)
	if a.id == TechniqueJudge.T_MATCH and att.has(other):
		att[other] = a.other_point
	if not PoseSolver.can_reach(body.pos, body.angle, a.limb, a.point, body.yaw) or not PoseSolver.is_valid(body.pos, body.angle, att, body.yaw):
		return false
	if a.id == TechniqueJudge.T_FOOT_SWAP:
		var o: Dictionary = session.limbs[other]
		o.state = "Free"
		o.contact = null
	if a.id == TechniqueJudge.T_MATCH and session.attached().has(other):
		var o: Dictionary = session.limbs[other]
		var oc: ContactInfo = ClimbSnapshot.copy_contact(o.contact) if o.contact != null else GripCheck.contact_for(o.key, session.route.slots, other, a.other_point)
		oc.point = a.other_point
		oc.quality = HoldArea.project_hand(session.route.slots[o.key], a.other_point).quality
		o.grab = a.other_point
		o.pos = a.other_point
		o.contact = oc
	return session.grab(a.limb, a.key, a.point, TechniqueJudge.contact_for(session.route, a.id, a.limb, a.key, a.point))


## 하이스텝 일어서기: 최소 0.5초 뒤 골반이 멈추면, 늦어도 1초에 끝.
func _tick_stand(session: ClimbSession) -> void:
	var a := active
	a.ticks += 1
	if not session.attached().has(a.limb):
		_end(session, CANCELLED, &"cancelled")
		return
	if (a.ticks >= STAND_MIN_TICKS and session.body.vel.length() < STAND_STOP_SPEED) or a.ticks >= STAND_MAX_TICKS:
		_end(session, SUCCEEDED, &"")


## 록오프: 반대 손이 떨어졌다가 다시 잡으면 끝, 그 손이 미끄러지면 실패. 휴식: 패드 조작(finish)까지 유지.
func _tick_hold(session: ClimbSession) -> void:
	var a := active
	a.ticks += 1
	if a.id != TechniqueJudge.T_LOCK_OFF:
		return
	var att := session.attached()
	if not att.has(a.limb):
		_end(session, FAILED, TechniqueJudge.TOO_TIRED)
		return
	var other := TechniqueJudge.other_of(a.limb)
	if not att.has(other):
		a.other_released = true
	elif a.other_released:
		_end(session, SUCCEEDED, &"")


# ---------- 이벤트 ----------

func _push(_session: ClimbSession, type: StringName, reason: StringName) -> void:
	var a := active
	_events.append({"type": type, "id": a.id, "side": a.side, "key": a.key, "quality": a.quality, "reason": reason})


func _end(session: ClimbSession, type: StringName, reason: StringName) -> void:
	_push(session, type, reason)
	session.rules.profile_override = {}
	session.rules.fatigue_multiplier = {}
	if TechniqueJudge.is_yaw_tech(active.id):
		# ψ 복귀(목표 NAN), 아직 딛고 있다면 접점 edge를 inside로 되돌린다
		session.rules.yaw_target = NAN
		session.rules.yaw_guard = false
		var c = session.limbs[active.limb].contact
		if c != null and (c.edge == &"drop_knee" or c.edge == &"outside"):
			c.edge = &"inside"
	active = {}
