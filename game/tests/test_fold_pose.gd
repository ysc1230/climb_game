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


## 월드 점 w가 접힌 벽면 앞(+)·뒤(−)로 떨어진 거리(m). 벽면 선을 1cm마다 훑어 가장 가까운 곳의 법선 쪽 부호.
static func _wall_dist(f: WallProfile, w: Vector3, s_lo: float, s_hi: float) -> float:
	var best := INF
	var signed := 0.0
	var s := s_lo
	while s <= s_hi:
		var p := f.point(Vector3(w.x, s, 0.0))
		var d := Vector2(w.y - p.y, w.z - p.z).length()
		if d < best:
			best = d
			signed = (w - p).dot(f.basis_at(s) * Vector3(0, 0, 1))
		s += 0.01
	return signed


## 2026-11-27 사용자 "벽이 위에 있을때 손이 벽에 파고들고있어. 벽 각도가 저렇게 될 때는 저 각도에 맞춰서 벽과 특정 거리를 두고 손을 뻗도록":
## 위로 기운 벽(180° → 112° → 148°, 사용자 화면)·천장(180° → 95°)·앞으로 튀어나온 능선(120° → 240°, 벽 모양 점검)을 오르는 매 틱,
## 팔·다리 관절(팔꿈치·손목·손끝, 무릎·발목)과 몸통(가슴·목·머리, 능선에서 13cm 박혔음)이
## 벽면 뒤로 들어가지 않는다(1cm 여유). 고치기 전: 손끝 25~30cm, 팔꿈치 13~26cm.
func test_free_limbs_stay_out_of_wall() -> void:
	for walls in [[[0, 0], [1, 68], [2, 32]], [[0, 0], [1, 85]], [[0, 0], [1, 60], [2, -60], [3, 60]]]:
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
		var r := d.build()
		var f := WallProfile.new(r, -1.5, d.max_y() + 3.0)
		var cp := ClimberPose.new()
		var worst := {"d": INF, "at": "", "n": 0}
		# 발끝은 뺀다: 판정 자세(ClimberPose)에서부터 수직 벽에서도 벽 쪽으로 7~8cm 꺾일 때가 있다(따로 볼 것)
		var keys := ["elbow_L", "wrist_L", "hand_L", "elbow_R", "wrist_R", "hand_R", "knee_L", "ankle_L", "knee_R", "ankle_R", "chest", "neck", "head"]
		var on_tick := func(s: ClimbSession, _res) -> void:
			worst.n += 1
			if worst.n % 3 != 0:
				return
			var t := cp.compute(s, 1.0 / 20.0)
			var held := {}
			for l in PoseSolver.LIMBS:
				held[l] = s.limbs[l].state in ["Attached", "Armed"]
			var m: Dictionary = P3.climber_to_char(t, f, held)
			var fr := f.frame((t.pelvis as Vector3).y)
			for k in keys:
				var w: Vector3 = fr * (m[k] as Vector3)
				var dd := _wall_dist(f, w, -0.5, d.max_y() + 1.0)
				if dd < worst.d:
					worst.d = dd
					worst.at = "%s 틱 %d" % [k, worst.n]
		SessionBot.run(r, [["LF", "U_X/F06/foot_1"], ["LH", "U_X/H05/hand_1"], ["RH", "U_X/H07/hand_1"], ["LH", "U_X/H09/hand_1"]], {}, null, on_tick)
		runner.check(worst.n > 200 and worst.d > -0.01, "벽 %s: %d틱, 벽면에 가장 깊이 %.3fm (%s)" % [walls.map(func(w): return 180 - w[1]), worst.n, worst.d, worst.at])


