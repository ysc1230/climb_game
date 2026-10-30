class_name ClimbRules
extends RefCounted
## 한 틱의 지지·몸통 이동·피로·유예 규칙(docs/04 §4·§7, docs/15 확정 순서 5~7).
## 게임 장면(PlayTest)과 경로 검증기(RouteBot)가 같은 규칙을 쓰도록 한 곳에 둔다. 노드 의존 없음.
##
## 상태: STABLE(힘 해 있음, 모든 u≤0.80) / STRAINED(해 있음, 일부 u>0.80) /
##       REBALANCING(손·플랫폼 자격은 있으나 힘 해 없음, 18틱 예산) / GRACE(유효 손·플랫폼 없음, 9틱)
## 미구현(docs/23 참고): 무브 단계·무브별 선호 거리, 손 하중의 목표 자세 비용, 경로 sweep, yaw/pitch.

enum Phase { STABLE, STRAINED, REBALANCING, GRACE }

const IMBALANCE_BUDGET_TICKS := 18
const BALANCE_CONFIRM_TICKS := 6
const REST_CONFIRM_TICKS := 6
const LOADED_FOOT_ENTER := 0.05
const LOADED_FOOT_EXIT := 0.03
const REBALANCE_LATERAL_WEIGHT := 5.0
const ACCEPT_EPSILON := 0.0005

var stamina := {PoseSolver.LH: 100.0, PoseSolver.RH: 100.0}
var feet_eligible: Array[StringName] = []
var loaded_feet: Array[StringName] = []
var unsupported_ticks := 0
var imbalance_ticks := 0
var balance_confirm_ticks := 0
var rest_confirm_ticks := 0
var phase := Phase.STABLE
var last := {}            # 마지막 확정 힘 계산 결과
var fatigue_disabled := false
var slipped: Array[StringName] = []
var moves := MoveClassifier.new()   # 무브 라벨·무브별 선호 거리(docs/25)
var flag_ready: Array[StringName] = []  # 지금 놓으면 균형 발(Free/Flag)로 남는 드래그 발

# accept 콜백용 틱 문맥
var _ctx_attached := {}
var _ctx_endpoints := {}
var _ctx_platform := false
var _ctx_prev_feasible := false
var _ctx_prev_residual := INF
var _eval_sig := []
var _eval := {}
var _target_sig := []
var _target := Vector3.ZERO
var _target_from_pos := Vector2(INF, INF)
var _target_from_angle := 0.0


func reset(body: BodyState, attached: Dictionary, endpoints: Dictionary, platform: bool) -> void:
	stamina = {PoseSolver.LH: 100.0, PoseSolver.RH: 100.0}
	unsupported_ticks = 0
	imbalance_ticks = 0
	balance_confirm_ticks = BALANCE_CONFIRM_TICKS  # 새 시작은 사전 검증된 균형 자세(docs/04)
	rest_confirm_ticks = 0
	feet_eligible = PoseSolver.supporting_feet(body.pos, body.angle, attached)
	last = evaluate(body.pos, body.angle, attached, endpoints, platform)
	loaded_feet = _loaded_from(last, [])
	phase = _phase_of(last)


func balance_confirmed() -> bool:
	return balance_confirm_ticks >= BALANCE_CONFIRM_TICKS


func phase_name() -> String:
	return ["Stable", "Strained", "Rebalancing", "Grace"][phase]


## 하중을 받을 자격이 있는 접점 목록. 손: 하중 자격, 발: 지지 원뿔(플랫폼 발 포함).
func contacts_for(pelvis: Vector2, angle_deg: float, attached: Dictionary, feet: Array) -> Array:
	var out := []
	for limb in PoseSolver.LIMBS:
		if not attached.has(limb):
			continue
		if PoseSolver.is_hand(limb):
			if PoseSolver.hand_load_eligible(pelvis, angle_deg, limb, attached[limb]):
				out.append(SupportSolver.contact(limb, attached[limb]))
		elif feet.has(limb):
			out.append(SupportSolver.contact(limb, attached[limb]))
	return out


func evaluate(pelvis: Vector2, angle_deg: float, attached: Dictionary, endpoints: Dictionary, _platform: bool, feet: Array = feet_eligible) -> Dictionary:
	var eps := endpoints.duplicate()
	for limb in attached:
		eps[limb] = attached[limb]
	var com := SupportSolver.com_proxy(pelvis, angle_deg, eps)
	var r := SupportSolver.solve(contacts_for(pelvis, angle_deg, attached, feet), com)
	r["com"] = com
	return r


## 한 틱. attached: limb→접점 위치, endpoints: 자유 말단 위치, platform: 플랫폼 지지 성립,
## moving: 활성 이동 목표(드래그 중 말단)가 있는지. 반환: "" | "NO_SUPPORT" | "BALANCE_LOST" | "UNRESOLVED".
## slipped에 피로 0으로 미끄러진 손을 담는다(호출 측이 접점을 해제).
## intents: limb → 활성(드래그) 말단의 요청 목표. hints: limb → 호출 측이 아는 무브 단서(HandMatch/FootSwap).
## flag_probe: 잡을 후보가 없는 드래그 발 목록. 균형 발 조건을 통과하면 flag_ready에 담는다(25 MV06).
func tick(body: BodyState, attached: Dictionary, endpoints: Dictionary, platform: bool, moving: bool, intents: Dictionary = {}, hints: Dictionary = {}, flag_probe: Array = []) -> String:
	slipped.clear()
	_update_flags(body, attached, endpoints, flag_probe)
	var all_hints := hints.duplicate()
	for foot in flag_ready:
		if intents.has(foot) and not all_hints.has(foot):
			all_hints[foot] = MoveClassifier.FLAG
	moves.update(body.pos, body.angle, attached, intents, endpoints, all_hints)
	var has_hand := PoseSolver.eligible_hands(body.pos, body.angle, attached) > 0
	var result: Dictionary
	if has_hand or platform:
		unsupported_ticks = 0
		_ctx_attached = attached
		_ctx_endpoints = endpoints
		_ctx_platform = platform
		_ctx_prev_feasible = last.get("status", -1) == SupportSolver.Status.FEASIBLE
		_ctx_prev_residual = last.get("residual", INF)
		var lateral := NAN
		var weight := 0.0
		if phase == Phase.REBALANCING:
			# 무게중심이 지지점 평균 X 아래로 오도록 골반 목표를 옮긴다(몸이 손 아래로 정렬)
			var com_offset: float = (last.get("com", body.pos) as Vector2).x - body.pos.x
			lateral = _support_center_x(body.pos, body.angle, attached) - com_offset
			weight = REBALANCE_LATERAL_WEIGHT
		PoseSolver.move_body(body, _target_for(body, attached, intents, lateral, weight), attached, Tuning.DT, Callable(self, "_accept"))
		feet_eligible = PoseSolver.supporting_feet(body.pos, body.angle, attached, feet_eligible)
		result = _evaluate_cached(body.pos, body.angle)
		if result.status == SupportSolver.Status.UNRESOLVED:
			return "UNRESOLVED"
		phase = _phase_of(result)
	else:
		unsupported_ticks += 1
		result = {"status": SupportSolver.Status.INFEASIBLE, "loads": {}, "u": {}, "residual": INF}
		phase = Phase.GRACE
	loaded_feet = _loaded_from(result, loaded_feet)
	last = result
	# 피로(docs/04 §7)
	var speed := body.vel.length()
	var still := phase == Phase.STABLE and speed <= Fatigue.STABLE_SPEED and not moving
	rest_confirm_ticks = rest_confirm_ticks + 1 if still else 0
	var rest_ok := rest_confirm_ticks >= REST_CONFIRM_TICKS
	var hands_attached := int(attached.has(PoseSolver.LH)) + int(attached.has(PoseSolver.RH))
	var low_load := true
	for hand in [PoseSolver.LH, PoseSolver.RH]:
		if result.u.get(hand, 0.0) > SupportSolver.RECOVER_HAND_LOAD_RATIO:
			low_load = false
	for hand in [PoseSolver.LH, PoseSolver.RH]:
		var rate := Fatigue.FREE_HAND_RATE
		if attached.has(hand):
			rate = Fatigue.attached_hand_rate(phase == Phase.REBALANCING, platform, rest_ok, loaded_feet.size(), hands_attached, result.u.get(hand, 0.0), low_load)
		stamina[hand] = Fatigue.apply(stamina[hand], rate, Tuning.DT, fatigue_disabled)
		if attached.has(hand) and stamina[hand] <= 0.0:
			slipped.append(hand)
	# 미끄러진 손을 뺀 상태로 같은 틱에 지지 재평가(시간·몸통 적분은 다시 하지 않음)
	if not slipped.is_empty():
		var remain := attached.duplicate()
		for hand in slipped:
			remain.erase(hand)
		if PoseSolver.eligible_hands(body.pos, body.angle, remain) == 0 and not platform:
			if phase != Phase.GRACE:
				unsupported_ticks += 1
			phase = Phase.GRACE
			result = {"status": SupportSolver.Status.INFEASIBLE, "loads": {}, "u": {}, "residual": INF}
		else:
			result = evaluate(body.pos, body.angle, remain, endpoints, platform)
			if result.status == SupportSolver.Status.UNRESOLVED:
				return "UNRESOLVED"
			phase = _phase_of(result)
		loaded_feet = _loaded_from(result, loaded_feet)
		last = result
	# 무지지·불균형 카운터(docs/04 §4 정확한 카운터 정의)
	if phase == Phase.STABLE or phase == Phase.STRAINED:
		balance_confirm_ticks += 1
		if balance_confirm_ticks >= BALANCE_CONFIRM_TICKS:
			imbalance_ticks = 0
	else:
		balance_confirm_ticks = 0
		imbalance_ticks += 1
	if unsupported_ticks >= Tuning.UNSUPPORTED_GRACE_TICKS:
		return "NO_SUPPORT"
	if imbalance_ticks >= IMBALANCE_BUDGET_TICKS:
		return "BALANCE_LOST"
	return ""


## 몸통 이동 후보 검사: 균형이 있던 틱에는 균형을 유지하는 이동만, 불균형 중에는 잔차를 줄이는 이동만.
func _accept(p: Vector2, a: float) -> bool:
	var r := _evaluate_cached(p, a)
	if r.status == SupportSolver.Status.UNRESOLVED:
		return false
	if _ctx_prev_feasible:
		return r.status == SupportSolver.Status.FEASIBLE
	return r.status == SupportSolver.Status.FEASIBLE or r.residual <= _ctx_prev_residual + ACCEPT_EPSILON


## 같은 자세·접점·자유 말단·지지 발 후보에 대한 힘 계산은 다시 풀지 않는다(결과 동일).
func _evaluate_cached(p: Vector2, a: float) -> Dictionary:
	var feet := PoseSolver.supporting_feet(p, a, _ctx_attached, feet_eligible)
	var key := [p, a, _signature(_ctx_attached), _signature(_ctx_endpoints), feet]
	if key != _eval_sig:
		_eval = evaluate(p, a, _ctx_attached, _ctx_endpoints, _ctx_platform, feet)
		_eval_sig = key
	return _eval


## 목표 자세 재사용: 접점·지지 발·정렬 목표가 같고 탐색 시작점이 직전 탐색과 거의 같으면 그대로 쓴다.
## find_target은 시작점 근방의 국소 탐색이라 시작점이 3mm·0.3° 안이면 같은 수렴 목표로 본다.
func _target_for(body: BodyState, attached: Dictionary, intents: Dictionary, lateral: float, weight: float) -> Vector3:
	var sig := [_signature(attached), feet_eligible.duplicate(), lateral, weight, _signature(intents), moves.profile.duplicate()]
	if sig == _target_sig and body.pos.distance_to(_target_from_pos) < 0.003 and absf(body.angle - _target_from_angle) < 0.3:
		return _target
	_target = PoseSolver.find_target(body.pos, body.angle, attached, feet_eligible, moves.profile, intents, lateral, weight)
	_target_sig = sig
	_target_from_pos = body.pos
	_target_from_angle = body.angle
	return _target


static func _signature(d: Dictionary) -> Array:
	var out := []
	for limb in PoseSolver.LIMBS:
		out.append(d.get(limb, Vector2(INF, INF)))
	return out


func _support_center_x(pelvis: Vector2, angle_deg: float, attached: Dictionary) -> float:
	var cs := contacts_for(pelvis, angle_deg, attached, feet_eligible)
	if cs.is_empty():
		return pelvis.x
	var sx := 0.0
	for c in cs:
		sx += c.pos.x
	return sx / cs.size()


## 25 MV06: 잡을 후보가 없는 드래그 발을 현재 위치에 두는 것이 휴식 위치에 두는 것보다
## 균형 비용(손 하중 Σ2u², 불균형이면 잔차²×10)을 0.02 이상 줄이면 균형 발 후보.
func _update_flags(body: BodyState, attached: Dictionary, endpoints: Dictionary, probe: Array) -> void:
	flag_ready.clear()
	if probe.is_empty() or PoseSolver.eligible_hands(body.pos, body.angle, attached) == 0:
		return
	for foot in probe:
		if not endpoints.has(foot):
			continue
		var here := evaluate(body.pos, body.angle, attached, endpoints, false)
		var rest_eps := endpoints.duplicate()
		rest_eps[foot] = PoseSolver.clamp_endpoint(body.pos, body.angle, foot, endpoints[foot], body.pos + Vector2(0.25 * PoseSolver.side_sign(foot), -0.70))
		var rest := evaluate(body.pos, body.angle, attached, rest_eps, false)
		if balance_cost(rest) - balance_cost(here) >= Tuning.FLAG_COST_IMPROVEMENT:
			flag_ready.append(foot)


static func balance_cost(r: Dictionary) -> float:
	if r.get("status", -1) != SupportSolver.Status.FEASIBLE:
		return 10.0 * pow(r.get("residual", 1.0), 2) + 4.0
	var c := 0.0
	for limb in r.u:
		if PoseSolver.is_hand(limb):
			c += SupportSolver.LOAD_COST_HAND * pow(r.u[limb], 2)
	return c


func _phase_of(r: Dictionary) -> Phase:
	if r.status != SupportSolver.Status.FEASIBLE:
		return Phase.REBALANCING
	return Phase.STABLE if SupportSolver.max_u(r) <= SupportSolver.STABLE_LOAD_RATIO else Phase.STRAINED


func _loaded_from(r: Dictionary, previous: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	if r.get("status", -1) != SupportSolver.Status.FEASIBLE:
		return out
	for foot in [PoseSolver.LF, PoseSolver.RF]:
		var load: float = r.loads.get(foot, 0.0)
		var threshold := LOADED_FOOT_EXIT if previous.has(foot) else LOADED_FOOT_ENTER
		if load >= threshold:
			out.append(foot)
	return out
