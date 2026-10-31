extends RefCounted
## 홀드 영역·그립 방식 데이터와 품질 투영 (docs/27 §8, docs/04 §10.2).

var runner


func _slot(c: Vector2) -> Dictionary:
	return {"pos": c, "hand_area": {"dir": Vector2(1, 0), "half_width": 0.1}}


func test_defaults_filled() -> void:
	var r := RouteDef.load_json("res://data/routes/R01.json")
	var g: Dictionary = r.slots["R01/G01/goal_left"]
	runner.check(is_equal_approx(g.hand_area.half_width, 0.08), "손 기본 반폭 0.08")
	runner.check(g.hand_area.dir == Vector2(1, 0), "손 기본 방향 (1,0)")
	runner.check(g.grip_modes.size() == 1 and g.grip_modes[0].mode == &"pull", "기본 방식 pull")
	runner.check(g.grip_modes[0].axis == Vector2(0, 1), "pull 축 (0,1)")
	runner.check(is_equal_approx(g.grip_modes[0].half_angle, 65.0), "pull 반각 65")
	var f: Dictionary = r.slots["R01/F01/foot_1"]
	runner.check(is_equal_approx(f.foot_area.half_height, 0.04), "발 기본 반높이 0.04")
	runner.check(f.foot_area.up == Vector2(0, 1), "발 기본 up (0,1)")
	runner.check(f.pivot_allowed == true, "pivot 기본 허용")
	runner.check(f.hook == false, "hook 기본 false")
	runner.check(not f.has("hand_area"), "발 전용 슬롯에 hand_area 없음")
	runner.check(not g.has("foot_area"), "손 전용 슬롯에 foot_area 없음")


func test_hand_quality_center_and_edge() -> void:
	var s := _slot(Vector2(1, 2))
	var p: Dictionary = HoldArea.project_hand(s, Vector2(1, 2.5))
	runner.check(is_equal_approx(p.quality, 1.0) and is_equal_approx(p.t, 0.0), "중심 q=1")
	p = HoldArea.project_hand(s, Vector2(1.1, 2))
	runner.check(is_equal_approx(p.t, 1.0) and is_equal_approx(p.quality, 0.0), "끝 q=0")
	p = HoldArea.project_hand(s, Vector2(1.05, 3))
	runner.check(is_equal_approx(p.quality, 0.75), "t=0.5 q=0.75")
	runner.check(p.point.is_equal_approx(Vector2(1.05, 2)), "투영점은 선분 위")
	p = HoldArea.project_hand(s, Vector2(5, 2))
	runner.check(p.point.is_equal_approx(Vector2(1.1, 2)) and is_equal_approx(p.quality, 0.0), "선분 밖은 끝으로 클램프")
	var iv: Vector2 = HoldArea.hand_interval(s, Vector2(1.05, 2))
	runner.check(iv.is_equal_approx(Vector2(0.01, 0.09)), "구간 [s-0.04,s+0.04], 실제 %s" % iv)


func test_foot_quality_top_mid_same_bottom_worse() -> void:
	var s := {"pos": Vector2(0, 1), "foot_area": {"up": Vector2(0, 1), "half_height": 0.05}}
	var cases := {1.0: 1.0, 0.0: 1.0, -0.2: 1.0, -1.0: 0.5, -0.6: 0.75}
	for v in cases:
		var p: Dictionary = HoldArea.project_foot(s, Vector2(0.3, 1.0 + v * 0.05))
		runner.check(is_equal_approx(p.v, v), "v=%s 실제 %s" % [v, p.v])
		runner.check(is_equal_approx(p.quality, cases[v]), "v=%s q=%s 실제 %s" % [v, cases[v], p.quality])
	var far: Dictionary = HoldArea.project_foot(s, Vector2(0, 5))
	runner.check(is_equal_approx(far.v, 1.0) and far.point.is_equal_approx(Vector2(0, 1.05)), "위쪽 클램프")


func test_tx_tech_loads() -> void:
	var r := RouteDef.load_json("res://data/routes/TX_TECH.json")
	runner.check(r.errors.is_empty(), "TX_TECH 오류: %s" % [r.errors])
	var modes := {}
	var no_pivot := 0
	var wide := 0
	var narrow := 0
	for key in r.slots:
		var s: Dictionary = r.slots[key]
		for gm in s.grip_modes:
			modes[gm.mode] = true
		if s.has("foot_area") and not s.pivot_allowed:
			no_pivot += 1
		if s.has("hand_area"):
			if s.hand_area.half_width >= 0.16:
				wide += 1
			if is_equal_approx(s.hand_area.half_width, 0.04):
				narrow += 1
	for m in [&"sidepull", &"gaston", &"undercling"]:
		runner.check(modes.has(m), "방식 %s 슬롯 필요" % m)
	runner.check(no_pivot >= 1, "pivot_allowed=false 발판 필요")
	runner.check(wide >= 1, "반폭 0.16 이상 홀드 필요")
	runner.check(narrow >= 1, "반폭 0.04 홀드 필요")


func test_invalid_area_rejected() -> void:
	var r := RouteDef.load_json("res://data/routes/R01.json")
	r.slots["R01/H01/hand_1"].hand_area.half_width = 0.0
	r.errors.clear()
	r._validate()
	runner.check(r.errors.size() > 0, "half_width<=0 거부")
	r = RouteDef.load_json("res://data/routes/R01.json")
	r.slots["R01/H01/hand_1"].grip_modes = []
	r.errors.clear()
	r._validate()
	runner.check(r.errors.size() > 0, "빈 grip_modes 거부")
	r = RouteDef.load_json("res://data/routes/R01.json")
	r.slots["R01/F01/foot_1"].foot_area.half_height = -1.0
	r.errors.clear()
	r._validate()
	runner.check(r.errors.size() > 0, "half_height<=0 거부")


func test_r01_holds_are_big() -> void:
	var r := RouteDef.load_json("res://data/routes/R01.json")
	runner.check(r.content_version == 4, "R01 content_version 4")
	for i in range(1, 7):
		var k := "R01/H0%d/hand_1" % i
		runner.check(is_equal_approx(r.slots[k].hand_area.half_width, 0.12), "%s 반폭 0.12" % k)
