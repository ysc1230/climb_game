extends RefCounted
## 뒤로 누운 벽(2026-11-27 사용자 "벽 각도가 밑에 있을때는 절대 떨어질수없는 각도인데 떨어지게 돼. 중력의 영향을 받지않는것같아"):
## 누울수록 무게가 벽을 눌러 마찰로 붙잡힌다(벽면 안 무게 = cos − 마찰 × sin). 다 붙잡히는 각도부터는 손을 다 떼도 안 떨어진다.

var runner


func _route(walls: Array) -> RouteDef:
	var d := RouteDraft.new()
	d.route_id = "U_S"
	d.name = "s"
	var ids := [d.place("jug", -0.3, 2.0), d.place("jug", 0.3, 2.0), d.place("crimp", -0.15, 0.6, "foot"), d.place("crimp", 0.18, 0.6, "foot")]
	for i in 4:
		d.set_start([&"LH", &"RH", &"LF", &"RF"][i], ids[i])
	for i in 8:
		d.place(["jug", "crimp", "sloper"][i % 3], -0.5 + 0.14 * i, 1.0 + 0.3 * (i % 5), "hand" if i % 2 == 0 else "foot")
	d.place("jug", 0.0, 3.4, "top", "L")
	for w in walls:
		d.set_wall(w[0], w[1])
	return d.build()


func _release_hands(r: RouteDef) -> String:
	var s := ClimbSession.new(r)
	s.hold_on_fall = false
	for i in 20:
		s.step()
	s.apply_input([{"type": "detach", "limb": &"LH"}, {"type": "detach", "limb": &"RH"}])  # 두 손을 떼고 끄는 중(안 놓음)
	var res := ""
	for i in 300:
		res = s.step()
		if res != "":
			break
	return res


func test_no_hands() -> void:
	runner.check(_release_hands(_route([[0, 0]])).begins_with("fall:"), "수직 벽: 두 손을 떼면 떨어짐")
	for walls in [[[0, -60]], [[0, 0], [1, -90]], [[0, 0], [1, -119]]]:
		var res := _release_hands(_route(walls))
		runner.check(not res.begins_with("fall:"), "%s: 두 손을 떼도 안 떨어짐 '%s'" % [walls.map(func(w): return 180 - w[1]), res])


## 무작위로 손발·몸통을 움직여도 누운 벽에서는 떨어지지 않는다(고치기 전: 240°·270°·299° 모두 40번 중 40번 떨어짐).
func test_random_moves_never_fall() -> void:
	var rng := RandomNumberGenerator.new()
	for walls in [[[0, -60]], [[0, 0], [1, -90]], [[0, 0], [1, -119]]]:
		var r := _route(walls)
		var falls := 0
		for ep in 12:
			rng.seed = ep
			var s := ClimbSession.new(r)
			s.hold_on_fall = false
			for i in 20:
				s.step()
			var res := ""
			for act in 30:
				var l: StringName = PoseSolver.LIMBS[rng.randi() % 4]
				var dir := Vector2(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1)).normalized() * 0.03
				if rng.randf() < 0.25:
					s.apply_input([{"type": "body_start"}])
					for k in 15:
						s.apply_input([{"type": "body_move", "delta": dir}])
						res = s.step()
					s.apply_input([{"type": "body_end"}])
				else:
					s.apply_input([{"type": "detach", "limb": l}])
					for k in rng.randi_range(5, 25):
						s.apply_input([{"type": "move", "limb": l, "delta": dir}])
						res = s.step() if res == "" else res
					s.apply_input([{"type": "release", "limb": l, "speed": 0.0}])
				for k in 30:
					res = s.step() if res == "" else res
				if res.begins_with("fall:"):
					break
				res = ""
			falls += 1 if res.begins_with("fall:") else 0
		runner.check(falls == 0, "%s: 무작위 12번 중 떨어짐 %d" % [walls.map(func(w): return 180 - w[1]), falls])


## 90° 천장(2026-11-28): 실제 천장처럼 발을 걸어(토훅·힐훅) 몸을 당겨 버틴다. 예전에는 천장에서 발이 받는 힘이 0이라
## 손 하나를 떼면 남은 손이 체중 91%를 들고 문처럼 돌아 첫 손 옮기기에서 떨어졌다. 45°까지는 그대로(공식 문제).
func test_roof_climbable() -> void:
	var d := RouteDraft.new()
	d.route_id = "U_R"
	d.name = "r"
	var ids := [d.place("jug", -0.25, 2.3, "hand", "L"), d.place("jug", 0.25, 2.3, "hand", "L"), d.place("jug", -0.2, 1.4, "foot", "L"), d.place("jug", 0.2, 1.4, "foot", "L")]
	for i in 4:
		d.set_start([&"LH", &"RH", &"LF", &"RF"][i], ids[i])
	var a := d.place("jug", -0.25, 2.75, "hand", "L")
	var b := d.place("jug", 0.25, 2.75, "hand", "L")
	var c := d.place("jug", -0.2, 1.85, "foot", "L")
	var e := d.place("jug", 0.2, 1.85, "foot", "L")
	d.place("jug", 0.0, 3.2, "top", "L")
	d.set_wall(0, 0)
	d.set_wall(2, 90)
	var R := "U_R/"
	var bot := SessionBot.run(d.build(), [["LH", R + a + "/hand_1"], ["RH", R + b + "/hand_1"], ["LF", R + c + "/foot_1"], ["RF", R + e + "/foot_1"], ["LH", R + "G01/hand_1"], ["RH", R + "G01/hand_1"]])
	runner.check(bot.ok(), "천장에서 손발을 옮겨 탑까지 %s" % bot.failure)
	var att := {&"LH": Vector2(-0.3, 1.8), &"LF": Vector2(-0.2, 0.5), &"RF": Vector2(0.2, 0.5)}
	for deg in [45.0, 90.0]:
		ClimbRules.wall_deg = deg
		var rules := ClimbRules.new()
		rules.feet_eligible.assign([&"LF", &"RF"])
		rules.loaded_feet.assign([&"LF", &"RF"])
		var r := rules.evaluate(Vector2(0.0, 1.0), 0.0, att, {&"RH": Vector2(0.2, 1.2)}, false, [&"LF", &"RF"])
		if deg == 45.0:
			runner.check(absf(r.u[&"LH"] - 0.48) < 0.01, "45°는 그대로(한 손 부담 %.2f)" % r.u[&"LH"])
		else:
			runner.check(r.status == SupportSolver.Status.FEASIBLE and r.u[&"LH"] < 0.8 and not r.barn.exceeded and r.u[&"LF"] > 0.05, "90°: 한 손 + 두 발 버팀 %s" % [r.u])
	ClimbRules.wall_deg = 0.0


## 누운 벽에 기대 있으면 손이 쉰다(2026-11-28 벽 모양 재점검: 하중이 0이라 발이 받치는 몫도 0으로 쳐 "팔로만 매달림"처럼 손 힘이
## 초당 20씩 빠졌다 — 턱 계단에서 봇이 1~2수 만에 손 힘 소진).
func test_resting_hands_recover() -> void:
	var src: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/routes/general/G_V0_11.json"))
	src.wall_sections = [{"from_y": 0.0, "deg": -90.0}]
	var s := ClimbSession.new(RouteDef.from_dict(src))
	for i in 30:
		s.step()
	s.rules.stamina[&"LH"] = 60.0
	s.rules.stamina[&"RH"] = 60.0
	s.apply_input([{"type": "detach", "limb": &"RH"}])  # 한 손을 떼고 버팀(예전엔 남은 손이 빨리 지침)
	for i in 180:
		s.step()
	runner.check(ClimbRules.resting_on_wall() and s.rules.stamina[&"LH"] >= 55.0, "누운 벽에 기대 다른 손을 끄는 3초: 남은 손 힘 %.1f(60에서, 다른 손이 움직이는 동안이라 조금 빠짐)" % s.rules.stamina[&"LH"])
