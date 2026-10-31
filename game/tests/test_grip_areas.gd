extends RefCounted
## 영역 기반 잡기와 점유 구간 (docs/27 §8).

var runner

const R01_H03 := "R01/H03/hand_1"


func _r01() -> RouteDef:
	return RouteDef.load_json("res://data/routes/R01.json")


func _tx() -> RouteDef:
	return RouteDef.load_json("res://data/routes/TX_TECH.json")


## 손 하나만 후보 검사에 필요한 최소 attached(몸통 유효성은 다른 접점 없이 통과해야 함).
func _cand(r: RouteDef, limb: StringName, end: Vector2, occ: Dictionary) -> Dictionary:
	var pelvis: Vector2 = end + Vector2(0, -0.7)
	return GripCheck.candidate(r.slots, limb, end, pelvis, 0.0, {}, occ)


func _hand_occ(limb: StringName, lo: float, hi: float) -> Array:
	return [{"limb": limb, "interval": Vector2(lo, hi)}]


func test_candidate_returns_projected_point() -> void:
	var r := _r01()
	var c: Vector2 = r.slots[R01_H03].pos
	var cand := _cand(r, &"LH", c + Vector2(0.05, 0.03), {})
	runner.check(not cand.is_empty() and cand.key == R01_H03, "후보 있음 %s" % [cand])
	if cand.is_empty():
		return
	runner.check(cand.point.is_equal_approx(c + Vector2(0.05, 0)), "투영점 %s" % cand.point)
	var expect := 1.0 - pow(0.05 / 0.12, 2)
	runner.check(absf(cand.quality - expect) < 0.001, "품질 %f vs %f" % [cand.quality, expect])


func test_pad_grab_shifts_off_occupied_interval() -> void:
	var r := _tx()
	var key := "TX_TECH/N02/hand_1"
	var c: Vector2 = r.slots[key].pos
	var occ := {key: _hand_occ(&"RH", -0.04, 0.04)}
	var cand := _cand(r, &"LH", c, occ)
	runner.check(not cand.is_empty() and cand.key == key, "후보 있음 %s" % [cand])
	if cand.is_empty():
		return
	var s: float = cand.point.x - c.x
	runner.check(absf(s) >= 0.08 - 0.001, "중심에서 떨어짐 %f" % s)
	var iv := HoldArea.hand_interval(r.slots[key], cand.point)
	runner.check(not GripCheck.overlaps(iv, Vector2(-0.04, 0.04)), "구간 안 겹침 %s" % iv)


func test_narrow_hold_rejects_second_hand() -> void:
	var r := _tx()
	var key := "TX_TECH/N01/hand_1"
	var c: Vector2 = r.slots[key].pos
	var occ := {key: _hand_occ(&"RH", -0.04, 0.04)}
	var cand := _cand(r, &"LH", c, occ)
	runner.check(cand.is_empty(), "좁은 홀드는 두 번째 손 불가 %s" % [cand])
	var pelvis := c + Vector2(0, -0.7)
	var reason := GripCheck.reject_reason(r.slots, &"LH", c, c, pelvis, 0.0, {}, occ, [])
	runner.check(reason == GripCheck.OCCUPIED, "사유 %s" % reason)


func test_big_hold_match_by_pad() -> void:
	var r := _r01()
	var c: Vector2 = r.slots[R01_H03].pos
	var lh := c + Vector2(-0.04, 0)
	var occ := {R01_H03: _hand_occ(&"LH", -0.08, 0.0)}
	var cand := GripCheck.candidate(r.slots, &"RH", c, c + Vector2(0, -0.7), 0.0, {&"LH": lh}, occ)
	runner.check(not cand.is_empty() and cand.key == R01_H03, "합손 후보 %s" % [cand])
	if cand.is_empty():
		return
	var iv := HoldArea.hand_interval(r.slots[R01_H03], cand.point)
	runner.check(not GripCheck.overlaps(iv, Vector2(-0.08, 0.0)), "RH 구간 안 겹침 %s" % iv)
	runner.check(cand.quality >= 0.85, "RH 품질 %f" % cand.quality)
	var lq: float = HoldArea.project_hand(r.slots[R01_H03], lh).quality
	runner.check(lq >= 0.85, "LH 품질 %f" % lq)


func test_touching_intervals_allowed() -> void:
	var r := _r01()
	var key := "R01/H07/hand_1"
	if not r.slots.has(key):
		key = "R01/G01/goal_left"
	var c: Vector2 = r.slots[key].pos
	runner.check(is_equal_approx(r.slots[key].hand_area.half_width, 0.08), "반폭 0.08 홀드")
	var occ := {key: _hand_occ(&"LH", -0.08, 0.0)}
	var cand := _cand(r, &"RH", c + Vector2(0.04, 0), occ)
	runner.check(not cand.is_empty(), "맞닿음 허용 %s" % [cand])
	if not cand.is_empty():
		runner.check(absf(cand.point.x - c.x - 0.04) < 0.001, "RH 점 %s" % cand.point)
	var occ2 := {key: _hand_occ(&"LH", 0.0, 0.08)}
	var cand2 := _cand(r, &"RH", c + Vector2(-0.04, 0), occ2)
	runner.check(not cand2.is_empty() and absf(cand2.point.x - c.x + 0.04) < 0.001, "반대쪽도 허용 %s" % [cand2])


func test_foot_single_occupant() -> void:
	var r := _r01()
	var key := "R01/F01/foot_1"
	var p: Vector2 = r.slots[key].pos
	var occ := {key: [{"limb": &"LF", "interval": Vector2.ZERO}]}
	var pelvis := p + Vector2(0, 0.75)
	var other := GripCheck.candidate(r.slots, &"RF", p, pelvis, 0.0, {}, occ)
	runner.check(other.is_empty() or other.key != key, "다른 발이 있으면 후보 아님 %s" % [other])
	var free := GripCheck.candidate(r.slots, &"RF", p, pelvis, 0.0, {}, {})
	runner.check(not free.is_empty() and free.key == key, "빈 발 슬롯은 후보 %s" % [free])


func test_contact_for() -> void:
	var r := _tx()
	var key := "TX_TECH/S01/hand_1"
	var ci := GripCheck.contact_for(key, r.slots, &"LH", r.slots[key].pos)
	runner.check(ci.mode == &"sidepull" and ci.edge == &"" and ci.key == key, "손 접점 정보")
	var fk := "TX_TECH/F01/foot_1"
	var cf := GripCheck.contact_for(fk, r.slots, &"LF", r.slots[fk].pos)
	runner.check(cf.mode == &"foot" and cf.edge == &"inside", "발 접점 정보")
