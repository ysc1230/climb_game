extends RefCounted
## 루트 데이터 불변 조건과 의도 경로 자동 재생.

var runner


func test_r01_content_valid() -> void:
	var r := RouteDef.load_json("res://data/routes/R01.json")
	runner.check(r.errors.is_empty(), "저작 오류: %s" % [r.errors])
	runner.check(r.slots.size() == 14, "R01 슬롯 14개, 실제 %d" % r.slots.size())
	runner.check(r.intended_moves.size() == 10, "R01 의도 이동 10회")


func test_r01_intended_path_both_orders() -> void:
	var r := RouteDef.load_json("res://data/routes/R01.json")
	for moves in [r.intended_moves, RouteBot.swapped_pairs(r.intended_moves)]:
		var bot := RouteBot.run(r, moves)
		runner.check(bot.ok(), bot.failure)
		runner.check(bot.ticks <= int(r.time_medal_seconds * Tuning.TICK_HZ), "봇 시간이 메달 기준보다 김")


func test_r01_requires_moving_feet() -> void:
	# 16 수락 조건: 발을 전혀 움직이지 않으면 정상에 갈 수 없다.
	var r := RouteDef.load_json("res://data/routes/R01.json")
	var hands_only := r.intended_moves.filter(func(m): return PoseSolver.is_hand(m[0]))
	runner.check(not RouteBot.run(r, hands_only).ok(), "손만으로 완등되면 R01 목적 위반")


func test_validator_catches_bad_reference() -> void:
	var r := RouteDef.load_json("res://data/routes/R01.json")
	r.intended_moves.append([PoseSolver.LF, "R01/H01/hand_1"])
	r.errors.clear()
	r._validate()
	runner.check(r.errors.size() > 0, "발이 손 슬롯을 쓰는 경로를 잡아내야 함")
