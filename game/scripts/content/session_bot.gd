class_name SessionBot
extends RefCounted
## 세션 검증 봇(docs/28 §7.4). 실제 게임 경로(ClimbSession)에 InputRouter 명령과 기술 선택을 넣어 단계를 재생한다.
## 패드 잡기 방향 자동 선택·검증기 금지 플래그(forbid)·기술 실행기가 플레이와 똑같이 동작한다.
## 단계 형식: [limb, key] 패드 이동, [limb, "T_DROP_KNEE"] 제자리 버튼 기술, [limb, "T_OUTSIDE_EDGE", key] 홀드로 옮기는 버튼 기술,
## [foot, "flag", [x, y]] 발을 벽 지점으로 끌어 균형 발로 두기.
## 빈 배열 []은 아무것도 하지 않는 단계다(ContentCheck가 버튼 기술을 금지할 때 인덱스를 유지하려고 쓴다).
## 결과는 정적·결정적 시뮬레이션이며 기기 플레이 검증이 아니다.

const DRAG_SPEED := 2.5           # 말단 끌기 속도(m/s, 말단 따라가기와 같음)
const CANDIDATE_TICKS := 180      # 이 안에 후보가 그 키가 되지 않으면 실패
const SETTLE_MAX_TICKS := 240
const SETTLE_SPEED := 0.01        # 골반 속도(m/s)가 이보다 작은 틱이
const SETTLE_CALM_TICKS := 6      # 이만큼 이어지면 안정
const TECHNIQUE_TICKS := 120      # 버튼 기술이 유지 단계(yaw)에 들어가거나 끝날 때까지
const FLAG_TICKS := 120
const FLAG_ARRIVE := 0.02         # 균형 발 지점 도착 판정(m)
const START_MIN_TICKS := 30      # 시작 자세 최소 대기 틱
const GOAL_TICKS := 240           # 모든 단계 뒤 정상에서 "clear"를 기다리는 최대 틱

var route: RouteDef
var session: ClimbSession
var failure := ""
const START_FAILED := -2  # failed_step: 시작 자세 안정 중 실패(추락 등)
var failed_step := -1   # 실패한 단계 인덱스. -1 = 성공 또는 모든 단계 뒤 목표 미도달, START_FAILED = 시작 자세에서 실패
var log: PackedStringArray = []
## min_reach_margin: 잡은 뒤 안정된 자세(그 단계 뒤 _settle이 끝난 골반·회전)에서 그 팔다리의 최대 벽면 도달 거리 −
##   어깨/고관절에서 잡은 점까지 거리(m)의 최소. 최대 거리는 PoseSolver.can_reach와 같이 planar_range(limb, 접점 깊이 범위 +
##   관절 깊이 오프셋)의 먼 쪽이다. 봇은 후보가 생기는 첫 틱에 놓으므로 잡는 순간에는 여유가 항상 0 근처라, 몸이 자리 잡은 뒤를 잰다.
##   패드·버튼 기술로 잡은 모든 손발을 같은 방법으로 잰다. 안정 중 완등하면 완등 직전 틱 자세로 잰다.
##   잰 때 그 팔다리가 더 이상 그 홀드에 붙어 있지 않으면 재지 않는다.
## min_hand_half_width: 경로에서 잡은 손홀드(정상 슬롯 제외)의 hand_area.half_width 최소. max_hand_u: 틱마다의 손 사용률 최대.
## min_stamina: 붙어 있는 손의 피로 최소. moves: 마친 단계 수(건너뛴 [] 제외). seconds: 시뮬레이션 시간.
var metrics := {"min_reach_margin": INF, "min_hand_half_width": INF, "max_hand_u": 0.0, "min_stamina": 100.0, "moves": 0, "seconds": 0.0}
var _pending_grabs: Array = []  # 아직 도달 여유를 재지 않은 잡기 [{limb, key}]
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
	var start_err := ""
	for i in START_MIN_TICKS:  # 무지지·불균형 유예(9·18틱)가 지나도록 먼저 기다린다: 서 있지 못하는 시작 자세를 잡아낸다
		start_err = _tick()
		if not start_err.is_empty():
			break
	if start_err.is_empty():
		start_err = _settle()
	if not start_err.is_empty():
		failed_step = START_FAILED
		failure = "시작 자세: " + start_err
		log.append(failure)
		return
	var b := session.body
	log.append("시작 안정 자세 골반=(%.3f, %.3f) θ=%.1f°" % [b.pos.x, b.pos.y, b.angle])
	for i in steps.size():
		if cleared:
			break
		var m: Array = steps[i]
		var err := _do_step(m)
		if not err.is_empty():
			failed_step = i
			failure = "#%d %s: %s" % [i, _desc(m), err]
			log.append(failure)
			return
		if not m.is_empty():
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


static func _desc(m: Array) -> String:
	return "건너뜀" if m.is_empty() else " ".join(m.map(func(v): return str(v)))


## 한 단계. 오류 문구(성공이면 "").
func _do_step(m: Array) -> String:
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
	else:
		err = _technique(limb, StringName(second), str(m[2]))
	if not err.is_empty() or cleared:
		return err
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
	session.apply_input(cmds)
	_scan_events()


## 한 틱. 오류 문구(없으면 ""). 완등하면 cleared(세션은 시작 자세로 돌아간다).
func _tick() -> String:
	var b := session.body
	var pose := [b.pos, b.angle, b.yaw]
	var held := _held() if not _pending_grabs.is_empty() else {}
	var r := session.step()
	_ticks += 1
	if r == "clear":
		cleared = true
		_measure_pending(pose, held)  # 세션이 시작 자세로 돌아갔으므로 완등 직전 틱 자세로 잰다
		return ""
	_scan_events()
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
			break
		if i == SETTLE_MAX_TICKS - 1:
			log.append("안정 대기 %d틱 초과(골반 속도 %.3fm/s), 그대로 진행" % [SETTLE_MAX_TICKS, session.body.vel.length()])
	var b := session.body
	_measure_pending([b.pos, b.angle, b.yaw], _held())
	return ""


## 새 grab 이벤트: 손홀드 반폭(정상 슬롯 제외)을 재고, 도달 여유는 안정 뒤에 재도록 남겨 둔다.
func _scan_events() -> void:
	var fresh := session.technique_log.filter(func(e): return e.seq > _seen_seq)
	if fresh.is_empty():
		return
	_seen_seq = fresh.back().seq
	for e in fresh:
		if e.type != "grab":
			continue
		var limb: StringName = e.limb
		var key: String = e.key
		if PoseSolver.is_hand(limb) and route.slots[key].has("hand_area") and not route.goal_slots.has(key):
			metrics.min_hand_half_width = minf(metrics.min_hand_half_width, float(route.slots[key].hand_area.half_width))
		_pending_grabs.append({"limb": limb, "key": key})


## 붙어 있는 팔다리 → [슬롯 키, 잡은 점].
func _held() -> Dictionary:
	var d := {}
	for limb in session.limbs:
		var l: Dictionary = session.limbs[limb]
		if l.state in ["Attached", "Armed"]:
			d[limb] = [l.key, l.grab]
	return d


## 남은 잡기의 도달 여유를 pose [골반, 각도, yaw]와 그때 붙어 있던 팔다리(held)로 잰다(그 홀드에 아직 붙어 있는 것만).
func _measure_pending(pose: Array, held: Dictionary) -> void:
	for g in _pending_grabs:
		if held.has(g.limb) and held[g.limb][0] == g.key:
			metrics.min_reach_margin = minf(metrics.min_reach_margin, reach_margin(pose[0], pose[1], pose[2], g.limb, held[g.limb][1]))
	_pending_grabs.clear()


## 그 자세에서 limb이 point를 잡을 때 더 뻗을 수 있는 거리(m). PoseSolver.can_reach의 최대 거리 조건과 같은 식.
static func reach_margin(pelvis: Vector2, angle: float, yaw: float, limb: StringName, point: Vector2) -> float:
	var dz := PoseSolver.contact_dz_range() + Vector2.ONE * PoseSolver.joint_depth_offset(limb, yaw)
	var far := PoseSolver.planar_range(limb, dz.x, dz.y).y
	return far - PoseSolver.limb_distance(pelvis, angle, limb, point, yaw)


func _log_clear() -> void:
	log.append("완등: %d틱(%.2f초), 이동 %d, 도달 여유 최소 %.3fm, 손 반폭 최소 %.3fm, 최대 손 사용률 %.2f, 최저 손 피로 %.0f" % [_ticks, _ticks / float(Tuning.TICK_HZ), metrics.moves, metrics.min_reach_margin, metrics.min_hand_half_width, metrics.max_hand_u, metrics.min_stamina])
