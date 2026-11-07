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
		for v in Anatomy.check(t, s.body.angle, s.body.yaw):
			var key := "%s/%s" % [v.kind, v.limb]
			counts[key] = counts.get(key, 0) + 1
			if v.kind != "ankle" and _forced(t, s.body, v.limb):
				forced[key] = forced.get(key, 0) + 1
			if not examples.has(key):
				examples[key] = {"tick": i, "value": v.value, "pelvis": s.body.pos, "angle": s.body.angle, "yaw": s.body.yaw,
					"limbs": PoseSolver.LIMBS.map(func(l): return [l, s.limbs[l].state, s.limbs[l].pos])}


func _forced(t: Dictionary, body, limb: StringName) -> bool:
	var hand := PoseSolver.is_hand(limb)
	var sd := "L" if PoseSolver.side_sign(limb) < 0 else "R"
	var frame := Anatomy.body_basis(body.angle, body.yaw)
	return LimbIK.min_violation(limb, t[("shoulder_" if hand else "hip_") + sd], t[("wrist_" if hand else "ankle_") + sd], frame, t.pelvis, t.up) > 0.0


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
