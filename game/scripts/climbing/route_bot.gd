class_name RouteBot
extends RefCounted
## 의도 경로 자동 재생기. 루트의 intended_moves를 고정 틱으로 따라가며
## docs/04의 도달·지지·피로 규칙으로 각 이동이 성립하는지 확인한다.
## 플레이어 모델: 팔다리를 떼고, 말단 이동 속도(2.5m/s) 이상 걸리는 시간 이후
## 잡을 수 있는 첫 틱에 놓는다. 잡은 뒤에는 몸통이 안정될 때까지 기다린다.
## 이 결과는 정적·결정적 시뮬레이션이며 실제 기기 플레이 검증이 아니다.

const ENDPOINT_FOLLOW_SPEED := 2.5
const MAX_WAIT_TICKS := 180
const SETTLE_MAX_TICKS := 240
const SETTLE_SPEED := 0.01

var route: RouteDef
var body: BodyState
var attached := {}        # limb -> Vector2
var attached_keys := {}   # limb -> slot key
var stamina := {PoseSolver.LH: 100.0, PoseSolver.RH: 100.0}
var feet: Array[StringName] = []
var ticks := 0
var min_stamina := 100.0
var log: PackedStringArray = []
var failure := ""


static func run(p_route: RouteDef, moves: Array = []) -> RouteBot:
	var bot := RouteBot.new()
	bot.route = p_route
	bot._play(moves if not moves.is_empty() else p_route.intended_moves)
	return bot


## 같은 손/발 쌍의 순서를 바꾼 경로(좌우 시작 순서 검증용).
static func swapped_pairs(moves: Array) -> Array:
	var out := moves.duplicate()
	var i := 0
	while i + 1 < out.size():
		var a: StringName = out[i][0]
		var b: StringName = out[i + 1][0]
		if PoseSolver.is_hand(a) == PoseSolver.is_hand(b) and a != b:
			var tmp = out[i]
			out[i] = out[i + 1]
			out[i + 1] = tmp
		i += 2
	return out


func ok() -> bool:
	return failure.is_empty()


func _play(moves: Array) -> void:
	body = BodyState.new(route.start_pelvis, route.start_angle)
	for limb in route.start_slots:
		attached_keys[limb] = route.start_slots[limb]
		attached[limb] = route.slot_pos(route.start_slots[limb])
	feet = PoseSolver.supporting_feet(body.pos, body.angle, attached)
	_settle()
	log.append("시작 안정 자세 골반=(%.3f, %.3f) θ=%.1f° (저작값 %.3f, %.3f)" % [body.pos.x, body.pos.y, body.angle, route.start_pelvis.x, route.start_pelvis.y])
	for m in moves:
		if not _move(m[0], m[1]):
			return
	_check_goal()


func _move(limb: StringName, key: String) -> bool:
	var target := route.slot_pos(key)
	var from: Vector2 = attached[limb]
	attached.erase(limb)
	attached_keys.erase(limb)
	var travel := int(ceil(from.distance_to(target) / ENDPOINT_FOLLOW_SPEED * Tuning.TICK_HZ))
	for wait in MAX_WAIT_TICKS + 1:
		if wait >= travel:
			var with_new := attached.duplicate()
			with_new[limb] = target
			if PoseSolver.can_reach(body.pos, body.angle, limb, target) and PoseSolver.is_valid(body.pos, body.angle, with_new):
				attached = with_new
				attached_keys[limb] = key
				_settle()
				log.append("%s→%s 성공 (뗀 뒤 %d틱) 안정 골반=(%.3f, %.3f) θ=%.1f° 지지발=%s 손피로 L%.0f R%.0f" % [limb, key, wait, body.pos.x, body.pos.y, body.angle, feet, stamina[PoseSolver.LH], stamina[PoseSolver.RH]])
				return true
		if not _tick():
			return false
	var d := PoseSolver.limb_distance(body.pos, body.angle, limb, target)
	failure = "%s→%s 잡기 불가: %d틱 기다려도 거리 %.3fm (허용 %.3f~%.3f), 골반=(%.3f, %.3f)" % [limb, key, MAX_WAIT_TICKS, d, PoseSolver.reach_of(limb).x, PoseSolver.reach_of(limb).y, body.pos.x, body.pos.y]
	log.append(failure)
	return false


func _settle() -> void:
	var calm := 0
	for i in SETTLE_MAX_TICKS:
		if not _tick():
			return
		calm = calm + 1 if body.vel.length() < SETTLE_SPEED else 0
		if calm >= 10:
			return


func _hands_attached() -> int:
	return int(attached.has(PoseSolver.LH)) + int(attached.has(PoseSolver.RH))


func _on_platform() -> bool:
	if not (attached.has(PoseSolver.LF) and attached.has(PoseSolver.RF)) or feet.size() < 2:
		return false
	for p in route.platforms:
		var keys: Array = p.foot_slot_keys
		if keys.has(attached_keys[PoseSolver.LF]) and keys.has(attached_keys[PoseSolver.RF]):
			var lo := minf(attached[PoseSolver.LF].x, attached[PoseSolver.RF].x) - 0.10
			var hi := maxf(attached[PoseSolver.LF].x, attached[PoseSolver.RF].x) + 0.10
			return body.pos.x >= lo and body.pos.x <= hi
	return false


func _tick() -> bool:
	ticks += 1
	var platform := _on_platform()
	if _hands_attached() == 0 and not platform:
		failure = "지지 상실: 손 0개, 플랫폼 지지 없음"
		log.append(failure)
		return false
	PoseSolver.step_body(body, attached, feet)
	feet = PoseSolver.supporting_feet(body.pos, body.angle, attached, feet)
	var speed := body.vel.length()
	for hand in [PoseSolver.LH, PoseSolver.RH]:
		var rate := Fatigue.FREE_HAND_RATE
		if attached.has(hand):
			rate = Fatigue.attached_hand_rate(platform and speed <= Fatigue.STABLE_SPEED, feet.size(), _hands_attached(), speed)
		stamina[hand] = Fatigue.apply(stamina[hand], rate, Tuning.DT)
		if attached.has(hand):
			min_stamina = minf(min_stamina, stamina[hand])
			if stamina[hand] <= 0.0:
				failure = "%s 피로 소진" % hand
				log.append(failure)
				return false
	return true


func _check_goal() -> void:
	for key in route.goal_slots:
		if not attached_keys.values().has(key):
			failure = "정상 슬롯 %s를 잡지 않은 채 경로 종료" % key
			log.append(failure)
			return
	for i in Tuning.GOAL_DWELL_TICKS:
		if not _tick():
			return
	log.append("완등: %d틱(%.2f초), 최저 손 피로 %.0f" % [ticks, ticks / float(Tuning.TICK_HZ), min_stamina])
