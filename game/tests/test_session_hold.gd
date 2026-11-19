extends RefCounted
## 세션 멈춤 플래그(docs/superpowers/specs/2026-11-19-1-feel-design.md §1.1·§1.2): 완등·착지 뒤 판정을 멈추고 기다린다.
## 기본값(끔)에서는 지금 동작 그대로.

var runner


func _route() -> RouteDef:
	return RouteDef.load_json("res://tests/fixtures/G_V0_01.json")


## 봇으로 정답 순서를 오른다. hold_on_clear를 켜고 싶으면 true.
func _bot(hold_clear: bool) -> SessionBot:
	var r := _route()
	var bot := SessionBot.new()
	bot.route = r
	bot.session = ClimbSession.new(r)
	bot.session.hold_on_clear = hold_clear
	bot._play(r.intended_moves)
	return bot


func test_default_flags_unchanged() -> void:
	var bot := _bot(false)
	runner.check(bot.ok(), "완등: %s" % bot.failure)
	var s := bot.session
	runner.check(not s.hold_on_clear and not s.hold_on_fall, "기본값 끔")
	runner.check(s.halted == &"", "멈춤 없음")
	runner.check(s.body.pos.distance_to(s.route.start_pelvis) < 0.001, "완등 뒤 시작 자세로 돌아감 %s" % s.body.pos)


func test_hold_on_clear_keeps_pose() -> void:
	var bot := _bot(true)
	runner.check(bot.ok(), "완등: %s" % bot.failure)
	var s := bot.session
	runner.check(s.halted == &"clear", "완등 멈춤 %s" % s.halted)
	for hand in [&"LH", &"RH"]:
		runner.check(s.route.goal_slots.has(s.limbs[hand].key), "%s가 탑에 그대로 (%s)" % [hand, s.limbs[hand].key])
	var pos := s.body.pos
	for i in 10:
		runner.check(s.step() == "", "멈춘 동안 step은 빈 결과")
	runner.check(s.body.pos == pos, "멈춘 동안 몸 그대로")


func test_hold_on_clear_ignores_input() -> void:
	var s := _bot(true).session
	var before: Vector2 = s.limbs[&"LH"].pos
	s.apply_input([{"type": "detach", "limb": &"LH"}, {"type": "move", "limb": &"LH", "delta": Vector2(0.3, 0)}])
	for i in 5:
		s.step()
	runner.check(s.limbs[&"LH"].pos == before, "멈춘 동안 입력 무시")
	s.reset()
	runner.check(s.halted == &"", "reset이 멈춤을 푼다")
	var start: Vector2 = s.limbs[&"LH"].pos
	s.apply_input([{"type": "detach", "limb": &"LH"}, {"type": "move", "limb": &"LH", "delta": Vector2(0.05, 0)}])
	for i in 10:
		s.step()
	runner.check((s.limbs[&"LH"].pos as Vector2).distance_to(start) > 0.01, "reset 뒤 입력이 다시 먹음")


func test_hold_on_fall_lands() -> void:
	var s := ClimbSession.new(_route())
	s.hold_on_fall = true
	for i in 40:
		s.step()
	var falls0 := s.falls
	s.apply_input([{"type": "detach", "limb": &"LH"}, {"type": "detach", "limb": &"RH"},
		{"type": "detach", "limb": &"LF"}, {"type": "detach", "limb": &"RF"}])
	var results: Array = []
	for i in 400:
		var r := s.step()
		if r != "":
			results.append(r)
	runner.check(results.count("landed") == 1, "착지 한 번 %s" % [results])
	runner.check(not results.has("respawn"), "자동 다시 시작 없음 %s" % [results])
	runner.check(s.halted == &"fall", "착지 멈춤 %s" % s.halted)
	runner.check(s.falls == falls0 + 1, "추락 수 +1 (%d)" % s.falls)
