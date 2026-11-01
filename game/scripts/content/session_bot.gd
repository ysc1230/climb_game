class_name SessionBot
extends RefCounted
## 세션 검증 봇(docs/28 §7.4). 실제 게임 경로(ClimbSession)에 InputRouter 명령과 기술 선택을 넣어 단계를 재생한다.
## 패드 잡기 방향 자동 선택·검증기 금지 플래그(forbid)·기술 실행기가 플레이와 똑같이 동작한다.
## 단계 형식: [limb, key] 패드 이동, [limb, "T_DROP_KNEE"] 제자리 버튼 기술, [limb, "T_OUTSIDE_EDGE", key] 홀드로 옮기는 버튼 기술,
## [hand, key, "deadpoint"] 패드 데드포인트, [foot, "flag", [x, y]] 발을 벽 지점으로 끌어 균형 발로 두기.
## 빈 배열 []은 아무것도 하지 않는 단계다(ContentCheck가 버튼 기술을 금지할 때 인덱스를 유지하려고 쓴다).
## 결과는 정적·결정적 시뮬레이션이며 기기 플레이 검증이 아니다.

const DRAG_SPEED := 2.5           # 말단 끌기 속도(m/s, 말단 따라가기와 같음)
const CANDIDATE_TICKS := 180      # 이 안에 후보가 그 키가 되지 않으면 실패
const SETTLE_MAX_TICKS := 240
const SETTLE_SPEED := 0.01        # 골반 속도(m/s)가 이보다 작은 틱이
const SETTLE_CALM_TICKS := 6      # 이만큼 이어지면 안정
const DEADPOINT_WAIT_TICKS := 120 # 데드포인트 창을 기다리는 최대 틱
const DEADPOINT_DRAG_TICKS := 30  # 창이 열린 뒤 손을 끄는 최대 틱
const DEADPOINT_RELEASE_SPEED := 2.0
const DEADPOINT_FLIGHT_TICKS := 20
const TECHNIQUE_TICKS := 120      # 버튼 기술이 유지 단계(yaw)에 들어가거나 끝날 때까지
const FLAG_TICKS := 120
const FLAG_ARRIVE := 0.02         # 균형 발 지점 도착 판정(m)
const GOAL_TICKS := 240           # 모든 단계 뒤 정상에서 "clear"를 기다리는 최대 틱

var route: RouteDef
var session: ClimbSession
var failure := ""
var failed_step := -1   # 실패한 단계 인덱스. -1 = 성공 또는 모든 단계 뒤 목표 미도달
var log: PackedStringArray = []
## min_reach_margin: 잡는 순간(그 틱 시작의 골반·회전) 그 팔다리의 최대 벽면 도달 거리 − 어깨/고관절에서 잡은 점까지 거리(m).
##   최대 거리는 PoseSolver.can_reach와 같이 planar_range(limb, 접점 깊이 범위 + 관절 깊이 오프셋)의 먼 쪽이다.
##   패드·버튼 기술로 잡은 모든 손발을 재고, 데드포인트로 받은 손은 도달 보너스를 쓰므로 제외한다(28 §7.3 V3 "또는 데드포인트").
## min_hand_half_width: 경로에서 잡은 손홀드(정상 포함)의 hand_area.half_width 최소. max_hand_u: 틱마다의 손 사용률 최대.
## min_stamina: 붙어 있는 손의 피로 최소. moves: 마친 단계 수. seconds: 시뮬레이션 시간.
var metrics := {"min_reach_margin": INF, "min_half_width": INF, "max_hand_u": 0.0, "min_stamina": 100.0, "moves": 0, "seconds": 0.0}
var cleared := false
var _ticks := 0
var _seen_seq := 0


static func run(p_route: RouteDef, steps: Array, forbid := {}) -> SessionBot:
	var bot := SessionBot.new()
	bot.route = p_route
	bot.session = ClimbSession.new(p_route)
	bot.session.forbid = forbid
	bot._play(steps)
	bot.metrics.seconds = bot._ticks / float(Tuning.TICK_HZ)
	return bot


func ok() -> bool:
	return failure.is_empty() and cleared


func _play(steps: Array) -> void:
	_settle()
	if not failure.is_empty():
		failed_step = -1
		return
	var b := session.body
	log.append("시작 안정 자세 골반=(%.3f, %.3f) θ=%.1f°" % [b.pos.x, b.pos.y, b.angle])
	for i in steps.size():
		if cleared:
			break
		var m: Array = steps[i]
		var err := _do_step(m, i + 1 < steps.size() and _is_deadpoint(steps[i + 1]))
		if not err.is_empty():
			failed_step = i
			failure = "#%d %s: %s" % [i, _desc(m), err]
			log.append(failure)
			return
		metrics.moves += 1
	if cleared:
		_log_clear()
		return
	for i in GOAL_TICKS:
		var err := _tick()
		if cleared:
			_log_clear()
			return
		if not err.is_empty():
			failure = "정상 대기 중 " + err
			log.append(failure)
			return
	failure = "모든 단계 뒤 %d틱 안에 완등하지 못함(정상 슬롯 양손 유지·균형 확인)" % GOAL_TICKS
	log.append(failure)


static func _is_deadpoint(m: Array) -> bool:
	return m.size() == 3 and m[2] is String and m[2] == "deadpoint"


static func _desc(m: Array) -> String:
	return "건너뜀" if m.is_empty() else " ".join(m.map(func(v): return str(v)))


## 한 단계. 오류 문구(성공이면 ""). next_deadpoint면 다음 단계(데드포인트)를 위해 안정을 기다리지 않는다.
func _do_step(m: Array, next_deadpoint: bool) -> String:
	if m.is_empty():
		log.append("건너뜀")
		return ""
	var limb := StringName(str(m[0]))
	var second := str(m[1])
	var err := ""
	if m.size() == 2 and second.begins_with("T_"):
		err = _technique(limb, StringName(second), "")
	elif m.size() == 2:
		err = _pad_move(limb, second)
	elif second == "flag":
		err = _flag(limb, Vector2(m[2][0], m[2][1]))
	elif _is_deadpoint(m):
		err = _deadpoint(limb, second)
	else:
		err = _technique(limb, StringName(second), str(m[2]))
	if not err.is_empty() or cleared:
		return err
	if not next_deadpoint:
		err = _settle()
	if err.is_empty():
		var b := session.body
		var st: Dictionary = session.rules.stamina
		log.append("%s 성공 골반=(%.3f, %.3f) θ=%.1f° ψ=%.1f° %s 하중발=%s 손피로 L%.0f R%.0f 틱%d" % [_desc(m), b.pos.x, b.pos.y, b.angle, b.yaw, session.rules.phase_name(), session.rules.loaded_feet, st[PoseSolver.LH], st[PoseSolver.RH], _ticks])
	return err


# ---------- 단계 종류 ----------

## 패드 이동: 떼고 목표 쪽으로 끌다가 후보가 그 키가 되면 speed 0으로 놓는다.
func _pad_move(limb: StringName, key: String) -> String:
	var target := route.slot_pos(key)
	_input([{"type": "detach", "limb": limb}])
	for i in CANDIDATE_TICKS:
		_drag(limb, target)
		var err := _tick()
		if not err.is_empty() or cleared:
			return err
		if session.limbs[limb].cand.get("key", "") == key:
			_input([{"type": "release", "limb": limb, "speed": 0.0}])
			var l: Dictionary = session.limbs[limb]
			if l.state != "Attached" or l.key != key:
				return "놓았지만 붙지 않음(%s %s)" % [l.state, l.key]
			return ""
	var reason := GripCheck.reject_reason(route.slots, limb, session.limbs[limb].pos, session.limbs[limb].req, session.body.pos, session.body.angle, session.attached(), session.occupied(), session.rules.feet_eligible, session.body.yaw)
	return "%d틱 안에 후보가 되지 않음(%s), 거리 %.3fm" % [CANDIDATE_TICKS, reason, PoseSolver.limb_distance(session.body.pos, session.body.angle, limb, target, session.body.yaw)]


## 버튼 기술: 선택을 열고 고른 뒤 실행기가 유지 단계(yaw)에 들어가거나 끝날 때까지 틱.
## 버튼 기술은 취소될 때까지 유지되므로(27 §10) "실행기가 빈다"는 실패·취소를 뜻한다. 유지 단계 도달이 성공이다.
func _technique(limb: StringName, id: StringName, key: String) -> String:
	var side := &"left" if limb in [PoseSolver.LH, PoseSolver.LF] else &"right"
	if not session.open_select():
		return "기술 선택을 열 수 없음"
	var point := route.slot_pos(key) if not key.is_empty() else Vector2.INF
	var reason := session.choose(id, side, key, point)
	if reason != &"":
		session.close_select()
		return "기술 시작 거부 %s" % reason
	for i in TECHNIQUE_TICKS:
		var err := _tick()
		if not err.is_empty() or cleared:
			return err
		if session.runner.active.is_empty():
			var ev: Array = session.technique_log.filter(func(e): return e.get("id") == id and e.type in [TechniqueRunner.FAILED, TechniqueRunner.CANCELLED])
			return "기술 %s 끝남(%s)" % [id, ev.back().get("reason", "") if not ev.is_empty() else "?"]
		if session.runner.active.step == &"yaw":
			log.append("%s %s 실행(유지)" % [limb, id])
			return ""
	return "기술 %s가 %d틱 안에 자리 잡지 못함" % [id, TECHNIQUE_TICKS]


## 패드 데드포인트: 창(골반 상승 중 또는 직후 0.25초)이 열릴 때까지 붙은 채 기다렸다가, 손을 떼어 목표 쪽으로 끌고
## 손이 더 나아가지 못하거나 정적 후보가 그 키가 되면 빠르게(2.0m/s) 놓는다. 정적 후보가 있으면 일반 잡기가 우선한다(세션 규칙 그대로).
## 창은 앞 단계의 일어서기로 열리므로 앞 단계 뒤에는 안정을 기다리지 않는다(_play).
func _deadpoint(hand: StringName, key: String) -> String:
	var target := route.slot_pos(key)
	var opened := session.deadpoint_window()
	for i in DEADPOINT_WAIT_TICKS:
		if opened:
			break
		var err := _tick()
		if not err.is_empty() or cleared:
			return err
		opened = session.deadpoint_window()
	if not opened:
		return "%d틱 안에 데드포인트 창이 열리지 않음" % DEADPOINT_WAIT_TICKS
	_input([{"type": "detach", "limb": hand}])
	var last_d := INF
	var released := false
	for i in DEADPOINT_DRAG_TICKS:
		_drag(hand, target)
		var err := _tick()
		if not err.is_empty() or cleared:
			return err
		var l: Dictionary = session.limbs[hand]
		var d := (l.pos as Vector2).distance_to(target)
		var stalled := d > last_d - 0.001
		last_d = d
		if stalled or l.cand.get("key", "") == key:
			_input([{"type": "release", "limb": hand, "speed": DEADPOINT_RELEASE_SPEED}])
			released = true
			break
	if not released:
		return "%d틱 동안 끌어도 손이 멈추지 않음" % DEADPOINT_DRAG_TICKS
	for i in DEADPOINT_FLIGHT_TICKS:
		if session.limbs[hand].state != "Deadpoint":
			break
		var err := _tick()
		if not err.is_empty() or cleared:
			return err
	var l: Dictionary = session.limbs[hand]
	if l.state != "Attached" or l.key != key:
		return "데드포인트로 잡지 못함(%s %s)" % [l.state, l.key]
	return ""


## 발을 벽 지점으로 끌어 놓아 균형 발(Flag)로 둔다. 말단이 그 지점에 닿거나(FLAG_ARRIVE) 더 나아가지 못하면 놓는다.
## 놓는 순간 균형 발 예고(flag_ready)가 켜져 있어야 Flag가 된다(세션 규칙 그대로). 지점은 저작자가 예고가 켜지는 곳으로 고른다.
func _flag(foot: StringName, point: Vector2) -> String:
	_input([{"type": "detach", "limb": foot}])
	var last_d := INF
	for i in FLAG_TICKS:
		_drag(foot, point)
		var err := _tick()
		if not err.is_empty() or cleared:
			return err
		var d := (session.limbs[foot].pos as Vector2).distance_to(point)
		if d <= FLAG_ARRIVE or d > last_d - 0.001:
			break
		last_d = d
	_input([{"type": "release", "limb": foot, "speed": 0.0}])
	var l: Dictionary = session.limbs[foot]
	if l.state != "Flag":
		return "균형 발이 되지 않음(%s %s)" % [l.state, l.key]
	return ""


# ---------- 틱·측정 ----------

func _drag(limb: StringName, target: Vector2) -> void:
	var req: Vector2 = session.limbs[limb].req
	_input([{"type": "move", "limb": limb, "delta": (target - req).limit_length(DRAG_SPEED * Tuning.DT)}])


## 입력을 넣고, 그 입력으로 생긴 잡기를 지금 자세로 잰다.
func _input(cmds: Array) -> void:
	var b := session.body
	var pose := [b.pos, b.angle, b.yaw]
	session.apply_input(cmds)
	_scan_events(pose)


## 한 틱. 오류 문구(없으면 ""). 완등하면 cleared(세션은 시작 자세로 돌아간다).
func _tick() -> String:
	var b := session.body
	var pose := [b.pos, b.angle, b.yaw]
	var r := session.step()
	_ticks += 1
	_scan_events(pose)
	if r == "clear":
		cleared = true
		return ""
	var u: Dictionary = session.rules.last.get("u", {})
	for hand in [PoseSolver.LH, PoseSolver.RH]:
		metrics.max_hand_u = maxf(metrics.max_hand_u, float(u.get(hand, 0.0)))
		if session.attached().has(hand):
			metrics.min_stamina = minf(metrics.min_stamina, float(session.rules.stamina[hand]))
	if r.begins_with("fall:"):
		return "추락 %s 골반=(%.3f, %.3f)" % [r.substr(5), session.body.pos.x, session.body.pos.y]
	if r == "unresolved":
		return "힘 계산 실패(내부 오류)"
	if not session.rules.slipped.is_empty():
		return "%s 피로 소진" % [session.rules.slipped]
	return ""


func _settle() -> String:
	var calm := 0
	for i in SETTLE_MAX_TICKS:
		var err := _tick()
		if not err.is_empty() or cleared:
			return err
		calm = calm + 1 if session.body.vel.length() < SETTLE_SPEED else 0
		if calm >= SETTLE_CALM_TICKS:
			return ""
	return ""


## 새 grab 이벤트마다 도달 여유와 손홀드 반폭을 잰다. pose: 그 잡기가 일어난 틱 시작의 [골반, 각도, yaw].
func _scan_events(pose: Array) -> void:
	var fresh := session.technique_log.filter(func(e): return e.seq > _seen_seq)
	if fresh.is_empty():
		return
	_seen_seq = fresh.back().seq
	for e in fresh:
		if e.type != "grab":
			continue
		var limb: StringName = e.limb
		var key: String = e.key
		if PoseSolver.is_hand(limb) and route.slots[key].has("hand_area"):
			metrics.min_half_width = minf(metrics.min_half_width, float(route.slots[key].hand_area.half_width))
		if fresh.any(func(x): return x.type == "pad_deadpoint" and x.limb == limb and x.ok):
			continue
		metrics.min_reach_margin = minf(metrics.min_reach_margin, reach_margin(pose[0], pose[1], pose[2], limb, session.limbs[limb].grab))


## 그 자세에서 limb이 point를 잡을 때 더 뻗을 수 있는 거리(m). PoseSolver.can_reach의 최대 거리 조건과 같은 식.
static func reach_margin(pelvis: Vector2, angle: float, yaw: float, limb: StringName, point: Vector2) -> float:
	var dz := PoseSolver.contact_dz_range() + Vector2.ONE * PoseSolver.joint_depth_offset(limb, yaw)
	var far := PoseSolver.planar_range(limb, dz.x, dz.y).y
	return far - PoseSolver.limb_distance(pelvis, angle, limb, point, yaw)


func _log_clear() -> void:
	log.append("완등: %d틱(%.2f초), 이동 %d, 도달 여유 최소 %.3fm, 손 반폭 최소 %.3fm, 최대 손 사용률 %.2f, 최저 손 피로 %.0f" % [_ticks, _ticks / float(Tuning.TICK_HZ), metrics.moves, metrics.min_reach_margin, metrics.min_half_width, metrics.max_hand_u, metrics.min_stamina])
