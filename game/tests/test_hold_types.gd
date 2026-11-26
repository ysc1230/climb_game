extends RefCounted
## 홀드 종류·크기·방향(docs/superpowers/specs/2026-11-19-4-holds-design.md §4.1).

var runner


func _route(slots: Array) -> RouteDef:
	var holds := [
		{"hold_id": "S1", "slots": [{"slot_id": "h", "pos": [-0.3, 1.2], "allowed": ["LH"]}]},
		{"hold_id": "S2", "slots": [{"slot_id": "h", "pos": [0.3, 1.2], "allowed": ["RH"]}]},
		{"hold_id": "S3", "slots": [{"slot_id": "f", "pos": [-0.2, 0.2], "allowed": ["LF"]}]},
		{"hold_id": "S4", "slots": [{"slot_id": "f", "pos": [0.2, 0.2], "allowed": ["RF"]}]},
		{"hold_id": "T", "slots": [{"slot_id": "a", "pos": [-0.1, 2.5], "allowed": ["LH", "RH"]}, {"slot_id": "b", "pos": [0.1, 2.5], "allowed": ["LH", "RH"]}]},
	]
	for i in slots.size():
		holds.append({"hold_id": "X%d" % i, "slots": [slots[i]]})
	return RouteDef.from_dict({"route_id": "HT", "holds": holds, "goal_slots": ["HT/T/a", "HT/T/b"],
		"start_pose": {"pelvis": [0, 0.9], "slots": {"LH": "HT/S1/h", "RH": "HT/S2/h", "LF": "HT/S3/f", "RF": "HT/S4/f"}}})


func _slot(type: String, size := "M", rot := 0, extra := {}) -> Dictionary:
	var hand := not type.begins_with("foot_")
	var s := {"slot_id": "s", "pos": [0, 1.5], "allowed": ["LH", "RH"] if hand else ["LF", "RF"], "hold_type": type, "size": size, "rot_deg": rot}
	s.merge(extra, true)
	return s


func _one(type: String, size := "M", rot := 0, extra := {}) -> Dictionary:
	var r := _route([_slot(type, size, rot, extra)])
	runner.check(r.errors.is_empty(), "%s %s %d 오류 없음 %s" % [type, size, rot, r.errors])
	return r.slots.get("HT/X0/s", {})


func _v(a: Vector2, b: Vector2) -> bool:
	return a.distance_to(b) < 0.001


func test_sizes_and_half_angles() -> void:
	for case in [["jug", "S", 0.07, 75.0], ["jug", "M", 0.09, 80.0], ["jug", "L", 0.12, 85.0], ["crimp", "S", 0.035, 45.0], ["crimp", "M", 0.045, 50.0],
			["sloper", "L", 0.13, 50.0], ["pocket", "M", 0.04, 60.0], ["pinch", "M", 0.05, 55.0], ["goal", "S", 0.12, 80.0]]:
		var s := _one(case[0], case[1])
		runner.check(is_equal_approx(s.hand_area.half_width, case[2]) and is_equal_approx(s.grip_modes[0].half_angle, case[3]),
			"%s %s → 반폭 %.3f 반각 %.0f %s" % [case[0], case[1], case[2], case[3], [s.hand_area, s.grip_modes]])
	var f := _one("foot_chip", "S")
	runner.check(is_equal_approx(f.foot_area.half_height, 0.03) and not f.has("hand_area"), "작은 발판 S 반높이 0.03 %s" % [f])
	runner.check(is_equal_approx(_one("foot_big", "L").foot_area.half_height, 0.08), "큰 발판 L 0.08")


func test_rotation_turns_dir_and_axis() -> void:
	var s := _one("jug", "M", 0)
	runner.check(_v(s.hand_area.dir, Vector2(1, 0)) and _v(s.grip_modes[0].axis, Vector2(0, 1)) and s.grip_modes[0].mode == &"pull", "rot 0 = pull 위 %s" % [s.grip_modes])
	s = _one("jug", "M", 90)
	runner.check(_v(s.grip_modes[0].axis, Vector2(1, 0)) and _v(s.hand_area.dir, Vector2(0, -1)) and s.grip_modes[0].mode == &"sidepull", "rot 90 = 날 오른쪽, 사이드풀 %s" % [s.grip_modes])
	s = _one("jug", "M", 180)
	runner.check(_v(s.grip_modes[0].axis, Vector2(0, -1)) and s.grip_modes[0].mode == &"undercling", "rot 180 = 언더클링 %s" % [s.grip_modes])
	s = _one("crimp", "M", 275)
	runner.check(s.grip_modes[0].mode == &"sidepull" and s.grip_modes[0].axis.x < -0.99, "rot 275 = 날 왼쪽 사이드풀 %s" % [s.grip_modes])
	s = _one("jug", "M", 40)
	runner.check(s.grip_modes[0].mode == &"pull", "rot 40은 pull")
	runner.check(s.rot_deg == 40 and s.hold_type == &"jug" and s.size == "M", "슬롯에 종류·크기·방향 %s" % [s])


func test_pinch_has_three_modes() -> void:
	var s := _one("pinch", "M", 0)
	var modes: Array = s.grip_modes.map(func(g): return g.mode)
	runner.check(modes == [&"pull", &"sidepull", &"sidepull"] and _v(s.grip_modes[1].axis, Vector2(1, 0)) and _v(s.grip_modes[2].axis, Vector2(-1, 0)),
		"핀치 = pull + 옆 둘 %s" % [s.grip_modes])


## 합손은 종류·크기마다(2026-11-26 사용자 "저그는 어느 사이즈든 … 크림프는 가장 큰 홀드만", "포켓은 큰건 되게", "슬로퍼는 보통·큰것만").
func test_match_by_type_and_size() -> void:
	var table := {"jug": ["S", "M", "L"], "crimp": ["L"], "sloper": ["M", "L"], "pinch": ["L"], "pocket": ["L"], "foot_chip": [], "foot_big": []}
	for type in table:
		for size in HoldTypes.SIZES:
			runner.check(HoldTypes.can_match(type, size) == table[type].has(size), "%s %s 합손 %s" % [type, size, table[type].has(size)])
	runner.check(not _one("crimp", "M", 0, {"hand_area": {"matchable": true}}).hand_area.matchable, "크림프 보통은 켜도 합손 안 됨")
	runner.check(_one("crimp", "L", 0, {"hand_area": {"matchable": true}}).hand_area.matchable, "크림프 큰 것은 합손")
	runner.check(_one("pocket", "L", 0, {"hand_area": {"matchable": true}}).hand_area.matchable, "포켓 큰 것은 합손")
	runner.check(not _one("jug", "S").hand_area.matchable, "켜지 않으면 합손 아님")


## 손홀드 종류도 발로 딛게 놓을 수 있다(2026-11-26 사용자 "홀드 종류가 기준이 된 후에 손 발 탑을 선택"). 발판은 손으로 못 잡는다.
func test_hand_type_as_foot() -> void:
	var s := _slot("jug", "L")
	s.allowed = ["LF", "RF"]
	var f := _one("jug", "L", 0, {"allowed": ["LF", "RF"]})
	runner.check(not f.has("hand_area") and is_equal_approx(f.foot_area.half_width, 0.12) and f.foot_area.half_height > 0.0, "저그를 발로: 발 영역(반폭 0.12) %s" % [f])
	var fb := _one("foot_big", "M", 0, {"allowed": ["LH", "RH"]})
	runner.check(fb.has("hand_area") and fb.has("foot_area") and fb.fatigue_mult > 1.0, "발판도 손 칸(2026-11-26 사용자 \"모든 홀드들이 손홀드이자 발홀드\") %s" % [fb])


func test_foot_rotation_and_share() -> void:
	var f := _one("foot_chip", "M", 90)
	runner.check(_v(f.foot_area.up, Vector2(1, 0)), "발판 up도 돌림 %s" % [f.foot_area])
	runner.check(is_equal_approx(f.foot_share, 0.85) and is_equal_approx(_one("foot_big").foot_share, 1.0) and is_equal_approx(_one("jug").foot_share, 1.0), "발 몫 배율")
	runner.check(is_equal_approx(_one("crimp").fatigue_mult, 1.3) and is_equal_approx(_one("jug").fatigue_mult, 0.7), "피로 배율")
	runner.check(not _one("sloper").window.is_empty() and _one("jug").window.is_empty(), "슬로퍼만 몸 창")


func test_new_fields_win_over_old() -> void:
	var s := _one("crimp", "S", 0, {"hand_area": {"half_width": 0.2, "dir": [0, 1]}, "grip_modes": [{"mode": "gaston", "axis": [1, 0], "half_angle": 30}]})
	runner.check(is_equal_approx(s.hand_area.half_width, 0.035) and s.grip_modes[0].mode == &"pull", "새 필드가 이김 %s" % [s])


func test_old_format_unchanged() -> void:
	var r := RouteDef.load_json("res://data/routes/TX_TECH.json")
	runner.check(r.errors.is_empty(), "옛 형식 그대로 %s" % [r.errors])
	for key in r.slots:
		runner.check(r.slots[key].hold_type == &"", "옛 형식은 종류 없음 %s" % key)
		break


func test_invalid_fields() -> void:
	for bad in [_slot("blob"), _slot("jug", "XL"), _slot("jug", "M", 7), _slot("jug", "M", 360)]:
		runner.check(not _route([bad]).errors.is_empty(), "잘못된 값은 오류 %s" % [bad])


## 그림: 종류마다 그 종류의 메시(작업 4 §4.2). 모든 변형이 holds.glb에 있다.
func test_hold_meshes_by_type() -> void:
	var P3 := preload("res://scenes/play_3d.gd")
	var names := {}
	var root: Node = load("res://art/holds/holds.glb").instantiate()
	for n in root.find_children("*", "MeshInstance3D", true, false):
		names[String(n.name)] = true
	root.free()
	for type in P3.TYPE_VARIANTS:
		runner.check(HoldTypes.has(type), "그림 종류 %s는 종류 표에 있음" % type)
		for v in P3.TYPE_VARIANTS[type]:
			runner.check(names.has(v), "메시 %s 있음" % v)
	for type in HoldTypes.types():
		var s := _one(type)
		runner.check(P3.hold_variant("k1", s, false).begins_with(type + "_") or type == "goal", "%s 슬롯은 %s 메시" % [type, P3.hold_variant("k1", s, false)])
	runner.check(P3.hold_variant("k1", {}, true) == "goal_0", "탑은 goal_0")
	runner.check(P3.hold_variant("k1", {"hand_area": {"half_width": 0.04}}, false).begins_with("crimp_"), "옛 형식 작은 손홀드는 크림프 모양")
