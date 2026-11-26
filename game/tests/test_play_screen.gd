extends RefCounted
## 플레이 화면 흐름(작업 1 최종 검토 지적): 루트 읽기·축하 중 일시정지, [다시] 뒤 패드, 낙하 장면 건너뛰기, 경고 남음.
## 테스트 실행기 안에서는 트리가 돌지 않아 _ready를 쓰지 않고, 흐름 필드와 처리 함수만 직접 부른다.

var runner
const PlayTest := preload("res://scenes/play_test.gd")


func _make() -> Node2D:
	var n: Node2D = PlayTest.new()
	n.route = RouteDef.load_json("res://tests/fixtures/G_V3_03.json")
	n.session = ClimbSession.new(n.route)
	return n


func _release(n: Node2D, index: int) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = Vector2(800, 400)
	e.pressed = false
	n._input(e)


func _press(n: Node2D, index: int) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = Vector2(800, 400)
	e.pressed = true
	n._input(e)


func test_pause_refused_during_preview() -> void:
	var n := _make()
	n.route_preview = RoutePreview.new(3.0, 1.0)
	n._pause()
	runner.check(not n.paused, "루트 읽기 중에는 일시정지하지 않음(갇힘 방지)")
	n.free()


func test_pause_refused_during_celebration() -> void:
	var n := _make()
	n.celebrate_left = 1.0
	n._pause()
	runner.check(not n.paused, "축하 중에는 일시정지하지 않음")
	n.free()


func test_release_reaches_swallow_during_preview() -> void:
	var n := _make()
	n._swallow[0] = true  # [다시]를 누른 손가락
	n.route_preview = RoutePreview.new(3.0, 1.0)
	_release(n, 0)
	runner.check(not n._swallow.has(0), "루트 읽기 중에 온 뗌도 삼킴 표시를 지움")
	n.free()


func test_fall_skip_only_with_fall_scene() -> void:
	var n := _make()
	n.session.hold_on_fall = false  # 튜토리얼
	n.session.falling = true
	_press(n, 0)
	runner.check(not n.fall_skip, "낙하 장면이 없으면 건너뛰기 표시 안 함")
	n.free()


## 떨어지기 시작한 직후(잡으려고 패드를 누르는 순간)의 터치는 건너뛰기가 아님. 낙하 판정이 끝난 뒤 누르면 건너뜀(2026-11-21 사용자).
func test_fall_skip_ignores_taps_while_falling() -> void:
	var n := _make()
	n.session.hold_on_fall = true
	n.session.falling = true
	_press(n, 0)
	runner.check(not n.fall_skip, "떨어지는 중 터치는 건너뛰지 않음")
	n.session.falling = false
	n.session.halted = &"fall"
	_press(n, 1)
	runner.check(n.fall_skip, "낙하 판정이 끝난 뒤 터치는 건너뜀")
	n.free()


func test_fall_retry_clears_state() -> void:
	var n := _make()
	n.fall_skip = true
	n.paused = true
	n.grip_level[PoseSolver.LH] = GripWarning.DANGER
	n._fall_retry()
	runner.check(not n.fall_skip, "건너뛰기 표시 지움")
	runner.check(not n.paused, "다시 시작하면 일시정지 풀림")
	runner.check(n.grip_level[PoseSolver.LH] == GripWarning.NONE, "손 힘 경고 지움")
	n.free()


## 조언 카드가 뜨고 FALL_AUTO_RETRY초가 지나면 누르지 않아도 처음부터 다시(2026-11-21 사용자).
func test_fall_card_auto_retry() -> void:
	var n := _make()
	n._fall_advice = {"cause": "떨어졌어요", "advice": ""}
	n.on_fall_scene_done()
	n.session.falls = 1
	n._fall_card_tick(n.FALL_AUTO_RETRY - 0.5)
	runner.check(not n.overlay.fall_card.is_empty(), "시간 전에는 카드 그대로")
	n._fall_card_tick(1.0)
	runner.check(n.overlay.fall_card.is_empty(), "시간이 지나면 저절로 다시")
	n.free()


## 높은 곳에서 떨어지면 조언 카드에 안전 팁 한 줄(2026-11-20 사용자). 낮으면 없음.
func test_landing_tip_only_when_high() -> void:
	var n := _make()
	n._fall_advice = {"cause": "떨어졌어요", "advice": ""}
	n.on_landing(&"low")
	runner.check(not n._fall_advice.has("tip"), "낮으면 팁 없음")
	n.on_landing(&"high")
	runner.check(str(n._fall_advice.get("tip", "")).contains("뒤로 구르"), "높으면 뒤로 구르기 팁 %s" % [n._fall_advice])
	n.free()


func _tilt_progress(with_drag := true) -> Progress:
	var p := Progress.new()
	p.set_control("body", "tilt")
	p.set_control("tilt_with_drag", with_drag)
	return p


## 휴대폰 기울이기(작업 2): 설정이 기울이기면 센서 값이 판정 입구(body_goal)로 간다.
func test_tilt_drives_body_goal() -> void:
	var n := _make()
	n._setup_tilt(_tilt_progress())
	runner.check(n.tilt != null, "기울이기 설정이면 TiltMapper를 만듦")
	var up := Vector3(0, -9.8, 0).rotated(Vector3.RIGHT, deg_to_rad(-30))
	n._tilt_tick(up)
	var side := up.rotated(Vector3.BACK, deg_to_rad(12))
	for i in 120:
		n._tilt_tick(side)
	runner.check(n.session.rules.body_goal.is_finite(), "기울이면 몸 목표가 생김 %s" % n.session.rules.body_goal)
	n.session.falling = true
	n.session.rules.body_goal = Vector2(NAN, NAN)
	n._tilt_tick(side)
	runner.check(not n.session.rules.body_goal.is_finite(), "떨어지는 중에는 무시")
	n.free()


func test_tilt_off_by_default() -> void:
	var n := _make()
	n._setup_tilt(Progress.new())
	runner.check(n.tilt == null, "기본(가운데 끌기)이면 기울이기 없음")
	n.free()


func test_tilt_only_drops_center_drag() -> void:
	var n := _make()
	n._setup_tilt(_tilt_progress(false))
	n._apply([{"type": "body_start", "limb": &"BODY"}])
	runner.check(not n.session.body_dragging(), "함께 쓰기를 끄면 가운데 끌기는 무시")
	n._setup_tilt(_tilt_progress(true))
	n._apply([{"type": "body_start", "limb": &"BODY"}])
	runner.check(n.session.body_dragging(), "함께 쓰기면 가운데 끌기도 됨")
	n.free()


## 작업 3: 시도 동안 점수 기록을 모으고, 결과에 점수·항목·도움이 실린다(게임 노드 없이).
func test_result_carries_score() -> void:
	var n := _make()
	n._new_attempt()
	for i in 30:
		var r: String = n.session.step()
		n._record_tick(r, 1.0 / 60.0)
	n._show_result()
	var res: Dictionary = n.overlay.result
	runner.check(res.has("score") and res.has("parts") and res.parts.has("energy") and not bool(res.helped), "결과에 점수 %s" % [res])
	n.free()


func test_rescue_marks_helped() -> void:
	var n := _make()
	n._new_attempt()
	n._mark_helped()
	n._show_result()
	runner.check(bool(n.overlay.result.helped), "자동 도움을 쓰면 도움 표시")
	n.free()


## 막혔을 때 도움: 3번 떨어지면 [힌트], 5번이면 [시범 보기]. 힌트를 켜면 그 시도는 도움.
func test_help_ladder_buttons() -> void:
	var n := _make()
	n._new_attempt()
	runner.check(n._help_buttons().is_empty(), "처음엔 없음")
	n.help_falls = 3
	var b: Array = n._help_buttons()
	runner.check(b.size() == 1 and b[0].action == "hint", "3번 → 힌트 %s" % [b])
	n.help_falls = 5
	runner.check(n._help_buttons().size() == 2, "5번 → 시범 보기도")
	n._hint_toggle()
	runner.check(n.hint_slot != "" and n.score_rec.helped, "힌트를 켜면 홀드가 생기고 도움 %s" % n.hint_slot)
	n._new_attempt()
	runner.check(n.hint_slot == "" and not n.score_rec.helped, "다음 시도는 다시 보통")
	n.free()


func test_demo_open_close() -> void:
	var n := _make()
	n._new_attempt()
	n._demo_open()
	runner.check(n.demo != null and n.overlay.blocking(), "시범 보기 중에는 게임이 멈춤")
	n._demo_tick(1.0)
	runner.check(n.demo_t > 0.9, "재생")
	n._demo_close()
	runner.check(n.demo == null and not n.overlay.blocking(), "닫으면 바로 도전")
	n.free()


## 탑을 두 손으로 잡으면 진행 바가 깃발까지 찬다(2026-11-25 사용자 "탑을 둘 다 잡으면 상단의 깃발 표시까지 도달해야 해").
## 바는 골반이 오른 높이인데, 탑을 잡아도 골반은 목표 높이의 70~85%만 올라 깃발에 못 닿았다(V0 첫 문제 71%).
func test_bar_reaches_flag_on_top() -> void:
	var n: Node2D = preload("res://scenes/play_test.gd").new()
	n.route = RouteDef.load_json("res://tests/fixtures/G_V0_02.json")
	n.session = ClimbSession.new(n.route)
	runner.check(n._height() < n._goal_height(), "시작에서는 깃발 아래")
	n.session.halted = &"clear"
	runner.check(is_equal_approx(n._height(), n._goal_height()), "완등하면 깃발까지 %.2f / %.2f" % [n._height(), n._goal_height()])
	n.free()


## 위쪽 진행 바 표시(2026-11-24 사용자 "1,6번만"): 벽 경사 구간과 떨어졌던 높이를 바 위치(0~1)로.
## 바는 시작 골반에서 목표 높이까지라, 구간 시작 높이·떨어진 골반 높이도 같은 기준으로 바꾼다.
func test_bar_marks_walls_and_falls() -> void:
	var r := RouteDef.load_json("res://tests/fixtures/G_V5_03.json")  # 30° → 1.5m부터 60°
	var g: float = PlayTest.goal_height_of(r)
	var m: Dictionary = PlayTest.bar_marks(r, [r.start_pelvis.y + g * 0.5, r.start_pelvis.y - 1.0, r.start_pelvis.y + g * 2.0])
	runner.check(m.walls.size() == 2 and m.walls[0] == [0.0, 30] and is_equal_approx(m.walls[1][0], (1.5 - r.start_pelvis.y) / g) and m.walls[1][1] == 60, "구간: 처음 30°, 1.5m부터 60° %s" % [m.walls])
	runner.check(m.falls.size() == 3 and is_equal_approx(m.falls[0], 0.5) and m.falls[1] == 0.0 and m.falls[2] == 1.0, "떨어진 높이 → 바 위치(0~1로 자름) %s" % [m.falls])
	var one := RouteDef.load_json("res://tests/fixtures/G_V4_02.json")
	runner.check(PlayTest.bar_marks(one, []).walls == [[0.0, roundi(one.wall_deg)]], "구간 없는 기운 벽은 각도 하나")
	var flat := RouteDef.load_json("res://tests/fixtures/G_V0_02.json")
	runner.check(PlayTest.bar_marks(flat, []).walls.is_empty(), "수직 벽은 경사 표시 없음")


## 시작 골반보다 아래에서 시작하는 구간은 바 맨 앞에 겹쳐 그 각도 글자가 숨었다(2026-11-27 사용자 화면: 180°만 보이고 누운 턱은 안 보임).
## 시작 높이에서 이미 지난 구간은 빼고, 시작 높이의 구간이 바 맨 앞 각도다.
func test_bar_marks_skip_sections_below_start() -> void:
	var d := RouteDraft.new()
	d.route_id = "U_B"
	d.name = "b"
	var ids := [d.place("jug", -0.3, 2.0), d.place("jug", 0.3, 2.0), d.place("crimp", -0.15, 0.6, "foot"), d.place("crimp", 0.18, 0.6, "foot")]
	for i in 4:
		d.set_start([&"LH", &"RH", &"LF", &"RF"][i], ids[i])
	d.place("jug", 0.0, 3.4, "top", "L")
	d.set_wall(0, 0)
	d.set_wall(1, -90)
	d.set_wall(2, 16)
	var r := d.build()
	var m: Dictionary = PlayTest.bar_marks(r, [])
	runner.check(r.start_pelvis.y > 1.0 and m.walls.size() == 2 and m.walls[0] == [0.0, -90] and m.walls[1][1] == 16, "시작 %.2fm: 270°부터 %s" % [r.start_pelvis.y, m.walls])
