extends SceneTree
## 굽힌 관절 + 반대쪽 무게 이동 장면 찍기(tools/bend_shift.gd와 같은 끌기). 실제 화면에서 팔꿈치·무릎 모양 확인용.
## godot --path game --resolution 1600x720 --script res://tools/capture_shift.gd -- <out_prefix> <루트> <손발> <dy> <첫 틱> <끝 틱> [간격=3] [body=female]

var play: Node
var frame := 0
var args: PackedStringArray
var off := Vector2.ZERO
var tick := -1


func _initialize() -> void:
	args = OS.get_cmdline_user_args()


func _process(_d: float) -> bool:
	frame += 1
	if frame == 1:
		var g = root.get_node_or_null("Game")
		if g != null:
			g.current_route_id = args[1]
			g.progress.look["body"] = args[7] if args.size() > 7 else "female"
			if OS.get_environment("CLEAN") != "":  # 휴대폰 기본 화면처럼(힘 %·AI 고스트 끔)
				g.progress.display = Progress.DISPLAY_DEFAULTS.duplicate()
		play = load("res://scenes/play_3d.tscn").instantiate()
		root.add_child(play)
		return false
	var logic = play.get_node("UI/PlayTest")
	if OS.get_environment("NOUI") != "":  # 2D 화면(패드·위쪽 줄·경고)을 숨기고 3D만(시안 바탕용)
		play.get_node("UI").visible = false
	if OS.get_environment("VIEW") != "":  # 시점: 좌우 도는 각(도). 예 VIEW=75
		logic.cam_yaw = deg_to_rad(float(OS.get_environment("VIEW")))
	logic.paused = false
	logic.prepare_left = 0.0
	var s: ClimbSession = logic.session
	if frame == 60:
		s.apply_input([{"type": "body_start"}])
		tick = 0
	if tick < 0:
		return false
	var limb := StringName(args[2])
	var side := PoseSolver.side_sign(limb)
	var vy := (0.3 if PoseSolver.is_hand(limb) else -0.3) * float(args[3])
	var goal := Vector2(side * 0.3, vy) if tick < 90 else Vector2(-side * 0.35, vy)
	var d := (goal - off).limit_length((0.6 if tick < 90 else 0.5) / 60.0)
	off += d
	s.apply_input([{"type": "body_move", "delta": d}])
	var every := int(args[6]) if args.size() > 6 else 3
	if tick >= int(args[4]) and tick <= int(args[5]) and (tick - int(args[4])) % every == 0:
		root.get_texture().get_image().save_png("%s_%03d.png" % [args[0], tick])
	if not play._last_t.is_empty():
		for v in Anatomy.check(play._last_t, s.body.angle, float(play._last_t.get("yaw", s.body.yaw)), AnatomySweep._free_map(s)):
			if v.kind == "in_wall":
				print("  위반 %d %s %s %.3f" % [tick, v.kind, v.limb, v.value])
	var js := OS.get_environment("JOINTS")  # 예: JOINTS=R 이면 오른팔 어깨·팔꿈치·손목(골반 기준)을 3틱마다
	if js != "" and tick % 3 == 0 and not play._last_t.is_empty():
		var t: Dictionary = play._last_t
		var p: Vector3 = t.pelvis
		print("  관절 %d 어깨 %s 팔꿈치 %s 손목 %s" % [tick, (t["shoulder_" + js] - p).snapped(Vector3.ONE * 0.01), (t["elbow_" + js] - p).snapped(Vector3.ONE * 0.01), (t["wrist_" + js] - p).snapped(Vector3.ONE * 0.01)])
	var dl := OS.get_environment("DEPTH")  # 예: DEPTH=RH 이면 골반 깊이 구간·지금 깊이와 깊이별 그 팔다리 최소 위반을 3틱마다
	if dl != "" and tick % 3 == 0:
		var cp: ClimberPose = play.climber_pose
		var b = s.body
		var r := PoseSolver.body_depth_range(b.pos, b.angle, s.attached(), b.yaw)
		var frame := Anatomy.body_basis(b.angle, b.yaw)
		var up := Vector3(-sin(deg_to_rad(b.angle)), cos(deg_to_rad(b.angle)), 0)
		var row := ""
		for i in 8:
			var dpt := 0.20 + 0.03 * i
			var root := ClimberPose._root(b, StringName(dl), dpt)
			var end := cp._end(s, StringName(dl), 0.0, dpt)
			row += " %.2f:%.2f" % [dpt, LimbIK.min_violation(StringName(dl), root, end, frame, Vector3(b.pos.x, b.pos.y, dpt), up)]
		print("  깊이 %d 구간 %s 지금 %.3f |%s" % [tick, r.snapped(Vector2.ONE * 0.001), cp.depth, row])
		# 몸통을 비틀면(yaw) 네 팔다리가 모두 가능한 깊이가 생기는가: yaw별 [구간, 가장 작은 네 팔다리 위반 합@깊이]
		var yr := ""
		for yaw in [0.0, -10.0, -20.0, -30.0, 10.0, 20.0]:
			var ry := PoseSolver.body_depth_range(b.pos, b.angle, s.attached(), yaw)
			if not ry.is_finite():
				yr += " %d:없음" % yaw
				continue
			var fy := Anatomy.body_basis(b.angle, yaw)
			var bestv := INF
			var bestd := 0.0
			var dpt := ry.x
			while dpt <= ry.y + 0.0001:
				var tot := 0.0
				for l in PoseSolver.LIMBS:
					var j2 := PoseSolver.joint_position(b.pos, b.angle, l, yaw)
					if not PoseSolver.is_hand(l):
						j2 += Vector2(-sin(deg_to_rad(b.angle)), cos(deg_to_rad(b.angle))) * LimbIK.hip_raise
					var root := Vector3(j2.x, j2.y, dpt + PoseSolver.joint_depth_offset(l, yaw))
					tot += LimbIK.min_violation(l, root, cp._end(s, l, 0.0, dpt), fy, Vector3(b.pos.x, b.pos.y, dpt), up)
				if tot < bestv:
					bestv = tot
					bestd = dpt
				dpt += 0.02
			yr += " %d:%.2f@%.2f%s" % [yaw, bestv, bestd, "" if PoseSolver.is_valid(b.pos, b.angle, s.attached(), yaw) else "(판정X)"]
		print("  비틀기 %d%s" % [tick, yr])
	if tick % 20 == 0:
		print("tick %d 골반 %s 상태 %s" % [tick, s.body.pos, PoseSolver.LIMBS.map(func(l): return s.limbs[l].state)])
	tick += 1
	return tick > int(args[5]) or s.falling
