extends RefCounted
## 기술 수업(docs/47): 실제 수업 파일을 세션 + TutorialRunner로 돌린다. 수업마다 첫 단계(기술 없이 해 보기)는 실제로 안 되고,
## 기술을 쓰면 다음으로 넘어가 끝까지 간다.

var runner

const Driver := preload("res://tests/tutorial_driver.gd")


func _route(id: String) -> RouteDef:
	return RouteDef.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://data/routes/course/%s.json" % id)))


func _k(id: String, h: String) -> String:
	if h.begins_with("G01/"):
		return "%s/%s" % [id, h]
	return "%s/%s/%s" % [id, h, "foot_1" if h.begins_with("F") else "hand_1"]


func _start(id: String):
	var d = Driver.new(_route(id))
	for i in 30:
		d.tick()
	return d


## 첫 단계: limb을 target으로 뻗어 놓으면 잡히지 않고(miss) 다음 단계로.
func _try_without(d, id: String, limb: StringName, target: String) -> void:
	d.reach_and_release(limb, _k(id, target))
	d.wait(30)
	runner.check(d.results == ["next"] and d.s.limbs[limb].get("key", "") != _k(id, target), "%s: 기술 없이는 %s가 %s에 안 닿음 %s" % [id, limb, target, d.results])
	_hold(d, 30)


## n틱을 결과와 상관없이 돌린다(사람이 다음 동작 전 잠깐 기다리는 것).
func _hold(d, n: int) -> void:
	for i in n:
		d.tick()


func _moves(d, id: String, moves: Array) -> void:
	for m in moves:
		runner.check(d.drag(StringName(m[0]), _k(id, m[1])), "%s: %s → %s" % [id, m[0], m[1]])
		_hold(d, 120)
	d.wait(200)
	runner.check(not d.results.is_empty() and d.results[-1] == "done", "%s 끝까지 %s (다시 %d)" % [id, d.results, d.restarts])


func test_high_step() -> void:
	var d = _start("C_HIGH_T")
	_try_without(d, "C_HIGH_T", &"RH", "H03")
	_moves(d, "C_HIGH_T", [["RF", "F05"], ["RH", "H03"], ["LF", "F06"], ["LH", "G01/goal_left"], ["RH", "G01/goal_right"]])


## 매치: 초록 홀드에 손을 모으면 먼저 있던 손이 밀려나고(slot_swap), 파란 홀드에는 두 손이 함께 잡힌다.
func test_match() -> void:
	var d = _start("C_MATCH_T")
	d.reach_and_release(&"LH", _k("C_MATCH_T", "N01"))
	d.wait(30)
	runner.check(d.results == ["next"], "초록 홀드에 모으면 오른손이 밀려남(slot_swap) %s" % [d.results])
	d.wait(30)
	runner.check(d.drag(&"LH", _k("C_MATCH_T", "M01")), "파란 홀드에 왼손을 모음")
	d.wait(60)
	runner.check(d.s.limbs[&"LH"].key == _k("C_MATCH_T", "M01") and d.s.limbs[&"RH"].key == _k("C_MATCH_T", "M01") and d.s.limbs[&"RH"].state == "Attached", "두 손이 함께 잡힘")
	_moves(d, "C_MATCH_T", [["RH", "H03"], ["RF", "F05"], ["LF", "F06"], ["LH", "G01/goal_left"], ["RH", "G01/goal_right"]])


func test_foot_swap() -> void:
	var d = _start("C_FSWAP_T")
	_try_without(d, "C_FSWAP_T", &"RF", "F05")
	d.reach_and_release(&"LF", _k("C_FSWAP_T", "F04"))
	_hold(d, 60)
	runner.check(d.results.size() == 2 and d.s.limbs[&"LF"].key == _k("C_FSWAP_T", "F04") and d.s.limbs[&"RF"].state != "Attached", "왼발을 넣으면 오른발이 비킴 %s" % [d.results])
	_moves(d, "C_FSWAP_T", [["RF", "F05"], ["RH", "H03"], ["LH", "H02"], ["LH", "G01/goal_left"], ["RH", "G01/goal_right"]])


func test_foot_match() -> void:
	var d = _start("C_FMATCH_T")
	_try_without(d, "C_FMATCH_T", &"RF", "F05")
	_moves(d, "C_FMATCH_T", [["LF", "B01"], ["RF", "F05"], ["RH", "H03"], ["LH", "H02"], ["LH", "G01/goal_left"], ["RH", "G01/goal_right"]])


func test_cross() -> void:
	var d = _start("C_CROSS_T")
	runner.check(d.drag(&"RH", _k("C_CROSS_T", "H03")), "오른손을 왼손 너머로")
	d.wait(60)
	runner.check(d.labels.has(MoveClassifier.CROSS_REACH), "크로스로 인식 %s" % [d.labels])
	_moves(d, "C_CROSS_T", [["LH", "H04"], ["LH", "G01/goal_left"], ["RH", "G01/goal_right"]])


func test_dyno() -> void:
	var d = _start("C_DYNO_T")
	_try_without(d, "C_DYNO_T", &"RH", "G01/goal_right")
	var s: ClimbSession = d.s
	s.apply_input([{"type": "dyno_start", "limb": InputRouter.DYNO}])
	s.apply_input([{"type": "dyno_move", "limb": InputRouter.DYNO, "delta": Vector2(0, -0.8)}])
	d.wait(30)
	s.apply_input([{"type": "dyno_end", "limb": InputRouter.DYNO}])
	var caught := false
	for i in 200:
		var aim := s.dyno_aim()
		for h in aim:
			if not str(aim[h]).is_empty() and not caught:
				s.apply_input([{"type": "detach", "limb": h}])
				caught = true
		if d.tick() != "":
			break
	runner.check(caught and d.results.size() == 2 and d.results[-1] == "next", "날아가며 손 패드로 잡으면 다음 %s" % [d.results])
	var free := &"LH" if s.limbs[&"LH"].state != "Attached" else &"RH"
	s.apply_input([{"type": "detach", "limb": free}])
	d.wait(300)
	runner.check(not d.results.is_empty() and d.results[-1] == "done", "다른 손도 잡아 완등 %s" % [d.results])
