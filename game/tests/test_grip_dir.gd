extends RefCounted
## 홀드 면 방향에 따른 손 잡기(2026-11-26 사용자 "홀드 방향에 따라 손이 잡는 방향도 같이 바뀌어야해 … 특정 방향에서 손으로 잡기 불가능한 홀드,
## 불편한 홀드 … 힘이 빠지는 속도가 달라져야", "실제 사람이 어떻게 동작하는지 판단해서", "크림프는 잡는게 한쪽면밖에 없고 슬로퍼도 … 한쪽으로밖에,
## 저그는 … 반대편으로 잡을수는 있으나 잡기 힘들어", "모든 홀드들이 손홀드이자 발홀드").

var runner

const PEL := Vector2(0.0, 1.0)   # 골반. 어깨는 대략 (±0.2, 1.5)


func _k(limb: StringName, rot: float, hold: Vector2) -> StringName:
	return GripDir.kind(limb, HoldTypes.rotate(Vector2(0, 1), rot), hold, PEL, 0.0, 0.0)


## 예시 1(사용자 "오른손만 잡힘"): 날이 오른쪽(rot 90)인 홀드가 몸 오른쪽 어깨 높이.
func test_sidepull_right_hand_only() -> void:
	var hold := Vector2(0.45, 1.5)
	runner.check(_k(&"RH", 90, hold) == &"sidepull", "오른손 사이드풀 %s" % _k(&"RH", 90, hold))
	runner.check(_k(&"LH", 90, hold) == &"", "왼손은 못 잡음 %s" % _k(&"LH", 90, hold))


## 예시 2(사용자 "실제 사람처럼 판단"): 같은 홀드가 몸 왼쪽(날이 몸 쪽). 왼손은 엄지 아래로 개스턴(밀기),
## 오른손은 몸을 가로질러야 해서 못 잡는다(예시 1에서 반대 손 가로지르기를 막은 것과 같은 이유).
func test_face_toward_body_gaston() -> void:
	var hold := Vector2(-0.45, 1.5)
	runner.check(_k(&"LH", 90, hold) == &"gaston", "왼손 개스턴 %s" % _k(&"LH", 90, hold))
	runner.check(_k(&"RH", 90, hold) == &"", "오른손은 가로질러 못 잡음 %s" % _k(&"RH", 90, hold))
	runner.check(_k(&"LH", 90, Vector2(-0.45, 2.3)) == &"", "개스턴은 어깨 높이에서만(머리 위 못 잡음)")
	runner.check(GripDir.FATIGUE[&"gaston"] > GripDir.FATIGUE[&"undercling"] and GripDir.FATIGUE[&"undercling"] > GripDir.FATIGUE[&"sidepull"] and GripDir.FATIGUE[&"sidepull"] > GripDir.FATIGUE[&"pull"], "불편할수록 힘이 빨리 빠짐")


## 아래를 보는 면(언더): 어깨보다 낮을 때만. 위를 보는 면: 어느 손이든.
func test_undercling_below_shoulder_and_pull() -> void:
	runner.check(_k(&"LH", 180, Vector2(-0.2, 1.2)) == &"undercling" and _k(&"RH", 180, Vector2(0.2, 1.2)) == &"undercling", "가슴 아래 언더")
	runner.check(_k(&"RH", 180, Vector2(0.2, 2.2)) == &"", "머리 위 언더는 못 잡음")
	runner.check(_k(&"LH", 0, Vector2(0.4, 2.2)) == &"pull" and _k(&"RH", 0, Vector2(-0.4, 2.2)) == &"pull", "위를 보는 면은 어느 손이든")
	runner.check(_k(&"RH", 45, Vector2(0.3, 2.0)) == &"pull" and _k(&"RH", 110, Vector2(0.4, 1.3)) == &"sidepull" and _k(&"RH", 150, Vector2(0.4, 1.3)) == &"undercling", "사선은 가까운 쪽 방식(위·아래 60° 안은 당기기·언더)")


## 종류마다 잡는 면: 크림프·슬로퍼·포켓은 한 면, 저그는 반대 면도(힘 두 배), 핀치는 양옆. 발판도 손으로 잡히지만 나쁨.
func test_hold_type_faces() -> void:
	var s := {}
	HoldTypes.fill(s, {"hold_type": "crimp", "size": "M", "rot_deg": 0})
	runner.check(s.grip_modes.size() == 1, "크림프 한 면")
	HoldTypes.fill(s, {"hold_type": "sloper", "size": "M", "rot_deg": 0})
	runner.check(s.grip_modes.size() == 1, "슬로퍼 한 면")
	HoldTypes.fill(s, {"hold_type": "jug", "size": "M", "rot_deg": 0})
	runner.check(s.grip_modes.size() == 2 and (s.grip_modes[1].axis as Vector2).y < -0.99 and float(s.grip_modes[1].get("fatigue", 1.0)) >= 2.0, "저그 반대 면은 힘 두 배 %s" % [s.grip_modes])
	HoldTypes.fill(s, {"hold_type": "foot_chip", "size": "M", "rot_deg": 0})
	runner.check(s.has("hand_area") and s.has("foot_area") and float(s.fatigue_mult) > 1.5, "작은 발판도 손으로(힘 빨리 빠짐) %s" % [s.get("fatigue_mult")])


## 잡기: 그 손으로 못 잡는 면이면 후보가 아니다. 잡은 뒤 몸이 옮겨 못 잡는 자세가 되면 품질이 떨어져 미끄러진다.
func test_candidate_and_slip() -> void:
	var r := RouteDef.from_dict({"route_id": "GD", "holds": [
		{"hold_id": "H1", "slots": [{"slot_id": "h", "pos": [-0.3, 1.5], "allowed": ["LH", "RH"], "hold_type": "jug", "size": "M"}]},
		{"hold_id": "H2", "slots": [{"slot_id": "h", "pos": [0.3, 1.5], "allowed": ["LH", "RH"], "hold_type": "jug", "size": "M"}]},
		{"hold_id": "F1", "slots": [{"slot_id": "f", "pos": [-0.15, 0.1], "allowed": ["LF"], "hold_type": "foot_chip", "size": "M"}]},
		{"hold_id": "F2", "slots": [{"slot_id": "f", "pos": [0.18, 0.1], "allowed": ["RF"], "hold_type": "foot_chip", "size": "M"}]},
		{"hold_id": "S", "slots": [{"slot_id": "h", "pos": [0.55, 1.75], "allowed": ["LH", "RH"], "hold_type": "crimp", "size": "L", "rot_deg": 90}]},
		{"hold_id": "T", "slots": [{"slot_id": "h", "pos": [0.0, 2.6], "allowed": ["LH", "RH"], "hold_type": "jug", "size": "L", "hand_area": {"matchable": true}}]}],
		"goal_slots": ["GD/T/h"], "start_pose": {"pelvis": [0.0, 0.75], "slots": {"LH": "GD/H1/h", "RH": "GD/H2/h", "LF": "GD/F1/f", "RF": "GD/F2/f"}}})
	runner.check(r.errors.is_empty(), "시험 문제 %s" % [r.errors])
	var s := ClimbSession.new(r)
	var at := s.attached()
	var key := "GD/S/h"
	var sp: Vector2 = r.slots[key].pos
	var lh := GripCheck.candidate(r.slots, &"LH", sp, s.body.pos, s.body.angle, at, s.occupied())
	var rh := GripCheck.candidate(r.slots, &"RH", sp, s.body.pos, s.body.angle, at, s.occupied())
	runner.check(lh.get("key", "") != key, "왼손은 오른쪽 사이드풀 후보 아님 %s" % [lh])
	runner.check(rh.get("key", "") == key, "오른손은 후보 %s" % [rh])
	var ci := GripCheck.contact_for(key, r.slots, &"RH", sp, s.body.pos, 0.0, 0.0)
	runner.check(ci.mode == &"sidepull" and ci.fatigue_mult > float(r.slots[key].fatigue_mult) + 0.01, "사이드풀로 붙고 힘 배율이 큼 %s %.2f" % [ci.mode, ci.fatigue_mult])
	var rules := ClimbRules.new()
	rules.contact_meta[&"RH"] = ci
	var ok_q := rules.quality_at(&"RH", NAN, Vector2(0.0, 1.0))
	var bad_q := rules.quality_at(&"RH", NAN, Vector2(1.0, 1.0))  # 몸이 홀드 오른쪽(날 쪽)으로 넘어감
	runner.check(bad_q < ok_q * 0.5, "몸이 날 쪽으로 넘어가면 미끄러짐 %.2f → %.2f" % [ok_q, bad_q])


## V4 "옆으로 당기기"(G_V4_12): 왼쪽을 보는 H03은 왼손만, 오른쪽을 보는 H05는 오른손만(몸은 두 홀드 사이).
func test_v4_side_route_hands() -> void:
	var r := RouteDef.load_json(ContentIndex.route_path("G_V4_12"))
	var pel := Vector2(0.15, 1.3)
	var h3: Dictionary = r.slots["G_V4_12/H03/hand_1"]
	var h5: Dictionary = r.slots["G_V4_12/H05/hand_1"]
	runner.check(GripDir.kind(&"LH", h3.grip_modes[0].axis, h3.pos, pel, 0.0, 0.0) == &"sidepull" and not GripDir.any_ok(h3, &"RH", pel, 0.0, 0.0), "H03은 왼손 사이드풀만")
	runner.check(GripDir.kind(&"RH", h5.grip_modes[0].axis, h5.pos, pel, 0.0, 0.0) == &"sidepull" and not GripDir.any_ok(h5, &"LH", pel, 0.0, 0.0), "H05는 오른손 사이드풀만")


## 잡기 안내 색(2026-11-27 사용자 "초록 주황 빨강 색으로 가이드"): 노리는 홀드를 그 손으로 못 잡으면 빨강, 잡히면 초록·주황.
func test_grip_guide_colors() -> void:
	var r := RouteDef.load_json(ContentIndex.route_path("G_V4_12"))
	var s := ClimbSession.new(r)
	var R := "G_V4_12/"
	s.reset_to({"pelvis": [0.05, 1.15], "slots": {"LH": R + "H01/hand_1", "RH": R + "H02/hand_1", "LF": R + "F04/foot_1", "RF": R + "F03/foot_1"}})
	var key := R + "H03/hand_1"   # 왼쪽을 보는 크림프(몸 왼쪽): 왼손만
	var hp: Vector2 = r.slots[key].pos
	for hand in [&"LH", &"RH"]:
		var l: Dictionary = s.limbs[hand]
		l.state = "Dragging"
		l.req = hp
		l.pos = hp
		l.cand = GripCheck.candidate(r.slots, hand, hp, s.body.pos, s.body.angle, s.attached(), s.occupied())
	var lg := ReachMarker.grip_guide(s, &"LH")
	var rg := ReachMarker.grip_guide(s, &"RH")
	runner.check(lg.get("key", "") == key and lg.level != ReachMarker.Guide.BAD, "왼손: 잡힘(초록·주황) %s" % [lg])
	runner.check(rg.get("key", "") == key and rg.level == ReachMarker.Guide.BAD, "오른손: 못 잡는 면이라 빨강 %s" % [rg])
	runner.check(ReachMarker.grip_guide(s, &"LF").is_empty(), "발은 안내 없음")


## 튜토리얼 잠금(2026-11-27 사용자 "가이드중인 스텝외에는 선택이 안되도록"): 플레이는 가리키는 홀드만 잡고, 만들기는 가리키는 버튼만.
func test_tutorial_locks() -> void:
	var r := RouteDef.load_json(ContentIndex.route_path("G_V4_12"))
	var s := ClimbSession.new(r)
	var R := "G_V4_12/"
	s.reset_to({"pelvis": [0.05, 1.15], "slots": {"LH": R + "H01/hand_1", "RH": R + "H02/hand_1", "LF": R + "F04/foot_1", "RF": R + "F03/foot_1"}})
	var hp: Vector2 = r.slots[R + "H03/hand_1"].pos
	s.limbs[&"LH"].pos = hp
	runner.check(s._candidate(&"LH").get("key", "") == R + "H03/hand_1", "잠금 없으면 H03 후보")
	s.only_slots = {&"LH": R + "H04/hand_1"}
	runner.check(s._candidate(&"LH").get("key", "") != R + "H03/hand_1", "튜토리얼이 H04를 가리키면 H03은 못 잡음")
	var ui = load("res://scenes/editor_ui.gd").new()
	ui.tut = EditorTutorial.new()
	runner.check(ui._tut_allows("type", "jug") and not ui._tut_allows("save", "") and not ui._tut_allows("type", "crimp") and ui._tut_allows("tut", ""),
		"만들기 첫 단계: [저그]와 [끄기]만")
	ui.tut.index = ui.tut.steps.map(func(st): return st.id).find("free")
	runner.check(ui._tut_allows("type", "crimp") and ui._tut_allows("tut_next", "") and not ui._tut_allows("save", "") and not ui._tut_allows("exit", ""),
		"자유롭게 놓기: 홀드 고치기·[다음]만")
	ui.free()
