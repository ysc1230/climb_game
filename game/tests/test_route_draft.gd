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
