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
