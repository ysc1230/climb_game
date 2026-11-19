extends RefCounted
## 잡는 손맛(docs/superpowers/specs/2026-11-19-1-feel-design.md §1.4): 사건 → 소리·진동·가루.

var runner


func _hand_slot(hw: float, matchable := false) -> Dictionary:
	return {"hand_area": {"half_width": hw, "matchable": matchable}}


func test_pick_hand_sizes() -> void:
	var ev := {"type": "grab", "limb": &"LH"}
	var big := GrabFeel.pick(ev, _hand_slot(0.12))
	runner.check(big.sound == &"grab_big" and big.vib_ms == 22 and is_equal_approx(big.vib_amp, 0.7) and big.puff == &"chalk", "큰 홀드 %s" % [big])
	var mid := GrabFeel.pick(ev, _hand_slot(0.06))
	runner.check(mid.sound == &"grab_mid" and mid.vib_ms == 18 and is_equal_approx(mid.vib_amp, 0.5) and mid.puff == &"chalk", "보통 %s" % [mid])
	var small := GrabFeel.pick(ev, _hand_slot(0.04))
	runner.check(small.sound == &"grab_small" and small.vib_ms == 12 and is_equal_approx(small.vib_amp, 0.35) and small.puff == &"chalk_small", "작은 %s" % [small])
	var m := GrabFeel.pick(ev, _hand_slot(0.04, true))
	runner.check(m.sound == &"grab_big", "합손 홀드는 큰 소리 %s" % [m])


func test_pick_foot_and_miss() -> void:
	var f := GrabFeel.pick({"type": "grab", "limb": &"RF"}, {"foot_area": {"half_height": 0.04}})
	runner.check(f.sound == &"step_foot" and f.vib_ms == 12 and is_equal_approx(f.vib_amp, 0.3) and f.puff == &"dust", "발 %s" % [f])
	var miss := GrabFeel.pick({"type": "miss", "limb": &"LH"}, {})
	runner.check(miss.sound == &"miss" and miss.vib_ms == 0 and miss.puff == &"", "헛놓기 %s" % [miss])
	runner.check(GrabFeel.pick({"type": "fall"}, {}).is_empty(), "다른 사건은 없음")


func test_feel_dedupe_same_window() -> void:
	var g := GrabFeel.Gate.new()
	runner.check(g.allow(&"grab_mid", 0.00), "처음 소리")
	runner.check(not g.allow(&"grab_mid", 0.03), "0.08초 안 같은 소리 막음")
	runner.check(g.allow(&"grab_mid", 0.09), "0.08초 뒤 다시")
	runner.check(g.allow(&"step_foot", 0.091), "다른 소리는 따로")
	runner.check(g.allow_vibe(0.00), "처음 진동")
	runner.check(not g.allow_vibe(0.05), "0.08초 안 진동 하나만")
