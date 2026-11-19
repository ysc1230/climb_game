extends RefCounted
## 잡힐 자리 표시·손이 홀드에 붙어 보이게(docs/superpowers/specs/2026-11-19-1-feel-design.md §1.5).

var runner


func _route() -> RouteDef:
	return RouteDef.load_json("res://tests/fixtures/G_V0_01.json")


func test_lift_scale() -> void:
	runner.check(ReachMarker.lift_scale(0.0) == 0.0, "홀드 위 0")
	runner.check(is_equal_approx(ReachMarker.lift_scale(0.075), 0.5), "절반 거리 0.5")
	runner.check(ReachMarker.lift_scale(0.15) == 1.0, "NEAR에서 1")
	runner.check(ReachMarker.lift_scale(0.3) == 1.0, "멀면 1")
	runner.check(ReachMarker.lift_scale(INF) == 1.0, "슬롯 없음 1")


func test_nearest_slot_dist() -> void:
	var r := _route()
	var hand_key := ""
	var foot_only := ""
	for key in r.slots:
		var sl: Dictionary = r.slots[key]
		if hand_key == "" and sl.allowed.has(&"LH") and not r.start_slots.values().has(key):
			hand_key = key
		if foot_only == "" and not sl.allowed.has(&"LH") and sl.allowed.has(&"LF"):
			foot_only = key
	runner.check(hand_key != "", "손 슬롯 있음")
	runner.check(is_zero_approx(ReachMarker.nearest_slot_dist(r, &"LH", r.slots[hand_key].pos, {})), "손 슬롯 위 0")
	if foot_only != "":
		var p: Vector2 = r.slots[foot_only].pos
		runner.check(ReachMarker.nearest_slot_dist(r, &"LH", p, {}) > 0.0, "발 전용 슬롯은 손에서 제외")
	var occ := {hand_key: &"RH"}
	runner.check(ReachMarker.nearest_slot_dist(r, &"LH", r.slots[hand_key].pos, occ) > 0.0, "점유 슬롯 제외")


func test_ring_point() -> void:
	runner.check(ReachMarker.ring_point({"pos": Vector2(1, 2), "cand": {}}) == Vector2(1, 2), "후보 없으면 판정 점")
	runner.check(ReachMarker.ring_point({"pos": Vector2(1, 2), "cand": {"key": "k", "point": Vector2(1.1, 2.1)}}) == Vector2(1.1, 2.1), "후보 있으면 후보 점")


func test_display_point_snaps_toward_candidate() -> void:
	var l := {"pos": Vector2(0, 0), "cand": {"key": "k", "point": Vector2(0, 0.15)}}
	var d := ReachMarker.display_point(Vector2(0, 0), l, 1.0 / 60.0)
	runner.check(d.y > 0.0 and d.y < 0.15, "한 프레임에 후보 쪽으로 조금 %s" % d)
	for i in 60:
		d = ReachMarker.display_point(d, l, 1.0 / 60.0)
	runner.check(d.distance_to(Vector2(0, 0.15)) < 0.005, "1초면 후보 점에 붙음 %s" % d)
	var back := ReachMarker.display_point(d, {"pos": Vector2(0, 0), "cand": {}}, 1.0)
	runner.check(back.distance_to(Vector2.ZERO) < 0.005, "후보가 없어지면 판정 점으로 %s" % back)
