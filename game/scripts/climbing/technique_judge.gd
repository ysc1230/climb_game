class_name TechniqueJudge
extends RefCounted
## 기술 실행 가능 판단(docs/27 §7, §10, §11). 입력은 ClimbSnapshot(확정된 틱의 복사본)이며 순수 함수다.
## 판단 순서(27 §7.1): 1 게임 상태 → 2 손발 상태 → 3 떼기 판단 → 4 홀드 → 5 관절·몸통 → 6 균형·하중 → 7 피로.
## 쪽 판단(judge)은 홀드 후보 목록을 계산하지 않는다(27 §11). 4단계는 거리·종류·점유만 보는 가벼운 존재 검사이고,
## 홀드별 관절·체중 이동·힘 균형(5·6단계)은 쪽을 고른 뒤 hold_targets/check_hold가 계산한다.
## 버튼 기술은 yaw형 드롭니·아웃사이드 엣지 2개뿐이다(docs/28 §4). 그 외 기술은 MOVE_NOT_SUPPORTED로 막아 둔다.
## 패드 경로가 같은 판단을 쓰도록 남긴 것: 패드 풋스왑(slot_filter·point_for·evaluate_target의 T_FOOT_SWAP),
## 패드 데드포인트(deadpoint_bonus·deadpoint_hand_reason·deadpoint_far·deadpoint_catch).

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

const T_FOOT_SWAP := &"T_FOOT_SWAP"
const T_OUTSIDE_EDGE := &"T_OUTSIDE_EDGE"
const T_DROP_KNEE := &"T_DROP_KNEE"
const T_DEADPOINT := &"T_DEADPOINT"

## 손발을 홀드로 옮기는 버튼 기술(hold_tap). 실행기는 Dragging 경로로 옮긴 뒤 붙인다.
const MOVE_TECHS: Array[StringName] = [T_OUTSIDE_EDGE]
## 판단하는 버튼 기술. 나머지 ID는 패드 기술(설명 데이터만)이거나 2차 기술이다.
const SUPPORTED: Array[StringName] = [T_OUTSIDE_EDGE, T_DROP_KNEE]

const DROP_KNEE_YAW := 35.0          # 27 §10: 드롭니 ψ 목표(도). 그 발 쪽 엉덩이를 벽으로: 왼발 ψ<0, 오른발 ψ>0
const OUTSIDE_EDGE_YAW := 30.0       # 27 §10: 아웃사이드 엣지 ψ 목표(도)
const DEADPOINT_RISE_SPEED := 0.20       # 04 §10.5: 어떤 동작이든 골반 상승 ≥ 0.20m/s면 창이 열림
const DEADPOINT_STANDUP_RISE := 0.05     # v6(docs/31): 발로 일어서는 중(StandUp)이면 상승 ≥ 0.05m/s부터 열림(자연 일어서기 최대 0.244의 정점만 열리던 문제)
const DEADPOINT_MIN_SPEED := 1.0     # 패드 놓기 속도(m/s)가 이 이상일 때만 데드포인트("빠르게 드래그", 27 §8.4)
const DEADPOINT_GRACE_TICKS := 24    # v6: 상승이 끝난 뒤 0.4초까지 열림(0.25 → 0.4)
const DEADPOINT_MAX_BONUS := 0.15
const DEADPOINT_MIN_QUALITY := 0.5
const DEADPOINT_LOAD_FACTOR := 1.3   # 순간 하중 배율(받기 판정은 최대 하중을 1/1.3로 계산)
const DEADPOINT_FOLLOW_MAX := 0.25   # v6: 받은 뒤 몸이 탄력으로 따라갈 수 있는 최대 골반 이동(m). 그 안에 성립 자세가 없으면 놓침
const DEADPOINT_AIM_MARGIN := 0.10   # 보너스 범위를 이만큼 넘는 홀드까지는 "던져 보는" 대상(놓치면 추락)
const SHIFT_SEARCHES := 3            # 체중 이동 후 도달 판정의 목표 탐색 반복(각 ±0.30m)
const MIN_GRIP_QUALITY := 0.5        # 27 §8.1: q < 0.5면 사이드풀·개스턴 불가
const GASTON_SHOULDER_BAND := 0.30   # 개스턴: 홀드가 어깨 높이 ±0.30m (구현 해석)
const HIGH_FOOT_BELOW_HIP := 0.55    # 언더클링의 "높은 발": 하중 발 Y ≥ 고관절 Y − 0.55 (25 StandUp의 높은 발 기준)

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


## 기술·쪽이 움직이는 팔다리. 버튼 기술은 모두 발 기술이다. 좌우 없는 쪽은 &"".
static func limb_for(_tech_id: StringName, side: StringName) -> StringName:
	if side == &"none":
		return &""
	return PoseSolver.LF if side == &"left" else PoseSolver.RF


## 이 yaw 기술(드롭니·아웃사이드 엣지)의 ψ 목표(도). 그 발 쪽 엉덩이를 벽으로(왼발 ψ<0, 오른발 ψ>0). yaw형이 아니면 NAN.
static func yaw_for(tech_id: StringName, limb: StringName) -> float:
	var mag := DROP_KNEE_YAW if tech_id == T_DROP_KNEE else (OUTSIDE_EDGE_YAW if tech_id == T_OUTSIDE_EDGE else NAN)
	return mag * PoseSolver.side_sign(limb)


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


## 패널 흐림용 가벼운 판단(27 §7.1 비용 관리): 2~5단계 중 힘 계산·목표 자세(yaw) 검사 없이 본다. 모양은 judge와 같다.
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
	if tech_id == T_DROP_KNEE:
		_judge_drop_knee(snap, limb, acc, light)
	else:
		_judge_move(snap, tech_id, limb, acc, light)
	return _result(acc)


static func _add(acc: Array, reason: StringName, text: String = "") -> void:
	acc.append([reason, text if not text.is_empty() else text_for(reason)])


static func _result(acc: Array) -> Dictionary:
	var reasons: Array[StringName] = []
	for e in acc:
		reasons.append(e[0])
	return {"available": acc.is_empty(), "reason": acc[0][0] if not acc.is_empty() else &"", "reasons": reasons, "text": acc[0][1] if not acc.is_empty() else ""}


## 데드포인트 도달 보너스(04 §10.5): min(0.15, 0.25·v_up + 0.05·드래그 속도). 패드 데드포인트가 쓴다.
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


## 손발을 홀드로 옮기는 기술(아웃사이드 엣지): 3 떼기 판단 → 손 ≥ 1 → 4 홀드 존재(가벼운 검사).
static func _judge_move(snap: ClimbSnapshot, tech_id: StringName, limb: StringName, acc: Array, light: bool = false) -> void:
	if not light and snap.attached.has(limb) and not release_ok(snap, [limb]):
		_add(acc, SUPPORT_NEEDED)
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


# ---------- 홀드 ----------

## 손 그립 방식의 자세 조건(27 §8.1·§10, 28 §4.3 4). 패드 잡기 방향 자동 선택이 쓴다. 거리·관절·힘은 보지 않는다.
## 사이드풀·개스턴: q ≥ 0.5. 개스턴: 홀드가 그 손 쪽(골반 기준)이고 어깨 높이 ±0.30m.
## 언더클링: 홀드가 어깨 아래이고 하중 받는 발이 높다(발 Y ≥ 고관절 Y − 0.55). pull 등 나머지는 항상 성립.
## hold: 홀드 중심, att: 붙은 접점(limb → 위치), loaded: 하중 받는 발.
static func grip_mode_ok(mode: StringName, hand: StringName, hold: Vector2, quality: float, pelvis: Vector2, angle: float, yaw: float, att: Dictionary, loaded: Array) -> bool:
	match mode:
		&"sidepull":
			return quality >= MIN_GRIP_QUALITY
		&"gaston":
			var sh := PoseSolver.joint_position(pelvis, angle, hand, yaw)
			return quality >= MIN_GRIP_QUALITY and (hold.x - pelvis.x) * PoseSolver.side_sign(hand) > 0.0 and absf(hold.y - sh.y) <= GASTON_SHOULDER_BAND
		&"undercling":
			var sh := PoseSolver.joint_position(pelvis, angle, hand, yaw)
			return hold.y < sh.y and has_high_loaded_foot(pelvis, angle, yaw, att, loaded)
	return true


## 하중 받는 발 중 높은 발(발 Y ≥ 고관절 Y − 0.55)이 있는가.
static func has_high_loaded_foot(pelvis: Vector2, angle: float, yaw: float, att: Dictionary, loaded: Array) -> bool:
	for foot in loaded:
		if att.has(foot) and (att[foot] as Vector2).y >= PoseSolver.joint_position(pelvis, angle, foot, yaw).y - HIGH_FOOT_BELOW_HIP:
			return true
	return false


## 기술로 붙일 접점 정보: 손(패드 데드포인트)은 홀드의 첫 grip_mode, 발은 inside(아웃사이드 엣지는 outside).
static func contact_for(route: RouteDef, tech_id: StringName, limb: StringName, key: String, point: Vector2) -> ContactInfo:
	var slot: Dictionary = route.slots[key]
	if not PoseSolver.is_hand(limb):
		var edge := &"outside" if tech_id == T_OUTSIDE_EDGE else &"inside"
		return ContactInfo.make(key, point, HoldArea.project_foot(slot, point).quality, &"foot", edge)
	var gm: Dictionary = slot.grip_modes[0]
	var ci := ContactInfo.make(key, point, HoldArea.project_hand(slot, point).quality, gm.mode, &"")
	ci.axis = gm.axis
	ci.half_angle = gm.half_angle
	return ci


## 기술별 홀드 조건(27 §10)을 지금 자세에서 본다. 거리·관절·힘은 보지 않는다. 패드 풋스왑도 T_FOOT_SWAP으로 쓴다.
static func slot_filter(snap: ClimbSnapshot, tech_id: StringName, limb: StringName, key: String) -> bool:
	var slot: Dictionary = snap.route.slots[key]
	if not slot.allowed.has(limb):
		return false
	var hand := PoseSolver.is_hand(limb)
	if (hand and not slot.has("hand_area")) or (not hand and not slot.has("foot_area")):
		return false
	var other := other_of(limb)
	match tech_id:
		T_OUTSIDE_EDGE:
			return slot.pivot_allowed
		T_FOOT_SWAP:
			# 반대 발의 발판. 이 발이 이미 그 발판에 있으면 후보가 아니다
			return snap.attached.has(other) and key == snap.keys[other] and not (snap.attached.has(limb) and snap.keys[limb] == key)
	return true


## 기술이 쓸 접점 위치. aim(탭 지점 또는 홀드 중심)을 영역에 투영하고 점유 구간을 피한다. 자리 없으면 {}.
static func point_for(snap: ClimbSnapshot, tech_id: StringName, limb: StringName, key: String, aim: Vector2) -> Dictionary:
	var slot: Dictionary = snap.route.slots[key]
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
	var yaw := 0.0 if tech_id == T_OUTSIDE_EDGE else b.yaw  # 아웃사이드 엣지는 발을 놓는 동안 엉덩이 정면(ψ→0)
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
		if pt.is_empty():
			continue
		var ev := evaluate_target(snap, tech_id, limb, key, pt.point)
		if ev.ok:
			out.append({"key": key, "needs_shift": ev.needs_shift, "area_center": slot.pos, "point": pt.point, "quality": pt.quality})
	return out


## 탭한 홀드·지점 검사. 탭 지점을 영역에 투영(점유 구간 회피)하고 5·6단계를 본다.
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
	var ev := evaluate_target(snap, tech_id, limb, key, pt.point)
	if not ev.ok:
		return fail.call(ev.reason)
	return {"ok": true, "reason": &"", "text": "", "point": pt.point, "quality": pt.quality, "needs_shift": ev.needs_shift}
