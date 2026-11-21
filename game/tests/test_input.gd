extends RefCounted
## docs/03 소유권 계약과 docs/10 IN·DT 일부.

var runner


func _router() -> InputRouter:
	var r := InputRouter.new()
	r.set_pad(&"LH", Vector2(100, 200), 160)
	r.set_pad(&"LF", Vector2(100, 600), 160)
	r.set_pad(&"RH", Vector2(1500, 200), 160)
	r.set_pad(&"RF", Vector2(1500, 600), 160)
	r.deadzone_px = 20
	return r


func test_in01_assignment_by_area_not_order() -> void:
	var r := _router()
	r.touch_down(7, Vector2(1500, 600), true)
	r.touch_down(3, Vector2(100, 200), true)
	runner.check(r.owner_of(7) == &"RF" and r.owner_of(3) == &"LH", "영역으로 배정")


func test_in03_ownership_kept_outside_pad() -> void:
	var r := _router()
	r.touch_down(1, Vector2(100, 200), true)
	var cmds := r.touch_drag(1, Vector2(1500, 600))
	runner.check(r.owner_of(1) == &"LH", "다른 패드로 가도 LH 유지")
	runner.check(cmds.all(func(c): return c.limb == &"LH"), "명령은 LH만")


func test_in05_second_touch_same_pad_and_center_ignored() -> void:
	var r := _router()
	r.touch_down(1, Vector2(100, 200), true)
	runner.check(r.touch_down(2, Vector2(110, 210), true).is_empty(), "같은 패드 두 번째 터치 무시")
	runner.check(r.touch_down(3, Vector2(800, 450), true).is_empty(), "중앙 터치 무시")
	r.touch_drag(3, Vector2(100, 600))
	runner.check(r.owner_of(3) == &"", "중앙 시작 터치는 패드로 와도 배정 안 함")


func test_dt01_deadzone_uses_straight_distance() -> void:
	var r := _router()
	r.touch_down(1, Vector2(100, 200), true)
	for i in 20:
		var cmds := r.touch_drag(1, Vector2(100, 200) + Vector2(15, 0).rotated(i))
		runner.check(cmds.is_empty(), "데드존 안 경로 누적으로 분리하지 않음")
	runner.check(r.touch_up(1)[0].type == "disarm", "데드존 안 release는 유지")


func test_dt02_excess_beyond_deadzone() -> void:
	var r := _router()
	r.deadzone_px = 20  # 문서 DT02: k=2, 데드존 10단위 = 20px, 지름 160단위 = 320px
	r.set_pad(&"LH", Vector2(100, 200), 320)
	r.touch_down(1, Vector2(100, 200), true)
	var cmds := r.touch_drag(1, Vector2(122, 200))
	runner.check(cmds[0].type == "detach", "데드존 넘으면 분리")
	runner.check(absf(cmds[1].delta.x - 0.00625) < 0.000001, "초과분 2px → 0.00625m, 실제 %f" % cmds[1].delta.x)


func test_in10_cancel_is_not_release() -> void:
	var r := _router()
	r.touch_down(1, Vector2(100, 200), false)
	var cmds := r.cancel_all()
	runner.check(cmds[0].type == "cancel", "취소는 cancel")
	runner.check(r.touch_up(1).is_empty(), "취소 뒤 늦은 up 무시")
	runner.check(r.touch_drag(1, Vector2(0, 0)).is_empty(), "취소 뒤 늦은 drag로 소유권 부활 없음")



## 패드 그림 손잡이(2026-11-13): 누른 손가락 위치(반지름 안으로 제한), 떼면 없음. 조작은 끌기 그대로.
func test_pad_knob_follows_finger() -> void:
	var r := InputRouter.new()
	r.set_pad(&"LH", Vector2(100, 100), 200)
	runner.check(r.knob(&"LH") == null, "안 누르면 없음")
	r.touch_down(0, Vector2(120, 100), true)
	r.touch_drag(0, Vector2(400, 100), 0.0)
	runner.check((r.knob(&"LH") as Vector2).is_equal_approx(Vector2(100, 0)), "반지름 안으로")
	r.touch_up(0, 0.1)
	runner.check(r.knob(&"LH") == null, "떼면 없음")


## 두 손가락 가운데 = 시점(오버행 실험, 2026-11-22 사용자: 오르면서 시점 돌리기). 한 손가락은 몸 옮기기 그대로,
## 가운데에 둘째 손가락이 오면 몸 옮기기를 끝내고 두 손가락 모두 시점: 같이 움직이면 cam_orbit(화면 px), 벌리면 cam_zoom(<1 가까이).
func _center_router() -> InputRouter:
	var r := InputRouter.new()
	r.body_area = Rect2(300, 100, 1000, 600)
	r.camera_enabled = true
	return r


func test_two_fingers_in_center_turn_camera() -> void:
	var r := _center_router()
	var a := r.touch_down(0, Vector2(700, 400), false, 0.0)
	runner.check(a.size() == 1 and a[0].type == "body_start", "한 손가락은 몸 옮기기")
	var b := r.touch_down(1, Vector2(900, 400), false, 0.05)
	var types: Array = b.map(func(c): return c.type)
	runner.check(types == ["body_end", "cam_start"], "둘째 손가락: 몸 옮기기 끝 + 시점 시작 %s" % [types])
	var m := r.touch_drag(0, Vector2(760, 380), 0.1).filter(func(c): return c.type == "cam_orbit")
	runner.check(m.size() == 1 and m[0].delta.x > 0.0, "움직이면 돌리기 %s" % [m])
	var z := r.touch_drag(1, Vector2(1100, 380), 0.15)
	var zoom: Array = z.filter(func(c): return c.type == "cam_zoom")
	runner.check(zoom.size() == 1 and zoom[0].ratio < 1.0, "벌리면 가까이 %s" % [z])
	runner.check(r.touch_up(0, 0.2).is_empty() and r.touch_up(1, 0.2).is_empty(), "시점 손가락 떼기는 명령 없음")
	var again := r.touch_down(2, Vector2(700, 400), false, 1.0)
	runner.check(again.size() == 1 and again[0].type == "body_start", "다시 한 손가락이면 몸 옮기기")


func test_camera_off_keeps_old_center_rules() -> void:
	var r := _center_router()
	r.camera_enabled = false
	r.touch_down(0, Vector2(700, 400), false, 0.0)
	runner.check(r.touch_down(1, Vector2(900, 400), false, 0.05).is_empty(), "시점 끔: 둘째 가운데 터치 무시(이전과 같음)")


func test_double_tap_still_dyno_with_camera() -> void:
	var r := _center_router()
	r.touch_down(0, Vector2(700, 400), false, 0.0)
	r.touch_up(0, 0.05)
	var d := r.touch_down(1, Vector2(700, 400), false, 0.12)
	runner.check(d.size() == 1 and d[0].type == "dyno_start", "두 번 톡은 다이노 그대로 %s" % [d])
