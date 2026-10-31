class_name TechniqueJudge
extends RefCounted
## 기술 실행 가능 판단(docs/27 §7, §10, §11). 입력은 ClimbSnapshot(확정된 틱의 복사본)이며 순수 함수다.
## 판단 순서(27 §7.1): 1 게임 상태 → 2 손발 상태 → 3 떼기 판단 → 4 홀드 → 5 관절·몸통 → 6 균형·하중 → 7 피로.
## 쪽 판단(judge)은 홀드 후보 목록을 계산하지 않는다(27 §11). 4단계는 거리·종류·점유만 보는 가벼운 존재 검사이고,
## 홀드별 관절·체중 이동·힘 균형(5·6단계)은 쪽을 고른 뒤 hold_targets/check_hold가 계산한다.
## 구현: 위치형 기술(8a), yaw형 기술 드롭니·아웃사이드 엣지(8b), 플래그 3종(8c). 그 외 기술은 MOVE_NOT_SUPPORTED로 막아 둔다.

const WRONG_PHASE := &"WRONG_PHASE"
const LIMB_STATE := &"LIMB_STATE"
const SUPPORT_NEEDED := &"SUPPORT_NEEDED"
const NO_HOLD := &"NO_HOLD"
const JOINT_LIMIT := &"JOINT_LIMIT"
const BODY_ORIENTATION_LIMIT := &"BODY_ORIENTATION_LIMIT"
const NEED_WEIGHT_SHIFT := &"NEED_WEIGHT_SHIFT"
const SUPPORT_OVERLOAD := &"SUPPORT_OVERLOAD"
const BARN_DOOR := &"BARN_DOOR"
const PIVOT_NOT_ALLOWED := &"PIVOT_NOT_ALLOWED"
const GRIP_TOO_POOR := &"GRIP_TOO_POOR"
const TOO_TIRED := &"TOO_TIRED"
const MOVE_NOT_SUPPORTED := &"MOVE_NOT_SUPPORTED"
const DEADPOINT_MISS := &"DEADPOINT_MISS"

## 27 §7.3 문구. LIMB_STATE는 기술별 문구를 따로 만든다. 홀드 탭 거부는 GripCheck 문구도 쓴다.
const TEXTS := {
	WRONG_PHASE: "",
	SUPPORT_NEEDED: "이 손발을 떼면 버틸 수 없어요",
	NO_HOLD: "지금 이 기술로 쓸 수 있는 홀드가 없어요",
	JOINT_LIMIT: "팔·다리 각도 한계예요",
	BODY_ORIENTATION_LIMIT: "몸을 더 돌릴 수 없어요",
	NEED_WEIGHT_SHIFT: "먼저 체중을 옮겨야 해요",
	SUPPORT_OVERLOAD: "남은 손발로 버티기 어려워요",
	BARN_DOOR: "몸이 문처럼 돌아가요. 반대쪽으로 균형을 잡아 보세요",
	PIVOT_NOT_ALLOWED: "이 발판에서는 발을 돌릴 수 없어요",
	GRIP_TOO_POOR: "홀드를 너무 끝에 잡았어요",
	TOO_TIRED: "팔 힘이 부족해요",
	MOVE_NOT_SUPPORTED: "아직 준비 중인 기술이에요",
	DEADPOINT_MISS: "홀드를 놓쳤어요",
}

const T_INSIDE_EDGE := &"T_INSIDE_EDGE"
const T_HIGH_STEP := &"T_HIGH_STEP"
const T_CROSS := &"T_CROSS"
const T_MATCH := &"T_MATCH"
const T_FOOT_SWAP := &"T_FOOT_SWAP"
const T_SIDEPULL := &"T_SIDEPULL"
const T_GASTON := &"T_GASTON"
const T_UNDERCLING := &"T_UNDERCLING"
const T_REST := &"T_REST"
const T_LOCK_OFF := &"T_LOCK_OFF"
const T_OUTSIDE_EDGE := &"T_OUTSIDE_EDGE"
const T_DROP_KNEE := &"T_DROP_KNEE"
const T_FLAG := &"T_FLAG"
const T_FLAG_INSIDE := &"T_FLAG_INSIDE"
const T_FLAG_OUTSIDE := &"T_FLAG_OUTSIDE"
const T_DEADPOINT := &"T_DEADPOINT"

## 손발을 홀드로 옮기는 기술(hold_tap). 실행기는 Dragging 경로로 옮긴 뒤 붙인다.
const MOVE_TECHS: Array[StringName] = [T_INSIDE_EDGE, T_HIGH_STEP, T_CROSS, T_MATCH, T_FOOT_SWAP, T_SIDEPULL, T_GASTON, T_UNDERCLING, T_OUTSIDE_EDGE, T_DEADPOINT]
const SUPPORTED: Array[StringName] = [T_INSIDE_EDGE, T_HIGH_STEP, T_CROSS, T_MATCH, T_FOOT_SWAP, T_SIDEPULL, T_GASTON, T_UNDERCLING, T_REST, T_LOCK_OFF, T_OUTSIDE_EDGE, T_DROP_KNEE, T_FLAG, T_FLAG_INSIDE, T_FLAG_OUTSIDE, T_DEADPOINT]
const HAND_TECHS: Array[StringName] = [T_CROSS, T_MATCH, T_SIDEPULL, T_GASTON, T_UNDERCLING, T_LOCK_OFF, T_DEADPOINT]
## 잡기 방식을 정하는 기술. 그 외 손 기술은 패드와 같이 홀드의 첫 grip_mode를 쓴다(27 §11).
const MODE_OF := {T_SIDEPULL: &"sidepull", T_GASTON: &"gaston", T_UNDERCLING: &"undercling"}

const MIN_GRIP_QUALITY := 0.5        # 27 §8.1: q < 0.5면 록오프·사이드풀·개스턴 불가
const LOCK_OFF_MIN_STAMINA := 30.0   # 27 §7.1 7단계
const LOCK_OFF_PREF := Tuning.PREF_ARM_LOCKOFF
const GASTON_SHOULDER_BAND := 0.30   # 개스턴: 홀드가 어깨 높이 ±0.30m (구현 해석)
const HIGH_FOOT_BELOW_HIP := 0.55    # 언더클링의 "높은 발": 하중 발 Y ≥ 고관절 Y − 0.55 (25 StandUp의 높은 발 기준)
const DROP_KNEE_YAW := 35.0          # 27 §10: 드롭니 ψ 목표(도). 그 발 쪽 엉덩이를 벽으로: 왼발 ψ<0, 오른발 ψ>0
const OUTSIDE_EDGE_YAW := 30.0       # 27 §10: 아웃사이드 엣지 ψ 목표(도)
const FLAG_GRID := 0.05              # 플래그 위치 탐색 격자(m, 04 §10.6)
const FLAG_COARSE := 3               # 1차 거친 탐색 간격 = FLAG_GRID × 3 (0.15m)
const FLAG_REFINE_TOP := 3           # 거친 탐색 상위 몇 점 주변을 0.05m로 다듬는가
const FLAG_NO_GAIN_TEXT := "지금은 균형에 도움이 안 돼요"
const FLAG_MIN_BELOW_JOINT := 0.10   # 플래그 발은 고관절보다 이만큼 이상 아래(m, 구현 해석)
## 변형별 깊이 힌트(m, 표현용; 판정은 평면): 인사이드는 지지발 앞(벽과 몸 사이), 아웃사이드는 뒤
const FLAG_DEPTH := {T_FLAG: 0.0, T_FLAG_INSIDE: -0.05, T_FLAG_OUTSIDE: 0.10}
const DEADPOINT_RISE_SPEED := 0.20   # 04 §10.5: 골반 위 방향 속도 ≥ 0.20m/s면 창이 열림(자연 일어서기 최대 0.244)
const DEADPOINT_MIN_SPEED := 1.0     # 패드 놓기 속도(m/s)가 이 이상일 때만 데드포인트("빠르게 드래그", 27 §8.4)
const DEADPOINT_GRACE_TICKS := 15    # 상승이 끝난 뒤 0.25초까지 열림
const DEADPOINT_MAX_BONUS := 0.15
const DEADPOINT_MIN_QUALITY := 0.5
const DEADPOINT_LOAD_FACTOR := 1.3   # 순간 하중 배율(받기 판정은 최대 하중을 1/1.3로 계산)
const DEADPOINT_AIM_MARGIN := 0.10   # 보너스 범위를 이만큼 넘는 홀드까지는 "던져 보는" 대상(놓치면 추락)
const DEADPOINT_TEXT_CLOSED := "몸이 올라가는 중에만 쓸 수 있어요"
const SHIFT_SEARCHES := 3            # 체중 이동 후 도달 판정의 목표 탐색 반복(각 ±0.30m)

static var _defs := {}


static func defs() -> Dictionary:
	if _defs.is_empty():
		_defs = TechniqueDefs.load_all()
	return _defs


static func text_for(reason: StringName) -> String:
	if TEXTS.has(reason):
		return TEXTS[reason]
	return GripCheck.MESSAGES.get(reason, "")


static func uses_hold(tech_id: StringName) -> bool:
	return MOVE_TECHS.has(tech_id)


## 기술·쪽이 움직이는 팔다리. 좌우 없는 기술은 &"".
static func limb_for(tech_id: StringName, side: StringName) -> StringName:
	if side == &"none":
		return &""
	var left := side == &"left"
	if HAND_TECHS.has(tech_id):
		return PoseSolver.LH if left else PoseSolver.RH
	return PoseSolver.LF if left else PoseSolver.RF


## 이 yaw 기술(드롭니·아웃사이드 엣지)의 ψ 목표(도). 그 발 쪽 엉덩이를 벽으로(왼발 ψ<0, 오른발 ψ>0). yaw형이 아니면 NAN.
static func yaw_for(tech_id: StringName, limb: StringName) -> float:
	var mag := DROP_KNEE_YAW if tech_id == T_DROP_KNEE else (OUTSIDE_EDGE_YAW if tech_id == T_OUTSIDE_EDGE else NAN)
	return mag * PoseSolver.side_sign(limb)


static func is_flag(tech_id: StringName) -> bool:
	return FLAG_DEPTH.has(tech_id)


static func flag_depth(tech_id: StringName) -> float:
	return FLAG_DEPTH.get(tech_id, 0.0)


static func is_yaw_tech(tech_id: StringName) -> bool:
	return tech_id == T_DROP_KNEE or tech_id == T_OUTSIDE_EDGE


static func other_of(limb: StringName) -> StringName:
	return {PoseSolver.LH: PoseSolver.RH, PoseSolver.RH: PoseSolver.LH, PoseSolver.LF: PoseSolver.RF, PoseSolver.RF: PoseSolver.LF}[limb]


static func limb_name(limb: StringName) -> String:
	return {PoseSolver.LH: "왼손", PoseSolver.RH: "오른손", PoseSolver.LF: "왼발", PoseSolver.RF: "오른발"}[limb]


# ---------- 쪽 판단 ----------

## 기술의 쪽별 판단. {&"left": J, &"right": J} 또는 {&"none": J}.
## J = {available, reason(첫 이유), reasons(전체), text(첫 이유 문구)}
static func judge(snap: ClimbSnapshot, tech_id: StringName, light: bool = false) -> Dictionary:
	var d: Dictionary = defs().get(tech_id, {})
	var sides: Array = [&"none"] if d.get("sides", &"left_right") == &"none" else [&"left", &"right"]
	var out := {}
	for side in sides:
		out[side] = judge_side(snap, tech_id, side, light)
	return out


## 패널 흐림용 가벼운 판단(27 §7.1 비용 관리): 2~5단계 중 힘 계산·플래그 탐색·목표 자세 탐색 없이 본다. 모양은 judge와 같다.
static func light_judge(snap: ClimbSnapshot, tech_id: StringName) -> Dictionary:
	return judge(snap, tech_id, true)


static func judge_side(snap: ClimbSnapshot, tech_id: StringName, side: StringName, light: bool = false) -> Dictionary:
	var acc: Array = []  # [[reason, text], ...]
	if snap.falling or snap.executing or snap.dragging or snap.deadpoint_active:
		_add(acc, WRONG_PHASE)
		return _result(acc)
	if not SUPPORTED.has(tech_id):
		_add(acc, MOVE_NOT_SUPPORTED)
		return _result(acc)
	var limb := limb_for(tech_id, side)
	match tech_id:
		T_REST:
			_judge_rest(snap, acc)
		T_LOCK_OFF:
			_judge_lock_off(snap, limb, acc, light)
		T_DROP_KNEE:
			_judge_drop_knee(snap, limb, acc, light)
		T_FLAG, T_FLAG_INSIDE, T_FLAG_OUTSIDE:
			_judge_flag(snap, tech_id, limb, acc, light)
		T_DEADPOINT:
			_judge_deadpoint(snap, limb, acc, light)
		_:
			_judge_move(snap, tech_id, limb, acc, light)
	return _result(acc)


static func _add(acc: Array, reason: StringName, text: String = "") -> void:
	acc.append([reason, text if not text.is_empty() else text_for(reason)])


static func _result(acc: Array) -> Dictionary:
	var reasons: Array[StringName] = []
	for e in acc:
		reasons.append(e[0])
	return {"available": acc.is_empty(), "reason": acc[0][0] if not acc.is_empty() else &"", "reasons": reasons, "text": acc[0][1] if not acc.is_empty() else ""}


## 휴식: 지지 안정, 하중 받는 발 ≥ 1(27 §10).
static func _judge_rest(snap: ClimbSnapshot, acc: Array) -> void:
	if snap.loaded_feet.is_empty():
		_add(acc, LIMB_STATE, "발로 체중을 받치고 있어야 해요")
	if snap.phase != ClimbRules.Phase.STABLE:
		_add(acc, BARN_DOOR if snap.imbalance_cause == &"BARN_DOOR" else SUPPORT_OVERLOAD)


## 록오프: 그 손 붙음·하중 자격, q ≥ 0.5, 반대 손 자유 또는 뗄 수 있음, 목표 자세(그 팔 0.42) 성립, 피로 ≥ 30.
static func _judge_lock_off(snap: ClimbSnapshot, hand: StringName, acc: Array, light: bool = false) -> void:
	var b := snap.body
	var held := snap.attached.has(hand) and PoseSolver.hand_counts_for_support(b.pos, b.angle, hand, snap.attached[hand], _mode(snap, hand), snap.loaded_feet, b.yaw)
	if not held:
		_add(acc, LIMB_STATE, "%s이 홀드를 잡고 있어야 해요" % limb_name(hand))
	elif _quality(snap, hand) < MIN_GRIP_QUALITY:
		_add(acc, GRIP_TOO_POOR)
	var other := other_of(hand)
	if not light and snap.attached.has(other) and not release_ok(snap, [other]):
		_add(acc, SUPPORT_NEEDED)
	if held and not light:
		var profile := snap.profile.duplicate()
		profile[hand] = LOCK_OFF_PREF
		var t := PoseSolver.find_target(b.pos, b.angle, snap.attached, snap.feet_eligible, profile, {}, NAN, 0.0, b.yaw)
		var tp := Vector2(t.x, t.y)
		if not PoseSolver.is_valid(tp, t.z, snap.attached, b.yaw):
			_add(acc, JOINT_LIMIT)
		else:
			var r := support_reason(snap, tp, t.z, b.yaw, snap.attached, _free_endpoints(snap, snap.attached), snap.contact_meta, snap.loaded_feet)
			if r != &"":
				_add(acc, r)
	if float(snap.stamina.get(hand, 0.0)) < LOCK_OFF_MIN_STAMINA:
		_add(acc, TOO_TIRED)


## 데드포인트 도달 보너스(04 §10.5): min(0.15, 0.25·v_up + 0.05·드래그 속도). 버튼 흐름은 드래그 속도 대신 1을 넣는다(= 0.05).
static func deadpoint_bonus(v_up: float, drag_speed: float) -> float:
	return minf(DEADPOINT_MAX_BONUS, 0.25 * maxf(v_up, 0.0) + 0.05 * maxf(drag_speed, 0.0))


## 이 손의 데드포인트 조건 중 창(상승) 외 부분: 반대 손이 붙어 하중 자격이 있고 하중 받는 발 ≥ 1. 만족하면 "".
static func deadpoint_hand_reason(snap: ClimbSnapshot, hand: StringName) -> String:
	var b := snap.body
	var other := other_of(hand)
	if not (snap.attached.has(other) and PoseSolver.hand_counts_for_support(b.pos, b.angle, other, snap.attached[other], _mode(snap, other), snap.loaded_feet, b.yaw)):
		return "%s로 홀드를 잡고 체중을 받고 있어야 해요" % limb_name(other)
	if snap.loaded_feet.is_empty():
		return "발로 체중을 받치고 있어야 해요"
	return ""


## 정적 도달 한계: can_reach의 먼 쪽 3D 거리 한계(관절~점 거리 기준).
static func deadpoint_far(hand: StringName, yaw: float) -> float:
	var dz := PoseSolver.contact_dz_range() + Vector2.ONE * PoseSolver.joint_depth_offset(hand, yaw)
	return PoseSolver.planar_range(hand, dz.x, dz.y).y


## 데드포인트 받기 판정(받는 순간의 자세 그대로). 손 hand는 att에 없어도(떼어진 상태) 있어도 된다.
## 1 품질 ≥ 0.5  2 방향 영역(완화 없음)  3 거리는 정적 한계 + bonus까지  4 모든 접점이 함께 만족하는 깊이
## 5 최대 하중 /1.3 힘 균형. 반환 {ok, reason}.
static func deadpoint_catch(snap: ClimbSnapshot, hand: StringName, key: String, point: Vector2, bonus: float) -> Dictionary:
	var b := snap.body
	var slot: Dictionary = snap.route.slots[key]
	if HoldArea.project_hand(slot, point).quality < DEADPOINT_MIN_QUALITY:
		return {"ok": false, "reason": GRIP_TOO_POOR}
	if not PoseSolver.direction_ok(b.pos, b.angle, hand, point, b.yaw):
		return {"ok": false, "reason": JOINT_LIMIT}
	var d := PoseSolver.limb_distance(b.pos, b.angle, hand, point, b.yaw)
	var over := d - deadpoint_far(hand, b.yaw)
	if over > bonus + Tuning.DISTANCE_EPSILON:
		return {"ok": false, "reason": GripCheck.OUT_OF_REACH}
	var remaining := snap.attached.duplicate()
	var meta := snap.contact_meta.duplicate()
	var loaded := snap.loaded_feet.duplicate()
	remaining.erase(hand)
	meta.erase(hand)
	loaded.erase(hand)
	var with_new := remaining.duplicate()
	with_new[hand] = point
	# 깊이: 정적 한계를 넘는 만큼(≤ bonus)만 관절 쪽으로 당긴 가상점으로 공통 깊이를 본다(방향은 같다)
	var virtual := point
	if over > 0.0:
		var joint := PoseSolver.joint_position(b.pos, b.angle, hand, b.yaw)
		virtual = joint + (point - joint) * ((d - over) / d)
	var vw := remaining.duplicate()
	vw[hand] = virtual
	if not PoseSolver.is_valid(b.pos, b.angle, vw, b.yaw):
		return {"ok": false, "reason": JOINT_LIMIT}
	meta[hand] = contact_for(snap.route, T_DEADPOINT, hand, key, point)
	var r := support_reason(snap, b.pos, b.angle, b.yaw, with_new, _free_endpoints(snap, with_new), meta, loaded, {hand: key}, 1.0 / DEADPOINT_LOAD_FACTOR)
	if r != &"":
		return {"ok": false, "reason": r}
	return {"ok": true, "reason": &""}


## 데드포인트(27 §8.4): 창이 열려 있고(상승 중), 그 손이 붙어 있고 떼도 버티며, 반대 손·발 조건이 맞고,
## 보너스 범위 안에 홀드가 하나라도 있어야 한다.
static func _judge_deadpoint(snap: ClimbSnapshot, hand: StringName, acc: Array, light: bool = false) -> void:
	if not snap.deadpoint_window:
		_add(acc, LIMB_STATE, DEADPOINT_TEXT_CLOSED)
		return
	if not snap.attached.has(hand):
		_add(acc, LIMB_STATE, "%s이 홀드를 잡고 있어야 해요" % limb_name(hand))
		return
	var why := deadpoint_hand_reason(snap, hand)
	if why != "":
		_add(acc, LIMB_STATE, why)
	if not light and not release_ok(snap, [hand]):
		_add(acc, SUPPORT_NEEDED)
	if not _any_deadpoint_hold(snap, hand):
		_add(acc, NO_HOLD)


## 보너스(버튼 흐름) 범위 안의 빈 홀드가 하나라도 있는가(가벼운 존재 검사).
static func _any_deadpoint_hold(snap: ClimbSnapshot, hand: StringName) -> bool:
	var b := snap.body
	var joint := PoseSolver.joint_position(b.pos, b.angle, hand, b.yaw)
	var limit := deadpoint_far(hand, b.yaw) + deadpoint_bonus(b.vel.y, 1.0)
	for key in snap.route.slots:
		if not slot_filter(snap, T_DEADPOINT, hand, key):
			continue
		var pt := point_for(snap, T_DEADPOINT, hand, key, snap.route.slots[key].pos)
		if not pt.is_empty() and joint.distance_to(pt.point) <= limit:
			return true
	return false


## 드롭니(27 §10): 그 발이 붙어 있고 하중, 발판 pivot_allowed, 다른 발 하중, 손 ≥ 1, 그 발이 고관절보다 바깥·아래,
## ψ=±35°에서 관절·방향·깊이·힘 균형 성립(그 발 edge = drop_knee).
static func _judge_drop_knee(snap: ClimbSnapshot, foot: StringName, acc: Array, light: bool = false) -> void:
	var b := snap.body
	if not (snap.attached.has(foot) and snap.loaded_feet.has(foot)):
		_add(acc, LIMB_STATE, "%s로 발판을 딛고 체중을 받고 있어야 해요" % limb_name(foot))
		return
	if not snap.loaded_feet.has(other_of(foot)):
		_add(acc, LIMB_STATE, "다른 발도 발판을 딛고 체중을 받고 있어야 해요")
	if PoseSolver.eligible_hands(b.pos, b.angle, snap.attached, snap.contact_meta, snap.loaded_feet, b.yaw) < 1:
		_add(acc, LIMB_STATE, "손으로 홀드를 잡고 있어야 해요")
	var hip := PoseSolver.joint_position(b.pos, b.angle, foot, b.yaw)
	var fp: Vector2 = snap.attached[foot]
	if not ((fp.x - hip.x) * PoseSolver.side_sign(foot) > 0.0 and fp.y < hip.y):
		_add(acc, LIMB_STATE, "발이 엉덩이보다 바깥쪽 아래에 있어야 해요")
	var slot: Dictionary = snap.route.slots.get(snap.keys[foot], {})
	if not slot.get("pivot_allowed", true):
		_add(acc, PIVOT_NOT_ALLOWED)
		return
	if light:
		return
	var r := yaw_pose_reason(snap, snap.attached, snap.contact_meta, foot, &"drop_knee", yaw_for(T_DROP_KNEE, foot))
	if r != &"":
		_add(acc, r)


## 플래그(27 §10, 04 §10.6): 그 발이 자유이거나 떼도 버틸 수 있고, 하중 손 ≥ 1, 관절 범위 안 격자에서
## 균형 비용(ClimbRules.flag_cost)이 최소인 위치가 휴식 위치보다 FLAG_COST_IMPROVEMENT 이상 나아야 한다.
static func _judge_flag(snap: ClimbSnapshot, tech_id: StringName, foot: StringName, acc: Array, light: bool = false) -> void:
	var b := snap.body
	if not light and snap.attached.has(foot) and not release_ok(snap, [foot]):
		_add(acc, SUPPORT_NEEDED)
		return
	if PoseSolver.eligible_hands(b.pos, b.angle, snap.attached, snap.contact_meta, snap.loaded_feet, b.yaw) < 1:
		_add(acc, LIMB_STATE, "손으로 홀드를 잡고 있어야 해요")
		return
	var other := other_of(foot)
	if not (snap.attached.has(other) and snap.loaded_feet.has(other)):
		_add(acc, LIMB_STATE, "다른 발로 발판을 딛고 체중을 받고 있어야 해요")
		return
	if not light and flag_plan(snap, tech_id, foot).is_empty():
		_add(acc, LIMB_STATE, FLAG_NO_GAIN_TEXT)


## 이 발을 떼고(또는 자유인 채) 변형 영역의 격자에서 균형 비용이 최소인 플래그 위치. 이득이 없으면 {}.
## 영역(지지발 X 기준): 같은 쪽 = 그 발 쪽 바깥, 인사이드·아웃사이드 = 지지발 너머로 교차(평면 판정은 같고 깊이 힌트만 다름).
## 반환 {point, cost, gain}
static func flag_plan(snap: ClimbSnapshot, tech_id: StringName, foot: StringName) -> Dictionary:
	# 인사이드·아웃사이드는 평면 판정이 같아 한 번만 계산한다
	var cache_key := [T_FLAG if tech_id == T_FLAG else T_FLAG_INSIDE, foot]
	if snap.plan_cache.has(cache_key):
		return snap.plan_cache[cache_key]
	var plan := _flag_search(snap, tech_id, foot)
	snap.plan_cache[cache_key] = plan
	return plan


static func _flag_search(snap: ClimbSnapshot, tech_id: StringName, foot: StringName) -> Dictionary:
	var b := snap.body
	var att := snap.attached.duplicate()
	var meta := snap.contact_meta.duplicate()
	var loaded := snap.loaded_feet.duplicate()
	att.erase(foot)
	meta.erase(foot)
	loaded.erase(foot)
	var s := PoseSolver.side_sign(foot)
	var sup_x := b.pos.x
	var other := other_of(foot)
	if att.has(other):
		sup_x = (att[other] as Vector2).x
	var cur: Vector2 = snap.endpoints[foot]
	var joint := PoseSolver.joint_position(b.pos, b.angle, foot, b.yaw)
	var rules := ClimbRules.new()
	rules.contact_meta = meta
	rules.loaded_feet.assign(loaded)
	var feet := PoseSolver.supporting_feet(b.pos, b.angle, att, snap.feet_eligible, b.yaw)
	var eps := _free_endpoints(snap, att)
	var rest := PoseSolver.clamp_endpoint(b.pos, b.angle, foot, cur, b.pos + Vector2(0.25 * s, -0.70), b.yaw)
	eps[foot] = rest
	var rest_cost := ClimbRules.flag_cost(rules.evaluate(b.pos, b.angle, att, eps, false, feet, b.yaw))
	var n := int(ceil(PoseSolver.reach_of(foot).y / FLAG_GRID))
	var seen := {}
	var scored: Array = []  # [[cost, ix, iy], ...]
	# 격자 인덱스 (ix, iy)는 joint 기준. 평가한 점은 seen에 기록해 중복 계산을 막는다
	var eval_point := func(ix: int, iy: int) -> void:
		var key := Vector2i(ix, iy)
		if seen.has(key) or iy >= 0 or absi(ix) > n or iy < -n:
			return
		seen[key] = true
		var p := joint + Vector2(ix, iy) * FLAG_GRID
		if p.y > joint.y - FLAG_MIN_BELOW_JOINT:
			return
		var dx := (p.x - sup_x) * s
		if tech_id == T_FLAG and not (dx >= 0.0 and (p.x - joint.x) * s >= 0.0):
			return
		if tech_id != T_FLAG and dx >= 0.0:
			return
		if PoseSolver.clamp_endpoint(b.pos, b.angle, foot, cur, p, b.yaw).distance_to(p) > 0.01:
			return  # 관절 방향·거리 범위 밖
		eps[foot] = p
		var r := rules.evaluate(b.pos, b.angle, att, eps, false, feet, b.yaw)
		if r.status != SupportSolver.Status.FEASIBLE or ClimbRules.barn_exceeded(r):
			return
		scored.append([ClimbRules.flag_cost(r), ix, iy])
	# 1차: 거친 격자(0.15m)
	for ix in range(-n, n + 1, FLAG_COARSE):
		for iy in range(-n, 0, FLAG_COARSE):
			eval_point.call(ix, iy)
	if scored.is_empty():
		return {}
	scored.sort_custom(func(x, y): return x[0] < y[0])
	# 2차: 상위 몇 점 주변을 0.05m 격자로 다듬는다(이웃 ±(FLAG_COARSE-1) 칸)
	var tops := scored.slice(0, FLAG_REFINE_TOP)
	for t in tops:
		for dx in range(-(FLAG_COARSE - 1), FLAG_COARSE):
			for dy in range(-(FLAG_COARSE - 1), FLAG_COARSE):
				eval_point.call(t[1] + dx, t[2] + dy)
	scored.sort_custom(func(x, y): return x[0] < y[0])
	var best: Array = scored[0]
	if rest_cost - best[0] < Tuning.FLAG_COST_IMPROVEMENT:
		return {}
	return {"point": joint + Vector2(best[1], best[2]) * FLAG_GRID, "cost": best[0], "gain": rest_cost - best[0]}


## 목표 yaw에서 자세가 성립하는가(몸통 위치·각도는 지금 그대로). 성립하면 &"".
## 관절 방향·길이·깊이 실패는 JOINT_LIMIT, 몸통 회전 한계는 BODY_ORIENTATION_LIMIT, 힘 균형·barn door는 SUPPORT_OVERLOAD/BARN_DOOR.
## foot의 접점 edge를 edge로 바꿔 계산한다(barn door 용량).
static func yaw_pose_reason(snap: ClimbSnapshot, att: Dictionary, meta: Dictionary, foot: StringName, edge: StringName, yaw: float, pelvis: Vector2 = Vector2.INF, angle: float = NAN) -> StringName:
	var b := snap.body
	var p := b.pos if not pelvis.is_finite() else pelvis
	var a := b.angle if is_nan(angle) else angle
	if absf(yaw) > Tuning.PELVIS_YAW_LIMIT_DEG:
		return BODY_ORIENTATION_LIMIT
	if not PoseSolver.is_valid(p, a, att, yaw):
		return JOINT_LIMIT
	var m := meta.duplicate()
	if m.has(foot):
		var c := ClimbSnapshot.copy_contact(m[foot])
		c.edge = edge
		m[foot] = c
	return support_reason(snap, p, a, yaw, att, _free_endpoints(snap, att), m, snap.loaded_feet)


## 손발을 홀드로 옮기는 기술: 3 떼기 판단 → 4 홀드 존재(가벼운 검사).
## 크로스·매치·풋스왑의 "반대 손발이 붙어 있음"은 홀드 기준(반대 손 X, 반대 손발의 홀드)이라 4단계 조건으로 본다
## (TA02: 마지막 손을 떼는 크로스는 SUPPORT_NEEDED가 첫 이유).
static func _judge_move(snap: ClimbSnapshot, tech_id: StringName, limb: StringName, acc: Array, light: bool = false) -> void:
	if not light and snap.attached.has(limb) and not release_ok(snap, [limb]):
		_add(acc, SUPPORT_NEEDED)
	if tech_id == T_OUTSIDE_EDGE:
		var b := snap.body
		if PoseSolver.eligible_hands(b.pos, b.angle, snap.attached, snap.contact_meta, snap.loaded_feet, b.yaw) < 1:
			_add(acc, LIMB_STATE, "손으로 홀드를 잡고 있어야 해요")
	if not _any_hold_cheap(snap, tech_id, limb):
		_add(acc, NO_HOLD)


# ---------- 공통 지지 검사 ----------

## 떼기 판단(27 §7.1 3단계): removed를 뺀 attached·contact_meta로 지금 자세에서 지지가 성립하는가.
## 지지 = (하중 자격 손 ≥ 1 또는 플랫폼) 이고 힘 해 FEASIBLE, barn door 초과 아님.
static func release_ok(snap: ClimbSnapshot, removed: Array) -> bool:
	var att := snap.attached.duplicate()
	var meta := snap.contact_meta.duplicate()
	var loaded := snap.loaded_feet.duplicate()
	for limb in removed:
		att.erase(limb)
		meta.erase(limb)
		loaded.erase(limb)
	var b := snap.body
	return support_reason(snap, b.pos, b.angle, b.yaw, att, _free_endpoints(snap, att), meta, loaded) == &""


## 이 자세·접점에서의 지지 이유. 성립하면 &"", 힘 해 없음·지지 자격 없음은 SUPPORT_OVERLOAD, barn door 초과는 BARN_DOOR.
static func support_reason(snap: ClimbSnapshot, pelvis: Vector2, angle: float, yaw: float, att: Dictionary, eps: Dictionary, meta: Dictionary, loaded: Array, key_over: Dictionary = {}, load_scale: float = 1.0) -> StringName:
	var rules := ClimbRules.new()
	rules.load_scale = load_scale
	rules.contact_meta = meta
	rules.loaded_feet.assign(loaded)
	var feet := PoseSolver.supporting_feet(pelvis, angle, att, snap.feet_eligible, yaw)
	var hands := PoseSolver.eligible_hands(pelvis, angle, att, meta, loaded, yaw)
	if hands == 0 and not snap.platform_for(att, feet, pelvis, key_over):
		return SUPPORT_OVERLOAD
	var r := rules.evaluate(pelvis, angle, att, eps, false, feet, yaw)
	if r.status != SupportSolver.Status.FEASIBLE:
		return SUPPORT_OVERLOAD
	if ClimbRules.barn_exceeded(r):
		return BARN_DOOR
	return &""


## att에 없는 팔다리의 실제 말단(무게중심 대리점 계산용).
static func _free_endpoints(snap: ClimbSnapshot, att: Dictionary) -> Dictionary:
	var eps := {}
	for limb in snap.endpoints:
		if not att.has(limb):
			eps[limb] = snap.endpoints[limb]
	return eps


static func _mode(snap: ClimbSnapshot, limb: StringName) -> StringName:
	return snap.contact_meta[limb].mode if snap.contact_meta.has(limb) else &"pull"


static func _quality(snap: ClimbSnapshot, limb: StringName) -> float:
	return snap.contact_meta[limb].quality if snap.contact_meta.has(limb) else 1.0


# ---------- 홀드 ----------

## 홀드의 잡기 방식 항목. 없으면 {}.
static func mode_entry(slot: Dictionary, mode: StringName) -> Dictionary:
	for gm in slot.grip_modes:
		if gm.mode == mode:
			return gm
	return {}


## 기술로 붙일 접점 정보: 손은 기술의 방식(없으면 첫 grip_mode), 발은 inside.
static func contact_for(route: RouteDef, tech_id: StringName, limb: StringName, key: String, point: Vector2) -> ContactInfo:
	var slot: Dictionary = route.slots[key]
	if not PoseSolver.is_hand(limb):
		var edge := &"outside" if tech_id == T_OUTSIDE_EDGE else &"inside"
		return ContactInfo.make(key, point, HoldArea.project_foot(slot, point).quality, &"foot", edge)
	var gm := mode_entry(slot, MODE_OF[tech_id]) if MODE_OF.has(tech_id) else {}
	if gm.is_empty():
		gm = slot.grip_modes[0]
	var ci := ContactInfo.make(key, point, HoldArea.project_hand(slot, point).quality, gm.mode, &"")
	ci.axis = gm.axis
	ci.half_angle = gm.half_angle
	return ci


## 기술별 홀드 조건(27 §10)을 지금 자세에서 본다. 거리·관절·힘은 보지 않는다.
static func slot_filter(snap: ClimbSnapshot, tech_id: StringName, limb: StringName, key: String) -> bool:
	var slot: Dictionary = snap.route.slots[key]
	if not slot.allowed.has(limb):
		return false
	var hand := PoseSolver.is_hand(limb)
	if (hand and not slot.has("hand_area")) or (not hand and not slot.has("foot_area")):
		return false
	var b := snap.body
	var other := other_of(limb)
	var p: Vector2 = slot.pos
	if tech_id == T_OUTSIDE_EDGE and not slot.pivot_allowed:
		return false
	match tech_id:
		T_DEADPOINT:
			# 지금 잡은 홀드로 되돌아가는 데드포인트는 없다
			return not (snap.attached.has(limb) and snap.keys[limb] == key)
		T_CROSS:
			# 반대 손 X를 넘는 홀드(LH는 RH보다 오른쪽)
			return snap.attached.has(other) and (p.x - (snap.attached[other] as Vector2).x) * PoseSolver.side_sign(other) > 0.0
		T_MATCH, T_FOOT_SWAP:
			# 반대 손발의 홀드. 이 손발이 이미 그 홀드에 있으면 후보가 아니다
			return snap.attached.has(other) and key == snap.keys[other] and not (snap.attached.has(limb) and snap.keys[limb] == key)
		T_HIGH_STEP:
			return p.y >= PoseSolver.joint_position(b.pos, b.angle, limb, b.yaw).y - Tuning.HIGH_STEP_BELOW_HIP
		T_SIDEPULL:
			# 몸이 홀드 반대쪽: 홀드가 그 손 어깨보다 바깥
			if mode_entry(slot, &"sidepull").is_empty():
				return false
			var sh := PoseSolver.joint_position(b.pos, b.angle, limb, b.yaw)
			return (p.x - sh.x) * PoseSolver.side_sign(limb) >= 0.0
		T_GASTON:
			# 손과 같은 쪽, 어깨 높이
			if mode_entry(slot, &"gaston").is_empty():
				return false
			var sh := PoseSolver.joint_position(b.pos, b.angle, limb, b.yaw)
			return (p.x - b.pos.x) * PoseSolver.side_sign(limb) > 0.0 and absf(p.y - sh.y) <= GASTON_SHOULDER_BAND
		T_UNDERCLING:
			# 홀드가 어깨 아래, 하중 받는 발이 높음
			if mode_entry(slot, &"undercling").is_empty():
				return false
			var sh := PoseSolver.joint_position(b.pos, b.angle, limb, b.yaw)
			return p.y < sh.y and _has_high_loaded_foot(snap)
	return true


static func _has_high_loaded_foot(snap: ClimbSnapshot) -> bool:
	var b := snap.body
	for foot in snap.loaded_feet:
		if snap.attached.has(foot) and (snap.attached[foot] as Vector2).y >= PoseSolver.joint_position(b.pos, b.angle, foot, b.yaw).y - HIGH_FOOT_BELOW_HIP:
			return true
	return false


## 매치의 두 손 배치: 홀드 중심 기준 ±0.04(들어오는 손은 자기 쪽). 반폭 < 0.08이면 자리 없음({}).
## 반환 {point, quality, other_point, other_quality}
static func match_layout(snap: ClimbSnapshot, limb: StringName, key: String) -> Dictionary:
	var slot: Dictionary = snap.route.slots[key]
	var area: Dictionary = slot.hand_area
	var hw: float = area.half_width
	if hw < 2.0 * HoldArea.HAND_INTERVAL_HALF - 0.0001:
		return {}
	var other := other_of(limb)
	for e in snap.occupied.get(key, []):
		if e.limb != other and e.limb != limb:
			return {}
	var dir: Vector2 = area.dir
	var s := HoldArea.HAND_INTERVAL_HALF * PoseSolver.side_sign(limb) * (signf(dir.x) if dir.x != 0.0 else 1.0)
	var q := 1.0 - pow(absf(s) / hw, 2)
	return {"point": slot.pos + dir * s, "quality": q, "other_point": slot.pos - dir * s, "other_quality": q}


## 기술이 쓸 접점 위치. aim(탭 지점 또는 홀드 중심)을 영역에 투영하고 점유 구간을 피한다. 자리 없으면 {}.
static func point_for(snap: ClimbSnapshot, tech_id: StringName, limb: StringName, key: String, aim: Vector2) -> Dictionary:
	var slot: Dictionary = snap.route.slots[key]
	if tech_id == T_MATCH:
		return match_layout(snap, limb, key)
	if tech_id == T_FOOT_SWAP:
		var pf := HoldArea.project_foot(slot, snap.attached[other_of(limb)])
		return {"point": pf.point, "quality": pf.quality}
	return GripCheck.contact_point(slot, limb, aim, snap.occupied.get(key, []), INF)


## 4단계 가벼운 검사: 기술 조건·빈 자리가 있고 관절에서 도달+체중 이동 범위 안인 홀드가 하나라도 있는가.
static func _any_hold_cheap(snap: ClimbSnapshot, tech_id: StringName, limb: StringName) -> bool:
	var b := snap.body
	var joint := PoseSolver.joint_position(b.pos, b.angle, limb, b.yaw)
	var limit := PoseSolver.reach_of(limb).y + Tuning.SEARCH_POS_EXTENT
	for key in snap.route.slots:
		if not slot_filter(snap, tech_id, limb, key):
			continue
		var pt := point_for(snap, tech_id, limb, key, snap.route.slots[key].pos)
		if not pt.is_empty() and joint.distance_to(pt.point) <= limit:
			return true
	return false


## 홀드 한 지점에 대한 5·6단계: 지금 자세(아니면 남은 접점을 유지한 체중 이동 목표)에서 닿고 관절·깊이·힘 균형 성립.
## 반환 {ok, reason, needs_shift, pose: Vector3}
static func evaluate_target(snap: ClimbSnapshot, tech_id: StringName, limb: StringName, key: String, point: Vector2) -> Dictionary:
	var b := snap.body
	if tech_id == T_DEADPOINT:
		var dp := deadpoint_catch(snap, limb, key, point, deadpoint_bonus(b.vel.y, 1.0))
		return {"ok": dp.ok, "reason": dp.reason, "needs_shift": false, "pose": Vector3(b.pos.x, b.pos.y, b.angle)}
	var remaining := snap.attached.duplicate()
	var meta := snap.contact_meta.duplicate()
	var loaded := snap.loaded_feet.duplicate()
	var removed: Array = [limb]
	if tech_id == T_FOOT_SWAP:
		removed.append(other_of(limb))  # 들어올 발이 닿는 틱에 반대 발을 뗀다(한 발 구간)
	for l in removed:
		remaining.erase(l)
		meta.erase(l)
		loaded.erase(l)
	var with_new := remaining.duplicate()
	with_new[limb] = point
	if tech_id == T_MATCH:
		# 매치는 잡고 있던 손도 같은 홀드의 반대쪽 절반으로 옮겨 잡는다(match_layout)
		var lay := match_layout(snap, limb, key)
		var other := other_of(limb)
		if not lay.is_empty() and with_new.has(other):
			with_new[other] = lay.other_point
			if meta.has(other):
				var oc := ClimbSnapshot.copy_contact(meta[other])
				oc.point = lay.other_point
				oc.quality = lay.other_quality
				meta[other] = oc
	var yaw := 0.0 if (tech_id == T_INSIDE_EDGE or tech_id == T_OUTSIDE_EDGE) else b.yaw  # 엣지 기술은 발을 놓는 동안 엉덩이 정면(ψ→0)
	var p := b.pos
	var a := b.angle
	var shift := false
	if not (PoseSolver.can_reach(p, a, limb, point, yaw) and PoseSolver.is_valid(p, a, with_new, yaw)):
		# 실행 중 Shift는 매 틱 목표를 다시 찾으므로 국소 탐색(±0.30m)을 몇 번 이어 붙여 근사한다
		var tp := p
		var ta := a
		var reached := false
		for _i in SHIFT_SEARCHES:
			var feet := PoseSolver.supporting_feet(tp, ta, remaining, snap.feet_eligible, yaw)
			var t := PoseSolver.find_target(tp, ta, remaining, feet, {}, {limb: point}, NAN, 0.0, yaw)
			var moved := Vector2(t.x, t.y).distance_to(tp) > 0.002 or absf(t.z - ta) > 0.2
			tp = Vector2(t.x, t.y)
			ta = t.z
			if PoseSolver.can_reach(tp, ta, limb, point, yaw) and PoseSolver.is_valid(tp, ta, with_new, yaw):
				reached = true
				break
			if not moved:
				break
		if not reached:
			var reason := JOINT_LIMIT if not PoseSolver.direction_ok(p, a, limb, point, yaw) else GripCheck.OUT_OF_REACH
			return {"ok": false, "reason": reason, "needs_shift": false, "pose": Vector3(p.x, p.y, a)}
		p = tp
		a = ta
		shift = true
	meta[limb] = contact_for(snap.route, tech_id, limb, key, point)
	var eps := _free_endpoints(snap, with_new)
	var r := support_reason(snap, p, a, yaw, with_new, eps, meta, loaded, {limb: key})
	if r == &"" and tech_id == T_OUTSIDE_EDGE:
		# 발을 놓은 뒤 엉덩이를 ψ=±30°로 돌린 자세도 성립해야 한다(27 §10)
		r = yaw_pose_reason(snap, with_new, meta, limb, &"outside", yaw_for(tech_id, limb), p, a)
	return {"ok": r == &"", "reason": r, "needs_shift": shift, "pose": Vector3(p.x, p.y, a)}


## 쪽을 고른 뒤의 홀드 후보(27 §7.2): [{key, needs_shift, area_center, point, quality}]
static func hold_targets(snap: ClimbSnapshot, tech_id: StringName, side: StringName) -> Array:
	var out := []
	if not uses_hold(tech_id):
		return out
	var limb := limb_for(tech_id, side)
	for key in snap.route.slots:
		if not slot_filter(snap, tech_id, limb, key):
			continue
		var slot: Dictionary = snap.route.slots[key]
		var pt := point_for(snap, tech_id, limb, key, slot.pos)
		if pt.is_empty() or (_needs_quality(tech_id) and pt.quality < MIN_GRIP_QUALITY):
			continue
		var ev := evaluate_target(snap, tech_id, limb, key, pt.point)
		if ev.ok:
			out.append({"key": key, "needs_shift": ev.needs_shift, "area_center": slot.pos, "point": pt.point, "quality": pt.quality})
	return out


static func _needs_quality(tech_id: StringName) -> bool:
	return tech_id in [T_SIDEPULL, T_GASTON, T_DEADPOINT]


## 탭한 홀드·지점 검사. 탭 지점을 영역에 투영(점유 구간 회피)하고 기술별 품질 조건·5·6단계를 본다.
## 반환 {ok, reason, text, point, quality, needs_shift}
static func check_hold(snap: ClimbSnapshot, tech_id: StringName, side: StringName, key: String, point: Vector2) -> Dictionary:
	var limb := limb_for(tech_id, side)
	var fail := func(reason: StringName) -> Dictionary:
		var text := GripCheck.message(reason, limb) if reason == GripCheck.TYPE_MISMATCH else text_for(reason)
		return {"ok": false, "reason": reason, "text": text, "point": point, "quality": 0.0, "needs_shift": false}
	if not uses_hold(tech_id) or limb == &"" or not snap.route.slots.has(key):
		return fail.call(NO_HOLD)
	var slot: Dictionary = snap.route.slots[key]
	if not slot.allowed.has(limb):
		return fail.call(GripCheck.TYPE_MISMATCH)
	if tech_id == T_OUTSIDE_EDGE and not slot.pivot_allowed:
		return fail.call(PIVOT_NOT_ALLOWED)
	if not slot_filter(snap, tech_id, limb, key):
		return fail.call(NO_HOLD)
	var aim: Vector2 = point if is_finite(point.x) and is_finite(point.y) else slot.pos
	var pt := point_for(snap, tech_id, limb, key, aim)
	if pt.is_empty():
		return fail.call(GripCheck.OCCUPIED)
	if _needs_quality(tech_id) and pt.quality < MIN_GRIP_QUALITY:
		return fail.call(GRIP_TOO_POOR)
	var ev := evaluate_target(snap, tech_id, limb, key, pt.point)
	if not ev.ok:
		return fail.call(ev.reason)
	var out := {"ok": true, "reason": &"", "text": "", "point": pt.point, "quality": pt.quality, "needs_shift": ev.needs_shift}
	if tech_id == T_MATCH:
		out["other_point"] = pt.other_point
	return out
