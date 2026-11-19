extends RefCounted
## 표현 전용 낙하 인형(docs/superpowers/specs/2026-11-19-1-feel-design.md §1.2).

var runner

const MAT := -0.075
const WALL := 0.02


## 벽에 매달린 자세(골반 1.2m, 벽에서 0.28m)의 그림 목표 점들.
func _pose(pelvis_y := 1.2) -> Dictionary:
	var p := Vector3(0, pelvis_y, 0.28)
	var t := {"pelvis": p, "spine": p + Vector3(0, 0.16, 0), "chest": p + Vector3(0, 0.37, 0), "neck": p + Vector3(0, 0.49, 0),
		"head": p + Vector3(0, 0.56, 0), "head_top": p + Vector3(0, 0.81, 0)}
	for s in ["L", "R"]:
		var x := -1.0 if s == "L" else 1.0
		t["shoulder_" + s] = p + Vector3(0.175 * x, 0.49, -0.05)
		t["elbow_" + s] = p + Vector3(0.3 * x, 0.75, -0.15)
		t["wrist_" + s] = p + Vector3(0.3 * x, 1.05, -0.2)
		t["hand_" + s] = p + Vector3(0.3 * x, 1.12, -0.2)
		t["hip_" + s] = p + Vector3(0.095 * x, 0.0, 0)
		t["knee_" + s] = p + Vector3(0.25 * x, -0.3, -0.1)
		t["ankle_" + s] = p + Vector3(0.2 * x, -0.65, -0.2)
		t["toe_" + s] = p + Vector3(0.2 * x, -0.65, -0.1)
	return t


func _run(sim: FallSim, seconds: float) -> void:
	for i in int(seconds * 60.0):
		sim.step(1.0 / 60.0)


func _all_ok(sim: FallSim) -> bool:
	for k in sim.points():
		var v: Vector3 = sim.points()[k]
		if not (is_finite(v.x) and is_finite(v.y) and is_finite(v.z)) or v.y < MAT - 1e-3 or v.z < WALL - 1e-3:
			return false
	return true


func test_fallsim_lands_on_mat() -> void:
	var sim := FallSim.new()
	sim.start(_pose(), Vector3.ZERO, {}, MAT, WALL)
	_run(sim, 1.6)
	runner.check(sim.done(), "1.6초 안에 멈춤")
	runner.check(_all_ok(sim), "모든 점이 매트 위·벽 앞·숫자")
	runner.check((sim.points().pelvis as Vector3).y < 0.5, "골반이 바닥 가까이 %s" % sim.points().pelvis)


func test_fallsim_keeps_lengths() -> void:
	var t := _pose()
	var sim := FallSim.new()
	sim.start(t, Vector3(0.5, 0, 0), {}, MAT, WALL)
	var worst := 0.0
	for i in 90:
		sim.step(1.0 / 60.0)
		for e in FallSim.EDGES:
			var a: Vector3 = sim.points()[e[0]]
			var b: Vector3 = sim.points()[e[1]]
			var l0 := (t[e[0]] as Vector3).distance_to(t[e[1]])
			worst = maxf(worst, absf(a.distance_to(b) - l0))
	runner.check(worst < 0.02, "막대 길이 오차 < 2cm (%.3f)" % worst)


func test_fallsim_one_hand_swings() -> void:
	var t := _pose()
	var sim := FallSim.new()
	sim.start(t, Vector3.ZERO, {"hand_R": FallSim.RELEASE_DELAY, "wrist_R": FallSim.RELEASE_DELAY}, MAT, WALL)
	_run(sim, 0.1)
	runner.check((sim.points().hand_R as Vector3).distance_to(t.hand_R) < 1e-4, "0.1초까지 오른손 고정")
	runner.check((sim.points().hand_L as Vector3).y < (t.hand_L as Vector3).y, "왼손은 떨어짐")
	_run(sim, 0.3)
	runner.check((sim.points().hand_R as Vector3).y < (t.hand_R as Vector3).y - 0.05, "0.12초 뒤 오른손도 떨어짐")


func test_fallsim_edge_starts() -> void:
	for case in [[Vector3.ZERO, 1.2], [Vector3(0, -5, 0), 1.2], [Vector3.ZERO, 0.66]]:
		var sim := FallSim.new()
		sim.start(_pose(case[1]), case[0], {}, MAT, WALL)
		_run(sim, FallSim.MAX_TIME + 0.05)
		runner.check(sim.done(), "멈춤 %s" % [case])
		runner.check(_all_ok(sim), "숫자·매트·벽 %s" % [case])


func test_fallsim_skip_and_resume() -> void:
	var sim := FallSim.new()
	sim.start(_pose(), Vector3.ZERO, {}, MAT, WALL)
	_run(sim, 0.2)
	sim.skip()
	runner.check(sim.done(), "건너뛰면 끝")
	runner.check(_all_ok(sim), "끝 자세도 매트 위")


## 뼈대 점이 아닌 값("up" 방향 등)은 인형에 넣지 않는다(작업 1 최종 검토 #7).
func test_fallsim_ignores_non_skeleton_keys() -> void:
	var t := _pose()
	t["up"] = Vector3(0, 1, 0)
	var sim := FallSim.new()
	sim.start(t, Vector3.ZERO, {}, MAT, WALL)
	runner.check(not sim.points().has("up"), "up은 점이 아님")
