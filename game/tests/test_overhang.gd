extends RefCounted
## 벽 기울기 실험(experiment/overhang, docs/48 R2): 문제마다 벽 각도. 판정은 벽면 그대로, 힘만 기운다.

var runner


func _route(deg: float) -> RouteDef:
	var r := RouteDef.load_json("res://tests/fixtures/G_V0_02.json")
	r.wall_deg = deg
	return r


func _hands(s: ClimbSession) -> float:
	var loads: Dictionary = s.rules.last.get("loads", {})
	return float(loads.get(&"LH", 0.0)) + float(loads.get(&"RH", 0.0))


## 벽 각도는 등급이 정한다(2026-11-22 사용자: "벽 기울기는 내가 정하는 게 아니라 기울기에 따라 난이도가 달라져야 해").
func test_grade_sets_wall_angle() -> void:
	var degs := []
	for g in ["V0", "V1", "V2", "V3", "V4", "V5", "V6", "V7"]:
		degs.append(GradeInfo.wall_deg(g))
	runner.check(degs == [0.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0], "등급별 각도 %s" % [degs])
	var r := RouteDef.from_dict({"route_id": "X", "mode": "general", "grade": "V5", "wall_angle_deg": 45})
	runner.check(is_equal_approx(r.wall_deg, 30.0), "일반 문제는 등급 각도(JSON 각도는 안 씀) %s" % r.wall_deg)
	runner.check(is_equal_approx(RouteDef.from_dict({"route_id": "M", "mode": "custom", "grade": "V3"}).wall_deg, 20.0), "만든 문제는 예상 등급 각도")
	runner.check(RouteDef.from_dict({"route_id": "C", "mode": "course", "grade": "V7"}).wall_deg == 0.0, "수업은 수직")
	runner.check(RouteDef.load_json("res://tests/fixtures/G_V7_01.json").wall_deg == 40.0, "실제 문제도 등급 각도")


## 같은 시작 자세에서 45° 벽은 손이 더 무겁다(시작은 바닥에 서 있어 쉬는 자세라 버틴다).
func test_tilt_loads_hands() -> void:
	var v := ClimbSession.new(_route(0.0))
	var o := ClimbSession.new(_route(45.0))
	for i in 120:
		v.step()
		o.step()
	runner.check(_hands(o) > _hands(v) + 0.15, "45°에서 손 하중 증가(%.2f → %.2f)" % [_hands(v), _hands(o)])
	runner.check(not o.falling, "바닥에 선 시작 자세로는 버팀")


## 봇이 같은 정답 순서로 오르면 기운 벽에서 손 힘이 더 많이 준다(발이 받는 몫 × cosθ, 손 사용률 증가).
func test_tilt_tires_hands_on_route() -> void:
	var v := RouteBot.run(_route(0.0))
	var o := RouteBot.run(_route(25.0))
	runner.check(v.ok(), "수직 완등")
	runner.check(o.min_stamina < v.min_stamina - 5.0 or not o.ok(), "25°에서 최저 손 힘이 더 낮음(%.0f vs %.0f, %s)" % [o.min_stamina, v.min_stamina, o.failure])
	runner.check(o.max_hand_u > v.max_hand_u, "25°에서 최대 손 사용률이 큼(%.2f vs %.2f)" % [o.max_hand_u, v.max_hand_u])


## 설정 "벽 기울기": 0·15·25·35·45° 중 하나(기본 25°, 실험 앱은 처음부터 기운 벽). 일반 문제에만 적용.
## 설정 "벽 기울기"는 없앴다(등급이 정함).
func test_no_wall_angle_setting() -> void:
	runner.check(not Progress.CONTROL_DEFAULTS.has("wall_deg"), "설정 기본값에 벽 기울기 없음")


## 홀드가 너무 많으면 안 된다(2026-11-22 사용자). 손홀드(정상 제외)·발 전용 홀드 수 상한, 높은 등급일수록 적게.
func test_general_routes_hold_caps() -> void:
	for r in ContentIndex.load_all().all_routes():
		if r.mode != "general":
			continue
		var m := PlacementMetrics.measure(r)
		runner.check(m.hand_holds <= GradeInfo.max_hands(r.grade) and m.foot_only <= GradeInfo.max_feet(r.grade),
			"%s %s 손 %d/%d 발 %d/%d" % [r.route_id, r.grade, m.hand_holds, GradeInfo.max_hands(r.grade), m.foot_only, GradeInfo.max_feet(r.grade)])


## 실험 앱은 모든 등급을 연다(2026-11-22 사용자). 테스트의 Progress.new()는 잠금 규칙 그대로.
func test_unlock_all() -> void:
	var idx := ContentIndex.load_all()
	var p := Progress.new()
	runner.check(not p.grade_unlocked("V7", idx), "기본은 잠금 규칙 그대로")
	p.unlock_all = true
	for g in ["V0", "V3", "V7"]:
		runner.check(p.grade_unlocked(g, idx), "%s 열림" % g)
	runner.check(not p.first_run_locked(idx), "첫 실행 잠금도 풀림")


func _touch(n: Node2D, index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	n._input(e)


func _drag(n: Node2D, index: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	n._input(e)


## 오르면서 가운데 두 손가락으로 시점을 돌린다(2026-11-22 사용자: 몸 옮기기와 겹치지 않게 조작 검토). 게임은 멈추지 않는다.
func test_two_finger_camera_while_climbing() -> void:
	var n: Node2D = preload("res://scenes/play_test.gd").new()
	n.route = _route(30.0)
	n.session = ClimbSession.new(n.route)
	n.router.body_area = Rect2(300, 100, 1000, 600)
	runner.check(not n._help_buttons().map(func(b): return b.action).has("view_reset"), "처음에는 [처음 시점] 없음")
	_touch(n, 0, Vector2(700, 400), true)
	_touch(n, 1, Vector2(900, 400), true)
	_drag(n, 0, Vector2(800, 330))
	_drag(n, 1, Vector2(1000, 330))
	runner.check(absf(n.cam_yaw) > 0.2 and absf(n.cam_pitch) > 0.1, "두 손가락을 같이 끌면 돎(%.2f, %.2f)" % [n.cam_yaw, n.cam_pitch])
	_drag(n, 1, Vector2(1200, 330))
	runner.check(n.cam_zoom < 1.0, "벌리면 가까이(%.2f)" % n.cam_zoom)
	_touch(n, 0, Vector2(800, 330), false)
	_touch(n, 1, Vector2(1200, 330), false)
	runner.check(n.router.active_limbs().is_empty(), "손가락을 떼면 시점 터치도 끝")
	runner.check(n._help_buttons().map(func(b): return b.action).has("view_reset"), "돌렸으면 [처음 시점]")
	n._overlay_action("view_reset")
	runner.check(n.cam_yaw == 0.0 and n.cam_pitch == 0.0 and n.cam_zoom == 1.0, "처음 시점으로")
	n.route.wall_deg = 0.0
	n.free()


## 홈 배경 그림(2026-11-22 사용자: "메인화면은 이걸로 바꿔줘"): 어떤 화면 비율이든 빈틈 없이 덮고 그림 비율은 그대로.
func test_home_key_art_covers_screen() -> void:
	var Home := load("res://scenes/home.gd")
	var art: Texture2D = Home.KEY_ART
	runner.check(art != null and art.get_width() > 0, "홈 배경 그림을 읽음")
	for size in [Vector2(1600, 720), Vector2(2400, 1080), Vector2(1600, 900), Vector2(1024, 768)]:
		var r: Rect2 = Home.cover_rect(Vector2(art.get_size()), size)
		var covers: bool = r.position.x <= 0.01 and r.position.y <= 0.01 and r.end.x >= size.x - 0.01 and r.end.y >= size.y - 0.01
		runner.check(covers, "%s 화면을 덮음" % size)
		runner.check(is_equal_approx(r.size.x / r.size.y, float(art.get_width()) / art.get_height()), "%s 그림 비율 그대로" % size)


## 홈 글꼴(2026-11-22 사용자 "밤티스러워 → 깔끔·세련·가독성"): 기기 글꼴 대신 넣은 SUIT(OFL). 굵기별로 다르고, 없는 글자는 기기 글꼴로.
func test_ui_font_weights() -> void:
	var r := UiFont.get_font(400)
	var b := UiFont.get_font(700)
	runner.check(r != null and b != null and r != b, "굵기마다 다른 글꼴")
	runner.check(UiFont.get_font(700) == b, "같은 굵기는 다시 만들지 않음")
	runner.check(r.get_string_size("완등", HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x > 0, "한글을 그림")
	var base: Font = (r as FontVariation).base_font
	runner.check(base.fallbacks.size() > 0 and base.fallbacks[0] is SystemFont, "없는 글자는 기기 글꼴")
