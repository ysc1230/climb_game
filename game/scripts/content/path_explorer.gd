class_name PathExplorer
extends RefCounted
## 쉬운 길 탐색기(docs/41 §5 도구 B). 문제의 홀드로 갈 수 있는 길 가운데 부담이 가장 작은 길을 찾는다.
## 상태 = 네 손발이 붙은 슬롯. 이동 = 손발 하나를 다른 슬롯으로. 이동이 되려면 그 손발을 뗀 세 접점으로 몸이 스스로
## 자리 잡은 자세(PoseSolver.find_target)에서 버틸 수 있고(판정과 같은 힘 계산) 그 자세에서 새 슬롯에 닿아야 한다(정적 검사).
## 비용이 작은 순서(다익스트라)로 찾은 길을 SessionBot으로 재생해 확인하고, 재생이 막힌 이동은 금지하고 다시 찾는다.
## 한계: 정적 검사는 움직이는 도중을 보지 않는다. 봇은 몸 끌기를 못 쓴다. "못 찾음"은 이 탐색 범위에서의 결과다.

const W_MOVE := 1.0
const W_LOAD := 3.0                   # 세 접점으로 버틸 때 손 사용률 최대값 가중
const W_LOW_FEET := 1.5               # 버티는 동안 하중 받는 발이 2개 미만
const MAX_STATES := 60000
const MAX_RETRY := 30

var route: RouteDef
var banned := {}       # 금지한 이동 서명 → true
var expanded := 0


## 반환 {ok, steps: [[limb, key], ...], bot: SessionBot(재생 성공한 것), tries, expanded, log: PackedStringArray}.
## forbid: 세션 금지 플래그(예: {&"cross": true}). 그 기술 없이 가는 길을 찾을 때 쓴다.
static func explore(p_route: RouteDef, forbid := {}) -> Dictionary:
	var ex := PathExplorer.new()
	ex.route = p_route
	var log: PackedStringArray = []
	for attempt in MAX_RETRY:
		var path := ex._search()
		if path.is_empty():
			log.append("탐색 %d: 길을 찾지 못함(펼친 상태 %d)" % [attempt + 1, ex.expanded])
			return {"ok": false, "steps": [], "bot": null, "tries": attempt + 1, "expanded": ex.expanded, "log": log}
		var steps: Array = path.map(func(e): return [e.limb, e.key])
		var bot := SessionBot.run(p_route, steps, forbid)
		if bot.ok():
			log.append("탐색 %d: 이동 %d개 길을 재생으로 확인(펼친 상태 %d)" % [attempt + 1, steps.size(), ex.expanded])
			return {"ok": true, "steps": steps, "bot": bot, "tries": attempt + 1, "expanded": ex.expanded, "log": log}
		var i: int = clampi(bot.failed_step, 0, path.size() - 1)
		ex.banned[path[i].sig] = true
		log.append("탐색 %d: 재생이 #%d %s %s에서 막힘(%s) → 이 이동을 금지하고 다시 찾음" % [attempt + 1, i + 1, path[i].limb, path[i].key, bot.failure])
	return {"ok": false, "steps": [], "bot": null, "tries": MAX_RETRY, "expanded": ex.expanded, "log": log}


func _search() -> Array:
	var start := {}
	for limb in route.start_slots:
		start[StringName(limb)] = String(route.start_slots[limb])
	var start_sig := _sig(start)
	var dist := {start_sig: 0.0}
	var prev := {}
	var states := {start_sig: start}
	var seeds := {start_sig: Vector3(route.start_pelvis.x, route.start_pelvis.y, route.start_angle)}
	var heap: Array = [[0.0, start_sig]]
	var done := {}
	while not heap.is_empty():
		var top: Array = _pop(heap)
		var sig: String = top[1]
		if done.has(sig):
			continue
		done[sig] = true
		expanded += 1
		var keys: Dictionary = states[sig]
		if _is_goal(keys):
			var path: Array = []
			var cur := sig
			while prev.has(cur):
				path.push_front(prev[cur][1])
				cur = prev[cur][0]
			return path
		if done.size() > MAX_STATES:
			break
		var pose := _settle(keys, seeds[sig])
		if not is_finite(pose.x):
			continue
		for mv in _moves(keys, pose):
			var nk := keys.duplicate()
			nk[mv.limb] = mv.key
			var ns := _sig(nk)
			var nd: float = top[0] + mv.cost
			if nd < dist.get(ns, INF):
				dist[ns] = nd
				states[ns] = nk
				seeds[ns] = mv.pose
				prev[ns] = [sig, mv]
				_push(heap, [nd, ns])
	return []


func _is_goal(keys: Dictionary) -> bool:
	return route.goal_slots.has(keys.get(PoseSolver.LH, "")) and route.goal_slots.has(keys.get(PoseSolver.RH, "")) and keys[PoseSolver.LH] != keys[PoseSolver.RH]


## 이 접점들로 몸이 스스로 자리 잡는 자세(세션의 자동 자세와 같은 PoseSolver.find_target). 안 되면 Vector3(INF).
func _settle(keys: Dictionary, seed: Vector3) -> Vector3:
	var att := _att(keys)
	var p := Vector2(seed.x, seed.y)
	if not PoseSolver.is_valid(p, seed.z, att, 0.0):
		return Vector3(INF, INF, INF)
	var t := PoseSolver.find_target(p, seed.z, att, PoseSolver.supporting_feet(p, seed.z, att, [], 0.0))
	if not PoseSolver.is_valid(Vector2(t.x, t.y), t.z, att, 0.0):
		return Vector3(INF, INF, INF)
	return t


## 이 상태(자리 잡은 자세 pose)에서 할 수 있는 이동 [{limb, key, cost, sig, pose(다음 상태의 시작 자세)}].
## 손발을 떼고 남은 세 접점으로 몸이 자리 잡은 자세에서 버틸 수 있고, 그 자세에서 새 슬롯에 닿아야 한다(봇은 몸을 끌지 않는다).
func _moves(keys: Dictionary, pose: Vector3) -> Array:
	var out: Array = []
	for limb in PoseSolver.LIMBS:
		if not keys.has(limb):
			continue
		var rest := keys.duplicate()
		rest.erase(limb)
		var p3 := _settle(rest, pose)
		if not is_finite(p3.x):
			continue
		var att := _att(rest)
		var meta := {}
		for l in rest:
			meta[l] = GripCheck.contact_for(rest[l], route.slots, l, att[l])
		var pel := Vector2(p3.x, p3.y)
		var c := _hold_cost(rest, att, meta, pel, p3.z)
		if c.is_empty():
			continue
		var rsig := _sig(rest)
		for key in route.slots:
			if key == keys[limb] or not _slot_free(key, limb, rest):
				continue
			var slot: Dictionary = route.slots[key]
			var msig := "%s|%s>%s" % [rsig, limb, key]
			if banned.has(msig) or not PoseSolver.can_reach(pel, p3.z, limb, slot.pos, 0.0):
				continue
			var att4 := att.duplicate()
			att4[limb] = slot.pos
			if PoseSolver.is_valid(pel, p3.z, att4, 0.0):
				out.append({"limb": limb, "key": key, "cost": W_MOVE + c[0], "sig": msig, "pose": p3})
	return out


## 슬롯을 limb이 쓸 수 있는가(허용·점유 규칙: 손이 잡은 홀드는 발이 못 딛고 그 반대도, 합손·합발은 파란 홀드만).
func _slot_free(key: String, limb: StringName, others: Dictionary) -> bool:
	var slot: Dictionary = route.slots[key]
	if not slot.allowed.has(limb):
		return false
	var hand := PoseSolver.is_hand(limb)
	if route.goal_slots.has(key):
		if not hand:
			return false
		for o in others:
			if others[o] == key:
				return false
		return true
	var hold := key.get_base_dir()
	var matchable: bool = slot.get("hand_area", {}).get("matchable", false)
	for o in others:
		if String(others[o]).get_base_dir() != hold:
			continue
		if PoseSolver.is_hand(o) != hand or not matchable:
			return false
	return true


func _att(keys: Dictionary) -> Dictionary:
	var att := {}
	for limb in keys:
		att[limb] = route.slots[keys[limb]].pos
	return att


## 그 자세로 버틸 수 있으면 [비용, 하중 받는 발 수], 아니면 [].
func _hold_cost(keys: Dictionary, att: Dictionary, meta: Dictionary, p: Vector2, a: float) -> Array:
	var feet := PoseSolver.supporting_feet(p, a, att, [], 0.0)
	var rules := ClimbRules.new()
	rules.contact_meta = meta
	rules.feet_eligible = feet
	rules.loaded_feet.assign(feet)
	var platform := _on_platform(keys, att, p)
	if rules._eligible_hand_count(p, a, att, 0.0) == 0 and not ClimbRules.platform_holds(platform, att):
		return []
	var eps := {}
	for limb in PoseSolver.LIMBS:
		if not att.has(limb):
			eps[limb] = p + ClimbSession._rest_offset(limb)
	var r := rules.evaluate(p, a, att, eps, platform, feet, 0.0)
	if r.status != SupportSolver.Status.FEASIBLE or ClimbRules.barn_exceeded(r):
		return []
	var loaded := ClimbRules.loaded_from(r, []).size()
	var u := 0.0
	for limb in r.u:
		if PoseSolver.is_hand(limb):
			u = maxf(u, r.u[limb])
	return [W_LOAD * u + (W_LOW_FEET if loaded < 2 and not platform else 0.0), loaded]


func _on_platform(keys: Dictionary, att: Dictionary, pelvis: Vector2) -> bool:
	if not (keys.has(PoseSolver.LF) and keys.has(PoseSolver.RF)):
		return false
	for pl in route.platforms:
		if pl.foot_slot_keys.has(keys[PoseSolver.LF]) and pl.foot_slot_keys.has(keys[PoseSolver.RF]):
			var a: Vector2 = att[PoseSolver.LF]
			var b: Vector2 = att[PoseSolver.RF]
			return pelvis.x >= minf(a.x, b.x) - 0.10 and pelvis.x <= maxf(a.x, b.x) + 0.10
	return false


static func _sig(keys: Dictionary) -> String:
	var parts: PackedStringArray = []
	for limb in PoseSolver.LIMBS:
		parts.append(String(keys.get(limb, "-")))
	return ",".join(parts)


static func _push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if heap[parent][0] <= heap[i][0]:
			break
		var t = heap[parent]
		heap[parent] = heap[i]
		heap[i] = t
		i = parent


static func _pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var i := 0
		while true:
			var l := 2 * i + 1
			var r := l + 1
			var m := i
			if l < heap.size() and heap[l][0] < heap[m][0]:
				m = l
			if r < heap.size() and heap[r][0] < heap[m][0]:
				m = r
			if m == i:
				break
			var t = heap[m]
			heap[m] = heap[i]
			heap[i] = t
			i = m
	return top
