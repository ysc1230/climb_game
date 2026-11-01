extends RefCounted
## 테스트 공용: 튜토리얼 루트를 실제 세션(ClimbSession)과 TutorialRunner로 돌리며 패드 입력을 넣는다.
## test_ 로 시작하지 않으므로 실행기가 따로 돌리지 않는다. 사용: const TutorialDriver := preload("res://tests/tutorial_driver.gd")

const DT := Tuning.DT
const DRAG_SPEED := 2.5

var s: ClimbSession
var t: TutorialRunner
var results: Array = []
var labels: Array = []  # 이번 단계의 move 이벤트 라벨


func _init(route: RouteDef) -> void:
	s = ClimbSession.new(route)
	t = TutorialRunner.new(route)
	t.begin_step(s)


func tick() -> String:
	var seq := s.event_seq
	var r := s.step()
	for ev in s.technique_log:
		if int(ev.seq) > seq and ev.type == "move":
			labels.append(ev.label)
	var act := t.observe(s, r, DT)
	if act == "":
		return ""
	results.append(act)
	if act in ["next", "restart"]:
		t.begin_step(s)
	return act


## 떼어 끌고, 후보가 그 키가 되면 놓는다. 결과가 나오면 멈춘다.
func drag(limb: StringName, key: String) -> bool:
	s.apply_input([{"type": "detach", "limb": limb}])
	for i in 300:
		var req: Vector2 = s.limbs[limb].req
		s.apply_input([{"type": "move", "limb": limb, "delta": (s.route.slot_pos(key) - req).limit_length(DRAG_SPEED * DT)}])
		var act := tick()
		if s.limbs[limb].cand.get("key", "") == key:
			s.apply_input([{"type": "release", "limb": limb, "speed": 0.0}])
			return true
		if act != "":
			return true
	return false
