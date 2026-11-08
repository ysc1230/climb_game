class_name AnatomySweep
extends RefCounted
## 해부학 점검 스윕(docs/04 §8.4): 루트 하나에서 실제 세션(ClimbSession)에 무작위 패드 입력(손발 끌기·놓기,
## 가운데 영역 몸통 끌기)을 넣어 여러 각도의 팔다리 움직임을 만들고, 매 틱 표현 관절(ClimberPose)을
## Anatomy.check로 점검한다. 도구(tools/anatomy_sweep.gd)와 테스트(test_anatomy.gd)가 같이 쓴다.

const DRAG_SPEED := 1.6     # m/s
const EPISODE_MAX := 75     # 끌기 한 번의 최대 틱

var ticks := 0
var poses := 0
var counts := {}            # "kind/limb" → 횟수
var examples := {}          # "kind/limb" → 첫 예시
var twists := {&"arm": [], &"leg": []}
var forced := {}            # "kind/limb" → 그중 어떤 굽힘도 가능하지 않았던(말단 위치가 강제한) 횟수


var session: ClimbSession   # 마지막 세션(재현·디버그용)
var flips := {}             # limb → 굽힘 방향이 한 틱에 FLIP_DEG 넘게 바뀐 횟수(관절이 갑자기 뒤집힘)
var flip_examples := {}
var _prev_bend := {}
const FLIP_DEG := 25.0      # 한 틱(1/60초) 굽힘 방향 변화 한도. 180°/s 회전 한도의 8배 남짓
const FLIP_MIN_BEND := 0.08 # 굽힘 반지름(중간 관절이 축에서 떨어진 거리)이 이보다 작으면(거의 펴짐) 보지 않음
## 떨림: 관절 위치의 한 틱 이동이 바로 전 틱과 반대 방향(내적 < 0)이고 둘 다 JITTER_MIN보다 크면 1번.
## 표현 관절(t)과 판정 상태(세션의 골반·말단)를 따로 세어 원인이 표현인지 판정인지 가른다.
const JITTER_MIN := 0.003    # m/틱(0.18 m/s)
const JITTER_KEYS := ["elbow_L", "elbow_R", "wrist_L", "wrist_R", "knee_L", "knee_R", "ankle_L", "ankle_R", "pelvis", "shoulder_L", "shoulder_R"]
var jitter := {}             # 키 → 횟수(표현)
var jitter_big := {}         # 키 → 그중 큰 떨림(두 이동 모두 JITTER_BIG 넘음) 횟수
const JITTER_BIG := 0.01     # m/틱(0.6 m/s): 눈에 띄는 떨림
var jitter_sim := {}         # 키 → 횟수(판정: body, LH/RH/LF/RF 2D 위치)
var _jp := {}                # 키 → [직전 위치, 직전 이동]
var _jp_sim := {}
var compute_us_total := 0   # ClimberPose.compute 시간 합·최대(µs)
var compute_us_max := 0
var pose_state: ClimberPose


static func run(route: RouteDef, n_ticks: int, seed: int) -> AnatomySweep:
	var sw := AnatomySweep.new()
	sw._run(route, n_ticks, seed)
	return sw


func _run(route: RouteDef, n_ticks: int, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var s := ClimbSession.new(route)
	var pose := ClimberPose.new()
	var holds: Array = route.slots.values().map(func(sl): return sl.pos)
	var limb := &""
	var target := Vector2.ZERO
	var left := 0
	var body_drag := false
	for i in n_ticks:
		ticks += 1
		if left <= 0 and not s.falling:
			if limb != &"":
				s.apply_input([{"type": "release", "limb": limb, "speed": 0.0}])
				limb = &""
			if body_drag:
				s.apply_input([{"type": "body_end"}])
				body_drag = false
			if rng.randf() < 0.2:
				body_drag = true
				s.apply_input([{"type": "body_start"}])
				target = Vector2(rng.randf_range(-0.45, 0.45), rng.randf_range(-0.45, 0.45))
			else:
				limb = PoseSolver.LIMBS[rng.randi() % 4]
				var from: Vector2 = s.limbs[limb].pos
				if rng.randf() < 0.65:
					target = holds[rng.randi() % holds.size()]
					if target.distance_to(from) > 1.2:
						target = from + (target - from).limit_length(1.2)
				else:
					target = from + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.2, 1.1)
				s.apply_input([{"type": "detach", "limb": limb}])
			left = EPISODE_MAX
		if body_drag:
			s.apply_input([{"type": "body_move", "delta": target.limit_length(DRAG_SPEED * Tuning.DT)}])
			target -= target.limit_length(DRAG_SPEED * Tuning.DT)
		elif limb != &"" and s.limbs[limb].state == "Dragging":
			var req: Vector2 = s.limbs[limb].req
			s.apply_input([{"type": "move", "limb": limb, "delta": (target - req).limit_length(DRAG_SPEED * Tuning.DT)}])
			if req.distance_to(target) < 0.01:
				left = mini(left, 5)
		left -= 1
		var r := s.step()
		if r == "respawn" or r == "clear":
			_prev_bend.clear()
			_jp.clear()
			_jp_sim.clear()
			limb = &""
			body_drag = false
			left = 0
			pose = ClimberPose.new()
		if s.falling:
			continue
		var t0 := Time.get_ticks_usec()
		var t := pose.compute(s, Tuning.DT)
		var us := Time.get_ticks_usec() - t0
		compute_us_total += us
		compute_us_max = maxi(compute_us_max, us)
		session = s
		pose_state = pose
		poses += 1
		_record_twists(t, s.body)
		_record_flips(t, s, i)
		_record_jitter(t, s)
		for v in Anatomy.check(t, s.body.angle, s.body.yaw, _free_map(s)):
			var key := "%s/%s" % [v.kind, v.limb]
			counts[key] = counts.get(key, 0) + 1
			if v.kind != "ankle" and _forced(t, s.body, v.limb):
				forced[key] = forced.get(key, 0) + 1
			if not examples.has(key):
				examples[key] = {"tick": i, "value": v.value, "pelvis": s.body.pos, "angle": s.body.angle, "yaw": s.body.yaw,
					"limbs": PoseSolver.LIMBS.map(func(l): return [l, s.limbs[l].state, s.limbs[l].pos])}


static func _free_map(s) -> Dictionary:
	var m := {}
	for l in PoseSolver.LIMBS:
		m[l] = ClimberPose._free(s, l)
	return m


func _forced(t: Dictionary, body, limb: StringName) -> bool:
	var hand := PoseSolver.is_hand(limb)
	var sd := "L" if PoseSolver.side_sign(limb) < 0 else "R"
	var frame := Anatomy.body_basis(body.angle, body.yaw)
	return LimbIK.min_violation(limb, t[("shoulder_" if hand else "hip_") + sd], t[("wrist_" if hand else "ankle_") + sd], frame, t.pelvis, t.up, ClimberPose._free(session, limb)) > 0.0


## 중간 관절(팔꿈치·무릎)이 팔다리 축에서 떨어진 방향(굽힘 방향)이 한 틱에 크게 바뀌면 "뒤집힘"으로 센다.
func _record_flips(t: Dictionary, s, tick: int) -> void:
	for limb in PoseSolver.LIMBS:
		var hand := PoseSolver.is_hand(limb)
		var sd := "L" if PoseSolver.side_sign(limb) < 0 else "R"
		var root: Vector3 = t[("shoulder_" if hand else "hip_") + sd]
		var mid: Vector3 = t[("elbow_" if hand else "knee_") + sd]
		var end: Vector3 = t[("wrist_" if hand else "ankle_") + sd]
		var axis := (end - root).normalized()
		var off := (mid - root) - axis * (mid - root).dot(axis)
		if off.length() < FLIP_MIN_BEND:
			_prev_bend.erase(limb)
			continue
		var b := off.normalized()
		if _prev_bend.has(limb):
			var pb: Vector3 = _prev_bend[limb]
			pb = (pb - axis * pb.dot(axis))
			if pb.length() > 0.3:
				var a := rad_to_deg(pb.normalized().angle_to(b))
				if a > FLIP_DEG:
					flips[limb] = flips.get(limb, 0) + 1
					if not flip_examples.has(limb):
						flip_examples[limb] = {"tick": tick, "deg": a, "pelvis": s.body.pos, "limbs": PoseSolver.LIMBS.map(func(l): return [l, s.limbs[l].state, s.limbs[l].pos])}
		_prev_bend[limb] = b


func _record_jitter(t: Dictionary, s) -> void:
	for k in JITTER_KEYS:
		var before: int = jitter.get(k, 0)
		var prev_v: Vector3 = _jp[k][1] if _jp.has(k) else Vector3.ZERO
		var prev_p: Vector3 = _jp[k][0] if _jp.has(k) else t[k]
		_jit(jitter, _jp, k, t[k])
		if jitter.get(k, 0) > before and prev_v.length() > JITTER_BIG and ((t[k] as Vector3) - prev_p).length() > JITTER_BIG:
			jitter_big[k] = jitter_big.get(k, 0) + 1
	_jit(jitter_sim, _jp_sim, "body", Vector3(s.body.pos.x, s.body.pos.y, 0))
	for l in PoseSolver.LIMBS:
		var p: Vector2 = s.limbs[l].pos
		_jit(jitter_sim, _jp_sim, String(l), Vector3(p.x, p.y, 0))


static func _jit(out: Dictionary, mem: Dictionary, key: String, p: Vector3) -> void:
	if mem.has(key):
		var v: Vector3 = p - mem[key][0]
		var pv: Vector3 = mem[key][1]
		if v.length() > JITTER_MIN and pv.length() > JITTER_MIN and v.dot(pv) < 0.0:
			out[key] = out.get(key, 0) + 1
		mem[key] = [p, v]
	else:
		mem[key] = [p, Vector3.ZERO]


func jitter_total() -> int:
	var n := 0
	for k in jitter:
		n += jitter[k]
	return n


func _record_twists(t: Dictionary, body) -> void:
	var frame := Anatomy.body_basis(body.angle, body.yaw)
	for limb in PoseSolver.LIMBS:
		var hand := PoseSolver.is_hand(limb)
		var sd := "L" if PoseSolver.side_sign(limb) < 0 else "R"
		var tw := Anatomy.limb_twist(limb, t[("shoulder_" if hand else "hip_") + sd], t[("elbow_" if hand else "knee_") + sd], t[("wrist_" if hand else "ankle_") + sd], frame)
		if not is_nan(tw):
			twists[&"arm" if hand else &"leg"].append(tw)


func total() -> int:
	var n := 0
	for k in counts:
		n += counts[k]
	return n


## 다리 올리기 시나리오(2026-11-08 사용자: "다리를 낮은 곳에서 높은 곳으로 올릴 때 관절이 갑자기 반대로 꺾인다"):
## 시작 자세에서 한 발을 떼어 엉덩이 기준 가로 offset, 엉덩이 높이 + rise까지 speed로 끌어 올리고 잠시 둔다.
static func run_lift(route: RouteDef, foot: StringName, offset_x: float, rise: float, speed: float) -> AnatomySweep:
	var sw := AnatomySweep.new()
	var s := ClimbSession.new(route)
	sw.session = s
	var pose := ClimberPose.new()
	for i in 30:
		s.step()
		pose.compute(s, Tuning.DT)
	var hip := PoseSolver.joint_position(s.body.pos, s.body.angle, foot, s.body.yaw)
	var target := Vector2(hip.x + offset_x * PoseSolver.side_sign(foot), hip.y + rise)
	s.apply_input([{"type": "detach", "limb": foot}])
	for i in 150:
		var req: Vector2 = s.limbs[foot].req
		s.apply_input([{"type": "move", "limb": foot, "delta": (target - req).limit_length(speed * Tuning.DT)}])
		s.step()
		if s.falling:
			break
		var t := pose.compute(s, Tuning.DT)
		sw.poses += 1
		sw._record_flips(t, s, i)
		sw._record_jitter(t, s)
		for v in Anatomy.check(t, s.body.angle, s.body.yaw, _free_map(s)):
			var key := "%s/%s" % [v.kind, v.limb]
			sw.counts[key] = sw.counts.get(key, 0) + 1
			if v.kind != "ankle" and sw._forced(t, s.body, v.limb):
				sw.forced[key] = sw.forced.get(key, 0) + 1
	return sw


## 손 뻗기 시나리오(2026-11-08 사용자: "팔 움직임이 부자연스럽고 기괴한 각도로 꺾인다, 움직일 때 팔이 심각하게 떨린다"):
## 시작 자세에서 한 손을 떼어 어깨 기준 (dx, dy)까지 speed로 끈 뒤 hold틱 동안 그대로 둔다. dx는 바깥(+)·안쪽(−).
static func run_reach(route: RouteDef, hand: StringName, dx: float, dy: float, speed: float, hold := 40) -> AnatomySweep:
	var sw := AnatomySweep.new()
	var s := ClimbSession.new(route)
	sw.session = s
	var pose := ClimberPose.new()
	for i in 30:
		s.step()
		pose.compute(s, Tuning.DT)
	var sh := PoseSolver.joint_position(s.body.pos, s.body.angle, hand, s.body.yaw)
	var target := Vector2(sh.x + dx * PoseSolver.side_sign(hand), sh.y + dy)
	s.apply_input([{"type": "detach", "limb": hand}])
	for i in 200:
		var req: Vector2 = s.limbs[hand].req
		if req.distance_to(target) > 0.005:
			s.apply_input([{"type": "move", "limb": hand, "delta": (target - req).limit_length(speed * Tuning.DT)}])
		elif hold <= 0:
			break
		else:
			hold -= 1
		s.step()
		if s.falling:
			break
		var t := pose.compute(s, Tuning.DT)
		sw.poses += 1
		sw._record_flips(t, s, i)
		sw._record_jitter(t, s)
		for v in Anatomy.check(t, s.body.angle, s.body.yaw, _free_map(s)):
			var key := "%s/%s" % [v.kind, v.limb]
			sw.counts[key] = sw.counts.get(key, 0) + 1
			if v.kind != "ankle" and sw._forced(t, s.body, v.limb):
				sw.forced[key] = sw.forced.get(key, 0) + 1
	return sw


## 몸 밀기 시나리오(2026-11-08 사용자: "무릎이 굽은 상태에서 몸을 옆으로 옮기면 무릎이 뒤로 꺾인다"):
## 시작 자세에서 손발을 붙인 채 가운데 영역 끌기로 몸을 (dx, dy)만큼 민다.
static func run_body_shift(route: RouteDef, dx: float, dy: float) -> AnatomySweep:
	var sw := AnatomySweep.new()
	var s := ClimbSession.new(route)
	sw.session = s
	var pose := ClimberPose.new()
	for i in 30:
		s.step()
		pose.compute(s, Tuning.DT)
	s.apply_input([{"type": "body_start"}])
	var left := Vector2(dx, dy)
	for i in 150:
		if left.length() > 0.001:
			var d := left.limit_length(0.8 * Tuning.DT)
			s.apply_input([{"type": "body_move", "delta": d}])
			left -= d
		s.step()
		if s.falling:
			break
		var t := pose.compute(s, Tuning.DT)
		sw.poses += 1
		sw._record_flips(t, s, i)
		sw._record_jitter(t, s)
		for v in Anatomy.check(t, s.body.angle, s.body.yaw, _free_map(s)):
			var key := "%s/%s" % [v.kind, v.limb]
			sw.counts[key] = sw.counts.get(key, 0) + 1
			if v.kind != "ankle" and sw._forced(t, s.body, v.limb):
				sw.forced[key] = sw.forced.get(key, 0) + 1
	return sw
