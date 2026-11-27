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


## 2026-11-26 사용자 "탑홀드는 무조건 하나로 해야해. 그리고 탑홀드 종류는 제각각이야", 탑은 합손 되는 크기만(사용자 고름).
func test_top_is_one_hold_of_any_type() -> void:
	var d := RouteDraft.new()
	var a := d.place("crimp", 0.0, 3.0, "top")
	runner.check(d.hold(a).role == "top" and d.hold(a).size == "L" and d.hold(a).matchable, "크림프 탑은 합손 되는 큰 것 %s" % [d.hold(a)])
	var b := d.place("sloper", 0.3, 3.2, "top")
	var tops := d.holds.filter(func(h): return h.role == "top")
	runner.check(b == a and tops.size() == 1 and d.goal_hold().type == "sloper" and is_equal_approx(d.goal_hold().x, 0.3), "탑은 하나: 다시 놓으면 그 탑이 옮겨지고 종류가 바뀜 %s" % [tops])
	runner.check(d.place("foot_chip", 0.0, 2.0, "top") == "" and d.place("foot_big", 0.0, 2.0, "hand") != "", "발판은 탑이 될 수 없음(합손 안 됨), 손 쓰임은 됨")
	d.set_size(a, "S")
	runner.check(d.goal_hold().size == "M", "탑은 합손 안 되는 크기로 못 줄임(슬로퍼 작은 것) %s" % d.goal_hold().size)
	runner.check(d.place("goal", 0.0, 3.5) == a and d.goal_hold().type == "jug", "예전 이름 goal은 저그 탑")


## 2026-11-26 사용자 "손홀드 발홀드 탑이 기준이 아니라 홀드 종류가 기준이 된 후에 손 발 탑을 선택".
func test_type_then_role() -> void:
	var d := _draft()
	var f := d.place("jug", -0.6, 0.9, "foot")
	var r := d.build()
	var slot: Dictionary = r.slots.get("U_TEST/%s/foot_1" % f, {})
	# 2026-11-26 사용자 "모든 홀드들이 손홀드이자 발홀드": 쓰임은 표시, 손발 모두
	runner.check(r.errors.is_empty() and slot.has("hand_area") and slot.allowed.has(&"LH") and slot.allowed.has(&"LF"), "저그를 발로 놓아도 손발 모두 %s %s" % [r.errors, slot])
	runner.check(d.set_start(&"LH", f), "발로 놓은 홀드에서도 손 시작")
	runner.check(RouteDraft.roles_for("crimp") == ["hand", "foot", "top"] and RouteDraft.roles_for("foot_big") == ["foot", "hand"], "종류마다 쓰임(발판 기본은 발) %s" % [RouteDraft.roles_for("foot_big")])


## 합손 켜기는 그 종류·크기가 될 때만, 크기를 바꿔 안 되면 꺼진다(2026-11-26 사용자 "홀드 크기에 따라 합손이 불가능한 경우").
func test_matchable_follows_size() -> void:
	var d := RouteDraft.new()
	var c := d.place("crimp", 0.0, 2.0)
	d.set_matchable(c, true)
	runner.check(not d.hold(c).matchable, "크림프 보통은 합손 못 켬")
	d.set_size(c, "L")
	d.set_matchable(c, true)
	runner.check(d.hold(c).matchable, "크림프 큰 것은 켬")
	d.set_size(c, "M")
	runner.check(not d.hold(c).matchable, "작게 바꾸면 꺼짐")


## 탑 하나(합손 칸 하나)를 두 손으로 잡아 완등한다: 탑이 될 수 있는 종류마다 가장 작은 탑 크기로, 봇이 길을 찾고 세션 재생으로 확인.
## 좁은 탑(포켓·크림프 큰 것)은 두 손이 겹쳐 잡는다.
func test_bot_finishes_on_one_top() -> void:
	for type in ["jug", "crimp", "sloper", "pinch", "pocket"]:
		var d := RouteDraft.new()
		d.route_id = "U_TOP"
		d.name = "탑"
		var ids := [d.place("jug", -0.3, 1.5), d.place("jug", 0.3, 1.5), d.place("foot_chip", -0.15, 0.1), d.place("foot_chip", 0.18, 0.1)]
		for i in 4:
			d.set_start([&"LH", &"RH", &"LF", &"RF"][i], ids[i])
		d.place(type, 0.0, 1.7, "top", "S")
		var r := d.build()
		runner.check(r.errors.is_empty() and r.goal_slots.size() == 1 and r.slots[r.goal_slots[0]].hand_area.matchable, "%s 탑 칸 하나, 합손 %s" % [type, r.errors])
		var res := PathExplorer.explore(r, {}, false, 8000)
		runner.check(res.ok, "%s %s 탑을 두 손으로 잡아 완등 %s" % [type, d.goal_hold().size, res.log])


## 0.37까지의 초안: 탑(goal 종류)은 큰 저그 탑으로, 손·발 종류는 손·발 쓰임으로 읽는다.
func test_old_draft_roles() -> void:
	var old := {"route_id": "U_OLD", "holds": [{"id": "G01", "type": "goal", "x": 0.0, "y": 3.0}, {"id": "H01", "type": "crimp", "size": "M", "x": 0.2, "y": 1.5, "matchable": true},
		{"id": "F02", "type": "foot_big", "x": 0.0, "y": 0.3}]}
	var d := RouteDraft.from_dict(old)
	runner.check(d.goal_hold().type == "jug" and d.goal_hold().size == "L" and d.goal_hold().role == "top", "예전 탑 → 큰 저그 탑 %s" % [d.goal_hold()])
	runner.check(d.hold("H01").role == "hand" and not d.hold("H01").matchable and d.hold("F02").role == "foot", "손·발 쓰임, 안 되는 합손은 끔 %s" % [d.holds])


func test_max_holds_and_undo() -> void:
	var d := RouteDraft.new()
	for i in RouteDraft.MAX_HOLDS:
		d.place("jug", -0.9 + (i % 10) * 0.2, 0.3 + int(i / 10) * 0.5)
	runner.check(d.place("jug", 0.0, 4.0) == "", "%d개 넘으면 놓지 않음" % RouteDraft.MAX_HOLDS)
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
	runner.check(r.mode == "custom" and r.name_ko == "시험 문제" and r.goal_slots.size() == 1, "custom·이름·탑 한 칸")
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
	d.place("crimp", 0.75, 1.0)
	d.place("crimp", 0.75, 1.13)  # 2026-11-26 사용자 "홀드간 거리는 거의 겹치지만 않으면": 붙어 있지 않으면 된다
	runner.check(not d.problems().has(RouteDraft.P_SPACING), "겹치지 않으면 가까워도 됨 %s" % [d.spacing_details()])
	var far := _draft()
	far.move(far.start[&"LH"], -0.9, 3.5)
	runner.check(far.problems().has(RouteDraft.P_POSE), "손이 너무 멀면 시작 자세 못 만듦 %s" % [far.problems()])


func test_start_rules() -> void:
	var d := _draft()
	var foot: String = d.start[&"LF"]
	runner.check(not d.set_start(&"LH", d.goal_hold().id) and d.set_start(&"LH", foot), "손 시작은 탑이 아닌 아무 홀드(발판도)")
	d = _draft()
	foot = d.start[&"LF"]
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


## 2026-11-25 사용자 "높이를 계속해서 높게 … 100m까지, 벽 제한 높이보다 위에 홀드를 놓으면 높아지도록(용량 관리)", "홀드는 300개".
## 벽 높이는 따로 저장하지 않고 가장 높은 홀드에서 정한다(최소 4.5m). 벽 끝 위 EXTEND m까지 놓을 수 있고, 놓으면 벽이 높아진다.
func test_wall_grows_with_holds() -> void:
	runner.check(RouteDraft.MAX_HOLDS == 300, "홀드 300개까지")
	var d := RouteDraft.new()
	runner.check(is_equal_approx(d.wall_limit(), 4.5) and is_equal_approx(d.max_y(), 4.5 + RouteDraft.EXTEND), "빈 초안 벽 4.5m (%.1f, 놓기 %.1f)" % [d.wall_limit(), d.max_y()])
	var id := d.place("jug", 0.0, 50.0)
	runner.check(is_equal_approx(d.hold(id).y, 4.5 + RouteDraft.EXTEND), "벽 끝 위 %.0fm까지만 (%.2f)" % [RouteDraft.EXTEND, d.hold(id).y])
	var before := d.wall_limit()
	d.place("jug", 0.3, d.max_y())
	runner.check(d.wall_limit() > before, "벽 끝 위에 놓으면 벽이 높아짐 (%.1f → %.1f)" % [before, d.wall_limit()])
	for i in 200:  # 계속 올리면 100m에서 멈춘다
		d.move(id, 0.0, d.max_y())
	runner.check(is_equal_approx(d.wall_limit(), RouteDraft.WALL_H_MAX) and d.hold(id).y <= RouteDraft.WALL_H_MAX, "100m까지 (%.1f, 홀드 %.1f)" % [d.wall_limit(), d.hold(id).y])
	var r := d.to_route_dict()
	runner.check(is_equal_approx(float(r.bounds.y_max), d.wall_limit()), "문제 범위도 벽 높이 (%s)" % r.bounds.y_max)
	d.remove(id)
	runner.check(d.wall_limit() < 20.0, "높은 홀드를 지우면 벽도 낮아짐 (%.1f)" % d.wall_limit())


## 2026-11-25 사용자 "특정 높이마다 다르게 … 1m당 1도씩 가파라지게 설정할 수 있는 수준. 최소 단위 1m·1도, 횟수 제한 없음", "180도(평면)~90도".
## 저장은 플레이의 꺾이는 벽과 같은 오버행 각(0 수직 … 90 천장), 화면은 180 − 각.
func test_wall_angle_sections() -> void:
	var d := RouteDraft.new()
	runner.check(d.walls == [{"from_y": 0, "deg": 0}], "새 초안은 수직 하나 %s" % [d.walls])
	for m in 20:  # 1m마다 1°씩
		d.set_wall(m, m)
	runner.check(d.walls.size() == 20 and d.wall_deg_at(7.5) == 7, "20구간 %d, 7.5m = %d°" % [d.walls.size(), d.wall_deg_at(7.5)])
	d.set_wall(5, 4)
	runner.check(d.walls.size() == 20 and d.build(Vector2(0, 0.75)).wall_sections.size() == 19, "아래와 같은 각의 경계는 남겨 두고(끄는 중 이웃이 사라지지 않게) 문제로 바꿀 때 합침")
	d.set_wall(30, 120)
	runner.check(d.wall_deg_at(30.0) == 90, "90°(천장)까지 (%d)" % d.wall_deg_at(30.0))
	d.set_wall(40, -150)  # 2026-11-26 사용자 "벽각도는 90도부터 300도까지": 화면 300° = 오버행 −120
	runner.check(d.wall_deg_at(40.0) == -120 and is_equal_approx(d.build(Vector2(0, 0.75)).angle_at(45.0), -120.0), "300°(뒤로 120°)까지 (%d)" % d.wall_deg_at(40.0))
	d.remove_wall(40)
	var r := d.build(Vector2(0, 0.75))
	runner.check(is_equal_approx(r.angle_at(12.5), 12.0) and is_equal_approx(r.angle_at(35.0), 90.0), "플레이 벽도 같은 각 (%.1f, %.1f)" % [r.angle_at(12.5), r.angle_at(35.0)])
	d.remove_wall(30)
	runner.check(d.wall_deg_at(35.0) == 19, "경계 지우기 (%d)" % d.wall_deg_at(35.0))
	d.undo()
	runner.check(d.wall_deg_at(35.0) == 90, "되돌리기 (%d)" % d.wall_deg_at(35.0))
	var e := RouteDraft.from_dict(JSON.parse_string(JSON.stringify(d.to_dict())))
	runner.check(e.walls == d.walls, "저장 뒤 같음")
	var old := d.to_dict()
	old.erase("walls")
	old.grade = "V5"
	runner.check(RouteDraft.from_dict(old).walls == [{"from_y": 0, "deg": int(GradeInfo.wall_deg("V5"))}], "예전 초안은 등급 각도 그대로")


## 구간이 많아도(1m마다 100개) 각도 계산이 예전 식(차례로 섞기)과 같다.
func test_angle_at_many_sections() -> void:
	var d := RouteDraft.new()
	for m in 100:
		d.set_wall(m, (m * 7) % 91)
	var r := d.build(Vector2(0, 0.75))
	var worst := 0.0
	for i in 2000:
		var y := i * 0.05 - 1.0
		var a: float = r.wall_sections[0].deg
		for j in range(1, r.wall_sections.size()):
			var b: float = r.wall_sections[j].from_y
			a = lerpf(a, float(r.wall_sections[j].deg), smoothstep(b - RouteDef.WALL_BLEND, b + RouteDef.WALL_BLEND, y))
		worst = maxf(worst, absf(a - r.angle_at(y)))
	runner.check(worst < 0.001, "예전 식과 차이 %.4f" % worst)


## 2026-11-25 사용자 "가깝지 않다는 게 얼마나 가까워야 하는지 모르겠어. 완료할 수 없거나 문제가 있을 수 있는 경우를 모아 둔 창".
## 시작 자세가 안 되면 한 홀드를 어느 쪽으로 얼마나 옮기면 되는지 실제 자세 계산으로 찾는다(손이 발보다 0.65m 위: 너무 가까움).
func test_start_fix_suggestion() -> void:
	var d := RouteDraft.new()
	var f1 := d.place("foot_big", -0.05, 0.3)
	var f2 := d.place("foot_big", 0.25, 0.25)
	var h1 := d.place("sloper", 0.0, 0.95)
	var h2 := d.place("sloper", 0.25, 1.0)
	d.set_start(&"LH", h1); d.set_start(&"RH", h2); d.set_start(&"LF", f1); d.set_start(&"RF", f2)
	runner.check(not d.start_pose().ok, "재현: 시작 자세 안 됨")
	var fix: Dictionary = d.start_fix()
	runner.check(not fix.is_empty() and String(fix.text).contains("옮기면"), "고칠 곳 문구 %s" % [fix.get("text")])
	var h := d.hold(fix.hold)
	d.move(fix.hold, h.x + fix.move.x, h.y + fix.move.y)
	runner.check(d.start_pose().ok, "말한 대로 옮기면 시작 자세가 됨")
	runner.check(d.start_fix().is_empty(), "이미 되면 빈 값")


## 뒤로 누운 벽(화면 180°~300°, 2026-11-26 사용자 "90도부터 300도까지 … 땅 기준"): 시작 자세가 되고 탑까지 오른다.
func test_slab_walls_climbable() -> void:
	for deg in [-30, -90, -120]:
		var d := RouteDraft.new()
		d.route_id = "U_SLAB"
		d.name = "슬랩"
		var ids := [d.place("jug", -0.3, 1.5), d.place("jug", 0.3, 1.5), d.place("foot_chip", -0.15, 0.1), d.place("foot_chip", 0.18, 0.1)]
		for i in 4:
			d.set_start([&"LH", &"RH", &"LF", &"RF"][i], ids[i])
		d.place("jug", 0.0, 1.7, "top")
		if deg > -120:
			d.set_wall(0, deg)
		else:  # 300°는 아래로 꺾여 바닥부터면 바닥 밑으로 간다(2026-11-27 벽 모양 점검): 1m 수직 위에서 1m만, 그 위는 다시 수직
			d.set_wall(0, 0)
			d.set_wall(1, deg)
			d.set_wall(2, 0)
		runner.check(d.problems().is_empty(), "화면 %d°: 막는 것 없음 %s" % [180 - deg, d.problems()])
		runner.check(PathExplorer.explore(d.build(), {}, false, 8000).ok, "화면 %d°: 탑까지" % (180 - deg))


## 2026-11-26 사용자 "무게중심 때문에 시작 홀드 설정이 안 되는 경우가 있는데 여유롭게": 자세 계산이 고른 골반에서 못 버티면
## 가까운 골반을 찾아 버티는 자리로 시작한다(발이 손 아래 한쪽으로 치우친 배치).
func test_start_balance_lenient() -> void:
	var d := RouteDraft.new()
	d.route_id = "U_BAL"
	d.name = "균형"
	var ids := [d.place("jug", -0.3, 1.7), d.place("jug", 0.3, 1.7), d.place("foot_big", -0.4, 0.7), d.place("foot_big", -0.1, 0.7)]
	for i in 4:
		d.set_start([&"LH", &"RH", &"LF", &"RF"][i], ids[i])
	d.place("jug", 0.0, 3.0, "top")
	var g := d.start_pose(false)
	runner.check(g.ok and not SessionBot.start_ok(d.build(g.pelvis, g.angle)), "재현: 자세 계산의 골반에서는 못 버팀")
	var p := d.start_pose()
	runner.check(p.balanced and not d.problems().has(RouteDraft.P_POSE), "버티는 골반을 찾아 시작 자세가 됨 %s" % [d.problems()])
	runner.check(SessionBot.start_ok(d.build()), "문제의 시작 골반도 그 자리")


## 만들 수는 있지만 문제가 있을 수 있는 것: 손이 닿기 어려운 먼 홀드, 천장에 가까운 구간, 탑보다 높은 홀드, 아주 높은 벽.
func test_warnings() -> void:
	var d := RouteDraft.new()
	var h1 := d.place("jug", -0.3, 1.5)
	var h2 := d.place("jug", 0.3, 1.5)
	d.set_start(&"LH", h1); d.set_start(&"RH", h2)
	runner.check(d.warnings().is_empty(), "문제 없으면 빈 목록 %s" % [d.warnings()])
	var far := d.place("jug", 0.0, 3.2)
	d.place("goal", 0.0, 3.6)
	var w: Array = d.warnings()
	runner.check(w.any(func(x): return x.hold == far and String(x.text).contains("닿기 어려")), "아래 손홀드에서 1.2m 넘게 먼 홀드 %s" % [w])
	d.set_wall(2, 80)
	runner.check(d.warnings().any(func(x): return String(x.text).contains("천장")), "70° 넘는 구간(110° 이하)")
	d.place("jug", 0.5, 5.0)
	runner.check(d.warnings().any(func(x): return String(x.text).contains("탑보다 높은")), "탑보다 높은 홀드")


## 벽 모양(2026-11-27 사용자 "사람들이 어떻게 만들지 몰라 되게 다양한 case의 벽을 만들어서 하나씩 테스트해봐"): 1m마다 각도를 이어
## 만들 수 없는 벽 — 바닥 밑으로 내려감(300° 연속), 자기 자신을 가로지름(천장↔300° 번갈아), 바닥에 붙은 천장(바닥부터 90°) — 은 막는다.
## 가파른·누운·계단·지그재그처럼 실제로 있을 수 있는 벽은 막지 않는다.
func test_wall_shape_problems() -> void:
	var make := func(walls: Array) -> RouteDraft:
		var d := RouteDraft.new()
		for m in walls.size():
			d.set_wall(m, walls[m])
		d.place("jug", 0.0, 5.0, "top")
		return d
	for bad in [[[0, -120, -120, -120, -120, -120], "바닥"], [[0, 90, -120, 90, -120, 90, -120], "구간"], [[-120, -120, 0], "바닥"], [[90, 90, 0], "천장"]]:
		var iss: Dictionary = make.call(bad[0]).wall_issue()
		runner.check(not iss.is_empty() and str(iss.text).contains(bad[1]) and make.call(bad[0]).problems().has(iss.text), "%s: 막음 %s" % [bad[0].map(func(w): return 180 - w), iss])
	for ok in [[0], [0, 90, 90, 90, 90, 90], [0, 60, -60, 60, -60, 60], [0, 15, 30, 45, 60, 75, 90], [0, -20, -40, -60, -80, -100],
			[0, -90, 0, -90, 0, -90], [0, 90, 0, 90, 0, 90], [0, 90, 90, -90, -90, 0], [-60, 0], [45, 45, 0], [0, 0, 0, -120]]:
		runner.check(make.call(ok).wall_issue().is_empty(), "%s: 막지 않음 %s" % [ok.map(func(w): return 180 - w), make.call(ok).wall_issue()])



## 봇 길 찾기는 자세마다 그 높이의 벽 각도로 판정한다(2026-11-27 벽 모양 점검: 탐색이 문제의 가장 가파른 각도 하나로 모든 자세를
## 판정해, 천장 구간이 하나만 있어도 바닥 수직 구간에서 바로 포기했다 — 만들기 [봇으로 확인]).
func test_explorer_uses_angle_per_height() -> void:
	var d := RouteDraft.new()
	d.route_id = "U_R"
	d.name = "r"
	var ids := [d.place("jug", -0.3, 1.5), d.place("jug", 0.3, 1.5), d.place("crimp", -0.15, 0.1, "foot"), d.place("crimp", 0.18, 0.1, "foot")]
	for i in 4:
		d.set_start([&"LH", &"RH", &"LF", &"RF"][i], ids[i])
	d.place("jug", 0.0, 1.7, "top")
	d.set_wall(0, 0)
	d.set_wall(3, 90)  # 탑보다 위의 천장: 오르는 곳은 모두 수직
	var r := d.build()
	runner.check(r.wall_deg == 90.0 and r.angle_at(1.7) == 0.0, "재현 조건: 가장 가파른 구간 90°, 오르는 곳은 수직")
	runner.check(PathExplorer.explore(r, {}, false, 8000).ok, "수직인 곳만 오르면 봇이 길을 찾음")


## 가파른 오버행에서도 [봇으로 확인]이 길을 찾는다(2026-11-28: 계획이 관절 한계 경계의 수를 세워 재생에서 막히고, 다익스트라라
## 다시 찾을 시간이 없었다 → 방향 여유 4°, 남은 높이 추정(A*), 세 접점 결과 재사용, 못 닿으면 몸을 옮겨 한 번 더).
func test_explorer_steep_overhang() -> void:
	var d := RouteDraft.new()
	d.route_id = "U_R"
	d.name = "r"
	var ids := [d.place("jug", -0.3, 1.5), d.place("jug", 0.3, 1.5), d.place("crimp", -0.15, 0.1, "foot"), d.place("crimp", 0.18, 0.1, "foot")]
	for i in 4:
		d.set_start([&"LH", &"RH", &"LF", &"RF"][i], ids[i])
	for f in [[-0.2, 0.55], [0.2, 0.55], [-0.2, 0.95], [0.2, 0.95]]:
		d.place("crimp", f[0], f[1], "foot", "L")
	for y in [1.95, 2.4, 2.85, 3.3]:
		d.place("jug", -0.3, y, "hand", "L")
		d.place("jug", 0.3, y, "hand", "L")
	d.place("jug", 0.0, 3.75, "top", "L")
	d.set_wall(0, 0)
	d.set_wall(2, 45)
	var ex := PathExplorer.explore(d.build(), {}, false, 25000)
	runner.check(ex.ok, "2m부터 45° 오버행: 봇이 탑까지 %s" % [ex.log.slice(-1)])
