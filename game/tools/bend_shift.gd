extends SceneTree
## 굽힌 관절 + 반대쪽 무게 이동 점검(2026-11-21 사용자: "무릎이나 팔꿈치가 많이 구부러진 상태에서 반대편으로 무게중심을
## 옮기면 비이상적으로 꺾이거나 돌아간다"). 네 손발을 잡은 채 몸을 한 팔다리 쪽으로 끌어 그 관절을 굽히고, 반대쪽으로
## 천천히 끈다. 매 틱 관절 뒤집힘·해부학 위반과 실제 모델 뼈(RigPose + 손 쥐기 비틀림) 프레임의 한 틱 회전을 잰다.
## 실행: godot --headless --path game --script res://tools/bend_shift.gd -- [body=female] [루트 id…]
## 자세히 보기(환경 변수): TRACE="루트 손발 dy 틱|all" + BONE=뼈(뼈 회전) 또는 LIMB=손발(굽힘 원, PARTS=각°이면 위반 항목), VIOL="루트 손발 dy"(틱별 위반).

const BONE_JUMP_DEG := 12.0   # 한 틱(1/60초)에 뼈 하나가 이보다 많이 돌면 튐(720°/s)
const LIMB_BONES := ["upperarm", "forearm", "hand", "thigh", "shin", "foot"]

var rig := RigPose.new()


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var body := args[0] if args.size() > 0 else "female"
	var ids: Array = args.slice(1) if args.size() > 1 else ["G_V0_02", "G_V2_01", "G_V3_02", "C_BODY_T"]
	_setup_rig(body)
	var idx := ContentIndex.load_all()
	for id in ids:
		var route: RouteDef = idx.route(id)
		if route == null:
			print("루트 없음 ", id)
			continue
		for limb in PoseSolver.LIMBS:
			for dy in [1.0, 0.5]:
				_scenario(route, limb, dy)
	quit()


func _setup_rig(body: String) -> void:
	var asm := CharacterAssembler.load_catalog()
	var model: Node3D = load(asm.model_path(body)).instantiate()
	var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var leg := CharacterAssembler.leg_shape(sk)
	LimbIK.set_leg_shape(float(leg.raise), float(leg.upper), float(leg.lower))
	var rest_poses := {}
	var rest_joints := {}
	for name in RigPose.bone_names():
		var i := sk.find_bone(name)
		if i >= 0:
			rest_poses[name] = sk.get_bone_global_rest(i)
	var jb: Dictionary = load("res://scenes/play_3d.gd").JOINT_BONE
	for key in jb:
		if rest_poses.has(jb[key]):
			rest_joints[key] = (rest_poses[jb[key]] as Transform3D).origin
	rest_joints["head_top"] = rest_joints["head"] + Vector3(0, 0.14, 0)
	for s in ["L", "R"]:
		rest_joints["hand_" + s] = rest_joints["wrist_" + s] + (rest_joints["wrist_" + s] - rest_joints["elbow_" + s]).normalized() * Anatomy.HAND_LENGTH
		rest_joints["toe_" + s] = rest_joints["ankle_" + s] + Vector3(0, -0.05, -0.15)
	rig.setup(rest_poses, rest_joints)
	model.free()


## 손 쥐기 비틀림(play_3d._grip_hands, 붙은 손은 완전히 쥠).
func _grip(frames: Dictionary, s: ClimbSession) -> void:
	for sd in ["L", "R"]:
		if not (s.limbs[StringName(sd + "H")].state in ["Attached", "Armed"]):
			continue
		for name in ["forearm_" + sd, "hand_" + sd]:
			var f: Transform3D = frames[name]
			var dir: Vector3 = (f.basis * rig.rest_basis[name].inverse() * rig.rest_dir[name]).normalized()
			frames[name] = Transform3D(rig._twist(f.basis, name, dir, Vector3.DOWN, Vector3.FORWARD, 1.0), f.origin)


func _trace_limb(pose: ClimberPose, l: StringName, pb: Vector3, i: int) -> void:
	for key in pose._cache:
		if key[0] == l and key[4] == true:
			var c: Dictionary = pose._cache[key]
			var dir: Vector3 = c.dir
			var car := pb - dir * pb.dot(dir)
			var thp := rad_to_deg(atan2(car.dot(c.t), car.dot(c.n)))
			var nb: Vector3 = pose.bends[l]
			var thn := rad_to_deg(atan2(nb.dot(c.t), nb.dot(c.n)))
			var row := ""
			for v in c.bad:
				row += "." if v <= 0.0 else ("o" if v < 0.05 else "X")
			if OS.get_environment("PARTS") != "":
				for thd in [float(OS.get_environment("PARTS")), thp]:
					var th := deg_to_rad(thd)
					var mid: Vector3 = (c.center as Vector3) + ((c.n as Vector3) * cos(th) + (c.t as Vector3) * sin(th)) * float(c.h)
					print("    th%.0f mid(%.2f,%.2f,%.2f) %s" % [thd, mid.x, mid.y, mid.z, _parts(l, pose, mid)])
			print("  c%d %s h%.2f 직전%.0f 새%.0f 목표%.0f 직전위반%.3f 최소%.3f %s" % [i, l, c.h, thp, thn, rad_to_deg(c.target), (c.at as Callable).call(deg_to_rad(thp)), (c.bad as Array).min(), row])


var _last_t := {}
var _last_s: ClimbSession


func _parts(l: StringName, _pose: ClimberPose, mid: Vector3) -> String:
	var t := _last_t
	var hand := PoseSolver.is_hand(l)
	var sd := "L" if PoseSolver.side_sign(l) < 0 else "R"
	var root: Vector3 = t[("shoulder_" if hand else "hip_") + sd]
	var end: Vector3 = t[("wrist_" if hand else "ankle_") + sd]
	var frame := Anatomy.body_basis(_last_s.body.angle, _last_s.body.yaw)
	var up: Vector3 = t.up
	var pelvis: Vector3 = t.pelvis
	var out := {}
	out["kb"] = snappedf(Anatomy.knee_back(root, mid, end, frame), 0.01) if not hand else snappedf(Anatomy.elbow_up(root, mid, end, frame), 0.01)
	out["tw"] = snappedf(Anatomy.limb_twist(l, root, mid, end, frame), 1)
	out["z"] = snappedf(mid.z, 0.01)
	out["torso"] = snappedf(Anatomy._seg_dist(mid, pelvis + up * 0.04, pelvis + up * 0.45), 0.01)
	out["back"] = snappedf((mid - root).normalized().dot(frame * Vector3.BACK), 0.01)
	if not hand:
		out["lift"] = snappedf(Anatomy.hip_lift_excess((mid - root).normalized(), frame, 10.0), 1)
	else:
		out["head"] = snappedf(Anatomy.arm_head_distance(root, mid, end, pelvis + up * Anatomy.HEAD_CENTER_UP), 0.01)
		out["front"] = snappedf(mid.z - (root.z - LimbIK.ELBOW_FRONT_MARGIN), 0.01)
	return str(out)


func _trace(route: RouteDef, limb: StringName, dy: float, i: int) -> bool:
	var tr := OS.get_environment("TRACE").split(" ")
	return tr.size() == 4 and tr[0] == route.route_id and tr[1] == String(limb) and is_equal_approx(float(tr[2]), dy) and (absi(i - int(tr[3])) <= 6 or (tr[3] == "all" and i % 8 == 0))


## limb 쪽(가로 side, 위·아래 dy)으로 몸을 끌어 굽힌 뒤 반대쪽으로 끈다.
func _scenario(route: RouteDef, limb: StringName, dy: float) -> void:
	var s := ClimbSession.new(route)
	var pose := ClimberPose.new()
	var sw := AnatomySweep.new()
	sw.session = s
	rig._last.clear()
	var side := PoseSolver.side_sign(limb)
	var vy := (0.3 if PoseSolver.is_hand(limb) else -0.3) * dy
	var bent := Vector2(side * 0.3, vy)
	var away := Vector2(-side * 0.35, vy)
	var off := Vector2.ZERO
	var prev := {}
	var worst := {}   # 뼈 → [각, 틱]
	var fell := -1
	for i in 30:
		s.step()
		pose.compute(s, Tuning.DT)
	s.apply_input([{"type": "body_start"}])
	for i in 260:
		var goal := bent if i < 90 else away
		var d := (goal - off).limit_length((0.6 if i < 90 else 0.5) * Tuning.DT)
		off += d
		s.apply_input([{"type": "body_move", "delta": d}])
		s.step()
		if s.falling:
			fell = i
			break
		var pb: Vector3 = pose.bends.get(StringName(OS.get_environment("LIMB")), Vector3.ZERO)
		var t := pose.compute(s, Tuning.DT)
		_last_t = t
		_last_s = s
		if _trace(route, limb, dy, i) and OS.get_environment("LIMB") != "":
			_trace_limb(pose, StringName(OS.get_environment("LIMB")), pb, i)
			print("  d%d 깊이%.2f 범위%s 목표%.2f" % [i, pose.depth, PoseSolver.body_depth_range(s.body.pos, s.body.angle, s.attached(), s.body.yaw), float(pose._target.depth)])
		sw.poses += 1
		sw._record_flips(t, s, i)
		for v in Anatomy.check(t, s.body.angle, s.body.yaw, AnatomySweep._free_map(s)):
			var key := "%s/%s" % [v.kind, v.limb]
			sw.counts[key] = sw.counts.get(key, 0) + 1
			if OS.get_environment("VIOL") != "" and route.route_id == OS.get_environment("VIOL").split(" ")[0] and String(limb) == OS.get_environment("VIOL").split(" ")[1] and is_equal_approx(dy, float(OS.get_environment("VIOL").split(" ")[2])):
				print("  v%d %s %.3f 골반(%.2f,%.2f,%.2f) 무릎R(%.2f,%.2f,%.2f) 팔꿈치R(%.2f,%.2f,%.2f)" % [i, key, v.value, t.pelvis.x, t.pelvis.y, t.pelvis.z, t.knee_R.x, t.knee_R.y, t.knee_R.z, t.elbow_R.x, t.elbow_R.y, t.elbow_R.z])
		var frames := rig.solve(t, s.body.angle, s.body.yaw, {"L": false, "R": false})
		_grip(frames, s)
		for sd in ["L", "R"]:
			for b in LIMB_BONES:
				var name: String = b + "_" + sd
				if not frames.has(name):
					continue
				var q := Quaternion((frames[name] as Transform3D).basis.orthonormalized())
				if prev.has(name):
					var a := rad_to_deg((prev[name] as Quaternion).angle_to(q))
					if a > float(worst.get(name, [0.0])[0]):
						worst[name] = [a, i]
				if _trace(route, limb, dy, i) and name == OS.get_environment("BONE"):
					var sw_dir: Vector3 = (frames[name] as Transform3D).basis * rig.rest_basis[name].inverse() * rig.rest_dir[name]
					var hip: Vector3 = t["hip_" + sd]
					var knee: Vector3 = t["knee_" + sd]
					var ank: Vector3 = t["ankle_" + sd]
					var bend := knee - (hip + ank) * 0.5
					var dd := (knee - hip).normalized()
					print("  %d %s 회전%.1f° 축(%.2f,%.2f,%.2f) 굽힘%.3f 무릎(%.2f,%.2f,%.2f) 발목(%.2f,%.2f,%.2f) 골반z%.2f" % [i, name, rad_to_deg((prev.get(name, q) as Quaternion).angle_to(q)), sw_dir.x, sw_dir.y, sw_dir.z, (bend - dd * bend.dot(dd)).length(), knee.x, knee.y, knee.z, ank.x, ank.y, ank.z, t.pelvis.z])
				prev[name] = q
	var jumps := []
	for name in worst:
		if float(worst[name][0]) > BONE_JUMP_DEG:
			jumps.append("%s %.0f°@%d" % [name, worst[name][0], worst[name][1]])
	var line := "%-8s %s dy%.1f 골반(%.2f,%.2f)" % [route.route_id, limb, dy, s.body.pos.x, s.body.pos.y]
	if fell >= 0:
		line += " 떨어짐@%d" % fell
	if not sw.flips.is_empty():
		line += " 뒤집힘%s" % [sw.flip_examples.values().map(func(e): return "%.0f°@%d" % [e.deg, e.tick])]
	if not sw.counts.is_empty():
		line += " 위반%s" % [sw.counts]
	if not jumps.is_empty():
		line += " 뼈튐%s" % [jumps]
	print(line)
