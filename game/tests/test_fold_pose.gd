extends RefCounted
## 접힌 벽 위 3D 몸(play_3d.climber_to_char). 2026-11-27 사용자 "거의 누워있는 벽에서 무게중심에 따라 캐릭터가 엄청 찌그러져",
## "다음 홀드를 향해 뻗으면 손가락이 엄청 늘어지는 문제 … 극단적인 각도의 문제들을 통해 이상한 부분이 없는지 프레임별로 확인해".
## 관절 점을 하나씩 접던 방식은 꺾인 곳에서 뼈 길이가 2배 넘게 바뀌었다. 이제 봇이 오르는 매 틱 팔다리 뼈 길이는 그대로,
## 잡은 손발은 홀드 위다.

var runner
const P3 := preload("res://scenes/play_3d.gd")
const LIMB_SEGS := [["shoulder_L", "elbow_L"], ["elbow_L", "wrist_L"], ["wrist_L", "hand_L"], ["shoulder_R", "elbow_R"], ["elbow_R", "wrist_R"], ["wrist_R", "hand_R"],
	["hip_L", "knee_L"], ["knee_L", "ankle_L"], ["ankle_L", "toe_L"], ["hip_R", "knee_R"], ["knee_R", "ankle_R"], ["ankle_R", "toe_R"],
	["pelvis", "spine"], ["spine", "chest"], ["chest", "neck"], ["neck", "head"]]


func _check_route(name: String, r: RouteDef, steps: Array, top: float) -> void:
	var f := WallProfile.new(r, -1.5, top + 3.0)
	var cp := ClimberPose.new()
	var worst := {"len": 0.0, "miss": 0.0, "n": 0}
	var on_tick := func(s: ClimbSession, _res) -> void:
		worst.n += 1
		var t := cp.compute(s, 1.0 / 60.0)
		var held := {}
		for l in PoseSolver.LIMBS:
			held[l] = s.limbs[l].state in ["Attached", "Armed"]
		var m: Dictionary = P3.climber_to_char(t, f, held)
		for sg in LIMB_SEGS:
			var nominal: float = (t[sg[0]] as Vector3).distance_to(t[sg[1]])
			if nominal > 0.01:
				worst.len = maxf(worst.len, absf((m[sg[0]] as Vector3).distance_to(m[sg[1]]) / nominal - 1.0))
		var fi := f.frame((t.pelvis as Vector3).y).affine_inverse()
		for l in PoseSolver.LIMBS:
			if held[l]:
				var e: String = ("wrist_" if PoseSolver.is_hand(l) else "ankle_") + ("L" if PoseSolver.side_sign(l) < 0 else "R")
				worst.miss = maxf(worst.miss, (m[e] as Vector3).distance_to(fi * f.point(t[e])))
	SessionBot.run(r, steps, {}, null, on_tick)
	runner.check(worst.n > 300 and worst.len < 0.01 and worst.miss < 0.04, "%s: %d틱, 팔다리·몸통 뼈 길이 변화 최대 %.1f%%, 잡은 손발 홀드에서 최대 %.3fm" % [name, worst.n, worst.len * 100, worst.miss])


## 사용자 화면의 벽(180° → 245° → 148°)과 더 심한 꺾임(135° → 240° → 100°, 180° → 300°).
func test_extreme_folds_keep_body() -> void:
	for walls in [[[0, 0], [1, -65], [2, 32]], [[0, 45], [1, -60], [2, 80]], [[0, 0], [1, -120]]]:
		var d := RouteDraft.new()
		d.route_id = "U_X"
		d.name = "x"
		var ids := [d.place("jug", -0.3, 1.5), d.place("jug", 0.3, 1.5), d.place("crimp", -0.15, 0.1, "foot"), d.place("crimp", 0.18, 0.1, "foot")]
		for i in 4:
			d.set_start([&"LH", &"RH", &"LF", &"RF"][i], ids[i])
		for i in 6:
			d.place("jug", -0.3 if i % 2 == 0 else 0.3, 1.9 + i * 0.4, "hand", "L")
			d.place("jug", 0.0, 0.5 + i * 0.4, "foot", "M")
		d.place("jug", 0.0, 4.5, "top", "L")
		for w in walls:
			d.set_wall(w[0], w[1])
		var steps := [["LF", "U_X/F06/foot_1"], ["LH", "U_X/H05/hand_1"], ["RH", "U_X/H07/hand_1"]]
		_check_route("벽 %s" % [walls.map(func(w): return 180 - w[1])], d.build(), steps, d.max_y())


## 공식 문제 중 꺾이는 벽(물결·동굴 입구·비탈에서 지붕으로)을 끝까지.
func test_official_folds_keep_body() -> void:
	for id in ["G_V4_11", "G_V6_11", "G_V7_11"]:
		var r := RouteDef.load_json(ContentIndex.route_path(id))
		_check_route(id, r, r.intended_moves, ScoreCalc.top_y(r) + 2.5)
