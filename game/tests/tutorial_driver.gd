extends RefCounted
## 테스트 공용: 튜토리얼 루트를 실제 세션(ClimbSession)과 TutorialRunner로 돌리며 패드 입력을 넣는다.
## test_ 로 시작하지 않으므로 실행기가 따로 돌리지 않는다. 사용: const TutorialDriver := preload("res://tests/tutorial_driver.gd")

const DT := Tuning.DT
const DRAG_SPEED := 2.5

var s: ClimbSession
var t: TutorialRunner
var results: Array = []
var labels: Array = []  # 이번 단계의 move 이벤트 라벨
var restarts := 0       # observe가 돌려준 "restart" 수(누적)
var ticks := 0          # 세션 틱 수(누적, 추락 연출 대기 포함)
var fb := DangerFeedback.new()  # play_test와 같은 경고 상태(튜토리얼 화면 사건 목표용)
var visited: Array = []  # 시작한 단계 ID 순서


## level: "beginner"면 play_test처럼 버틸 시간 10배.
func _init(route: RouteDef, level := "intermediate") -> void:
	s = ClimbSession.new(route)
	if level == "beginner":
		s.rules.imbalance_budget = ClimbRules.IMBALANCE_BUDGET_TICKS * ClimbRules.BEGINNER_BUDGET_MULT
		s.rules.grace_budget = Tuning.UNSUPPORTED_GRACE_TICKS * ClimbRules.BEGINNER_BUDGET_MULT
	t = TutorialRunner.new(route)
	t.set_level(level)
	_begin()


func _begin() -> void:
	if t.done:
		return
	t.begin_step(s)
	fb.reset()
	visited.append(str(t.current().step_id))


## 한 틱 + 튜토리얼 관찰. play_test._tutorial_tick처럼 추락으로 끝난 단계는 추락 연출(respawn)까지 기다렸다 다음 단계를 시작한다.
func tick() -> String:
	var seq := s.event_seq
	var r := s.step()
	ticks += 1
	fb.observe_session(s, DT, true)
	for ev in fb.tutorial_events():
		t.note(ev)
	for ev in s.technique_log:
		if int(ev.seq) > seq and ev.type == "move":
			labels.append(ev.label)
	var act := t.observe(s, r, DT)
	if act == "":
		return ""
	results.append(act)
	if act == "restart":
		restarts += 1
	if act in ["next", "restart"]:
		if r.begins_with("fall:"):
			for i in 120:
				ticks += 1
				if s.step() == "respawn":
					break
		_begin()
	return act


## 패드를 누르기만 한다(붙은 손발 → Armed).
func arm(limb: StringName) -> void:
	s.apply_input([{"type": "arm", "limb": limb}])


## 패드 사이 가운데를 누르고 delta만큼 끈다(놓지 않음 — 다른 손가락으로 손발을 끌 때 몸통 목표 유지). frames 틱에 나눠 끈다.
func body_drag(delta: Vector2, frames := 40) -> void:
	s.apply_input([{"type": "body_start"}])
	for i in frames:
		s.apply_input([{"type": "body_move", "delta": delta / frames}])
		if tick() != "":
			return


## 초급 자동 도움(play_test._rescue)과 같은 결과: AutoRescue 계획대로 자세를 확정하고 튜토리얼에 알린다.
func rescue() -> bool:
	var plan := AutoRescue.plan(s)
	if plan.is_empty():
		return false
	s.reset_to({"pelvis": [plan.pelvis.x, plan.pelvis.y], "angle": plan.angle, "slots": plan.slots, "stamina": s.rules.stamina.duplicate()})
	fb.reset()
	t.note({"type": "rescue"})
	return true


## 아무 입력 없이 결과가 나올 때까지(최대 max_ticks) 틱을 돌린다. 돌린 틱 수를 돌려준다.
func wait(max_ticks: int) -> int:
	for i in max_ticks:
		if tick() != "":
			return i + 1
	return max_ticks


## 떼어 끌고 허공(target)까지 옮긴 뒤 그 자리에서 놓는다(잡을 후보가 없어야 함). 결과가 나오면 멈춘다.
func drag_to_air(limb: StringName, target: Vector2) -> bool:
	s.apply_input([{"type": "detach", "limb": limb}])
	for i in 300:
		var req: Vector2 = s.limbs[limb].req
		s.apply_input([{"type": "move", "limb": limb, "delta": (target - req).limit_length(DRAG_SPEED * DT)}])
		var act := tick()
		if act != "":
			return true
		if s.limbs[limb].req.distance_to(target) < 0.01 or i >= 30 and s.limbs[limb].req.distance_to(req) < 0.0005:
			break
	if not s.limbs[limb].cand.is_empty():
		return false
	s.apply_input([{"type": "release", "limb": limb, "speed": 0.0}])
	return true


## 떼어 끌고, 후보가 그 키가 되면 홀드 가운데까지(팔이 더 못 가면 거기서) 가져가 놓는다(SessionBot과 같음). 결과가 나오면 멈춘다.
func drag(limb: StringName, key: String) -> bool:
	s.apply_input([{"type": "detach", "limb": limb}])
	for i in 300:
		var req: Vector2 = s.limbs[limb].req
		s.apply_input([{"type": "move", "limb": limb, "delta": (s.route.slot_pos(key) - req).limit_length(DRAG_SPEED * DT)}])
		var act := tick()
		var now: Vector2 = s.limbs[limb].req
		var settled := now.distance_to(s.route.slot_pos(key)) < 0.03 or now.distance_to(req) < 0.0005
		if s.limbs[limb].cand.get("key", "") == key and settled:
			s.apply_input([{"type": "release", "limb": limb, "speed": 0.0}])
			return true
		if act != "":
			return true
	return false
