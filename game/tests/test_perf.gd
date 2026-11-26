extends RefCounted
## 최적화(2026-11-26 사용자 "프레임드랍이나 로딩 … 벽이 가장 높고 홀드가 가장 많을 경우"): 빨리 하는 길이 예전 결과와 같은지.

var runner


## 벽 100m·각도 구간 100개·홀드 300개(벽 끝까지 고르게).
func _big() -> RouteDraft:
	var d := RouteDraft.new()
	d.route_id = "U_BIG"
	d.name = "큰 벽"
	var ids := [d.place("jug", -0.3, 1.7), d.place("jug", 0.3, 1.7), d.place("foot_big", -0.3, 0.4), d.place("foot_big", 0.3, 0.4)]
	for i in 4:
		d.set_start([&"LH", &"RH", &"LF", &"RF"][i], ids[i])
	var types := ["jug", "crimp", "sloper", "pinch", "pocket", "foot_chip", "foot_big"]
	var n := 0
	while d.holds.size() < 299:
		var t: String = types[n % types.size()]
		d.place(t, -0.8 + 0.4 * (n % 5), 2.1 + n * (96.0 / 295.0), "foot" if t.begins_with("foot") else "hand")
		n += 1
	d.place("jug", 0.0, 99.5, "top")
	for m in 100:
		d.set_wall(m, ((m * 37) % 151) - 60)
	return d


## 접힌 벽 각도 표: 곧은 곳을 건너뛰어 채워도 angle_at과 같다.
func test_wall_profile_matches_angle_at() -> void:
	var r := _big().layout_route()
	var f := WallProfile.new(r, -1.5, 103.0)
	var worst := 0.0
	for i in 2000:
		var s := -1.5 + i * 0.0523
		worst = maxf(worst, absf(f.angle_rad(s) - deg_to_rad(r.angle_at(s))))
	runner.check(worst < 0.002, "표와 angle_at 차이 %.5f rad" % worst)


## 띠 나누기: 곧은 벽은 4m마다, 꺾이는 곳은 촘촘히. 줄 사이 각도 변화가 꺾이는 칸 하나보다 크지 않다.
func test_strip_rows_coarse_when_straight() -> void:
	var P3 := preload("res://scenes/play_3d.gd")
	var straight := RouteDraft.new()
	straight.place("jug", 0.0, 99.0)
	var f := WallProfile.new(straight.layout_route(), -1.5, 103.0)
	var rows: PackedFloat32Array = P3.strip_rows(f, -0.6, 101.0)
	runner.check(rows.size() <= 28 and is_equal_approx(rows[0], -0.6) and is_equal_approx(rows[rows.size() - 1], 101.0), "곧은 100m 벽은 %d줄" % rows.size())
	var bent := _big()
	f = WallProfile.new(bent.layout_route(), -1.5, 103.0)
	rows = P3.strip_rows(f, -0.6, 101.0)
	var worst := 0.0
	for i in rows.size() - 1:
		var a := f.angle_rad(rows[i])
		var b := f.angle_rad(rows[i + 1])
		var mid := f.angle_rad((rows[i] + rows[i + 1]) * 0.5)
		worst = maxf(worst, absf(mid - (a + b) * 0.5))  # 줄 사이가 곧지 않으면 크다
	runner.check(rows.size() < 2100 and worst < 0.05, "꺾인 벽 %d줄(5cm마다면 2032), 줄 사이 굽음 %.4f" % [rows.size(), worst])


## 간격 검사(높이 순으로 가까운 것만)가 모든 쌍을 본 결과와 같다.
func test_spacing_sweep_matches_all_pairs() -> void:
	var d := RouteDraft.new()
	d.route_id = "U_SP"
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 120:
		d.place(["jug", "crimp", "sloper", "foot_big"][i % 4], rng.randf_range(-1.0, 1.0), rng.randf_range(0.2, 6.0))
	var r := d.layout_route()
	var fast := Array(HoldSpacing.violations(r, 0.0, 0.01))
	var slow := []
	var keys: Array = r.slots.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var ea := HoldSpacing.ellipse(r, keys[i])
			var eb := HoldSpacing.ellipse(r, keys[j])
			var pa := r.slot_pos(keys[i])
			var pb := r.slot_pos(keys[j])
			var u := (pb - pa).normalized()
			if pa.distance_to(pb) - HoldSpacing.radius(ea, u) - HoldSpacing.radius(eb, u) < 0.01 - 0.0005:
				slow.append([String(keys[i]).get_slice("/", 1), String(keys[j]).get_slice("/", 1)])
	var pairs := fast.map(func(l): return [l.get_slice(" ", 0), l.get_slice(" ", 2)])
	var same := pairs.size() == slow.size() and slow.all(func(p): return pairs.has(p) or pairs.has([p[1], p[0]]))
	runner.check(same and slow.size() > 0, "겹친 쌍 %d개, 빠른 길 %d개" % [slow.size(), pairs.size()])


## 만들기 화면: 홀드 하나를 고치면 그 홀드만 다시 만들고, 벽 각도를 바꾸면 벽만 다시 만들고 홀드는 새 벽에 다시 놓는다.
func test_editor_rebuilds_only_what_changed() -> void:
	var v: Node3D = load("res://scenes/editor_view.gd").new()
	v._ready()
	var d := RouteDraft.new()
	var a := d.place("jug", 0.0, 1.6)
	var b := d.place("crimp", 0.3, 2.4)
	v.rebuild(d)
	var key_a := "%s/%s/hand_1" % [d.route_id, a]
	var key_b := "%s/%s/hand_1" % [d.route_id, b]
	var node_a: Node = v.hold_nodes[key_a][0]
	var node_b: Node = v.hold_nodes[key_b][0]
	var wall: Node = v._built[0]
	d.move(b, 0.4, 2.4)
	v.rebuild(d)
	runner.check(v.hold_nodes[key_a][0] == node_a and v.hold_nodes[key_b][0] != node_b and v._built[0] == wall, "옮긴 홀드만 다시, 벽은 그대로")
	runner.check(v.hold_glows.is_empty(), "만들기 화면은 빛 메시를 만들지 않음")
	var before: Vector3 = (node_a as Node3D).position
	d.set_wall(0, 40)
	v.rebuild(d)
	var after: Vector3 = (node_a as Node3D).position
	runner.check(v.hold_nodes[key_a][0] == node_a and v._built[0] != wall and after.distance_to(before) > 0.1, "벽 각도를 바꾸면 벽만 다시, 홀드는 새 벽에 (%s → %s)" % [before, after])
	v.free()


## 같은 종류 홀드는 재질을 나눠 쓴다(홀드마다 재질 6개를 만들던 것).
func test_hold_materials_shared() -> void:
	var v: Node3D = load("res://scenes/editor_view.gd").new()
	v._ready()
	var d := RouteDraft.new()
	var a := d.place("jug", 0.0, 1.6)
	var b := d.place("jug", 0.4, 2.6)
	v.rebuild(d)
	var ma: Material = (v.hold_nodes["%s/%s/hand_1" % [d.route_id, a]][0] as MeshInstance3D).get_surface_override_material(0)
	var mb: Material = (v.hold_nodes["%s/%s/hand_1" % [d.route_id, b]][0] as MeshInstance3D).get_surface_override_material(0)
	runner.check(ma != null and ma == mb, "같은 손홀드는 같은 재질")
	v.free()


## 긴 등반(20분)도 고스트는 MAX_FRAMES를 넘지 않고 처음부터 끝까지 담는다.
func test_ghost_capped() -> void:
	var s := ClimbSession.new(_big().layout_route())
	var g := GhostTrack.new()
	for i in 72000:
		g.record(s, 1.0 / 60.0)
	runner.check(g.frames.size() <= GhostTrack.MAX_FRAMES and g.duration() > 1190.0 and float(g.frames[0][0]) < 0.1, "프레임 %d개, %.0f초" % [g.frames.size(), g.duration()])


## 편집 한 번의 점검(막는 것·주의·빨간 홀드)이 홀드 300개·벽 100m에서도 가볍다(데스크톱 기준 넉넉히 80ms 안, 예전 96ms).
func test_big_edit_check_fast() -> void:
	var d := _big()
	d.problems()  # 시작 자세 찾기(처음 한 번)
	d.move(d.holds[50].id, 0.1, float(d.holds[50].y))
	var t := Time.get_ticks_msec()
	d.problems()
	d.warnings()
	d.bad_holds()
	var ms := Time.get_ticks_msec() - t
	runner.check(ms < 80, "편집 한 번 점검 %dms" % ms)
