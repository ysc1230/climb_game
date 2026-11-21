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
		play = load("res://scenes/play_3d.tscn").instantiate()
		root.add_child(play)
		return false
	var logic = play.get_node("UI/PlayTest")
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
		for v in Anatomy.check(play._last_t, s.body.angle, s.body.yaw, AnatomySweep._free_map(s)):
			if v.kind == "in_wall":
				print("  위반 %d %s %s %.3f" % [tick, v.kind, v.limb, v.value])
	if tick % 20 == 0:
		print("tick %d 골반 %s 상태 %s" % [tick, s.body.pos, PoseSolver.LIMBS.map(func(l): return s.limbs[l].state)])
	tick += 1
	return tick > int(args[5]) or s.falling
