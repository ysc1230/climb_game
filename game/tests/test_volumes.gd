extends RefCounted
## 볼륨(2026-11-28 사용자 "세로로도 구분하여 특정 영역의 벽의 각도를 조정해서 튀어나온 볼륨처럼", "어 둘다야 어떤 케이스든
## 사람들이 만들어서 트집을 잡을거야"): 벽에 붙이는 상자·삼각(쐐기). 면에 홀드를 달고(깊이·기울기), 모서리 자체를 잡고 딛는다.

var runner
const P3 := preload("res://scenes/play_3d.gd")


func test_shape_geometry() -> void:
	var box := Volumes.make("V01", "box", 0.0, 2.0, "M", 0)
	runner.check(is_equal_approx(Volumes.side(box), 0.5) and is_equal_approx(Volumes.depth(box), 0.3), "보통 상자 0.5m·두께 0.3m")
	runner.check(is_equal_approx(Volumes.depth_at(box, Vector2(0.1, 2.1)), 0.3) and Volumes.depth_at(box, Vector2(0.3, 2.0)) == 0.0, "상자 안은 앞면 깊이, 밖은 0")
	runner.check(Volumes.normal_at(box, Vector2(0, 2)).is_equal_approx(Vector3(0, 0, 1)), "상자 앞면은 벽과 나란")
	var up := Volumes.make("V02", "wedge", 0.0, 2.0, "M", 0)  # 두꺼운 쪽 위
	runner.check(is_equal_approx(Volumes.depth_at(up, Vector2(0, 1.76)), 0.3 * 0.02) and is_equal_approx(Volumes.depth_at(up, Vector2(0, 2.24)), 0.3 * 0.98), "삼각: 아래 얇고 위 두꺼움")
	var n := Volumes.normal_at(up, Vector2(0, 2))
	runner.check(n.y < -0.4 and n.z > 0.8, "위가 두꺼운 삼각 면은 아래를 봄 %s" % n)
	var right := Volumes.make("V03", "wedge", 0.0, 2.0, "M", 90)
	runner.check(Volumes.depth_at(right, Vector2(0.2, 2.0)) > Volumes.depth_at(right, Vector2(-0.2, 2.0)), "90°: 오른쪽이 두꺼움")


## 모서리 칸: 상자는 네 모서리(위 당기기·옆 사이드풀·아래 언더), 삼각은 두꺼운 모서리와 양옆. 모서리 방향 = 볼륨 바깥.
func test_edges() -> void:
	var box := Volumes.make("V01", "box", 0.0, 2.0, "M", 0)
	var e := Volumes.edges(box)
	runner.check(e.size() == 4, "상자 모서리 4")
	for x in e:
		var axis := HoldTypes.rotate(Vector2(0, 1), x.rot)
		var out: Vector2 = ((x.pos as Vector2) - Vector2(0, 2)).normalized()
		runner.check(axis.dot(out) > 0.99 and is_equal_approx(float(x.depth), 0.3), "%s: 바깥을 봄 %s, 깊이 %.2f" % [x.slot_id, axis, x.depth])
	var w := Volumes.edges(Volumes.make("V02", "wedge", 0.0, 2.0, "M", 180))  # 두꺼운 쪽 아래
	runner.check(w.size() == 3 and w.any(func(x): return x.slot_id == "edge_b" and is_equal_approx(float(x.depth), 0.3)), "삼각: 두꺼운 아래 모서리 + 양옆 %s" % [w.map(func(x): return x.slot_id)])


func _draft() -> RouteDraft:
	var d := RouteDraft.new()
	d.route_id = "U_V"
	d.name = "볼륨"
	var ids := [d.place("jug", -0.3, 1.5), d.place("jug", 0.3, 1.5), d.place("crimp", -0.15, 0.1, "foot"), d.place("crimp", 0.18, 0.1, "foot")]
	for i in 4:
		d.set_start([&"LH", &"RH", &"LF", &"RF"][i], ids[i])
	d.place("jug", 0.0, 3.0, "top")
	return d


## 초안: 놓기·옮기기(위 홀드도 같이)·바꾸기·지우기·되돌리기·저장. 문제 데이터에 볼륨과 모서리 칸이 들어간다.
func test_draft_volumes() -> void:
	var d := _draft()
	var v := d.place_volume("box", 0.0, 2.2, "M")
	runner.check(v == "V05" and d.volumes.size() == 1, "볼륨 id %s" % v)
	var on := d.place("crimp", 0.1, 2.3)
	d.move_volume(v, 0.2, 2.4)
	runner.check(is_equal_approx(d.volume(v).x, 0.2) and is_equal_approx(d.hold(on).x, 0.3) and is_equal_approx(d.hold(on).y, 2.5), "볼륨을 옮기면 위의 홀드도 같이 %s" % d.hold(on))
	d.move_volume(v, 0.95, 2.4)
	runner.check(is_equal_approx(d.volume(v).x, 0.75), "벽 밖으로 안 나감(가운데 0.75 = 벽 끝 − 반 변) %.2f" % d.volume(v).x)
	d.set_volume(v, "wedge", "L", 90)
	runner.check(d.volume(v).shape == "wedge" and d.volume(v).size == "L" and int(d.volume(v).rot) == 90, "모양·크기·방향 바꿈")
	d.undo()
	runner.check(d.volume(v).shape == "box", "되돌리기")
	var r := d.build()
	runner.check(r.errors.is_empty() and r.volumes.size() == 1, "문제 데이터에 볼륨 %s" % [r.errors])
	var edge_keys := r.slots.keys().filter(func(k): return String(k).contains("/%s/edge_" % v))
	runner.check(edge_keys.size() == 4 and edge_keys.all(func(k): return r.slots[k].hold_type == &"volume" and r.slots[k].hand_area.matchable), "모서리 칸 4, 합손 %s" % [edge_keys])
	var back := RouteDraft.from_dict(d.to_dict())
	runner.check(back.volumes == d.volumes and d.to_dict().schema == 3, "저장·불러오기(공유 판 3)")
	d.remove_volume(v)
	runner.check(d.volumes.is_empty() and not d.hold(on).is_empty(), "지워도 위의 홀드는 벽에 남음")
	runner.check(d.place("volume", 0, 2) == "", "볼륨 모서리는 홀드로 놓지 못함")


## 볼륨 모서리로만 오르는 문제: 봇이 모서리(위 모서리 당기기·합손, 발 딛기)를 써서 탑까지 간다.
func test_edges_climbable() -> void:
	var d := _draft()
	d.place_volume("box", 0.0, 2.1, "M")  # 1.85~2.35m, 모서리: 위 2.35·아래 1.85·옆 ±0.25(2.1)
	for f in [[-0.2, 0.55], [0.2, 0.55], [-0.2, 0.95], [0.2, 0.95]]:
		d.place("crimp", f[0], f[1], "foot", "L")
	d.place("jug", 0.0, 2.7, "top")
	var r := d.build()
	var ex := PathExplorer.explore(r, {}, false, 15000)
	var used: Array = ex.steps.filter(func(s): return String(s[1]).contains("/edge_"))
	runner.check(ex.ok and not used.is_empty(), "볼륨 모서리를 써서 탑까지 %s %s" % [ex.ok, used])


## 트집 잡힐 배치는 막는다: 볼륨끼리 겹침, 벽이 꺾이는 곳에 걸침, 홀드가 볼륨 모서리에 반쯤 걸침, 너무 많음.
func test_volume_problems() -> void:
	var d := _draft()
	var a := d.place_volume("box", 0.0, 2.2, "M")
	runner.check(d.volume_issues().is_empty(), "하나는 괜찮음 %s" % [d.volume_issues()])
	var b := d.place_volume("wedge", 0.2, 2.4, "M")
	runner.check(d.volume_issues().any(func(i): return str(i.text).contains("겹쳐")) and d.problems().any(func(p): return str(p).contains("볼륨")), "겹치면 막음 %s" % [d.volume_issues()])
	d.remove_volume(b)
	d.set_wall(2, 30)  # 2m에서 꺾임: 볼륨(1.95~2.45)이 걸침
	runner.check(d.volume_issues().any(func(i): return str(i.text).contains("꺾이는")), "꺾이는 곳에 걸치면 막음 %s" % [d.volume_issues()])
	d.walls = [{"from_y": 0, "deg": 0}]
	var h := d.place("crimp", 0.25, 2.2)  # 오른쪽 모서리(0.25) 위
	runner.check(d.volume_issues().any(func(i): return i.get("hold", "") == h), "모서리에 걸친 홀드 %s" % [d.volume_issues()])
	d.move(h, 0.1, 2.2)
	runner.check(d.volume_issues().is_empty(), "면 안쪽으로 옮기면 괜찮음 %s" % [d.volume_issues()])
	for i in Volumes.MAX:
		d.place_volume("box", -0.6, 0.5 + i * 0.4, "S")
	runner.check(d.volumes.size() == Volumes.MAX and d.place_volume("box", 0, 4) == "", "볼륨은 %d개까지" % Volumes.MAX)


## 3D 몸이 볼륨에 박히지 않는다: 볼륨 모서리로 오르는 매 틱, 골반·가슴·머리와 떠 있는 손발이 볼륨 겉면 앞(트집: "몸이 볼륨을 뚫고 지나가").
func test_body_stays_out_of_volume() -> void:
	var d := _draft()
	var vid := d.place_volume("box", 0.0, 2.1, "M")
	for f in [[-0.2, 0.55], [0.2, 0.55], [-0.2, 0.95], [0.2, 0.95]]:
		d.place("crimp", f[0], f[1], "foot", "L")
	d.place("jug", 0.0, 2.7, "top")
	var r := d.build()
	var v := d.volume(vid)
	var ex := PathExplorer.explore(r, {}, false, 15000)
	var steps: Array = ex.steps
	var cp := ClimberPose.new()
	var worst := {"d": INF, "at": "", "n": 0, "body": INF, "body_at": "", "mid": INF, "mid_at": "", "f": null}
	var on_tick := func(s: ClimbSession, _res) -> void:
		worst.n += 1
		if worst.n % 3 != 0:
			return
		var t0 := cp.compute(s, 1.0 / 20.0)
		var held := {}
		for l in PoseSolver.LIMBS:
			held[l] = s.limbs[l].state in ["Attached", "Armed"]
		var fo: WallProfile = WallProfile.new(r, -1.0, 4.0) if worst.n == 3 else worst.f
		worst.f = fo
		var m: Dictionary = P3.climber_to_char(t0, fo, held, r.volumes)  # 화면 몸(팔꿈치·무릎은 3D에서 다시 푼다)
		var fr: Transform3D = fo.frame((t0.pelvis as Vector3).y)
		var t := {}
		for k in m:
			if m[k] is Vector3 and k != "up":
				var wv: Vector3 = fr * (m[k] as Vector3)
				t[k] = Vector3(wv.x, wv.y, wv.z)  # 수직 벽: 월드 = 판정 좌표
		for k in ["pelvis", "chest", "head"]:
			var p: Vector3 = t[k]
			if Volumes.contains(v, Vector2(p.x, p.y), 0.1):  # 몸통 두께만큼 넓혀
				var gap := p.z - Volumes.depth(v)
				if gap < worst.body:
					worst.body = gap
					worst.body_at = "%s 틱 %d" % [k, worst.n]
		for k in ["elbow_L", "elbow_R", "knee_L", "knee_R"]:
			var pm: Vector3 = t[k]
			if Volumes.contains(v, Vector2(pm.x, pm.y), 0.04):
				var gm := pm.z - Volumes.depth(v)
				if gm < worst.mid:
					worst.mid = gm
					worst.mid_at = "%s 틱 %d" % [k, worst.n]
		for l in PoseSolver.LIMBS:
			if s.limbs[l].state == "Dragging":
				var key: String = ("wrist_" if PoseSolver.is_hand(l) else "ankle_") + ("L" if PoseSolver.side_sign(l) < 0 else "R")
				var e: Vector3 = t[key]
				if Volumes.contains(v, Vector2(e.x, e.y)):
					var gap := e.z - Volumes.depth_at(v, Vector2(e.x, e.y))
					if gap < worst.d:
						worst.d = gap
						worst.at = "%s 틱 %d" % [key, worst.n]
	var bot := SessionBot.run(r, steps, {}, null, on_tick)
	runner.check(ex.ok and bot.ok() and worst.body < INF and worst.body > 0.10 and worst.d > 0.04 and worst.mid > -0.06,
		"%d틱 완등 %s, 몸통 중심이 볼륨 겉면에서 %.3fm(%s), 떠 있는 손목·발목 %.3fm(%s), 팔꿈치·무릎 %.3fm(%s)" % [worst.n, bot.ok(), worst.body, worst.body_at, worst.d, worst.at, worst.mid, worst.mid_at])


## 3D 볼륨 메시는 겉면 + 옆면 넷(상자 10삼각형), 삼각은 얇은 쪽 옆면이 없고 양옆이 세모(6삼각형). 꼭짓점 깊이가 0이면 납작했다(2026-11-28).
func test_volume_mesh_faces() -> void:
	var d := RouteDraft.new()
	d.route_id = "U_M"
	var f := WallProfile.new(d.build(Vector2(0, 0.75)), -1.0, 8.0)
	for shape in ["box", "wedge"]:
		for rot in [0, 90, 180, 270]:
			var m: ArrayMesh = P3.volume_mesh(f, Volumes.make("V01", shape, 0.0, 3.4, "L", rot))
			var n := (m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			runner.check(n == (10 if shape == "box" else 6), "%s %d°: 삼각형 %d" % [shape, rot, n])


## 위를 보는 면(아래가 두꺼운 삼각)에는 발을 비벼 딛는 칸이 있다. 아래를 보는 면·벽과 나란한 상자 앞면에는 없다(실제로 못 비빔).
func test_face_smear() -> void:
	var d := _draft()
	var up := d.place_volume("wedge", -0.5, 1.0, "L", 180)   # 아래가 두꺼움: 면이 위를 봄
	var down := d.place_volume("wedge", 0.5, 2.6, "M", 0)    # 위가 두꺼움: 면이 아래를 봄
	var box := d.place_volume("box", 0.5, 1.0, "S")
	var r := d.build()
	var faces := r.slots.keys().filter(func(k): return r.slots[k].hold_type == &"volume_face")
	runner.check(faces == ["U_V/%s/face" % up], "면 칸은 위를 보는 삼각만 %s" % [faces])
	var f: Dictionary = r.slots[faces[0]]
	runner.check(not f.has("hand_area") and not f.allowed.has(&"LH") and f.allowed.has(&"LF") and f.foot_area.half_width > 0.3, "발만, 면 거의 전체 %s" % [f.foot_area])
	runner.check(r.errors.is_empty() and d.volume_issues().is_empty(), "문제 없음 %s %s" % [r.errors, d.volume_issues()])


## 떨어지는 몸·카메라는 볼륨을 뚫지 않는다(볼륨 속 점은 겉면 앞으로).
func test_push_out_of_volume() -> void:
	var d := _draft()
	d.place_volume("box", 0.0, 2.2, "M")
	var r := d.build()
	var f := WallProfile.new(r, -1.0, 6.0)
	var inside := f.point(Vector3(0.05, 2.2, 0.1))  # 상자 속(앞면 0.3)
	var p := f.push_in_front(inside, 0.2, r.volumes)
	var l := f.volume_frame(r.volumes[0]).affine_inverse() * p
	runner.check(l.z >= 0.49 and absf(l.x - 0.05) < 0.01, "카메라: 상자 앞면 + 0.2 앞으로 %s" % l)
	var fs := FallSim.new()
	fs.set_volumes(f, r.volumes)
	var q := fs._clamp_point(inside)
	runner.check((f.volume_frame(r.volumes[0]).affine_inverse() * q).z >= 0.35, "떨어지는 관절도 앞으로 %s" % q)


## 아래 모서리(아래를 봄)는 손으로 언더만, 발로는 못 딛는다(트집: "볼륨 아래 모서리를 딛고 서 있다"). 위·옆 모서리는 발도 딛는다.
func test_bottom_edge_no_feet() -> void:
	var d := _draft()
	var v := d.place_volume("box", 0.0, 2.2, "M")
	var r := d.build()
	var b: Dictionary = r.slots["U_V/%s/edge_b" % v]
	var t: Dictionary = r.slots["U_V/%s/edge_t" % v]
	runner.check(not b.allowed.has(&"LF") and b.allowed.has(&"LH") and t.allowed.has(&"LF"), "아래 모서리 발 안 됨, 위는 됨 %s / %s" % [b.allowed, t.allowed])


## 볼륨 모서리를 시작 자리·탑으로(2026-11-28 남은 것): 시작은 모서리(발은 아래 모서리 빼고)·면(발만), 탑은 위 모서리(합손).
## 볼륨을 지우거나 모양을 바꿔 그 모서리가 없어지면 시작·탑에서 빠진다.
func test_edges_as_start_and_top() -> void:
	var d := RouteDraft.new()
	d.route_id = "U_S"
	d.name = "시작"
	var v := d.place_volume("box", 0.0, 1.6, "M")      # 1.35~1.85
	var w := d.place_volume("wedge", 0.0, 0.4, "L", 180)  # 0.05~0.85 면이 위를 봄
	runner.check(d.set_start(&"LH", v + "/edge_l") and d.set_start(&"RH", v + "/edge_r"), "손 시작: 옆 모서리")
	runner.check(not d.set_start(&"LF", v + "/edge_b") and not d.set_start(&"LH", w + "/face"), "아래 모서리는 발 안 됨, 면은 손 안 됨")
	runner.check(d.set_start(&"LF", w + "/face"), "발 시작: 삼각 면")
	d.set_start(&"RF", d.place("crimp", 0.5, 0.3, "foot"))
	var t := d.place_volume("box", 0.0, 2.8, "M")
	runner.check(d.set_top_edge(t + "/edge_t") and d.goal_hold().get("id", "") == t + "/edge_t", "탑: 위 모서리")
	var r := d.build()
	runner.check(r.errors.is_empty() and r.goal_slots == ["U_S/%s/edge_t" % t] and r.start_slots[&"LH"] == "U_S/%s/edge_l" % v, "문제 데이터 %s %s" % [r.errors, r.goal_slots])
	runner.check(not d.problems().has(RouteDraft.P_GOAL) and not d.problems().has(RouteDraft.P_START), "막는 것 없음(시작·탑) %s" % [d.problems()])
	d.place("jug", 0.0, 3.5, "top")
	runner.check(d.top_edge == "" and d.goal_hold().get("role", "") == "top", "탑 홀드를 놓으면 모서리 탑은 풀림")
	d.set_top_edge(t + "/edge_t")
	runner.check(d.holds.filter(func(h): return h.role == "top").is_empty(), "모서리를 탑으로 하면 탑 홀드는 지움(탑은 하나)")
	d.set_volume(v, "wedge", "M", 0)  # 삼각(위가 두꺼움): 옆 모서리는 남음
	runner.check(d.start[&"LH"] == v + "/edge_l", "모서리가 남으면 시작 그대로")
	d.set_volume(v, "wedge", "M", 90)  # 오른쪽이 두꺼움: 왼쪽(얇은 쪽) 모서리가 없어짐
	runner.check(d.start[&"LH"] == "" and d.start[&"RH"] == v + "/edge_r", "없어진 모서리는 시작에서 빠짐 %s" % [d.start])
	d.remove_volume(t)
	runner.check(d.top_edge == "" and d.problems().has(RouteDraft.P_GOAL), "볼륨을 지우면 탑이 빠짐")
	runner.check(RouteDraft.from_dict(d.to_dict()).start[&"LF"] == w + "/face", "저장·불러오기")


## 만들기 화면 시작홀드 도구: 모서리 선 근처를 누르면 그 모서리, 발이면 위를 보는 삼각 면.
func test_editor_picks_volume_slots() -> void:
	var ui = load("res://scenes/editor_ui.gd").new()
	ui.draft = RouteDraft.new()
	var v: String = ui.draft.place_volume("box", 0.0, 1.6, "M")
	var w: String = ui.draft.place_volume("wedge", 0.0, 0.4, "L", 180)
	runner.check(ui._volume_slot_at(Vector2(-0.27, 1.7), &"LH") == v + "/edge_l" and ui._volume_slot_at(Vector2(0.1, 1.84), &"RH") == v + "/edge_t", "모서리 근처")
	runner.check(ui._volume_slot_at(Vector2(0.0, 1.6), &"LH") == "", "앞면 가운데는 모서리 아님")
	runner.check(ui._volume_slot_at(Vector2(0.1, 0.4), &"LF") == w + "/face" and ui._volume_slot_at(Vector2(0.1, 0.4), &"LH") == "", "발은 삼각 면, 손은 안 됨")
	ui.free()
