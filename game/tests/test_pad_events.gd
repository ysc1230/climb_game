extends RefCounted
## 패드 기술 이벤트(move·grab·flag·pad_foot_swap·fall, seq)와 검증기 전용 금지 플래그(docs/28 §7.4), reset_to.
## 금지 시험은 같은 입력을 금지 없이/있게 두 번 넣어 결과가 다른지 본다.

var runner

const H01 := "G_V0_01/H01/hand_1"
const H02 := "G_V0_01/H02/hand_1"
const H03 := "G_V0_01/H03/hand_1"
const H04 := "G_V0_01/H04/hand_1"
const F01 := "G_V0_01/F01/foot_1"
const F02 := "G_V0_01/F02/foot_1"
const F03 := "G_V0_01/F03/foot_1"
const F04 := "G_V0_01/F04/foot_1"


func _g_v0_01() -> RouteDef:
	return RouteDef.load_json("res://data/routes/general/G_V0_01.json")


func _session(r: RouteDef, forbid := {}, settle: int = 30) -> ClimbSession:
	var s := ClimbSession.new(r)
	s.forbid = forbid
	for i in settle:
		s.step()
	return s


## limb을 key까지 끌어 후보가 key가 되면 놓는다(test_session과 같은 방식). 붙으면 true.
## hold: 후보가 key가 된 뒤 놓기 전에 목표에 머무는 틱 수(무브 라벨 확정은 같은 구성에서 6틱 연속 확인이 필요하다).
func _drag_to(s: ClimbSession, limb: StringName, key: String, budget: int = 300, hold: int = 0) -> bool:
	var target := s.route.slot_pos(key)
	s.apply_input([{"type": "detach", "limb": limb}])
	var held := 0
	for i in budget:
		var req: Vector2 = s.limbs[limb].req
		s.apply_input([{"type": "move", "limb": limb, "delta": (target - req).limit_length(2.5 * Tuning.DT)}])
		if s.step().begins_with("fall"):
			return false
		if s.limbs[limb].cand.get("key", "") == key:
			held += 1
			if held > hold:
				s.apply_input([{"type": "release", "limb": limb}])
				return s.limbs[limb].state == "Attached" and s.limbs[limb].key == key
	return false


func _events(s: ClimbSession, type: String) -> Array:
	return s.technique_log.filter(func(e): return e.type == type)


func _labels(s: ClimbSession) -> Array:
	return _events(s, "move").map(func(e): return e.label)


# ---------- seq ----------

## Ruling D: 모든 이벤트에 단조 증가 seq. 로그가 상한(200)으로 잘려도 seq는 계속 오른다.
func test_seq_monotonic_beyond_cap() -> void:
	var s := ClimbSession.new(_g_v0_01())
	var n := ClimbSession.TECHNIQUE_LOG_MAX + 50
	for i in n:
		s._log_event({"type": "x", "i": i})
	runner.check(s.technique_log.size() == ClimbSession.TECHNIQUE_LOG_MAX, "로그 상한 유지")
	runner.check(s.event_seq == n and s.technique_log.back().seq == n, "마지막 seq = 기록 수 (%d)" % s.event_seq)
	runner.check(s.technique_log.front().seq == 51, "잘린 뒤 첫 이벤트 seq 51 (%d)" % s.technique_log.front().seq)
	var mono := true
	for i in range(1, s.technique_log.size()):
		if s.technique_log[i].seq != s.technique_log[i - 1].seq + 1:
			mono = false
	runner.check(mono, "seq 연속 증가")
	var newer := s.technique_log.filter(func(e): return e.seq > n - 3)
	runner.check(newer.size() == 3, "seq > 마지막으로 본 값으로 새 이벤트를 고름")
	s.reset()
	s.reset_to({"pelvis": [0.0, 0.744], "angle": 0.0, "slots": {"LH": H01, "RH": H02, "LF": F01, "RF": F02}})
	s._log_event({"type": "x"})
	runner.check(s.technique_log.back().seq == n + 1, "reset·reset_to 뒤에도 seq 이어짐")


# ---------- 이벤트 ----------

## 높은 발판 딛기: 드래그 중 HighStep, 놓은 뒤 StandUp. 붙을 때 grab 이벤트.
func test_high_step_then_stand_up_events() -> void:
	var s := _session(_g_v0_01())
	var ok := _drag_to(s, &"LF", F03, 300, 10)
	runner.check(ok, "LF가 F03에 붙음")
	var grabs := _events(s, "grab")
	var g: Dictionary = grabs.back() if not grabs.is_empty() else {}
	runner.check(g.get("limb", &"") == &"LF" and g.get("key", "") == F03 and g.has("quality") and g.has("seq"), "grab 이벤트 limb·key·quality (%s)" % [g])
	for i in 30:
		s.step()
	var labels := _labels(s)
	runner.check(labels.has(MoveClassifier.HIGH_STEP), "move HighStep (%s)" % [labels])
	runner.check(labels.find(MoveClassifier.STAND_UP) > labels.find(MoveClassifier.HIGH_STEP), "HighStep 뒤 StandUp (%s)" % [labels])
	# 라벨이 바뀔 때 1회: 같은 라벨이 연달아 두 번 나오지 않는다
	var dup := false
	for i in range(1, labels.size()):
		if labels[i] == labels[i - 1]:
			dup = true
	runner.check(not dup, "라벨이 바뀔 때만 기록 (%s)" % [labels])


## 교차 잡기: 발을 F03·F04로 올린 자세(reset_to)에서 왼손을 위로 돌려(H02를 겨누지 않게) 오른손 X 너머 H04로 → move CrossReach.
## 시작 자세에서 곧장 끌면 H02를 겨누어 HandMatch가 되고 H04에 닿지 않는다.
## 반환: 놓은 뒤 세션(LH가 H04에 붙었는지, 라벨은 호출자가 본다).
func _cross_attempt(forbid: Dictionary) -> ClimbSession:
	var r := _g_v0_01()
	r.slots[H04].hand_area.half_width = 0.04  # 홀드 어느 점을 잡아도 오른손 X 너머(교차)가 되게
	var s := ClimbSession.new(r)
	s.forbid = forbid
	s.reset_to({"pelvis": [0.15, 1.1], "angle": 0.0, "slots": {"LH": H01, "RH": H02, "LF": F03, "RF": F04}})
	for i in 30:
		s.step()
	s.apply_input([{"type": "detach", "limb": &"LH"}])
	for target in [Vector2(0.0, 2.3), s.route.slot_pos(H04)]:
		for i in 60:
			var req: Vector2 = s.limbs[&"LH"].req
			s.apply_input([{"type": "move", "limb": &"LH", "delta": (target - req).limit_length(2.5 * Tuning.DT)}])
			s.step()
	s.apply_input([{"type": "release", "limb": &"LH"}])
	return s


func test_cross_reach_event() -> void:
	var s := _cross_attempt({})
	runner.check(s.limbs[&"LH"].state == "Attached" and s.limbs[&"LH"].key == H04, "LH가 H04에 붙음(교차)")
	runner.check(_labels(s).has(MoveClassifier.CROSS_REACH), "move CrossReach (%s)" % [_labels(s)])


## 패드 균형 발: 받칠 곳 없는 허공에서 균형 발 예고 중 놓으면 Flag 상태와 flag 이벤트.
## 반환: [놓은 틱 번호, 놓은 뒤 RF 상태]. release_at < 0이면 flag_ready가 처음 켜진 틱에 놓는다.
func _flag_attempt(forbid: Dictionary, release_at: int) -> Array:
	var s := _session(_g_v0_01(), forbid)
	s.apply_input([{"type": "detach", "limb": &"RF"}])
	for i in 120:
		var tgt: Vector2 = s.body.pos + Vector2(-0.7, 0.0)  # 발판(F01)에서 떨어진 왼쪽 허공: 풋스왑 아님
		var req: Vector2 = s.limbs[&"RF"].req
		s.apply_input([{"type": "move", "limb": &"RF", "delta": (tgt - req).limit_length(2.5 * Tuning.DT)}])
		s.step()
		if (release_at < 0 and s.rules.flag_ready.has(&"RF")) or i == release_at:
			s.apply_input([{"type": "release", "limb": &"RF"}])
			return [i, s.limbs[&"RF"].state, _events(s, "flag"), s.limbs[&"RF"].cand]
	return [-1, s.limbs[&"RF"].state, [], {}]


func test_flag_event() -> void:
	var a := _flag_attempt({}, -1)
	runner.check(a[0] >= 0, "균형 발 예고가 켜짐")
	runner.check(a[1] == "Flag", "놓으면 Flag (%s)" % a[1])
	runner.check(a[2].size() == 1 and a[2][0].limb == &"RF", "flag 이벤트 limb RF (%s)" % [a[2]])


## 추락 시작 시 fall 이벤트(reason).
func test_fall_event() -> void:
	var s := _session(_g_v0_01())
	for limb in PoseSolver.LIMBS:
		s.apply_input([{"type": "detach", "limb": limb}])
	var out := ""
	for i in 60:
		out = s.step()
		if out.begins_with("fall"):
			break
	runner.check(out.begins_with("fall"), "추락 (%s)" % out)
	var falls := _events(s, "fall")
	runner.check(falls.size() == 1 and falls[0].reason == out.trim_prefix("fall:"), "fall 이벤트 reason (%s)" % [falls])


## 패드 풋스왑(test_final_review 7과 같은 입력): RF를 LF가 딛은 발판으로 끌어 놓는다. 반환: [RF 상태, LF 상태, 이벤트들].
## pose가 있으면 그 자세(reset_to)에서, lf_key는 LF가 딛은 발판. 놓기 직전에 forbid를 release_forbid로 바꾸고(null이면 그대로)
## 골반을 release_drop(m)만큼 낮춘다.
func _foot_swap_attempt(forbid: Dictionary, pose: Dictionary = {}, lf_key: String = F01, release_forbid = null, release_drop: float = 0.0) -> Array:
	var s := _session(_g_v0_01(), forbid)
	if not pose.is_empty():
		s.reset_to(pose)
		for i in 30:
			s.step()
	var target := s.route.slot_pos(lf_key)
	s.apply_input([{"type": "arm", "limb": &"RF"}, {"type": "detach", "limb": &"RF"}])
	for i in 200:
		var req: Vector2 = s.limbs[&"RF"].req
		s.apply_input([{"type": "move", "limb": &"RF", "delta": (target - req).limit_length(2.5 * Tuning.DT)}])
		s.step()
		if (s.limbs[&"RF"].pos as Vector2).distance_to(target) < 0.02:
			break
	if release_forbid != null:
		s.forbid = release_forbid
	s.body.pos.y -= release_drop
	var hip := PoseSolver.joint_position(s.body.pos, s.body.angle, &"RF", s.body.yaw)
	runner.check(release_drop == 0.0 or target.y >= hip.y - Tuning.HIGH_STEP_BELOW_HIP, "전제: 놓는 순간 목표가 고관절−0.20 위 (목표 %.3f, 고관절 %.3f)" % [target.y, hip.y])
	s.apply_input([{"type": "release", "limb": &"RF"}])
	return [s.limbs[&"RF"].state, s.limbs[&"LF"].state, _events(s, "pad_foot_swap")]


func test_pad_foot_swap_event() -> void:
	var a := _foot_swap_attempt({})
	runner.check(a[0] == "Attached" and a[1] == "Free", "풋스왑 (%s %s)" % [a[0], a[1]])
	runner.check(a[2].size() == 1 and a[2][0].limb == &"RF" and a[2][0].key == F01, "pad_foot_swap limb·key (%s)" % [a[2]])


## 빠른 놓기(데드포인트 제거, 2026-11-05): 몸이 올라가는 중 정적 한계 밖 홀드를 겨누고 빠르게 놓아도 던지지 않고 일반 놓기다.
func test_fast_release_is_normal_release() -> void:
	var r := RouteDef.load_json("res://data/routes/TX_TECH.json")
	var hold := "TX_TECH/N02/hand_1"
	var s := _session(r)
	for k in r.slots:
		if k != hold and not k.contains("/H0") and not k.contains("/F0"):
			r.slots[k].pos = Vector2(3.0, 3.8)
	r.slots[hold].pos = Vector2(3.0, 3.8)
	var sh := PoseSolver.joint_position(s.body.pos, s.body.angle, &"LH", s.body.yaw)
	s.apply_input([{"type": "detach", "limb": &"LH"}])
	for i in 40:
		var req: Vector2 = s.limbs[&"LH"].req
		s.apply_input([{"type": "move", "limb": &"LH", "delta": (sh + Vector2(0, 1.2) - req).limit_length(2.5 * Tuning.DT)}])
		s.step()
	for i in 30:
		s.step()
	sh = PoseSolver.joint_position(s.body.pos, s.body.angle, &"LH", s.body.yaw)
	var dz := PoseSolver.contact_dz_range() + Vector2.ONE * PoseSolver.joint_depth_offset(&"LH", s.body.yaw)
	var aim := sh + Vector2(0, 1) * (PoseSolver.planar_range(&"LH", dz.x, dz.y).y + 0.10)
	r.slots[hold].pos = aim
	var req2: Vector2 = s.limbs[&"LH"].req
	s.apply_input([{"type": "move", "limb": &"LH", "delta": aim - req2}])
	s.body.vel.y = 0.40
	s.apply_input([{"type": "release", "limb": &"LH", "speed": 2.0}])
	runner.check(s.limbs[&"LH"].state == "Free", "빠르게 놓아도 일반 놓기: Free (%s)" % s.limbs[&"LH"].state)
	for i in 12:
		s.step()
	runner.check(s.limbs[&"LH"].state != "Attached", "먼 홀드를 잡지 않음 (%s)" % s.limbs[&"LH"].state)
	runner.check(_events(s, "grab").filter(func(e): return e.key == hold).is_empty(), "먼 홀드 grab 이벤트 없음")
	runner.check(_events(s, "fall").is_empty(), "추락 없음 (%s)" % [_events(s, "fall")])


# ---------- 금지 플래그(28 §7.4) ----------

func test_forbid_defaults_empty() -> void:
	var s := ClimbSession.new(_g_v0_01())
	runner.check(s.forbid.is_empty(), "forbid 기본값 비어 있음")
	for path in ["res://scenes/play_test.gd", "res://scenes/play_3d.gd"]:
		runner.check(FileAccess.file_exists(path), "%s 있음(옮겼으면 이 검사 경로를 고친다)" % path)
		runner.check(FileAccess.file_exists(path) and not FileAccess.get_file_as_string(path).contains("forbid"), "%s는 forbid를 설정하지 않음" % path)


func test_forbid_high_step_rejects_high_foot() -> void:
	runner.check(_drag_to(_session(_g_v0_01()), &"LF", F03), "금지 없음: F03 딛기")
	var s := _session(_g_v0_01(), {&"high_step": true})
	runner.check(not _drag_to(s, &"LF", F03, 200), "high_step 금지: F03(고관절−0.20 위) 후보 아님")
	runner.check(s.limbs[&"LF"].state != "Attached" or s.limbs[&"LF"].key != F03, "F03에 붙지 않음")


## StandUp 선호(다리 0.86·골반을 발 위로)를 끈다. 라벨은 그대로.
func test_forbid_high_step_disables_stand_up_profile() -> void:
	var att := {&"LH": Vector2(-0.45, 1.80), &"RH": Vector2(0.45, 1.80), &"LF": Vector2(-0.35, 0.65), &"RF": Vector2(0.30, 0.10)}
	var p := Vector2(0.0, 0.744)
	var c := MoveClassifier.new()
	for i in Tuning.MOVE_SWITCH_CONFIRM_TICKS:  # 같은 구성에서 라벨 전환은 확인 틱이 필요
		c.update(p, 0.0, att, {}, {}, {})
	runner.check(c.label == MoveClassifier.STAND_UP, "전제: StandUp (%s)" % c.label)
	runner.check(is_equal_approx(c.profile[&"LF"], Tuning.PREF_LEG_STAND) and c.profile.has(&"_stand_x"), "금지 없음: 다리 0.86·골반 목표 X")
	var f := MoveClassifier.new()
	f.forbid = {&"high_step": true}
	for i in Tuning.MOVE_SWITCH_CONFIRM_TICKS:
		f.update(p, 0.0, att, {}, {}, {})
	runner.check(f.label == MoveClassifier.STAND_UP, "라벨은 StandUp 유지")
	runner.check(is_equal_approx(f.profile[&"LF"], Tuning.PREF_LEG_DEFAULT) and not f.profile.has(&"_stand_x"), "금지: 다리 0.78, 골반 목표 X 없음 (%s)" % [f.profile])


## 같은 교차 입력(test_cross_reach_event): 금지 없으면 H04를 잡고, cross 금지면 못 잡는다.
func test_forbid_cross_rejects_crossing_hand() -> void:
	var a := _cross_attempt({})
	runner.check(a.limbs[&"LH"].state == "Attached" and a.limbs[&"LH"].key == H04, "금지 없음: LH가 H04를 교차해 잡음")
	var b := _cross_attempt({&"cross": true})
	runner.check(not (b.limbs[&"LH"].state == "Attached" and b.limbs[&"LH"].key == H04), "cross 금지: 오른손 X 너머 H04를 못 잡음 (%s %s)" % [b.limbs[&"LH"].state, b.limbs[&"LH"].key])
	var c := _session(_g_v0_01(), {&"cross": true})
	runner.check(_drag_to(c, &"LH", H03), "넘지 않는 H03은 잡음")


func test_forbid_flag() -> void:
	var a := _flag_attempt({}, -1)
	var b := _flag_attempt({&"flag": true}, a[0])
	runner.check(a[1] == "Flag", "금지 없음: Flag")
	runner.check(b[0] == a[0] and b[3].is_empty(), "같은 틱에 놓음, 후보 없음")
	runner.check(b[1] == "Free" and b[2].is_empty(), "flag 금지: Free, flag 이벤트 없음 (%s)" % b[1])


func test_forbid_match_rejects_other_hand_hold() -> void:
	runner.check(_drag_to(_session(_g_v0_01()), &"LH", H02), "금지 없음: 오른손 홀드 H02 매치")
	var s := _session(_g_v0_01(), {&"match": true})
	runner.check(not _drag_to(s, &"LH", H02, 200), "match 금지: 반대 손이 잡은 H02 후보 아님")


## high_step 금지는 높은 발판(고관절−0.20 위)으로 바꿔 딛는 패드 풋스왑도 막는다(우회로 방지).
## 자연 재생에서는 발이 닿을 즈음 몸이 올라와 목표가 더 이상 "높지" 않으므로(그리고 처음부터 금지하면 StandUp 선호가 꺼져
## 닿지 못해 풋스왑 검사를 거치지 않으므로), 같은 드래그를 금지 없이 하고 놓기 직전에 골반을 0.04m 낮춰(고관절 0.878→0.838, 문턱 0.638 < F03 0.65) 목표를 높게 만든 뒤
## 금지 없음/있음을 비교한다. 두 시도는 놓기 직전 상태가 같다.
func test_forbid_high_step_blocks_high_foot_swap() -> void:
	var pose := {"pelvis": [0.0, 0.744], "angle": 0.0, "slots": {"LH": H01, "RH": H02, "LF": F03, "RF": F02}}
	var a := _foot_swap_attempt({}, pose, F03, {}, 0.04)
	runner.check(a[0] == "Attached" and a[1] == "Free" and a[2].size() == 1 and a[2][0].key == F03, "금지 없음: 높은 F03으로 풋스왑 (%s %s %s)" % [a[0], a[1], a[2]])
	var b := _foot_swap_attempt({}, pose, F03, {&"high_step": true}, 0.04)
	runner.check(b[0] != "Attached" and b[1] == "Attached" and b[2].is_empty(), "high_step 금지: F03 풋스왑 거부 (%s %s %s)" % [b[0], b[1], b[2]])


func test_forbid_foot_swap() -> void:
	var a := _foot_swap_attempt({&"foot_swap": true})
	runner.check(a[0] != "Attached" and a[1] == "Attached", "foot_swap 금지: RF 못 붙고 LF 유지 (%s %s)" % [a[0], a[1]])
	runner.check(a[2].is_empty(), "pad_foot_swap 이벤트 없음")


## LockOff 선호(팔 0.42)를 끄고 뻗기(0.60). 라벨은 그대로.
func test_forbid_lock_off_profile() -> void:
	var att := {&"RH": Vector2(0.45, 1.80), &"LF": Vector2(-0.30, 0.10), &"RF": Vector2(0.30, 0.10)}
	var p := Vector2(0.0, 0.744)
	var intents := {&"LH": Vector2(-0.45, 3.0)}
	var eps := {&"LH": Vector2(-0.45, 1.80)}
	var c := MoveClassifier.new()
	c.update(p, 0.0, att, intents, eps, {})
	runner.check(c.label == MoveClassifier.LOCK_OFF and is_equal_approx(c.profile[&"RH"], Tuning.PREF_ARM_LOCKOFF), "금지 없음: LockOff, 붙은 팔 0.42 (%s %s)" % [c.label, c.profile])
	var f := MoveClassifier.new()
	f.forbid = {&"lock_off": true}
	f.update(p, 0.0, att, intents, eps, {})
	runner.check(f.label == MoveClassifier.LOCK_OFF and is_equal_approx(f.profile[&"RH"], Tuning.PREF_ARM_REACH), "lock_off 금지: 팔 0.60 (%s)" % [f.profile])


## ClimbRules가 무브 판별에 forbid를 넘긴다(세션 → 규칙 → 판별).
func test_forbid_reaches_classifier() -> void:
	var s := _session(_g_v0_01(), {&"lock_off": true}, 1)
	runner.check(s.rules.forbid.has(&"lock_off") and s.rules.moves.forbid.has(&"lock_off"), "rules·moves에 전달")


func test_forbid_grip_auto() -> void:
	var r := RouteDef.load_json("res://data/routes/TX_GRIP.json")
	var u01 := "TX_GRIP/U01/hand_1"  # undercling, pull. 발이 낮으면 자동은 pull
	var a := _session(r)
	runner.check(_drag_to(a, &"RH", u01), "RH가 U01에 붙음")
	runner.check(a.limbs[&"RH"].contact.mode == &"pull", "자동: pull (%s)" % a.limbs[&"RH"].contact.mode)
	var b := _session(RouteDef.load_json("res://data/routes/TX_GRIP.json"), {&"grip_auto": true})
	runner.check(_drag_to(b, &"RH", u01), "금지: RH가 U01에 붙음")
	runner.check(b.limbs[&"RH"].contact.mode == &"undercling", "grip_auto 금지: grip_modes[0] undercling (%s)" % b.limbs[&"RH"].contact.mode)


# ---------- reset_to ----------

func test_reset_to_pose() -> void:
	var s := _session(_g_v0_01())
	_drag_to(s, &"LH", H03)
	var pose := {"pelvis": [0.05, 0.80], "angle": 2.0, "slots": {"LH": H03, "RH": H04, "LF": F01, "RF": F02}, "stamina": {"LH": 60.0, "RH": 45.0}}
	s.reset_to(pose)
	runner.check(s.body.pos.is_equal_approx(Vector2(0.05, 0.80)) and is_equal_approx(s.body.angle, 2.0), "골반·각도 (%s %.1f)" % [s.body.pos, s.body.angle])
	for limb in [&"LH", &"RH", &"LF", &"RF"]:
		var want: String = pose.slots[String(limb)]
		runner.check(s.limbs[limb].state == "Attached" and s.limbs[limb].key == want and (s.limbs[limb].grab as Vector2).is_equal_approx(s.route.slot_pos(want)), "%s 붙음 %s" % [limb, want])
	runner.check(is_equal_approx(s.rules.stamina[&"LH"], 60.0) and is_equal_approx(s.rules.stamina[&"RH"], 45.0), "체력 (%s)" % [s.rules.stamina])
	runner.check(not s.falling and not s.selecting, "추락·선택 초기화")
	var bad := ""
	for i in 60:
		bad = s.step()
		if bad != "":
			break
	runner.check(bad == "", "새 자세로 60틱 진행 (%s)" % bad)
	# stamina 생략 → 100, slots에 없는 팔다리는 Free
	s.reset_to({"pelvis": [0.0, 0.744], "angle": 0.0, "slots": {&"LH": H01, &"RH": H02, &"LF": F01}})
	runner.check(is_equal_approx(s.rules.stamina[&"LH"], 100.0), "stamina 생략 → 100")
	runner.check(s.limbs[&"RF"].state == "Free" and s.limbs[&"LF"].key == F01, "빠진 RF는 Free")
