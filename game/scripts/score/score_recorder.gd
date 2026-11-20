class_name ScoreRecorder
extends RefCounted
## 시도 기록(docs/superpowers/specs/2026-11-19-3-score-design.md §3.1). 노드 없음. 판정 틱마다 tick(session, 결과)로
## 세션을 읽기만 한다(판정 변경 없음). 플레이 화면과 검사 봇(SessionBot.recorder)이 같이 쓴다.
## technique_log는 최근 200개만 남으므로 점수에 쓰는 사건(grab·miss·move·succeeded·flag·pad_foot_swap)은 여기서 다 모은다.

const KEEP := ["grab", "miss", "move", "succeeded", "flag", "pad_foot_swap"]

var ticks := 0
var stable_ticks := 0
var strained_ticks := 0   # 힘 해는 있지만 버티기 힘든(STRAINED) 틱
var danger_entries := 0   # 균형 회복 중·지지 없음에 들어간 수
var danger_ticks := 0     # 위험 상태로 보낸 틱
var barn_doors := 0       # 문 열림(몸이 문처럼 돎)에 들어간 수
var barn_ticks := 0
var spent := 0.0          # 두 손 손 힘 감소분의 합(회복은 빼지 않음)
var start_y := NAN        # 시도 시작 골반 높이
var events: Array = []
var finish := {}          # 완등 순간 {feet_on, stable}
var helped := false
var _prev_stamina := {}
var _prev_phase := ClimbRules.Phase.STABLE
var _prev_barn := false
var _seen_seq := -1
var _last := {}


func tick(s: ClimbSession, result: String) -> void:
	if result == "clear":
		finish = _last.duplicate() if not _last.is_empty() else _pose(s)
		_scan(s)
		return
	if is_nan(start_y):
		start_y = s.body.pos.y
		_seen_seq = s.event_seq
	ticks += 1
	var ph: int = s.rules.phase
	if ph == ClimbRules.Phase.STABLE:
		stable_ticks += 1
	elif ph == ClimbRules.Phase.STRAINED:
		strained_ticks += 1
	var danger := ph == ClimbRules.Phase.REBALANCING or ph == ClimbRules.Phase.GRACE
	var was := _prev_phase == ClimbRules.Phase.REBALANCING or _prev_phase == ClimbRules.Phase.GRACE
	if danger:
		danger_ticks += 1
		if not was:
			danger_entries += 1
	var barn := ph == ClimbRules.Phase.REBALANCING and s.rules.imbalance_cause == &"BARN_DOOR"
	if barn:
		barn_ticks += 1
		if not _prev_barn:
			barn_doors += 1
	_prev_phase = ph
	_prev_barn = barn
	for hand in [PoseSolver.LH, PoseSolver.RH]:
		var cur := float(s.rules.stamina[hand])
		if _prev_stamina.has(hand):
			spent += maxf(float(_prev_stamina[hand]) - cur, 0.0)
		_prev_stamina[hand] = cur
	_scan(s)
	_last = _pose(s)


func _scan(s: ClimbSession) -> void:
	for e in s.technique_log:
		if int(e.seq) <= _seen_seq:
			continue
		_seen_seq = int(e.seq)
		if str(e.type) in KEEP:
			var out := {"type": str(e.type), "tick": int(e.tick)}
			for k in ["key", "label", "id", "limb", "quality"]:
				if e.has(k):
					out[k] = e[k]
			if out.type == "grab":
				var tq := grab_tech_quality(s, StringName(str(e.get("limb", ""))), str(e.get("key", "")))
				out["tech"] = tq.keys()
				out["tq"] = tq
			events.append(out)


## 잡은 순간 자세로 본 패드 기술(검사기 금지 규칙과 같은 기준, ClimbSession.forbid):
## 발이 고관절 − HIGH_STEP_BELOW_HIP 이상이면 하이스텝, 손이 반대 손을 넘으면 크로스, 반대 손과 같은 홀드면 매치.
static func grab_techniques(s: ClimbSession, limb: StringName, key: String) -> Array:
	return grab_tech_quality(s, limb, key).keys()


## 기술마다 얼마나 잘했나(tq 0~1, 2026-11-20 사용자 "더 디테일하게"). 점수는 0.6 + 0.4 × tq(ScoreCalc).
## 하이스텝: 기준선 위로 발을 올린 높이(TQ_HIGH_STEP_M이면 1). 크로스: 반대 손을 넘어간 거리(TQ_CROSS_M이면 1).
## 매치: 두 번째 손의 잡은 자리 품질.
const TQ_HIGH_STEP_M := 0.15
const TQ_CROSS_M := 0.2


static func grab_tech_quality(s: ClimbSession, limb: StringName, key: String) -> Dictionary:
	if not s.route.slots.has(key) or not s.limbs.has(limb):
		return {}
	var point: Vector2 = s.route.slots[key].pos
	var out := {}
	if not PoseSolver.is_hand(limb):
		var hip := PoseSolver.joint_position(s.body.pos, s.body.angle, limb, s.body.yaw)
		var line := hip.y - Tuning.HIGH_STEP_BELOW_HIP
		if point.y >= line:
			out["T_HIGH_STEP"] = clampf(0.5 + 0.5 * (point.y - line) / TQ_HIGH_STEP_M, 0.0, 1.0)
		return out
	var other := PoseSolver.RH if limb == PoseSolver.LH else PoseSolver.LH
	var o: Dictionary = s.limbs[other]
	if o.state in ["Attached", "Armed"] and o.get("key", "") != null and str(o.get("key", "")) != "":
		var ox: float = (o.grab as Vector2).x
		if (limb == PoseSolver.LH and point.x > ox) or (limb == PoseSolver.RH and point.x < ox):
			out["T_CROSS"] = clampf(0.5 + 0.5 * absf(point.x - ox) / TQ_CROSS_M, 0.0, 1.0)
		if key.get_base_dir() == str(o.key).get_base_dir():
			var c = s.limbs[limb].get("contact")
			out["T_MATCH"] = clampf(c.quality if c != null else 1.0, 0.0, 1.0)
	return out


static func _pose(s: ClimbSession) -> Dictionary:
	var att := s.attached()
	var feet := (1 if att.has(PoseSolver.LF) else 0) + (1 if att.has(PoseSolver.RF) else 0)
	return {"feet": feet, "phase": s.rules.phase_name()}


func to_dict() -> Dictionary:
	return {"ticks": ticks, "stable_ticks": stable_ticks, "strained_ticks": strained_ticks, "danger_entries": danger_entries,
		"danger_ticks": danger_ticks, "barn_doors": barn_doors, "barn_ticks": barn_ticks,
		"spent": spent, "start_y": start_y, "events": events, "finish": finish, "helped": helped}
