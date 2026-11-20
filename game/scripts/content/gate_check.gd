class_name GateCheck
extends RefCounted
## R7 관문 검사 도구(작업 5 §5.1, docs/48 §4 R7·§5). 노드 없음.
## 관문 = score_gates의 {slot, technique}. 정답 순서에서 그 슬롯으로 가는 단계가 관문 단계다.
## 관문 단계 앞까지 검사 봇으로 재생한 접점에서, 골반을 격자(0.05m)·몸 기울기 몇 가지로 옮겨 가며
## ① 옮기는 손발을 뗀 세 접점으로 버티고(PathExplorer와 같은 힘 계산) ② 그 자세에서 관문 슬롯에 닿고
## ③ 그 기술 없이도 그 슬롯을 쓸 수 있고(금지 규칙 = ClimbSession._forbidden_target과 같음) ④ 네 접점으로 버티는 자세 수를 센다.
## 진짜 관문이면 금지한 결과 feasible이 0이다. free는 금지 없이 센 같은 값(도구가 자세를 제대로 찾는지 비교용).
## 방향 기술(사이드풀·개스턴·언더클링) "없이"는 그 홀드를 위로 당기기(축 위)로만 잡는 것으로 본다.
## 버튼 기술·다이노는 금지 플래그가 없어 "패드로 그냥 닿고 버티는가"만 본다.

const GRID := 0.05
const HALF := 0.6                       # 골반을 관문 앞 자세에서 좌우·위아래로 이만큼까지 옮겨 본다
const ANGLES := [-20.0, -10.0, 0.0, 10.0, 20.0]
const DIRECTION := [&"T_SIDEPULL", &"T_GASTON", &"T_UNDERCLING"]
## 기술 → 금지 플래그. 패드 기술(ContentCheck.PAD_FORBID) + 합발(다른 발 자리를 쓰지 못함 = 풋스왑 금지와 같은 규칙).
const FORBID := {&"T_HIGH_STEP": &"high_step", &"T_CROSS": &"cross", &"T_MATCH": &"match", &"T_FOOT_SWAP": &"foot_swap", &"T_FOOT_MATCH": &"foot_swap"}


## 관문 단계 [{index, limb, key, technique}].
static func gate_steps(route: RouteDef) -> Array:
	var out: Array = []
	for g in route.score_gates:
		var slot := str(g.get("slot", ""))
		var tech := StringName(str(g.get("technique", "")))
		var ci := int(route.crux_steps.get(tech, -1))  # crux_steps가 있으면 그 단계(매치는 두 번째 손이 오는 단계)
		if ci >= 0 and ci < route.intended_moves.size():
			var cm: Array = route.intended_moves[ci]
			out.append({"index": ci, "limb": StringName(str(cm[0])), "key": str(cm[cm.size() - 1]), "technique": tech})
			continue
		for i in route.intended_moves.size():
			var m: Array = route.intended_moves[i]
			if m.size() >= 2 and str(m[m.size() - 1]) == slot:
				out.append({"index": i, "limb": StringName(str(m[0])), "key": slot, "technique": StringName(str(g.get("technique", "")))})
				break
	return out


## 관문마다 {technique, index, limb, key, feasible(기술 없이 성립 자세 수), free(금지 없이), tried, pelvis(관문 앞 골반),
## breach(기술 없이 성립하는 자세가 있을 때: 몸통을 그 골반으로 끈 뒤 기술을 금지하고 관문 단계를 실제 세션으로 재생해 붙었는가)}.
static func check(route: RouteDef) -> Array:
	var out: Array = []
	for g in gate_steps(route):
		var before := state_before(route, g.index)
		var res := {"technique": g.technique, "index": g.index, "limb": g.limb, "key": g.key, "feasible": -1, "free": -1, "tried": 0, "pelvis": Vector2.INF, "error": "", "breach": false, "breach_log": ""}
		if before.has("error"):
			res.error = before.error
			out.append(res)
			continue
		res.pelvis = before.pelvis
		var forbid := {}
		if FORBID.has(g.technique):
			forbid[FORBID[g.technique]] = true
		var a := count_poses(route, before.keys, g.limb, g.key, forbid, DIRECTION.has(g.technique), before.pelvis)
		var b := count_poses(route, before.keys, g.limb, g.key, {}, false, before.pelvis)
		res.feasible = a.feasible
		res.free = b.feasible
		res.tried = a.tried
		if a.feasible > 0 and not DIRECTION.has(g.technique):
			var steps: Array = route.intended_moves.slice(0, g.index)
			steps.append(["BODY", "body", [a.example.x - before.pelvis.x, a.example.y - before.pelvis.y]])
			steps.append([String(g.limb), g.key])
			var bot := SessionBot.run(route, steps, forbid)
			res.breach = bot.failed_step == -1  # 모든 단계를 마침(정상 미도달은 상관없음)
			res.breach_log = "몸통을 (%.2f, %.2f)로 끌고 %s" % [a.example.x, a.example.y, "붙음" if res.breach else bot.failure]
		out.append(res)
	return out


## 정답 순서를 index 앞까지 재생한 뒤의 {keys: limb → 슬롯, pelvis} 또는 {error}.
static func state_before(route: RouteDef, index: int) -> Dictionary:
	var bot := SessionBot.run(route, route.intended_moves.slice(0, index))
	if bot.failed_step != -1:
		return {"error": bot.failure}
	var keys := {}
	for limb in PoseSolver.LIMBS:
		var l: Dictionary = bot.session.limbs[limb]
		if l.state in ["Attached", "Armed"]:
			keys[limb] = String(l.key)
	return {"keys": keys, "pelvis": bot.session.body.pos}


## 격자 탐색. keys: 관문 앞 접점(limb 포함 가능), forbid: 세션 금지 플래그, pull_only: 관문 손을 위로 당기기로만.
static func count_poses(route: RouteDef, keys: Dictionary, limb: StringName, key: String, forbid: Dictionary, pull_only: bool, center: Vector2) -> Dictionary:
	var ex := PathExplorer.new()
	ex.route = route
	var rest := keys.duplicate()
	rest.erase(limb)
	var att3 := ex._att(rest)
	var meta3 := {}
	for l in rest:
		meta3[l] = GripCheck.contact_for(rest[l], route.slots, l, att3[l])
	var keys4 := rest.duplicate()
	keys4[limb] = key
	var target: Vector2 = route.slots[key].pos
	var att4 := att3.duplicate()
	att4[limb] = target
	var meta4 := meta3.duplicate()
	var gc := GripCheck.contact_for(key, route.slots, limb, target)
	meta4[limb] = as_pull(gc) if pull_only and PoseSolver.is_hand(limb) else gc
	var n := int(round(HALF / GRID))
	var tried := 0
	var feasible := 0
	var example := Vector2.INF  # 성립 자세 중 관문 앞 골반에 가장 가까운 것
	if not ex._slot_free(key, limb, rest):
		return {"feasible": 0, "tried": 0, "example": example}
	for ix in range(-n, n + 1):
		for iy in range(-n, n + 1):
			var p := center + Vector2(ix, iy) * GRID
			for a in ANGLES:
				if not PoseSolver.is_valid(p, a, att3, 0.0) or ex._hold_cost(rest, att3, meta3, p, a).is_empty():
					continue
				if not PoseSolver.can_reach(p, a, limb, target, 0.0):
					continue
				tried += 1
				if forbidden(forbid, limb, key, target, p, a, rest, att3):
					continue
				if PoseSolver.is_valid(p, a, att4, 0.0) and not ex._hold_cost(keys4, att4, meta4, p, a).is_empty():
					feasible += 1
					if example == Vector2.INF or p.distance_to(center) < example.distance_to(center):
						example = p
	return {"feasible": feasible, "tried": tried, "example": example}


## 그 기술을 금지하면 이 잡기를 거부하는가(ClimbSession._forbidden_target과 같은 규칙 + 풋스왑: 다른 발이 딛은 자리).
## others: 다른 접점 limb → 슬롯 키, others_att: limb → 위치(손 규칙에 씀).
static func forbidden(forbid: Dictionary, limb: StringName, key: String, point: Vector2, pelvis: Vector2, angle: float, others: Dictionary, others_att := {}) -> bool:
	if forbid.is_empty():
		return false
	if PoseSolver.is_hand(limb):
		var o := TechniqueJudge.other_of(limb)
		if not others.has(o):
			return false
		var ox: float = (others_att.get(o, Vector2.ZERO) as Vector2).x
		if forbid.has(&"cross") and ((limb == PoseSolver.LH and point.x > ox) or (limb == PoseSolver.RH and point.x < ox)):
			return true
		return forbid.has(&"match") and key.get_base_dir() == String(others[o]).get_base_dir()
	if forbid.has(&"foot_swap"):
		var of := TechniqueJudge.other_of(limb)
		if others.has(of) and String(others[of]) == key:
			return true
	if forbid.has(&"high_step"):
		var hip := PoseSolver.joint_position(pelvis, angle, limb, 0.0)
		return point.y >= hip.y - Tuning.HIGH_STEP_BELOW_HIP
	return false


## 위로 당기기(축 위)로 바꾼 접점 복사본(방향 기술 없이 잡기).
static func as_pull(c: ContactInfo) -> ContactInfo:
	var o := ClimbSnapshot.copy_contact(c)
	o.mode = &"pull"
	o.axis = Vector2(0, 1)
	return o
