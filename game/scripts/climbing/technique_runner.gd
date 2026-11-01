class_name TechniqueRunner
extends RefCounted
## 기술 실행기(docs/27 §6 4·5단계, §10, §11). 한 번에 하나의 기술만 실행한다. 노드 의존 없음.
## 세션의 step()이 rules.tick 전에 tick(session)을 부른다. 손발 이동은 세션의 Dragging 경로(req = 목표점)를 쓰고
## 체중 이동(Shift)은 세션의 의도 비용(intents)이 맡는다. 도착하면 session.grab으로 기술의 접점 정보와 함께 붙인다.
## 실행할 수 있는 것은 버튼 기술(TechniqueDefs.button_ids: 아웃사이드 엣지·드롭니)뿐이다(docs/28 §4).
## 이벤트: {type: started/succeeded/cancelled/failed, id, side, key, quality, reason}. tick이 한 틱에 하나씩 돌려준다.

const STARTED := &"started"
const SUCCEEDED := &"succeeded"
const CANCELLED := &"cancelled"
const FAILED := &"failed"
## 버튼 기술이 아닌 ID로 시작하려 할 때의 이유(패드 기술은 패드로 한다).
const NOT_BUTTON := &"NOT_BUTTON"

const MOVE_BUDGET_TICKS := 90      # 27 §11: 체중 이동 후 도달은 1.5초까지
const ARRIVE_EPSILON := 0.02       # 말단이 목표점에 이만큼 가까우면 붙인다

## {id, side, limb, key, point, step, ticks, ...}. 비면 실행 없음.
## step: check(첫 틱 재검사) → move(아웃사이드 엣지: 발 이동) → yaw(드롭니·아웃사이드 엣지: 취소될 때까지 ψ 유지, 들어설 때 succeeded)
var active := {}
var _events: Array = []


## 기술을 시작한다. 성공 &"", 실패면 이유 ID. 판단은 지금 세션의 스냅숏으로 다시 한다(선택 중 상태 불변, 27 §11).
## 홀드를 쓰는 기술은 key가 필요하다(홀드 자동 선택 없음, TA12). point는 탭 지점(INF면 홀드 중심).
func start(session: ClimbSession, tech_id: StringName, side: StringName, key: String = "", point: Vector2 = Vector2.INF) -> StringName:
	if not TechniqueDefs.button_ids().has(tech_id):
		return NOT_BUTTON
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
		"step": &"check", "ticks": 0, "needs_shift": false}
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
	active = a
	return &""


## 실행 중 기술이 이 팔다리를 쓰는가(그 패드를 누르면 취소, 27 §6 5).
func uses(limb: StringName) -> bool:
	return not active.is_empty() and active.limb == limb


## 한 틱 진행. 이번 틱 이벤트(없으면 {}).
func tick(session: ClimbSession) -> Dictionary:
	if not active.is_empty():
		match active.step:
			&"check":
				_check_and_begin(session)
			&"move":
				_tick_move(session)
			&"yaw":
				_tick_yaw(session)
	return _events.pop_front() if not _events.is_empty() else {}


func cancel(session: ClimbSession, reason: StringName = &"cancelled") -> void:
	if active.is_empty():
		return
	_end(session, CANCELLED, reason)


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
	if a.id == TechniqueJudge.T_DROP_KNEE:
		# 이미 딛은 발: 접점 edge를 drop_knee로, ψ 목표를 그 발 쪽 엉덩이를 벽으로(27 §10)
		var c: ContactInfo = session.limbs[a.limb].contact
		c.edge = &"drop_knee"
		_begin_yaw(session)
		return
	# 아웃사이드 엣지: 발을 놓는 동안 엉덩이 정면으로
	session.rules.yaw_target = NAN
	var l: Dictionary = session.limbs[a.limb]
	l.state = "Dragging"
	l.contact = null
	l.cand = {}
	l.req = a.point
	a.last_d = INF
	a.step = &"move"


## 발을 목표점으로 옮긴다. 닿으면 붙이고 yaw 단계로, 1.5초 안에 못 닿으면 실패.
func _tick_move(session: ClimbSession) -> void:
	var a := active
	a.ticks += 1
	var l: Dictionary = session.limbs[a.limb]
	if l.state != "Dragging":
		_end(session, CANCELLED, &"cancelled")
		return
	l.req = a.point
	if _target_taken(session):
		l.state = "Free"
		_end(session, FAILED, GripCheck.OCCUPIED)
		return
	var d: float = (l.pos as Vector2).distance_to(a.point)
	var progressed: bool = d < float(a.last_d) - 0.0005
	a.last_d = d
	if d <= GripCheck.radius_of(a.limb) and (d <= ARRIVE_EPSILON or not progressed) and _attach(session):
		_begin_yaw(session)  # 발이 붙은 뒤 ψ 목표(접점 edge는 contact_for가 outside로 기록)
		return
	if a.ticks >= MOVE_BUDGET_TICKS:
		l.state = "Free"
		_end(session, FAILED, TechniqueJudge.NEED_WEIGHT_SHIFT if a.needs_shift else TechniqueJudge.JOINT_LIMIT)


## 이동 중 다른 팔다리가 목표 자리를 차지했는가(패드 조작 등).
func _target_taken(session: ClimbSession) -> bool:
	var a := active
	var entries: Array = session.occupied().get(a.key, [])
	var c := GripCheck.contact_point(session.route.slots[a.key], a.limb, a.point, entries, INF)
	return c.is_empty() or (c.point as Vector2).distance_to(a.point) > 0.001


## yaw 단계 시작: ψ 목표를 정하고 힘 균형 게이트를 켠다. 기술은 취소될 때까지 유지된다.
## 유지 자세에 들어선 이 순간 succeeded를 한 번 남긴다(튜토리얼 technique 목표, 28 §8.1). 끝날 때의 cancelled/failed는 그대로다.
func _begin_yaw(session: ClimbSession) -> void:
	var a := active
	session.rules.yaw_target = TechniqueJudge.yaw_for(a.id, a.limb)
	session.rules.yaw_guard = true
	a.step = &"yaw"
	a.ticks = 0
	_push(session, SUCCEEDED, &"")


## yaw 유지: 다른 패드 조작에는 영향받지 않는다. 그 발이 붙어 있지 않게 되면(슬립·떼기) 중립으로 복귀하며 취소.
func _tick_yaw(session: ClimbSession) -> void:
	var a := active
	a.ticks += 1
	if not session.attached().has(a.limb):
		_end(session, CANCELLED, &"cancelled")


## 도착한 발을 붙인다.
func _attach(session: ClimbSession) -> bool:
	var a := active
	var body := session.body
	var att := session.attached()
	att[a.limb] = a.point
	if not PoseSolver.can_reach(body.pos, body.angle, a.limb, a.point, body.yaw) or not PoseSolver.is_valid(body.pos, body.angle, att, body.yaw):
		return false
	return session.grab(a.limb, a.key, a.point, TechniqueJudge.contact_for(session.route, a.id, a.limb, a.key, a.point))


# ---------- 이벤트 ----------

func _push(_session: ClimbSession, type: StringName, reason: StringName) -> void:
	var a := active
	_events.append({"type": type, "id": a.id, "side": a.side, "key": a.key, "quality": a.quality, "reason": reason})


func _end(session: ClimbSession, type: StringName, reason: StringName) -> void:
	_push(session, type, reason)
	if type == CANCELLED and active.step == &"move":
		# 취소돼도 이동 중이던 발이 Dragging(터치 없음)으로 남지 않게 한다
		var ml: Dictionary = session.limbs[active.limb]
		if ml.state == "Dragging":
			ml.state = "Free"
			ml.cand = {}
			ml.req = ml.pos
	# ψ 복귀(목표 NAN), 아직 딛고 있다면 접점 edge를 inside로 되돌린다
	session.rules.yaw_target = NAN
	session.rules.yaw_guard = false
	var c = session.limbs[active.limb].contact
	if c != null and (c.edge == &"drop_knee" or c.edge == &"outside"):
		c.edge = &"inside"
	active = {}
