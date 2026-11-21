extends RefCounted
## 표현 전용 낙하·착지 장면(docs/superpowers/specs/2026-11-19-1-feel-design.md §1.2, 2026-11-20 사용자:
## "높은곳이 아니면 매트가 충격을 흡수해서 무릎이 구부러졌다가 서있게"). 어느 높이든 끝에는 서 있다.

var runner

const MAT := -0.075
const WALL := 0.02


## 벽에 매달린 자세(골반 pelvis_y, 벽에서 0.28m)의 그림 목표 점들. tilt: 몸이 옆으로 기운 각(도).
func _pose(pelvis_y := 1.2, tilt := 0.0) -> Dictionary:
	var p := Vector3(0, pelvis_y, 0.28)
	var off := {"pelvis": Vector3.ZERO, "spine": Vector3(0, 0.16, 0), "chest": Vector3(0, 0.37, 0), "neck": Vector3(0, 0.49, 0),
		"head": Vector3(0, 0.56, 0), "head_top": Vector3(0, 0.81, 0)}
	for s in ["L", "R"]:
		var x := -1.0 if s == "L" else 1.0
		off["shoulder_" + s] = Vector3(0.175 * x, 0.49, -0.05)
		off["elbow_" + s] = Vector3(0.3 * x, 0.75, -0.15)
		off["wrist_" + s] = Vector3(0.3 * x, 1.0, -0.2)
		off["hand_" + s] = Vector3(0.3 * x, 1.08, -0.2)
		off["hip_" + s] = Vector3(0.095 * x, 0.0, 0)
		off["knee_" + s] = Vector3(0.2 * x, -0.4, -0.1)
		off["ankle_" + s] = Vector3(0.2 * x, -0.82, -0.15)
		off["toe_" + s] = Vector3(0.2 * x, -0.84, -0.25)
	var t := {}
	for k in off:
		t[k] = p + (off[k] as Vector3).rotated(Vector3.BACK, deg_to_rad(tilt))
	return t


func _run(sim: FallSim, seconds: float, dt := 1.0 / 60.0) -> void:
	for i in int(round(seconds / dt)):
		sim.step(dt)


func _ok(pts: Dictionary) -> bool:
	for k in pts:
		var v: Vector3 = pts[k]
		if not (is_finite(v.x) and is_finite(v.y) and is_finite(v.z)) or v.y < MAT - 1e-3 or v.z < WALL - 1e-3:
			return false
	return true


func _sim(pelvis_y := 1.2, tilt := 0.0) -> FallSim:
	var sim := FallSim.new()
	sim.start(_pose(pelvis_y, tilt), Vector3.ZERO, {}, MAT, WALL)
	return sim


## 서 있음: 골반이 매트에서 서 있는 높이 가까이, 머리가 골반 위.
func _standing(sim: FallSim) -> bool:
	var p: Dictionary = sim.points()
	return (p.pelvis as Vector3).y > MAT + 0.7 and (p.head_top as Vector3).y > (p.pelvis as Vector3).y + 0.6


func test_kind_by_drop_height() -> void:
	runner.check(_sim(1.2).kind() == &"low", "발 0.5m 아래면 낮음 %s" % _sim(1.2).kind())
	runner.check(_sim(2.4).kind() == &"mid", "발 1.7m면 중간 %s" % _sim(2.4).kind())
	runner.check(_sim(3.4).kind() == &"high", "발 2.7m면 높음 %s" % _sim(3.4).kind())
	runner.check(_sim(1.2, 50.0).kind() == &"high", "몸이 크게 기울면 높이와 상관없이 높음 %s" % _sim(1.2, 50.0).kind())


func test_every_kind_ends_standing() -> void:
	for case in [[1.2, 0.0], [2.4, 0.0], [3.4, 0.0], [1.2, 50.0], [0.9, 0.0]]:
		var sim := _sim(case[0], case[1])
		var worst_ok := true
		for i in 60 * 5:
			sim.step(1.0 / 60.0)
			worst_ok = worst_ok and _ok(sim.points())
			if sim.done():
				break
		runner.check(sim.done(), "끝남 %s" % [case])
		runner.check(worst_ok, "모든 순간 매트 위·벽 앞·숫자 %s" % [case])
		runner.check(_standing(sim), "끝에는 서 있음 %s 골반 %s" % [case, sim.points().pelvis])


func test_low_crouches_then_stands() -> void:
	var sim := _sim(1.2)
	var lowest := 99.0
	var landed_at := -1.0
	for i in 60 * 4:
		sim.step(1.0 / 60.0)
		if sim.landed() and landed_at < 0.0:
			landed_at = sim.elapsed
		if sim.landed():
			lowest = minf(lowest, (sim.points().pelvis as Vector3).y)
		if sim.done():
			break
	runner.check(lowest < MAT + 0.75 and lowest > MAT + 0.4, "무릎을 굽혀 골반이 내려갔다(눕지 않음) %.2f" % lowest)
	runner.check(sim.elapsed - landed_at < 1.4, "착지 뒤 1.4초 안에 끝 %.2f" % (sim.elapsed - landed_at))


func test_high_lies_down_briefly() -> void:
	var sim := _sim(3.4)
	var lowest := 99.0
	var landed_at := -1.0
	for i in 60 * 6:
		sim.step(1.0 / 60.0)
		if sim.landed() and landed_at < 0.0:
			landed_at = sim.elapsed
		if sim.landed():
			lowest = minf(lowest, (sim.points().pelvis as Vector3).y)
		if sim.done():
			break
	runner.check(lowest < MAT + 0.25, "뒤로 굴러 골반이 매트 가까이 %.2f" % lowest)
	runner.check(sim.elapsed - landed_at > 1.8, "높으면 일어서기까지 더 길다 %.2f" % (sim.elapsed - landed_at))


func test_landing_keeps_lengths() -> void:
	var t := _pose(2.4)
	var sim := FallSim.new()
	sim.start(t, Vector3(0.3, 0, 0), {}, MAT, WALL)
	var worst := 0.0
	for i in 60 * 4:
		sim.step(1.0 / 60.0)
		if sim.landed() and sim.elapsed - sim.landed_at() > 0.2:
			for e in [["hip_L", "knee_L"], ["knee_L", "ankle_L"], ["shoulder_R", "elbow_R"], ["elbow_R", "wrist_R"], ["pelvis", "spine"], ["neck", "head"]]:
				var l0 := (t[e[0]] as Vector3).distance_to(t[e[1]])
				var l := (sim.points()[e[0]] as Vector3).distance_to(sim.points()[e[1]])
				worst = maxf(worst, absf(l - l0))
		if sim.done():
			break
	runner.check(worst < 0.02, "착지 동작 중 뼈 길이 오차 < 2cm (%.3f)" % worst)


func test_impact_reported_once() -> void:
	var sim := _sim(2.4)
	var got := []
	for i in 60 * 4:
		sim.step(1.0 / 60.0)
		var imp := sim.take_impact()
		if not imp.is_empty():
			got.append(imp)
	runner.check(got.size() == 1, "착지 사건 한 번 %d" % got.size())
	if got.size() == 1:
		runner.check(got[0].kind == &"mid" and absf((got[0].pos as Vector3).y - MAT) < 1e-4, "종류·매트 위치 %s" % [got[0]])


## 기기 프레임 수와 상관없이 같은 장면(작업 1 남긴 것: 프레임 의존).
func test_frame_rate_independent() -> void:
	var a := _sim(2.4)
	var b := _sim(2.4)
	_run(a, 1.5, 1.0 / 60.0)
	_run(b, 1.5, 1.0 / 30.0)
	var d := (a.points().pelvis as Vector3).distance_to(b.points().pelvis)
	runner.check(d < 0.01, "60fps와 30fps 골반 차이 < 1cm (%.4f)" % d)


func test_skip_ends_standing() -> void:
	var sim := _sim(3.4)
	_run(sim, 0.2)
	sim.skip()
	runner.check(sim.done(), "건너뛰면 끝")
	runner.check(_ok(sim.points()) and _standing(sim), "끝 자세는 서 있음")


func test_pinned_hand_holds_briefly() -> void:
	var t := _pose()
	var sim := FallSim.new()
	sim.start(t, Vector3.ZERO, {"hand_R": FallSim.RELEASE_DELAY, "wrist_R": FallSim.RELEASE_DELAY}, MAT, WALL)
	_run(sim, 0.08)
	runner.check((sim.points().pelvis as Vector3).distance_to(t.pelvis) < 1e-4, "남은 손을 놓기 전에는 매달려 있음")
	_run(sim, 0.3)
	runner.check((sim.points().pelvis as Vector3).y < (t.pelvis as Vector3).y - 0.05, "놓은 뒤 떨어짐")


## 뼈대 점이 아닌 값("up" 방향 등)은 점으로 다루지 않는다(작업 1 최종 검토 #7).
func test_ignores_non_skeleton_keys() -> void:
	var t := _pose()
	t["up"] = Vector3(0, 1, 0)
	var sim := FallSim.new()
	sim.start(t, Vector3.ZERO, {}, MAT, WALL)
	sim.step(1.0 / 60.0)
	runner.check(not sim.points().has("up"), "up은 점이 아님")


## 기운 벽(experiment/overhang): 45° 벽 아래로 떨어져 서면 몸 어느 점도 벽면 속에 있지 않다.
func test_overhang_landing_outside_wall() -> void:
	var sim := FallSim.new()
	var pts := {}
	for k in FallSim.NAMES:
		pts[k] = Vector3(0, 1.0 + 0.5 * FallSim.NAMES.find(k) / FallSim.NAMES.size(), 1.2)
	sim.start(pts, Vector3.ZERO, {}, -0.075, 0.02, 45.0)
	sim.skip()
	var inside := 0
	for k in sim.points():
		var p: Vector3 = sim.points()[k]
		if p.z < sim.wall_at(p.y) - 0.001:
			inside += 1
	runner.check(inside == 0, "45° 벽 아래 착지: 벽면 속 점 없음(%d)" % inside)
