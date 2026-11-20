extends RefCounted
## 플레이 화면 흐름(작업 1 최종 검토 지적): 루트 읽기·축하 중 일시정지, [다시] 뒤 패드, 낙하 장면 건너뛰기, 경고 남음.
## 테스트 실행기 안에서는 트리가 돌지 않아 _ready를 쓰지 않고, 흐름 필드와 처리 함수만 직접 부른다.

var runner
const PlayTest := preload("res://scenes/play_test.gd")


func _make() -> Node2D:
	var n: Node2D = PlayTest.new()
	n.route = RouteDef.load_json("res://data/routes/general/G_V3_03.json")
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
