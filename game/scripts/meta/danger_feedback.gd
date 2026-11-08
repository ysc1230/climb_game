class_name DangerFeedback
extends RefCounted
## 떨어지기 전 경고 3단계(2026-11-09 사용자: "경고라는 느낌이 전혀 없다, 게임하다 바로 알 수 있게").
## ① 주의(노랑): 붙은 손발 패드를 누른 순간, 그 손발을 떼면 버티지 못하는 자세면(ClimbSession.release_risk).
## ② 위험(빨강): 지지 상태가 균형 회복 중(REBALANCING)·지지 없음(GRACE)에 들어간 동안.
##    들어가는 순간 0.15초 멈칫(HITSTOP, 신호용), 심장 박동 진동·소리(HEARTBEAT 간격).
## ③ 회복(초록): 위험에서 떨어지지 않고 빠져나온 순간 RECOVER_SHOW 동안.
## 판정은 바꾸지 않는다. 노드 없이 매 실제 프레임 update(state)로 돌고, 이번 프레임 사건을 events에 담는다.
## state: {danger: bool, kind: &"GRACE"/&"FORCE"/&"BARN_DOOR", frac: 남은 예산 비율, ticks_left: int,
##         falling: bool, states: {limb: 상태}, keys: {limb: 슬롯 키}, risks: {limb: release_risk(눌린 손발만)},
##         hands_on: 붙은 손 수}

const HITSTOP := 0.15      # 실제 초. 위험에 들어가는 순간 판정을 멈춰 "뭔가 일어났다"를 알린다
const HEARTBEAT := 0.55    # 실제 초. 위험 동안 진동·소리 간격(두근 → 0.16초 뒤 두근)
const BEAT2 := 0.16
const RECOVER_SHOW := 0.8
const RECENT := 2.5        # 실제 초. 이 안에 뗀 손발을 추락 원인·안내에 쓴다
const LIMB_KO := {&"LH": "왼손", &"RH": "오른손", &"LF": "왼발", &"RF": "오른발"}

var danger := false
var kind: StringName = &""
var frac := 1.0
var ticks_left := -1
var danger_time := 0.0     # 이번 위험이 이어진 실제 초(글자 튀어나오는 연출용)
var hitstop_left := 0.0
var recover_left := 0.0
var caution := {}          # limb → 위험 종류(지금 눌러 둔 손발 중 떼면 위험한 것)
var last_release := {}     # {limb, key, slip: bool, age: 실제 초} 가장 최근에 붙어 있다가 떨어진 손발
var releases := {}         # limb → 같은 형식(손발마다 마지막으로 뗀 것). 해결 안내가 손을 고를 때
var hands_were_on := 0     # 위험 동안 붙어 있던 손 수(추락 원인 문구)
var events: Array[StringName] = []  # 이번 프레임: enter, beat, recover, caution, fall
var _risk_cache := {}      # limb → [release_risk, 다시 계산까지 남은 틱](눌러 둔 손발)
const RISK_RECHECK_TICKS := 12
var _beat := 0.0
var _beat2 := -1.0
var _prev_states := {}


func reset() -> void:
	danger = false
	kind = &""
	frac = 1.0
	ticks_left = -1
	danger_time = 0.0
	hitstop_left = 0.0
	recover_left = 0.0
	caution = {}
	last_release = {}
	releases = {}
	hands_were_on = 0
	events.clear()
	_beat = 0.0
	_beat2 = -1.0
	_prev_states = {}
	_risk_cache = {}


## 세션을 보고 한 프레임 진행한다(play_test와 튜토리얼 시험 드라이버가 같이 쓴다). 판정 틱이 돌았으면 stepped.
## 눌러 둔(Armed) 손발은 누른 순간과 그 뒤 RISK_RECHECK_TICKS 틱마다 떼면 버틸 수 있는지 다시 계산한다.
func observe_session(session: ClimbSession, real_dt: float, stepped: bool) -> void:
	var rules := session.rules
	var ph: int = rules.phase
	var states := {}
	var keys := {}
	var hands_on := 0
	var risks := {}
	for limb in session.limbs:
		var l: Dictionary = session.limbs[limb]
		states[limb] = l.state
		keys[limb] = l.key
		if PoseSolver.is_hand(limb) and l.state in ["Attached", "Armed"]:
			hands_on += 1
		if l.state == "Armed" and not session.falling:
			var c: Array = _risk_cache.get(limb, [&"", 0])
			if not _risk_cache.has(limb) or (stepped and c[1] <= 0):
				c = [session.release_risk(limb), RISK_RECHECK_TICKS]
			elif stepped:
				c[1] -= 1
			_risk_cache[limb] = c
			risks[limb] = c[0]
		else:
			_risk_cache.erase(limb)
	var bl := rules.budget_left()
	var k: StringName = &"GRACE" if ph == ClimbRules.Phase.GRACE else (rules.imbalance_cause if rules.imbalance_cause != &"" else &"FORCE")
	update(real_dt, {"danger": ph == ClimbRules.Phase.REBALANCING or ph == ClimbRules.Phase.GRACE, "kind": k,
		"frac": bl[0], "ticks_left": bl[1], "falling": session.falling, "states": states, "keys": keys, "risks": risks, "hands_on": hands_on})


## 이번 프레임 사건을 튜토리얼 목표용 사건으로(TutorialRunner.note). caution은 주의 중인 손발마다 하나.
func tutorial_events() -> Array:
	var out: Array = []
	for ev in events:
		match ev:
			&"caution":
				for limb in caution:
					out.append({"type": "caution", "limb": limb})
			&"enter":
				out.append({"type": "danger_enter"})
			&"recover":
				out.append({"type": "recover"})
				out.append({"type": "danger_end"})
			&"fall":
				out.append({"type": "danger_end"})
	return out


func update(real_dt: float, s: Dictionary) -> void:
	events.clear()
	hitstop_left = maxf(0.0, hitstop_left - real_dt)
	recover_left = maxf(0.0, recover_left - real_dt)
	var falling: bool = s.get("falling", false)
	var states: Dictionary = s.get("states", {})
	for limb in releases:
		releases[limb].age += real_dt
	# 붙어 있다가 떨어진 손발(끌기 시작 = Dragging, 미끄러짐 = 바로 Free). 추락 중에는 모두 Free가 되므로 보지 않는다.
	if not falling:
		for limb in states:
			var was: String = _prev_states.get(limb, "")
			var now: String = states[limb]
			if was in ["Attached", "Armed"] and not now in ["Attached", "Armed"]:
				releases[limb] = {"limb": limb, "key": s.get("keys", {}).get(limb, ""), "slip": now == "Free", "age": 0.0}
				last_release = releases[limb]
	_prev_states = states.duplicate()
	# ① 주의: 새로 위험해진 눌린 손발이 있으면 사건
	var risks: Dictionary = s.get("risks", {})
	var fresh := false
	for limb in risks:
		if risks[limb] != &"" and not caution.has(limb):
			fresh = true
	caution = {}
	for limb in risks:
		if risks[limb] != &"":
			caution[limb] = risks[limb]
	if fresh and not danger and not falling:
		events.append(&"caution")
	# ② 위험
	var now_danger: bool = s.get("danger", false) and not falling
	if falling and danger:
		events.append(&"fall")
	if now_danger and not danger:
		events.append(&"enter")
		hitstop_left = HITSTOP
		danger_time = 0.0
		_beat = 0.0
		_beat2 = BEAT2
	elif danger and not now_danger and not falling:
		events.append(&"recover")
		recover_left = RECOVER_SHOW
	danger = now_danger
	if danger:
		kind = s.get("kind", &"")
		frac = float(s.get("frac", 1.0))
		ticks_left = int(s.get("ticks_left", -1))
		hands_were_on = int(s.get("hands_on", 0))
		danger_time += real_dt
		_beat += real_dt
		if _beat >= HEARTBEAT:
			_beat -= HEARTBEAT
			_beat2 = BEAT2
			events.append(&"beat")
		if _beat2 >= 0.0:
			_beat2 -= real_dt
			if _beat2 < 0.0:
				events.append(&"beat2")
	else:
		frac = 1.0
		ticks_left = -1
		_beat2 = -1.0


## 심장 박동 위상(0 = 방금 뛰었음 → 1). 화면 붉은 테두리 맥박에 쓴다.
func pulse() -> float:
	if not danger:
		return 0.0
	var t := _beat / HEARTBEAT
	var t2 := t - BEAT2 / HEARTBEAT
	return exp(-6.0 * t) + (0.6 * exp(-6.0 * t2) if t2 >= 0.0 else 0.0)


## 최근에 뗀 손발(RECENT 안). 없으면 &"".
func recent_limb() -> StringName:
	if last_release.is_empty() or float(last_release.age) > RECENT:
		return &""
	return last_release.limb


## 해결 안내로 다시 잡게 할 손발: 버틸 손이 없으면(GRACE) 최근에 뗀 손, 아니면 가장 최근에 뗀 손발.
## not_attached: limb → 지금 붙어 있지 않은가. 없으면 {}.
func rescue_release(not_attached: Dictionary) -> Dictionary:
	var best := {}
	for limb in releases:
		var r: Dictionary = releases[limb]
		if float(r.age) > RECENT or not not_attached.get(limb, false) or str(r.key) == "":
			continue
		if kind == &"GRACE" and not PoseSolver.is_hand(limb):
			continue
		if best.is_empty() or float(r.age) < float(best.age):
			best = r
	return best


## 위험 종류별 큰 글자와 짧은 이유.
static func shout(k: StringName) -> String:
	match k:
		&"GRACE":
			return "잡아!"
		&"BARN_DOOR":
			return "버텨!"
	return "균형!"


static func reason_short(k: StringName) -> String:
	match k:
		&"GRACE":
			return "버틸 손이 없어요"
		&"BARN_DOOR":
			return "몸이 문처럼 돌아가요"
	return "몸이 지지 밖으로 기울었어요"


## 주의 단계 패드 글자.
static func caution_text(k: StringName) -> String:
	return "떼면 떨어져요" if k == &"GRACE" else "떼면 위험해요"


## 떨어진 뒤 원인 한 줄. reason: "NO_SUPPORT"/"BALANCE_LOST".
func fall_cause(reason: String) -> String:
	var limb := recent_limb()
	var rel := last_release
	if reason == "NO_SUPPORT":  # 버틸 손이 없어 떨어졌으면 마지막에 뗀 손이 원인
		limb = &""
		for l in releases:
			var r: Dictionary = releases[l]
			if PoseSolver.is_hand(l) and float(r.age) <= RECENT and (limb == &"" or float(r.age) < float(rel.age)):
				limb = l
				rel = r
	var who := ""
	if limb != &"":
		var name: String = LIMB_KO[limb]
		if rel.slip:
			return "팔 힘이 다 빠져 %s이 미끄러졌어요. 힘이 줄면 쉬운 자세에서 쉬어 주세요" % name
		who = "%s%s 뗀 뒤 " % [name, Progress.object_particle(name)]
	if reason == "NO_SUPPORT":
		if hands_were_on > 0:
			return who + "잡은 손이 어깨보다 낮아 몸을 버티지 못했어요"
		return who + "몸을 버틸 손이 없었어요. 다른 손을 먼저 잡고 떼 보세요"
	if kind == &"BARN_DOOR":
		return who + "몸이 문처럼 열려 돌아갔어요. 반대쪽 발로 버텨 보세요"
	return who + "몸이 손발 지지 밖으로 기울었어요. 몸을 지지 쪽으로 옮겨 보세요"
