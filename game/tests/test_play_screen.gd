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
