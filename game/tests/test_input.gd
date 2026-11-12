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


## D패드(2026-11-13): 가운데를 누르면 준비(arm), 가운데 밖을 누르면 바로 떼고, 누르고 있는 동안 그 방향으로 계속 움직인다.
func test_stick_mode_moves_toward_pressed_direction() -> void:
	var r := InputRouter.new()
	r.stick_mode = true
	r.set_pad(&"LH", Vector2(100, 100), 200)
	runner.check(r.touch_down(0, Vector2(102, 101), true)[0].type == "arm", "가운데 누르면 준비")
	runner.check(r.tick(1.0 / 60.0, 0.0).is_empty(), "가운데에서는 안 움직임")
	var d := r.touch_drag(0, Vector2(195, 100), 0.0)
	runner.check(d.size() == 1 and d[0].type == "detach", "가운데를 벗어나면 뗀다")
	var total := Vector2.ZERO
	for i in 60:
		for c in r.tick(1.0 / 60.0, i / 60.0):
			total += c.delta
	runner.check(total.x > 0.9 and absf(total.y) < 0.001, "오른쪽으로 1초 → 약 %.2fm" % total.x)
	r.touch_drag(0, Vector2(100, 40), 1.0)
	var up := Vector2.ZERO
	for c in r.tick(0.5, 1.0):
		up += c.delta
	runner.check(up.y > 0.0 and absf(up.x) < 0.001, "화면 위로 기울이면 월드 위로")
	var u := r.touch_up(0, 1.1)
	runner.check(u[0].type == "release" and r.stick_knob(&"LH") == null, "떼면 놓기")
	runner.check(r.touch_down(1, Vector2(30, 100), true)[0].type == "detach", "붙은 손을 가장자리부터 누르면 바로 뗀다")
	var k = r.stick_knob(&"LH")
	runner.check(k != null and (k as Vector2).is_equal_approx(Vector2(-70, 0)), "손잡이 위치 %s" % [k])
