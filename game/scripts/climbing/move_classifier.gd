class_name MoveClassifier
extends RefCounted
## docs/25 무브 판별(설명 라벨 + 무브별 선호 거리). 하드 제약을 완화하지 않고 홀드를 자동 선택하지 않는다.
## 판별 경계(25):
##  손: 같은 홀드의 다른 손 슬롯 → HandMatch, 반대 손 X를 넘음 → CrossReach,
##      먼 위 목표를 현재 몸으로 못 닿으면 붙은 손은 LockOff, 아래로 → DownClimb, 옆이 더 크면 Traverse, 그 외 Reach
##  발: 다른 발의 슬롯 → FootSwap, 균형 발 조건 → Flag, 목표 Y ≥ 고관절 Y−0.20 → HighStep, 아래 → DownClimb,
##      옆 → Traverse, 그 외 Reach
##  활성 말단 없음: 높이 둔 발이 아직 굽어 있으면 StandUp(Rockover), 아니면 Rest
## 라벨 우선순위(25): Match/Swap → Cross → HighStep → Flag → LockOff → Reach/Traverse/DownClimb → StandUp → Rest
## 전환: 활성 말단 구성이 바뀌면 즉시, 같은 구성에서 라벨만 바뀌면 6틱 연속 확인 후(docs/04 §5).
## 미지원: SideOn/DropKnee(yaw 미구현), 훅·다이노 등(25 제외 목록).

const REST := &"Rest"
const REACH := &"Reach"
const TRAVERSE := &"Traverse"
const HIGH_STEP := &"HighStep"
const STAND_UP := &"StandUp"
const LOCK_OFF := &"LockOff"
const FLAG := &"Flag"
const CROSS_REACH := &"CrossReach"
const HAND_MATCH := &"HandMatch"
const FOOT_SWAP := &"FootSwap"
const DOWN_CLIMB := &"DownClimb"

const PRIORITY := [HAND_MATCH, FOOT_SWAP, CROSS_REACH, HIGH_STEP, FLAG, LOCK_OFF, REACH, TRAVERSE, DOWN_CLIMB, STAND_UP, REST]
const KOREAN := {REST: "휴식", REACH: "뻗기", TRAVERSE: "옆 이동", HIGH_STEP: "높게 딛기", STAND_UP: "체중 싣고 일어서기",
	LOCK_OFF: "짧게 당기기", FLAG: "균형 발", CROSS_REACH: "손 교차", HAND_MATCH: "양손 모으기", FOOT_SWAP: "발 바꾸기", DOWN_CLIMB: "내려오기"}
const MIN_MOVE := 0.10
const STAND_UP_LEG_BELOW := 0.72  # 높은 발의 고관절 거리가 이보다 짧으면 아직 일어서는 중

var label: StringName = REST
var limb_labels := {}      # 활성 말단 → 라벨
var profile := {}          # limb → 선호 거리
var _origins := {}         # 활성 말단의 드래그 시작 위치
var _pending: StringName = REST
var _pending_ticks := 0
var _active_sig := []
var _stand_foot: StringName = &"" 


## intents: limb → 요청 목표, endpoints: limb → 현재 말단(자유·드래그), hints: limb → HAND_MATCH/FOOT_SWAP/FLAG
func update(pelvis: Vector2, angle_deg: float, attached: Dictionary, intents: Dictionary, endpoints: Dictionary, hints: Dictionary) -> void:
	for limb in _origins.keys():
		if not intents.has(limb):
			_origins.erase(limb)
	for limb in intents:
		if not _origins.has(limb):
			_origins[limb] = endpoints.get(limb, intents[limb])
	limb_labels.clear()
	var lock_off_hand: StringName = &""
	for limb in intents:
		var target: Vector2 = intents[limb]
		var origin: Vector2 = _origins[limb]
		var disp := target - origin
		var lbl: StringName
		if hints.has(limb):
			lbl = hints[limb]
		elif PoseSolver.is_hand(limb):
			var other := PoseSolver.RH if limb == PoseSolver.LH else PoseSolver.LH
			if attached.has(other) and ((limb == PoseSolver.LH and target.x > attached[other].x) or (limb == PoseSolver.RH and target.x < attached[other].x)):
				lbl = CROSS_REACH
			else:
				lbl = _direction_label(disp)
				if lbl == REACH and attached.has(other) and disp.y > 0.0 and not PoseSolver.can_reach(pelvis, angle_deg, limb, target):
					lock_off_hand = other
		else:
			var hip := PoseSolver.joint_position(pelvis, angle_deg, limb)
			if target.y >= hip.y - Tuning.HIGH_STEP_BELOW_HIP:
				lbl = HIGH_STEP
			else:
				lbl = _direction_label(disp)
		limb_labels[limb] = lbl
	var candidate := REST
	if not limb_labels.is_empty():
		candidate = _best(limb_labels.values())
		if lock_off_hand != &"" and PRIORITY.find(LOCK_OFF) < PRIORITY.find(candidate):
			candidate = LOCK_OFF
	else:
		_stand_foot = _standing_up(pelvis, angle_deg, attached)
		if _stand_foot != &"":
			candidate = STAND_UP
	# 전환 확인
	var sig := intents.keys()
	sig.sort()
	if sig != _active_sig:
		label = candidate
		_pending_ticks = 0
		_active_sig = sig
	elif candidate != label:
		if candidate == _pending:
			_pending_ticks += 1
		else:
			_pending = candidate
			_pending_ticks = 1
		if _pending_ticks >= Tuning.MOVE_SWITCH_CONFIRM_TICKS:
			label = candidate
			_pending_ticks = 0
	else:
		_pending_ticks = 0
	profile = _profile_for(label, pelvis, angle_deg, attached, lock_off_hand)


func korean() -> String:
	return KOREAN.get(label, String(label))


func _direction_label(disp: Vector2) -> StringName:
	if disp.y < -MIN_MOVE and absf(disp.y) >= absf(disp.x):
		return DOWN_CLIMB
	if absf(disp.x) > absf(disp.y) and absf(disp.x) > MIN_MOVE:
		return TRAVERSE
	return REACH


func _best(labels: Array) -> StringName:
	var best: StringName = REST
	for l in labels:
		if PRIORITY.find(l) < PRIORITY.find(best):
			best = l
	return best


## 높게 둔 발이 아직 굽어 있어(고관절 거리 < 0.72m) 체중을 실어 일어설 여지가 있으면 그 발(가장 굽은 발)
func _standing_up(pelvis: Vector2, angle_deg: float, attached: Dictionary) -> StringName:
	var best: StringName = &""
	var best_d := STAND_UP_LEG_BELOW
	for foot in [PoseSolver.LF, PoseSolver.RF]:
		if not attached.has(foot):
			continue
		var hip := PoseSolver.joint_position(pelvis, angle_deg, foot)
		var slot: Vector2 = attached[foot]
		var d := hip.distance_to(slot)
		if slot.y >= hip.y - 0.55 and d < best_d:
			best = foot
			best_d = d
	return best


## docs/04 §5 무브별 선호 거리: 팔 Rest 0.70 / Reach·Traverse 0.60 / LockOff 0.42, 다리 기본 0.78 / StandUp·Rest 0.86
func _profile_for(lbl: StringName, pelvis: Vector2, angle_deg: float, attached: Dictionary, lock_off_hand: StringName) -> Dictionary:
	var arm := Tuning.PREF_ARM_REST if lbl in [REST, STAND_UP] else Tuning.PREF_ARM_REACH
	var leg := Tuning.PREF_LEG_STAND if lbl in [REST, STAND_UP] else Tuning.PREF_LEG_DEFAULT
	var out := {PoseSolver.LH: arm, PoseSolver.RH: arm, PoseSolver.LF: leg, PoseSolver.RF: leg}
	if lbl == LOCK_OFF and lock_off_hand != &"":
		out[lock_off_hand] = Tuning.PREF_ARM_LOCKOFF
	if lbl == STAND_UP and _stand_foot != &"" and attached.has(_stand_foot):
		out[&"_stand_x"] = (attached[_stand_foot] as Vector2).x  # Rockover: 골반을 올린 발 위로
	return out
