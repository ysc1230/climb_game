class_name TutorialRunner
extends RefCounted
## 튜토리얼 실행기(docs/28 §6.1·§8.1). RouteDef.tutorial_steps를 한 단계씩 진행한다.
## 단계: {step_id, text_ko, start_pose?, goal_event, help_ko: [1단계, 2단계], rules?: {fatigue_drain, start_stamina, techniques}}.
## 세션 틱마다 observe()를 한 번 부르고, "next"/"restart"를 받으면 begin_step()으로 그 단계를 (다시) 시작한다.
## 이벤트는 technique_log의 seq > 마지막으로 본 seq만 본다(Ruling D). 판정 수치는 바꾸지 않는다.

const HELP_SECONDS := 12.0      # 이만큼 진행이 없으면 도움말 한 단계 올림(16과 같음)
const HELP_FAILS := 3           # 같은 단계 실패 횟수
const TOGETHER_GRAB_SECONDS := 2.0  # together: 첫 놓기 뒤 모두 잡아야 하는 시간(16 T03)
const _EPS := 0.000001

var route: RouteDef
var steps: Array = []
var index := 0
var done := false

var _last_seq := 0
var _step_pose := {}        # 지금 단계의 시작 자세(실패 시 돌아갈 곳)
var _restart := false       # 다음 begin_step은 같은 단계 재시작
var _help := 0
var _help_since := 0.0
var _help_fails := 0
# hold_still
var _still := 0.0
# together
var _tg_run := 0
var _tg_ready := false
var _tg_window := false
var _tg_elapsed := 0.0
var _tg_grabbed := {}


func _init(p_route: RouteDef) -> void:
	route = p_route
	steps = route.tutorial_steps
	done = steps.is_empty()


func current() -> Dictionary:
	return steps[index] if index < steps.size() else {}


## 지금 단계를 시작한다. start_pose가 있으면 그 자세로, 재시작이면 그 단계 시작 자세로,
## 첫 단계·추락 뒤(추락 목표 완료 포함)면 문제 시작 자세로 놓는다. 그 밖에는 지금 자세를 이어 쓴다.
## 그 뒤 단계 규칙(피로 감소·시작 체력)을 적용한다.
func begin_step(session: ClimbSession) -> void:
	if done:
		return
	var step := current()
	var pose := {}
	if step.has("start_pose"):
		pose = step.start_pose
	elif _restart and not _step_pose.is_empty():
		pose = _step_pose
	elif index == 0 or session.falling or _restart:
		pose = _route_pose()
	if pose.is_empty():
		_step_pose = _capture(session)
	else:
		session.reset_to(pose)
		_step_pose = pose
	_restart = false
	var r: Dictionary = step.get("rules", {})
	session.rules.fatigue_disabled = not bool(r.get("fatigue_drain", true))
	if r.has("start_stamina"):
		for hand in [PoseSolver.LH, PoseSolver.RH]:
			session.rules.stamina[hand] = float(r.start_stamina)
	_last_seq = session.event_seq
	_reset_goal_state()


## 지금 단계에서 보이는 기술 버튼(rules.techniques). 없으면 빈 배열.
func allowed_buttons() -> Array[StringName]:
	var out: Array[StringName] = []
	for t in current().get("rules", {}).get("techniques", []):
		out.append(StringName(t))
	return out


## 세션 틱마다 한 번. 반환: "" / "next"(다음 단계, begin_step 필요) / "done"(마지막 단계 완료) / "restart"(같은 단계 다시, begin_step 필요).
func observe(session: ClimbSession, step_result: String, dt: float) -> String:
	if done:
		return ""
	var goal: Dictionary = current().get("goal_event", {})
	var events: Array = []
	for ev in session.technique_log:
		if int(ev.seq) > _last_seq:
			events.append(ev)
	_last_seq = session.event_seq
	var fell := step_result.begins_with("fall:")
	var hit := false
	var failed := false
	match str(goal.get("type", "")):
		"clear":
			hit = step_result == "clear"
		"fall":
			hit = fell or events.any(func(e): return matches(goal, e))
		"hold_still":
			hit = _observe_still(session, fell, float(goal.get("seconds", 1.0)), dt)
		"together":
			var r := _observe_together(session, goal, events, dt)
			hit = r == 1
			failed = r == -1
		_:
			hit = events.any(func(e): return matches(goal, e))
	if hit:
		return _advance()
	_help_since += dt
	if fell or failed:
		_help_fails += 1
		_restart = true
		_reset_goal_state()
		_bump_help()
		return "restart"
	if _help_since >= HELP_SECONDS - _EPS:
		_bump_help()
	return ""


## 도움말 단계: 0 없음, 1 "움직일 팔다리", 2 "누를 버튼과 홀드"(help_ko[0], help_ko[1]).
func help_level() -> int:
	return _help


## 지금 도움말 문구(없으면 "").
func help_text() -> String:
	var h: Array = current().get("help_ko", [])
	return str(h[_help - 1]) if _help > 0 and _help <= h.size() else ""


## goal의 type 외 키가 ev에 같은 값으로 있으면 일치. type "technique"는 기술 실행기 성공 이벤트,
## 키 "slot"은 이벤트의 "key"와 비교한다(8.1 goal_event 예시 형식).
static func matches(goal: Dictionary, ev: Dictionary) -> bool:
	var gt := str(goal.get("type", ""))
	var et := str(ev.get("type", ""))
	if gt == "technique":
		if et != String(TechniqueRunner.SUCCEEDED):
			return false
	elif gt != et:
		return false
	for k in goal:
		if str(k) == "type":
			continue
		var ek := "key" if str(k) == "slot" else str(k)
		if not ev.has(ek) or not _same(goal[k], ev[ek]):
			return false
	return true


static func _same(a, b) -> bool:
	var sa := typeof(a) in [TYPE_STRING, TYPE_STRING_NAME]
	var sb := typeof(b) in [TYPE_STRING, TYPE_STRING_NAME]
	if sa or sb:
		return sa and sb and String(a) == String(b)
	var na := typeof(a) in [TYPE_INT, TYPE_FLOAT]
	var nb := typeof(b) in [TYPE_INT, TYPE_FLOAT]
	if na or nb:
		return na and nb and is_equal_approx(float(a), float(b))
	return typeof(a) == typeof(b) and a == b


func _advance() -> String:
	index += 1
	_help = 0
	_help_since = 0.0
	_help_fails = 0
	_restart = false
	_reset_goal_state()
	if index >= steps.size():
		done = true
		return "done"
	return "next"


func _bump_help() -> void:
	if _help_fails >= HELP_FAILS or _help_since >= HELP_SECONDS - _EPS:
		_help = mini(_help + 1, 2)
		_help_since = 0.0
		_help_fails = 0


func _reset_goal_state() -> void:
	_still = 0.0
	_tg_run = 0
	_tg_ready = false
	_tg_window = false
	_tg_elapsed = 0.0
	_tg_grabbed = {}


## hold_still: 끌거나 눌러 둔 팔다리가 없고 떨어지지 않은 채 seconds 동안 이어지면 true.
func _observe_still(session: ClimbSession, fell: bool, seconds: float, dt: float) -> bool:
	var busy := fell or session.falling or session.selecting or not session.deadpoint.is_empty()
	for limb in session.limbs:
		if session.limbs[limb].state in ["Dragging", "Armed", "Deadpoint"]:
			busy = true
	if busy:
		_still = 0.0
		return false
	_still += dt
	return _still >= seconds - _EPS


## together: 지정 팔다리가 모두 ticks틱 이상 함께 Dragging이고, 그중 첫 놓기 뒤 2초 안에 모두 grab하면 1.
## 2초 안에 다 잡지 못하면 -1(실패, 그 단계 다시), 아직이면 0.
func _observe_together(session: ClimbSession, goal: Dictionary, events: Array, dt: float) -> int:
	var want: Array = []
	for l in goal.get("limbs", []):
		want.append(StringName(l))
	if want.is_empty():
		return 0
	var all_drag := true
	for l in want:
		if session.limbs[l].state != "Dragging":
			all_drag = false
	if not _tg_ready:
		_tg_run = _tg_run + 1 if all_drag else 0
		if _tg_run >= int(goal.get("ticks", 6)):
			_tg_ready = true
		return 0
	if not _tg_window:
		if all_drag:
			return 0
		_tg_window = true
		_tg_elapsed = 0.0
		_tg_grabbed = {}
	for e in events:
		if str(e.type) == "grab" and StringName(e.get("limb", &"")) in want:
			_tg_grabbed[StringName(e.limb)] = true
	if _tg_grabbed.size() >= want.size():
		return 1
	_tg_elapsed += dt
	if _tg_elapsed > TOGETHER_GRAB_SECONDS + _EPS:
		return -1
	return 0


func _route_pose() -> Dictionary:
	var slots := {}
	for limb in route.start_slots:
		slots[limb] = route.start_slots[limb]
	return {"pelvis": route.start_pelvis, "angle": route.start_angle, "slots": slots}


## 지금 자세(붙은 팔다리·골반·체력)를 reset_to 형식으로.
func _capture(session: ClimbSession) -> Dictionary:
	var slots := {}
	for limb in session.limbs:
		var l: Dictionary = session.limbs[limb]
		if l.state in ["Attached", "Armed"]:
			slots[limb] = l.key
	return {"pelvis": session.body.pos, "angle": session.body.angle, "slots": slots,
		"stamina": {PoseSolver.LH: session.rules.stamina[PoseSolver.LH], PoseSolver.RH: session.rules.stamina[PoseSolver.RH]}}
