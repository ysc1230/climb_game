extends RefCounted
## 문제 만들기 초안(작업 6 §2·§3, docs/superpowers/specs/2026-11-19-6-editor-design.md).

var runner


## 바닥 발판 둘 + 손 둘 + 위로 이어지는 홀드 + 탑: 그대로 문제가 되는 초안.
func _draft() -> RouteDraft:
	var d := RouteDraft.new()
	d.route_id = "U_TEST"
	d.name = "시험 문제"
	var f1 := d.place("foot_chip", -0.15, 0.1)
	var f2 := d.place("foot_chip", 0.18, 0.1)
	var h1 := d.place("jug", -0.3, 1.5)
	var h2 := d.place("jug", 0.3, 1.5)
	d.place("foot_big", -0.2, 0.55)
	d.place("foot_big", 0.25, 0.6)
	d.place("jug", -0.3, 1.95)
	d.place("jug", 0.35, 2.05)
	d.place("goal", 0.05, 2.4)
	d.set_start(&"LH", h1)
	d.set_start(&"RH", h2)
	d.set_start(&"LF", f1)
	d.set_start(&"RF", f2)
	return d


func test_snap_and_clamp() -> void:
	var d := RouteDraft.new()
	var id := d.place("crimp", 0.123456, 1.5049)
	var h: Dictionary = d.hold(id)
	runner.check(is_equal_approx(h.x, 0.12) and is_equal_approx(h.y, 1.5), "1cm 맞물림 %s" % [h])
	d.rotate(id, 93)
	runner.check(d.hold(id).rot == 95, "5° 맞물림 %d" % d.hold(id).rot)
	d.set_rot(id, -10)
	runner.check(d.hold(id).rot == 350, "음수는 감아 돎 %d" % d.hold(id).rot)
	d.move(id, 5.0, -1.0)
	runner.check(is_equal_approx(d.hold(id).x, RouteDraft.WALL_HALF) and d.hold(id).y >= 0.05, "벽 밖은 가장자리로 %s" % [d.hold(id)])


func test_goal_is_single() -> void:
	var d := RouteDraft.new()
	d.place("goal", 0.0, 3.0)
	d.place("goal", 0.3, 3.2)
	runner.check(d.holds.filter(func(h): return h.type == "goal").size() == 1 and is_equal_approx(d.goal_hold().x, 0.3), "탑은 하나, 다시 놓으면 옮김")


func test_max_holds_and_undo() -> void:
	var d := RouteDraft.new()
	for i in RouteDraft.MAX_HOLDS:
		d.place("jug", -0.9 + (i % 10) * 0.2, 0.3 + int(i / 10) * 0.5)
	runner.check(d.place("jug", 0.0, 4.0) == "", "40개 넘으면 놓지 않음")
	var n := d.holds.size()
	d.remove(d.holds[0].id)
	runner.check(d.holds.size() == n - 1, "지우기")
	d.undo()
	runner.check(d.holds.size() == n, "되돌리기")
	for i in 40:
		d.move(d.holds[0].id, 0.0, 1.0 + i * 0.01)
	var k := 0
	while d.undo():
		k += 1
	runner.check(k == RouteDraft.UNDO_MAX, "되돌리기는 최근 %d단계 (%d)" % [RouteDraft.UNDO_MAX, k])


func test_builds_valid_route() -> void:
	var d := _draft()
	var r := d.build()
	runner.check(r.errors.is_empty(), "문제로 읽힘 %s" % [r.errors])
	runner.check(r.mode == "custom" and r.name_ko == "시험 문제" and r.goal_slots.size() == 2, "custom·이름·탑 두 칸")
	runner.check(int(d.to_route_dict().get("schema", 0)) == RouteDraft.SCHEMA, "schema 판")
	var p := d.problems()
	runner.check(p.is_empty(), "문제 없음 %s" % [p])
	var pose := d.start_pose()
	runner.check(pose.ok and (pose.pelvis as Vector2).y > 0.4, "시작 자세를 계산 %s" % [pose])


func test_problems_listed() -> void:
	var d := RouteDraft.new()
	d.name = ""
	var p := d.problems()
	runner.check(p.has(RouteDraft.P_NAME) and p.has(RouteDraft.P_START) and p.has(RouteDraft.P_GOAL), "이름·시작·탑 없음 %s" % [p])
	d = _draft()
	var a := d.place("jug", -0.3, 1.6)  # 손홀드 H01 바로 위: 간격 규칙 위반
	runner.check(d.problems().has(RouteDraft.P_SPACING) and d.bad_holds().has(a), "간격 위반 홀드 표시 %s" % [d.bad_holds()])
	d.remove(a)
	var far := _draft()
	far.move(far.start[&"LH"], -0.9, 3.5)
	runner.check(far.problems().has(RouteDraft.P_POSE), "손이 너무 멀면 시작 자세 못 만듦 %s" % [far.problems()])


func test_start_rules() -> void:
	var d := _draft()
	var foot: String = d.start[&"LF"]
	runner.check(not d.set_start(&"LH", foot), "손 시작은 손홀드만")
	runner.check(d.set_start(&"LF", d.start[&"RF"]) and d.start[&"RF"] == "", "같은 자리를 다른 손발에 주면 앞 손발은 비움")
	d.remove(d.start[&"LH"])
	runner.check(d.start[&"LH"] == "", "지운 홀드는 시작에서 빠짐")


func test_dict_roundtrip() -> void:
	var d := _draft()
	d.grade = "V3"
	var e := RouteDraft.from_dict(JSON.parse_string(JSON.stringify(d.to_dict())))
	runner.check(e.holds.size() == d.holds.size() and e.name == d.name and e.grade == "V3" and e.start == d.start, "저장 뒤 같음")
	runner.check(e.build().errors.is_empty(), "다시 문제로 읽힘")


## 올리기 조건(§3): 문제 없음 + 만든 사람이 도움 없이 이 판을 완등.
func test_publish_conditions() -> void:
	var d := _draft()
	var p := Progress.new()
	runner.check(not d.can_publish(p), "완등 전에는 못 올림")
	p.cleared[d.route_id] = {"content_version": d.version, "time": 30.0, "best_seconds": 30.0}
	runner.check(d.can_publish(p), "도움 없이 완등하면 올림")
	p.cleared[d.route_id] = {"content_version": d.version, "time": 30.0}
	runner.check(not d.can_publish(p), "도움 받은 완등(best 없음)은 안 됨")
	p.cleared[d.route_id] = {"content_version": d.version, "time": 30.0, "best_seconds": 30.0}
	d.freeze()  # 완등·올린 판을 고치기 시작하면 새 판
	d.move(d.holds[4].id, -0.2, 0.5)
	runner.check(d.version == 2 and not d.can_publish(p), "고치면 새 판, 다시 완등해야 함")
