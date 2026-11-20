extends RefCounted
## 홀드 종류가 판정에 주는 효과(작업 4 §4.1): 피로 배율, 발 몫, 슬로퍼 몸 창, 방향(힘 축 돌림).

var runner


## 두 손·두 발로 매달린 시작 자세. hand/foot: 손홀드·발홀드 종류(빈 문자열이면 옛 형식).
func _route(hand: String, foot: String, hand_rot := 0, hand_size := "M") -> RouteDef:
	var hs := func(id: String, x: float, limb: String) -> Dictionary:
		var s := {"slot_id": "h", "pos": [x, 1.55], "allowed": [limb]}
		if hand != "":
			s.merge({"hold_type": hand, "size": hand_size, "rot_deg": hand_rot})
		return {"hold_id": id, "slots": [s]}
	var fs := func(id: String, x: float, limb: String) -> Dictionary:
		var s := {"slot_id": "f", "pos": [x, 0.25], "allowed": [limb]}
		if foot != "":
			s.merge({"hold_type": foot, "size": "M", "rot_deg": 0})
		return {"hold_id": id, "slots": [s]}
	var r := RouteDef.from_dict({"route_id": "HE", "holds": [hs.call("L", -0.25, "LH"), hs.call("R", 0.25, "RH"), fs.call("A", -0.2, "LF"), fs.call("B", 0.2, "RF"),
		{"hold_id": "T", "slots": [{"slot_id": "a", "pos": [-0.1, 3.0], "allowed": ["LH", "RH"]}, {"slot_id": "b", "pos": [0.1, 3.0], "allowed": ["LH", "RH"]}]}],
		"goal_slots": ["HE/T/a", "HE/T/b"], "start_pose": {"pelvis": [0, 0.85], "slots": {"LH": "HE/L/h", "RH": "HE/R/h", "LF": "HE/A/f", "RF": "HE/B/f"}}})
	runner.check(r.errors.is_empty(), "루트 오류 없음 %s" % [r.errors])
	return r


## 두 발을 떼고(손 둘로 매달림) ticks만큼 지난 뒤 왼손 힘이 빠진 양.
func _drain(r: RouteDef, ticks := 60) -> float:
	var s := ClimbSession.new(r)
	s.apply_input([{"type": "detach", "limb": &"LF"}, {"type": "detach", "limb": &"RF"}])
	for i in ticks:
		s.step()
	return 100.0 - float(s.rules.stamina[&"LH"])


func test_contact_carries_hold_effects() -> void:
	var r := _route("crimp", "foot_chip")
	var s := ClimbSession.new(r)
	var lh: ContactInfo = s.limbs[&"LH"].contact
	var lf: ContactInfo = s.limbs[&"LF"].contact
	runner.check(is_equal_approx(lh.fatigue_mult, 1.3) and is_equal_approx(lf.foot_share, 0.85), "접점에 종류 효과 %s %s" % [lh.fatigue_mult, lf.foot_share])
	var c := ClimbSnapshot.copy_contact(lh)
	runner.check(is_equal_approx(c.fatigue_mult, 1.3) and c.hold_type == &"crimp", "스냅숏 복사도 그대로")


func test_crimp_drains_faster_than_jug() -> void:
	var jug := _drain(_route("jug", "foot_big", 0, "S"))
	var crimp := _drain(_route("crimp", "foot_big", 0, "L"))
	var legacy := _drain(_route("", "foot_big"))
	runner.check(crimp > jug * 1.5, "크림프가 저그보다 빨리 지침 jug %.2f crimp %.2f" % [jug, crimp])
	runner.check(jug < legacy, "저그(×0.7)는 옛 홀드보다 덜 지침 %.2f < %.2f" % [jug, legacy])


func test_small_foot_chip_counts_less() -> void:
	var big := ClimbSession.new(_route("jug", "foot_big"))
	var chip := ClimbSession.new(_route("jug", "foot_chip"))
	for i in 30:
		big.step()
		chip.step()
	runner.check(big.rules.foot_support > 0.0 and is_equal_approx(chip.rules.foot_support, big.rules.foot_support * 0.85),
		"작은 발판 발 몫 0.85배 %.3f / %.3f" % [chip.rules.foot_support, big.rules.foot_support])


func test_sloper_body_window() -> void:
	var w := [0.12, 0.35, 0.4]
	runner.check(is_equal_approx(HoldArea.window_factor(w, 0.0, 0.1), 1.0), "창 안이면 1")
	runner.check(is_equal_approx(HoldArea.window_factor(w, 0.0, -0.5), 0.4), "0.35m 밖이면 0.4")
	runner.check(is_equal_approx(HoldArea.window_factor(w, 0.0, 0.235), 0.7), "가운데는 선형 0.7")
	runner.check(is_equal_approx(HoldArea.window_factor([], 0.0, 1.0), 1.0), "창 없으면 1")
	var rules := ClimbRules.new()
	var ci := GripCheck.contact_for("HE/L/h", _route("sloper", "foot_big").slots, &"LH", Vector2(-0.25, 1.55))
	rules.contact_meta = {&"LH": ci}
	runner.check(is_equal_approx(rules.quality_at(&"LH", -0.25), ci.quality) and rules.quality_at(&"LH", 0.4) < ci.quality * 0.5, "몸이 멀면 슬로퍼 품질이 낮아짐")


## 날이 오른쪽(rot 90)인 크림프 한 손 + 두 발: 힘 축이 +x라 몸(무게중심)이 홀드 왼쪽일 때만 손이 버틴다.
func test_sidepull_needs_body_on_opposite_side() -> void:
	var r := _route("crimp", "foot_big", 90)
	var hold := Vector2(-0.25, 1.55)
	var meta := {&"LH": GripCheck.contact_for("HE/L/h", r.slots, &"LH", hold)}
	var att := {&"LH": hold, &"LF": Vector2(-0.2, 0.25), &"RF": Vector2(0.2, 0.25)}
	var feet := [&"LF", &"RF"]
	var left := ClimbRules.evaluate_pose(Vector2(-0.45, 0.85), 0.0, 0.0, att, {}, meta, feet, feet)
	var right := ClimbRules.evaluate_pose(Vector2(0.15, 0.85), 0.0, 0.0, att, {}, meta, feet, feet)
	runner.check(left.u.get(&"LH", 0.0) > 0.05, "몸이 왼쪽이면 사이드풀 손이 하중을 받음 %s" % [left.u])
	runner.check(right.u.get(&"LH", 0.0) < left.u.get(&"LH", 0.0), "몸이 같은 쪽이면 덜 받음 %s" % [right.u])


## 날이 아래(rot 180)면 언더클링: 하중 받는 발이 없으면 손이 지지에 들어가지 않는다.
func test_undercling_needs_loaded_foot() -> void:
	var r := _route("jug", "foot_big", 180)
	var ci := GripCheck.contact_for("HE/L/h", r.slots, &"LH", Vector2(-0.25, 1.55))
	runner.check(ci.mode == &"undercling" and ci.axis.y < -0.99, "rot 180 접점은 언더클링 %s %s" % [ci.mode, ci.axis])
	var pelvis := Vector2(-0.2, 1.3)
	runner.check(not PoseSolver.hand_counts_for_support(pelvis, 0.0, &"LH", Vector2(-0.25, 1.55), ci.mode, []), "발 없으면 지지 안 됨")
	runner.check(PoseSolver.hand_counts_for_support(pelvis, 0.0, &"LH", Vector2(-0.25, 1.55), ci.mode, [&"LF"]), "실린 발이 있으면 지지")
