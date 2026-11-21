extends RefCounted
## 벽 기울기 실험(experiment/overhang, docs/48 R2): 문제마다 벽 각도. 판정은 벽면 그대로, 힘만 기운다.

var runner


func _route(deg: float) -> RouteDef:
	var r := ContentIndex.load_all().route("G_V0_02")
	r.wall_deg = deg
	return r


func _hands(s: ClimbSession) -> float:
	var loads: Dictionary = s.rules.last.get("loads", {})
	return float(loads.get(&"LH", 0.0)) + float(loads.get(&"RH", 0.0))


func test_route_reads_wall_angle() -> void:
	var d := {"route_id": "X", "wall_angle_deg": 30}
	runner.check(is_equal_approx(RouteDef.from_dict(d).wall_deg, 30.0), "wall_angle_deg를 읽음")
	runner.check(RouteDef.from_dict({"route_id": "Y"}).wall_deg == 0.0, "없으면 수직")


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
func test_wall_angle_setting() -> void:
	var p := Progress.new()
	runner.check(int(p.control_get("wall_deg")) == 25, "기본 25°")
	p.set_control("wall_deg", 35)
	runner.check(int(p.control_get("wall_deg")) == 35, "35°로 바꿈")
	p.set_control("wall_deg", 20)
	runner.check(int(p.control_get("wall_deg")) == 35, "목록에 없는 각은 무시")
	var r := ContentIndex.load_all().route("G_V0_02")
	Progress.apply_wall_angle(r, p)
	runner.check(is_equal_approx(r.wall_deg, 35.0), "일반 문제에 적용")
	r.wall_deg = 0.0


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


## [시점]을 누르면 게임이 멈추고 손가락으로 시점을 돌린다(2026-11-22 사용자: "원하는 각도로 마음대로 손가락으로 조정").
## 한 손가락 끌기 = 좌우·위아래 돌리기, 두 손가락 벌리기 = 확대, [처음 시점] = 되돌리기, [완료] = 그 각도로 이어서.
func test_camera_edit_by_finger() -> void:
	var n: Node2D = preload("res://scenes/play_test.gd").new()
	n.route = _route(30.0)
	n.session = ClimbSession.new(n.route)
	var acts: Array = n._help_buttons().map(func(b): return b.action)
	runner.check(acts.has("view"), "기운 벽이면 시점 버튼")
	n._overlay_action("view")
	runner.check(n.cam_edit, "누르면 시점 조정")
	runner.check(n._help_buttons().map(func(b): return b.action).has("view_reset"), "처음 시점 버튼")
	_touch(n, 0, Vector2(800, 400), true)
	_drag(n, 0, Vector2(1000, 300))
	runner.check(absf(n.cam_yaw) > 0.2, "옆으로 끌면 좌우로 돎(%.2f)" % n.cam_yaw)
	runner.check(absf(n.cam_pitch) > 0.05, "위로 끌면 위아래로 돎(%.2f)" % n.cam_pitch)
	runner.check(n.session.limbs[&"LH"].state == "Attached", "시점 조정 중 터치는 패드로 가지 않음")
	_touch(n, 1, Vector2(1200, 300), true)
	_drag(n, 1, Vector2(1400, 300))
	runner.check(n.cam_zoom < 1.0, "두 손가락을 벌리면 가까이(%.2f)" % n.cam_zoom)
	_touch(n, 0, Vector2(1000, 300), false)
	_touch(n, 1, Vector2(1400, 300), false)
	var yaw: float = n.cam_yaw
	n._overlay_action("view")
	runner.check(not n.cam_edit and is_equal_approx(n.cam_yaw, yaw), "완료: 그 각도 그대로")
	n._overlay_action("view")
	n._overlay_action("view_reset")
	runner.check(n.cam_yaw == 0.0 and n.cam_pitch == 0.0 and n.cam_zoom == 1.0, "처음 시점으로")
	n.route.wall_deg = 0.0
	n.free()
