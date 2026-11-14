extends RefCounted
## 처음 배우기 수업 0~3(docs/42): 실제 튜토리얼 파일을 세션 + TutorialRunner로 끝까지 돌린다.

var runner

const Driver := preload("res://tests/tutorial_driver.gd")
const AIR := Vector2(-0.35, 0.45)


func _route(id: String) -> RouteDef:
	return RouteDef.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://data/routes/course/%s.json" % id)))


func _settle(d) -> void:
	for i in 30:
		d.tick()


## 의도 경로를 순서대로 끌면 단계가 차례로 넘어가고 끝난다.
func _play_moves(id: String) -> void:
	var r := _route(id)
	var d = Driver.new(r)
	_settle(d)
	for m in r.intended_moves:
		runner.check(d.drag(StringName(m[0]), m[1]), "%s: %s → %s 잡음" % [id, m[0], m[1]])
		d.wait(90)
	d.wait(200)
	runner.check(not d.results.is_empty() and d.results[-1] == "done" and d.restarts == 0, "%s 끝까지 %s" % [id, d.results])
	runner.check(d.visited.size() == r.tutorial_steps.size(), "%s 모든 단계를 거침 %s" % [id, d.visited])


func test_basic_lesson() -> void:
	_play_moves("C_BASIC_T")


func test_feet_lesson() -> void:
	_play_moves("C_FEET_T")


## 발을 올리지 않으면 높은 손홀드에 닿지 않는다(수업 1의 요점).
func test_feet_lesson_needs_feet() -> void:
	var d = Driver.new(_route("C_FEET_T"))
	_settle(d)
	d.drag(&"LH", "C_FEET_T/H03/hand_1")
	d.wait(60)
	runner.check(d.s.limbs[&"LH"].get("key", "") != "C_FEET_T/H03/hand_1" and d.results.is_empty(), "바닥에서는 높은 홀드에 안 닿음")


func test_body_lesson() -> void:
	var d = Driver.new(_route("C_BODY_T"))
	_settle(d)
	d.body_drag(Vector2(0.45, 0))
	d.wait(120)
	runner.check(d.results == ["next"], "몸통을 끌면 다음 단계 %s (골반 %s)" % [d.results, d.s.body.pos])
	d.drag(&"RH", "C_BODY_T/H07/hand_1")
	d.wait(120)
	runner.check(d.results == ["next", "done"], "몸통을 옮긴 채 먼 홀드를 잡음 %s" % [d.results])


## 몸통을 옮기지 않으면 먼 홀드에 닿지 않는다(수업 2의 요점).
func test_body_lesson_needs_body() -> void:
	var r := _route("C_BODY_T")
	var d = Driver.new(r)
	_settle(d)
	d.drag(&"RH", "C_BODY_T/H07/hand_1")
	d.wait(60)
	runner.check(d.s.limbs[&"RH"].get("key", "") != "C_BODY_T/H07/hand_1", "몸통을 안 옮기면 먼 홀드에 안 닿음")


func test_arm_lesson() -> void:
	var d = Driver.new(_route("C_ARM_T"))
	d.wait(400)
	runner.check(d.results == ["next"], "A1 두 발로 서면 팔 힘이 참 %s" % [d.results])
	var t0: int = d.ticks
	d.drag_to_air(&"LF", AIR)
	d.wait(900)
	var big: int = d.ticks - t0
	runner.check(d.results.size() == 2, "A2 한 발을 떼면 팔 힘이 빠짐 %s" % [d.results])
	d.drag(&"LF", "C_ARM_T/F01/foot_1")
	d.wait(120)
	d.drag(&"LH", "C_ARM_T/S01/hand_1")
	d.wait(120)
	runner.check(d.results.size() == 4, "A3·A4 발 딛고 작은 홀드 잡음 %s" % [d.results])
	t0 = d.ticks
	d.drag_to_air(&"LF", AIR)
	d.wait(900)
	var small: int = d.ticks - t0
	runner.check(d.results.size() == 5, "A5 작은 홀드에서 팔 힘이 빠짐 %s" % [d.results])
	runner.check(small * 15 < big * 30 * 1.0, "작은 홀드가 더 빨리 빠짐(15 줄어드는 데 %d틱 vs 큰 홀드 %d틱, 30은 %d틱)" % [big, big, small])
	d.drag(&"LF", "C_ARM_T/F01/foot_1")
	d.wait(900)
	runner.check(d.results.size() == 6, "A6 다시 딛고 쉬면 팔 힘이 돌아옴 %s" % [d.results])
	d.drag(&"LH", "C_ARM_T/G01/goal_left")
	d.wait(60)
	d.drag(&"RH", "C_ARM_T/G01/goal_right")
	d.wait(200)
	runner.check(d.results.size() == 7 and d.results[-1] == "done" and d.restarts == 0, "A7 정상을 잡으면 끝 %s" % [d.results])
