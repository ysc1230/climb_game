extends RefCounted
## 휴대폰 기울이기 → 몸 목표(docs/superpowers/specs/2026-11-19-2-tilt-design.md).

var runner


## 화면 기준 중력(x 오른쪽, y 위, z 화면 밖). 세워 든 휴대폰에서 좌우로 roll°, 위쪽을 앞으로 pitch° 숙임.
func _g(roll: float, pitch: float) -> Vector3:
	var r := deg_to_rad(roll)
	var p := deg_to_rad(pitch)
	return Vector3(sin(r), -cos(r) * cos(p), -cos(r) * sin(p)) * 9.8


## 같은 기울기를 충분히 오래(필터가 따라오게) 넣는다.
func _hold(m: TiltMapper, g: Vector3, frames := 120) -> Dictionary:
	var r := {}
	for i in frames:
		r = m.update(g)
	return r


func _mapper(sens := 3, dead := 3.0) -> TiltMapper:
	var m := TiltMapper.new()
	m.sensitivity = sens
	m.deadzone = dead
	m.update(_g(0, 30))  # 첫 값이 기준(30° 숙여 든 자세)
	return m


func test_inside_deadzone_is_zero() -> void:
	var m := _mapper()
	var r := _hold(m, _g(2.0, 32.0))
	runner.check(not r.active and (r.offset as Vector2) == Vector2.ZERO, "반응 시작 각도 안은 0 %s" % [r])


func test_axes_and_scale() -> void:
	var m := _mapper()
	var r := _hold(m, _g(10.0, 30.0))
	var want := (10.0 - 3.0) / 15.0 * Tuning.BODY_GOAL_MAX
	runner.check(r.active and absf((r.offset as Vector2).x - want) < 0.005 and absf((r.offset as Vector2).y) < 0.005, "오른쪽으로 10° → 오른쪽 %.3f %s" % [want, r])
	r = _hold(m, _g(0.0, 40.0))
	runner.check((r.offset as Vector2).y > 0.2 and absf((r.offset as Vector2).x) < 0.005, "위쪽을 앞으로 숙이면 위 %s" % [r])
	r = _hold(m, _g(-10.0, 20.0))
	runner.check((r.offset as Vector2).x < 0.0 and (r.offset as Vector2).y < 0.0, "왼쪽·뒤로 젖히면 왼쪽 아래 %s" % [r])


func test_sensitivity_ranges() -> void:
	for case in [[1, 25.0], [2, 20.0], [3, 15.0], [4, 11.0], [5, 8.0], [6, 6.5], [7, 5.0], [8, 4.0], [9, 3.0], [10, 2.5], [11, 2.5], [0, 25.0]]:
		runner.check(is_equal_approx(TiltMapper.range_deg(case[0]), case[1]), "민감도 %d → %.0f°" % case)
	var m := _mapper(5)
	var r := _hold(m, _g(40.0, 30.0))
	runner.check(is_equal_approx((r.offset as Vector2).x, Tuning.BODY_GOAL_MAX), "끝까지 기울이면 최대에서 멈춤 %s" % [r])


func test_filter_smooths() -> void:
	var m := _mapper(3, 0.0)
	var r := m.update(_g(10.0, 30.0))
	var full := 10.0 / 15.0 * Tuning.BODY_GOAL_MAX
	runner.check(absf((r.offset as Vector2).x - full * TiltMapper.FILTER) < 0.003, "한 프레임은 15%%만 따라감 %s" % [r])


func test_recalibrate() -> void:
	var m := _mapper()
	_hold(m, _g(10.0, 30.0))
	m.recalibrate()
	var r := _hold(m, _g(10.0, 30.0))
	runner.check(not r.active, "다시 맞추면 지금 기울기가 0 %s" % [r])


## 센서 값이 화면 회전을 따르지 않는 기기라면 두 가로 방향을 화면 기준으로 돌려 같은 결과.
func test_both_landscape_orientations() -> void:
	var gs := _g(12.0, 36.0)
	var dev := {DisplayServer.SCREEN_LANDSCAPE: Vector3(gs.y, -gs.x, gs.z), DisplayServer.SCREEN_REVERSE_LANDSCAPE: Vector3(-gs.y, gs.x, gs.z)}
	var outs := []
	for o in dev:
		var m := TiltMapper.new()
		m.screen_aligned = false
		m.orientation = o
		var g0 := _g(0, 30)
		m.update(Vector3(g0.y, -g0.x, g0.z) if o == DisplayServer.SCREEN_LANDSCAPE else Vector3(-g0.y, g0.x, g0.z))
		outs.append(_hold(m, dev[o]).offset)
	runner.check((outs[0] as Vector2).is_equal_approx(outs[1]) and (outs[0] as Vector2).x > 0.0, "정방향·뒤집힌 가로 같음 %s" % [outs])


func test_sensor_available() -> void:
	runner.check(not TiltMapper.available(Vector3.ZERO), "0이면 센서 없음")
	runner.check(TiltMapper.available(_g(0, 30)), "중력이 있으면 있음")
	var m := TiltMapper.new()
	var r := m.update(Vector3.ZERO)
	runner.check(not r.active and (r.offset as Vector2) == Vector2.ZERO, "센서 값이 없으면 움직이지 않음")
