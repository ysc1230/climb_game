class_name ScoreRecorder
extends RefCounted
## 시도 기록(docs/superpowers/specs/2026-11-19-3-score-design.md §3.1). 노드 없음. 판정 틱마다 tick(session, 결과)로
## 세션을 읽기만 한다(판정 변경 없음). 플레이 화면과 검사 봇(SessionBot.recorder)이 같이 쓴다.
## technique_log는 최근 200개만 남으므로 점수에 쓰는 사건(grab·miss·move·succeeded·flag·pad_foot_swap)은 여기서 다 모은다.

const KEEP := ["grab", "miss", "move", "succeeded", "flag", "pad_foot_swap"]

var ticks := 0
var stable_ticks := 0
var danger_entries := 0   # 균형 회복 중·지지 없음에 들어간 수
var barn_doors := 0       # 문 열림(몸이 문처럼 돎)에 들어간 수
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
	var danger := ph == ClimbRules.Phase.REBALANCING or ph == ClimbRules.Phase.GRACE
	var was := _prev_phase == ClimbRules.Phase.REBALANCING or _prev_phase == ClimbRules.Phase.GRACE
	if danger and not was:
		danger_entries += 1
	var barn := ph == ClimbRules.Phase.REBALANCING and s.rules.imbalance_cause == &"BARN_DOOR"
	if barn and not _prev_barn:
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
			for k in ["key", "label", "id", "limb"]:
				if e.has(k):
					out[k] = e[k]
			if out.type == "grab":
				out["tech"] = grab_techniques(s, StringName(str(e.get("limb", ""))), str(e.get("key", "")))
			events.append(out)


## 잡은 순간 자세로 본 패드 기술(검사기 금지 규칙과 같은 기준, ClimbSession.forbid):
## 발이 고관절 − HIGH_STEP_BELOW_HIP 이상이면 하이스텝, 손이 반대 손을 넘으면 크로스, 반대 손과 같은 홀드면 매치.
static func grab_techniques(s: ClimbSession, limb: StringName, key: String) -> Array:
	if not s.route.slots.has(key) or not s.limbs.has(limb):
		return []
	var point: Vector2 = s.route.slots[key].pos
	var out := []
	if not PoseSolver.is_hand(limb):
		var hip := PoseSolver.joint_position(s.body.pos, s.body.angle, limb, s.body.yaw)
		if point.y >= hip.y - Tuning.HIGH_STEP_BELOW_HIP:
			out.append("T_HIGH_STEP")
		return out
	var other := PoseSolver.RH if limb == PoseSolver.LH else PoseSolver.LH
	var o: Dictionary = s.limbs[other]
	if o.state in ["Attached", "Armed"] and o.get("key", "") != null and str(o.get("key", "")) != "":
		var ox: float = (o.grab as Vector2).x
		if (limb == PoseSolver.LH and point.x > ox) or (limb == PoseSolver.RH and point.x < ox):
			out.append("T_CROSS")
		if key.get_base_dir() == str(o.key).get_base_dir():
			out.append("T_MATCH")
	return out


static func _pose(s: ClimbSession) -> Dictionary:
	var att := s.attached()
	return {"feet_on": att.has(PoseSolver.LF) and att.has(PoseSolver.RF), "stable": s.rules.phase == ClimbRules.Phase.STABLE}


func to_dict() -> Dictionary:
	return {"ticks": ticks, "stable_ticks": stable_ticks, "danger_entries": danger_entries, "barn_doors": barn_doors,
		"spent": spent, "start_y": start_y, "events": events, "finish": finish, "helped": helped}
