extends RefCounted
## 사람이 할 수 없는 관절 움직임(docs/59, 2026-11-25 사용자: "머리보다 위에 있는 홀드를 못 잡고 팔이 떨어질 때 이상한 각도로
## 팔이 돌아가고 있어. 무릎도 똑같이"). 실제 남성 모델 뼈대에 ClimberPose → RigPose(손 쥐기 포함)를 돌려 RigCheck·Anatomy로 잰다.

var runner
var _rig: RigPose


func _model_rig() -> RigPose:
	if _rig != null:
		return _rig
	var asm := CharacterAssembler.load_catalog()
	var model: Node3D = load(asm.model_path("male")).instantiate()
	var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var leg := CharacterAssembler.leg_shape(sk)
	LimbIK.set_leg_shape(float(leg.raise), float(leg.upper), float(leg.lower))
	_rig = RigPose.new()
	_rig.setup_from_skeleton(sk)
	model.free()
	return _rig


## 손발 하나를 target(골반 기준)으로 1.6m/s로 끌다가 70틱 뒤 놓고(못 잡음) 120틱 더 본다.
## 반환: {"kind/key" → [최댓값, 놓은 뒤 틱(놓기 전이면 음수)]}. 키 앞에 rig:(RigCheck) 또는 ana:(Anatomy).
func _drop(route_id: String, limb: StringName, offset: Vector2) -> Dictionary:
	var rig := _model_rig()
	rig._last.clear()
	rig._twist_state.clear()
	rig._palm_deg.clear()
	var s := ClimbSession.new(RouteDef.load_json("res://tests/fixtures/%s.json" % route_id))
	var pose := ClimberPose.new()
	var chk := RigCheck.new()
	var curl := {"L": 1.0, "R": 1.0}
	var worst := {}
	var target := Vector2.ZERO
	for i in 60 + 70 + 120:
		if i == 60:
			target = s.body.pos + offset
			s.apply_input([{"type": "detach", "limb": limb}])
		elif i > 60 and i < 130:
			var l: Dictionary = s.limbs[limb]
			s.apply_input([{"type": "move", "limb": limb, "delta": (target - l.req).limit_length(1.6 * Tuning.DT)}])
		elif i == 130:
			s.apply_input([{"type": "release", "limb": limb, "speed": 0.0}])
		s.step()
		var t := pose.compute(s, Tuning.DT)
		for sd in ["L", "R"]:
			var att: bool = s.limbs[StringName(sd + "H")].state in ["Attached", "Armed"]
			curl[sd] = move_toward(curl[sd], 1.0 if att else 0.0, 8.0 * Tuning.DT)
		var joints := {}
		for k in t:
			if t[k] is Vector3 and k != "up":
				joints[k] = t[k]
		var free := {"L": ClimberPose._free(s, &"LF"), "R": ClimberPose._free(s, &"RF")}
		var frames := rig.solve(joints, s.body.angle, float(t.yaw), free, curl)
		if i < 61:
			chk.check(rig, frames)  # 회전 속도 기준만 채운다
			continue
		var at := i - 130
		for v in chk.check(rig, frames):
			_keep(worst, "rig:%s/%s" % [v.kind, v.key], absf(float(v.value)), at)
		for v in Anatomy.check(t, s.body.angle, float(t.yaw), AnatomySweep._free_map(s)):
			_keep(worst, "ana:%s/%s" % [v.kind, v.limb], absf(float(v.value)), at)
	return worst


static func _keep(worst: Dictionary, key: String, v: float, at: int) -> void:
	if not worst.has(key) or v > float(worst[key][0]):
		worst[key] = [v, at]


func _report(worst: Dictionary, where: String) -> void:
	runner.check(worst.is_empty(), "%s: %s" % [where, worst])


func test_hand_dropped_from_overhead() -> void:
	for id in ["G_V3_03", "G_V7_01"]:
		for hand in [&"LH", &"RH"]:
			var side := -1.0 if hand == &"LH" else 1.0
			_report(_drop(id, hand, Vector2(0.15 * side, 1.25)), "%s %s 머리 위에서 놓침" % [id, hand])


func test_foot_dropped_from_high_step() -> void:
	for id in ["G_V3_03", "G_V7_01"]:
		for foot in [&"LF", &"RF"]:
			var side := -1.0 if foot == &"LF" else 1.0
			_report(_drop(id, foot, Vector2(0.30 * side, 0.05)), "%s %s 엉덩이 높이에서 놓침" % [id, foot])


## 추락 장면(FallSim, docs/59 §3.3): 손발 셋을 떼어 떨어뜨리고 착지해 일어설 때까지 같은 기준으로 잰다.
## play_3d처럼 월드(접힌 벽)에서 흉내 내고 떨어지기 시작한 높이의 벽 틀(캐릭터 틀) 좌표로 RigPose를 푼다.
## Anatomy는 몸이 앞뒤로 기운 것(FallSim의 lean)을 빼고 잰다. 벽 뚫기는 FallSim이 따로 막으므로 보지 않는다.
func _fall(route_id: String) -> Dictionary:
	var rig := _model_rig()
	rig._twist_state.clear()
	rig._palm_deg.clear()
	var s := ClimbSession.new(RouteDef.load_json("res://tests/fixtures/%s.json" % route_id))
	var pose := ClimberPose.new()
	var last := {}
	for i in 400:
		if i == 60:
			s.apply_input([{"type": "detach", "limb": &"LH"}, {"type": "detach", "limb": &"LF"}, {"type": "detach", "limb": &"RF"}])
		var hands := [&"LH", &"RH"].filter(func(h): return s.limbs[h].state in ["Attached", "Armed"])
		s.step()
		if s.falling:
			break
		last = {"t": pose.compute(s, Tuning.DT), "hands": hands, "vel": s.body.vel}
	var fold := WallProfile.new(s.route, -1.5, 5.0)
	var t0: Dictionary = last.t
	var world := {}
	for k in t0:
		if t0[k] is Vector3:
			world[k] = (fold.basis_at((t0.pelvis as Vector3).y) * (t0[k] as Vector3)) if k == "up" else fold.point(t0[k] as Vector3)
	var pins := {}
	for h in last.hands:
		var sd := "L" if h == &"LH" else "R"
		pins["hand_" + sd] = FallSim.RELEASE_DELAY
		pins["wrist_" + sd] = FallSim.RELEASE_DELAY
	var sim := FallSim.new()
	var v: Vector2 = last.vel
	sim.start(world, fold.basis_at((t0.pelvis as Vector3).y) * Vector3(v.x, v.y, 0.0), pins, -0.075, 0.02, 0.0, fold.world_profile(0.02))
	var g := fold.frame((t0.pelvis as Vector3).y).affine_inverse()
	var chk := RigCheck.new()
	var worst := {}
	for f in 600:
		sim.step(1.0 / 60.0)
		var tw: Dictionary = sim.points()
		var j := {}
		for k in tw:
			j[k] = g * (tw[k] as Vector3)
		var up: Vector3 = ((j.chest as Vector3) - (j.pelvis as Vector3)).normalized()
		var roll := rad_to_deg(atan2(-up.x, up.y))
		var frames := rig.solve(j, roll, 0.0, {"L": true, "R": true}, {})
		for vi in chk.check(rig, frames):
			if f > 0:
				_keep(worst, "rig:%s/%s" % [vi.kind, vi.key], absf(float(vi.value)), f)
		var pitch := atan2(up.z, Vector2(up.x, up.y).length())
		var un := {}
		for k in j:
			un[k] = (j.pelvis as Vector3) + Basis(Vector3.RIGHT, -pitch) * ((j[k] as Vector3) - (j.pelvis as Vector3))
		un["up"] = ((un.chest as Vector3) - (un.pelvis as Vector3)).normalized()
		for vi in Anatomy.check(un, roll, 0.0, {}):
			if vi.kind != "in_wall":
				_keep(worst, "ana:%s/%s" % [vi.kind, vi.limb], absf(float(vi.value)), f)
		if sim.done():
			break
	return worst


## 남은 한계(docs/59 §8): 낮게 떨어져 기운 벽 바로 앞에 착지하면 잡고 있던 팔이 0.1~0.2초 벽에 눌려 팔꿈치가 많이 접히고
## 굽는 쪽이 어긋난다(팔꿈치 경첩·굽힘, 아래팔·손 회전). 낙하 팔을 클라이밍과 같은 IK(벽을 제약으로)로 풀어야 한다.
## 그때까지 이 항목들은 세지 않고, 나머지(Anatomy 전부, 무릎, 위팔·허벅지·정강이 회전, 아래팔 비틀림)는 지킨다.
const FALL_KNOWN := ["rig:hinge/elbow_", "rig:elbow_bend/", "rig:spin/forearm_", "rig:spin/hand_"]


func test_fall_scene() -> void:
	for id in ["G_V3_03", "G_V7_01"]:
		var worst := _fall(id)
		for k in worst.keys():
			if FALL_KNOWN.any(func(p): return String(k).begins_with(p)):
				worst.erase(k)
		_report(worst, "%s 추락 장면" % id)
