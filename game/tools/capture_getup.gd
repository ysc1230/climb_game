extends SceneTree
## 떨어진 뒤 일어선 자세 확인용(실제 낙하: 손발을 떼어 떨어뜨림). 몸: male/female.
## godot --path game --resolution 1600x720 --script res://tools/capture_getup.gd -- <out_prefix> [body] [dyno]

var play: Node
var frame := 0
var prefix := "user://getup"
var body := "female"
var t_fall := -1
var dyno := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		prefix = args[0]
	if args.size() > 1:
		body = args[1]
	dyno = args.size() > 2 and args[2] == "dyno"


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s_%s.png" % [prefix, name])
	print("saved %s_%s.png" % [prefix, name])


func _process(_d: float) -> bool:
	frame += 1
	if frame == 1:
		var g = root.get_node_or_null("Game")
		if g != null:
			g.current_route_id = "G_V2_01"
			g.progress.look["body"] = body
		if OS.get_environment("LODT") != "": root.mesh_lod_threshold = float(OS.get_environment("LODT"))
		play = load("res://scenes/play_3d.tscn").instantiate()
		root.add_child(play)
		return false
	var logic = play.get_node("UI/PlayTest")
	logic.paused = false
	logic.prepare_left = 0.0
	var s: ClimbSession = logic.session
	if frame == 150:
		if dyno:  # 다이노로 옆으로 뛰어 못 잡음
			s.apply_input([{"type": "dyno_start"}, {"type": "dyno_move", "delta": Vector2(float(OS.get_environment("DX")), float(OS.get_environment("DY")))}, {"type": "dyno_end"}])
		else:
			s.apply_input([{"type": "detach", "limb": &"LH"}, {"type": "detach", "limb": &"LF"}, {"type": "detach", "limb": &"RF"}])
	if t_fall < 0 and s.falling:
		t_fall = frame
	if t_fall > 0 and frame == t_fall + 3 and play.fall_sim != null:
		print("fall len ua %.3f fa %.3f hand %.3f" % [play.fall_sim._len.ua, play.fall_sim._len.fa, play.fall_sim._len.hand])
	if t_fall > 0 and (frame - t_fall) % 30 == 0 and play.skeleton != null:
		var sk: Skeleton3D = play.skeleton
		for side in ["L", "R"]:
			var h := sk.get_bone_global_pose(sk.find_bone("hand_" + side))
			var f := sk.get_bone_global_pose(sk.find_bone("finger_" + side))
			var hr := sk.get_bone_global_rest(sk.find_bone("hand_" + side))
			var fr := sk.get_bone_global_rest(sk.find_bone("finger_" + side))
			print("t+%d %s hand-finger %.3f (rest %.3f) scale %.3f curl %.2f" % [frame - t_fall, side, h.origin.distance_to(f.origin), hr.origin.distance_to(fr.origin), f.basis.get_scale().length() / sqrt(3.0), play.curl[side]])
	for f in [60, 120, 200, 300]:
		if t_fall > 0 and frame == t_fall + f:
			_shot("%d" % f)
	return (t_fall > 0 and frame > t_fall + 300) or frame > 900
