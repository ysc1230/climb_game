extends RefCounted
## 세션 검증 봇(SessionBot)·등급 기준(GradeRules)·콘텐츠 검사(ContentCheck), docs/28 §7.3·§7.4.

var runner

const G := "G_V0_01"


func _g_v0_01() -> RouteDef:
	return RouteDef.load_json("res://data/routes/general/G_V0_01.json")


func _g_v0_01_dict() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/routes/general/G_V0_01.json"))


func _hold(d: Dictionary, id: String) -> Dictionary:
	for h in d.holds:
		if h.hold_id == id:
			return h
	return {}


## 의도 경로와 좌우 손 순서를 바꾼 경로 모두 실제 세션으로 완등한다.
func test_bot_clears_g_v0_01() -> void:
	var r := _g_v0_01()
	var bot := SessionBot.run(r, r.intended_moves)
	runner.check(bot.ok(), "의도 경로 완등: %s" % bot.failure)
	runner.check(bot.failed_step == -1, "failed_step -1 (%d)" % bot.failed_step)
	runner.check(bot.metrics.moves == r.intended_moves.size(), "이동 수 %s" % bot.metrics.moves)
	runner.check(bot.metrics.seconds > 0.0 and bot.metrics.min_stamina <= 100.0 and bot.metrics.max_hand_u > 0.0, "측정값 %s" % [bot.metrics])
	runner.check(is_equal_approx(bot.metrics.min_hand_half_width, 0.12), "최소 손 반폭 0.12(정상 슬롯 제외) %s" % bot.metrics.min_hand_half_width)
	runner.check(is_finite(bot.metrics.min_reach_margin) and bot.metrics.min_reach_margin >= 0.0, "도달 여유 %s" % bot.metrics.min_reach_margin)
	var sw := SessionBot.run(r, RouteBot.swapped_pairs(r.intended_moves))
	runner.check(sw.ok(), "교체 경로 완등: %s" % sw.failure)


## 닿지 않는 홀드로 가는 단계에서 실패하고 그 인덱스를 알려 준다.
func test_bot_reports_failed_step() -> void:
	var r := _g_v0_01()
	var steps := [["LH", G + "/H03/hand_1"], ["RH", G + "/H04/hand_1"], ["RF", G + "/G01/goal_right"]]
	var bot := SessionBot.run(r, steps)
	runner.check(not bot.ok(), "실패")
	runner.check(bot.failed_step == 2, "실패 단계 2 (%d: %s)" % [bot.failed_step, bot.failure])
	runner.check(not bot.failure.is_empty() and bot.log.size() > 0, "실패 이유와 기록")
	# 모든 단계는 됐지만 정상에 닿지 않으면 실패이지만 단계 인덱스는 -1
	var short := SessionBot.run(r, [["LH", G + "/H03/hand_1"]])
	runner.check(not short.ok() and short.failed_step == -1, "목표 미도달: failed_step -1 (%d: %s)" % [short.failed_step, short.failure])


## 버튼 기술 단계(제자리 드롭니)를 세션의 기술 선택으로 실행하고 기록한다.
func test_bot_button_technique_step() -> void:
	var r := RouteDef.load_json("res://data/routes/TX_TECH.json")
	var bot := SessionBot.run(r, [["LF", "T_DROP_KNEE"]])
	runner.check(bot.failed_step == -1, "드롭니 단계 성공 (%d: %s)" % [bot.failed_step, bot.failure])
	runner.check(Array(bot.log).any(func(l): return l.contains("T_DROP_KNEE")), "기록에 드롭니: %s" % [bot.log])
	runner.check(bot.session.technique_log.any(func(e): return e.get("id") == &"T_DROP_KNEE" and e.type == TechniqueRunner.STARTED), "실행기 started 이벤트")
	var oe := SessionBot.run(r, [["RF", "T_OUTSIDE_EDGE", "TX_TECH/F04/foot_1"]])
	runner.check(oe.failed_step == -1, "아웃사이드 엣지 단계 성공 (%d: %s)" % [oe.failed_step, oe.failure])
	runner.check(oe.session.limbs[&"RF"].key == "TX_TECH/F04/foot_1", "RF가 F04에")


## 필요 없는 기술을 required로 넣으면(금지해도 완등) 검사가 실패한다.
func test_required_check_detects_unneeded() -> void:
	var d := _g_v0_01_dict()
	d.required_techniques = ["T_CROSS"]
	d.crux_steps = {"T_CROSS": 0}
	var r := RouteDef.from_dict(d)
	runner.check(r.errors.is_empty(), "저작 오류 없음 %s" % [r.errors])
	var res := ContentCheck.check(r)
	runner.check(not res.ok, "필요 없는 기술 → ok false")
	runner.check(Array(res.lines).any(func(l): return l.contains("T_CROSS")), "이유에 T_CROSS: %s" % [res.lines])
	var plain := ContentCheck.check(_g_v0_01())
	runner.check(plain.ok, "원래 루트는 통과: %s" % [plain.lines])
	runner.check(plain.metrics.has("min_reach_margin"), "측정값 포함")


## 등급 기준을 벗어나면 경고(ok에는 영향 없음).
func test_grade_warning() -> void:
	runner.check(GradeRules.LIMITS["V0"] == {"min_half_width": 0.12, "min_reach_margin": 0.035}, "V0 기준")
	runner.check(GradeRules.LIMITS["V2"] == {"min_half_width": 0.08, "min_reach_margin": 0.015}, "V2 기준")
	runner.check(GradeRules.LIMITS["V5"] == {"min_half_width": 0.04, "min_reach_margin": 0.0}, "V5 기준")
	var r := _g_v0_01()
	var good := {"min_hand_half_width": 0.12, "min_reach_margin": 0.06}
	runner.check(GradeRules.warnings(r, good).is_empty(), "기준 안: 경고 없음")
	var w := GradeRules.warnings(r, {"min_hand_half_width": 0.08, "min_reach_margin": 0.02})
	runner.check(w.size() == 2 and w[0].begins_with("경고:") and w[1].begins_with("경고:"), "반폭·도달 여유 경고 2개: %s" % [w])
	var tx := RouteDef.load_json("res://data/routes/TX_TECH.json")
	runner.check(GradeRules.warnings(tx, {"min_hand_half_width": 0.01, "min_reach_margin": -1.0}).is_empty(), "등급 없는 시험 루트는 경고 없음")
	# 경고만 있는 문제는 통과
	var d := _g_v0_01_dict()
	_hold(d, "H03").slots[0].hand_area.half_width = 0.05  # 의도 경로에서 잡는 손홀드
	var res := ContentCheck.check(RouteDef.from_dict(d))
	runner.check(res.ok, "경고는 실패가 아님: %s" % [res.lines])
	runner.check(Array(res.lines).any(func(l): return l.begins_with("경고:")), "경고 줄: %s" % [res.lines])


## 균형 발 단계: 발을 허공 지점으로 끌어 놓으면 Flag. 플래그 금지면 그 단계에서 실패.
func test_bot_flag_step() -> void:
	var r := _g_v0_01()
	var bot := SessionBot.run(r, [["RF", "flag", [-0.35, 0.52]]])
	runner.check(bot.failed_step == -1 and bot.session.limbs[&"RF"].state == "Flag", "Flag (%d: %s)" % [bot.failed_step, bot.failure])
	var no := SessionBot.run(r, [["RF", "flag", [-0.35, 0.52]]], {&"flag": true})
	runner.check(no.failed_step == 0, "금지하면 #0 실패 (%d: %s)" % [no.failed_step, no.failure])


## 정상 슬롯은 손 반폭 측정에서 빠진다(Ruling G). 건너뛴 단계 []는 이동 수에 세지 않는다.
func test_metrics_goal_excluded_and_skips() -> void:
	var r := _g_v0_01()
	var steps: Array = [[]] + r.intended_moves
	var bot := SessionBot.run(r, steps)
	runner.check(bot.ok(), "완등: %s" % bot.failure)
	runner.check(bot.metrics.moves == r.intended_moves.size(), "건너뜀 제외 이동 수 %s" % bot.metrics.moves)
	runner.check(is_equal_approx(bot.metrics.min_hand_half_width, 0.12), "정상(기본 0.08) 제외 반폭 %s" % bot.metrics.min_hand_half_width)
	runner.check(bot.metrics.min_reach_margin >= GradeRules.LIMITS["V0"].min_reach_margin, "안정 뒤 도달 여유가 V0 기준 이상 %s" % bot.metrics.min_reach_margin)
	runner.check(not bot.metrics.has("min_half_width"), "옛 키 없음")
	var res := ContentCheck.check(r)
	runner.check(not Array(res.lines).any(func(l): return l.begins_with("경고:")), "G_V0_01 등급 경고 없음: %s" % [res.lines])


## 시작 자세에서 바로 떨어지면 failed_step -2.
func test_start_fall_failed_step() -> void:
	var d := _g_v0_01_dict()
	d.start_pose.pelvis = [0.0, 2.5]  # 손발이 닿지 않는 골반
	var r := RouteDef.from_dict(d)
	var bot := SessionBot.run(r, r.intended_moves)
	runner.check(not bot.ok() and bot.failed_step == SessionBot.START_FAILED, "시작 실패 -2 (%d: %s)" % [bot.failed_step, bot.failure])
