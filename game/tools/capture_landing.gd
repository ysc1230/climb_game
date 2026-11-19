extends SceneTree
## 착지 동작 화면 확인용: 지금 자세를 높이 올려 떨어뜨린다(FallSim 낮음·중간·높음).
## godot --path game --resolution 1600x720 --script res://tools/capture_landing.gd -- <out_prefix> <올릴 m>

var play: Node
var frame := 0
var prefix := "user://landing"
var lift := 2.2
var t0 := -1


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		prefix = args[0]
	if args.size() > 1:
		lift = float(args[1])


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s_%s.png" % [prefix, name])
	print("saved %s_%s.png" % [prefix, name])


func _process(_d: float) -> bool:
	frame += 1
	if frame == 1:
		var g = root.get_node_or_null("Game")
		if g != null:
			g.current_route_id = "G_V3_03"
		play = load("res://scenes/play_3d.tscn").instantiate()
		root.add_child(play)
		return false
	var logic = play.get_node("UI/PlayTest")
	logic.paused = false
	logic.prepare_left = 0.0
	if frame == 120:
		var s: ClimbSession = logic.session
		s.halted = &"fall"
		s.falling = true
		logic._fall_advice = {"cause": "확인용 낙하", "advice": ""}
		var pts := {}
		for k in play._last_t:
			if play._last_t[k] is Vector3:
				pts[k] = (play._last_t[k] as Vector3) + Vector3(0, lift, 0)
		play.fall_sim = FallSim.new()
		play.fall_sim.start(pts, Vector3.ZERO, {}, play.MAT_TOP_Y, play.WALL_Z)
		print("kind %s" % play.fall_sim.kind())
		t0 = frame
	if t0 > 0:
		for f in [30, 50, 70, 95, 120, 150, 190]:
			if frame == t0 + f:
				_shot("%d" % f)
		if frame == t0 + 230:
			_shot("end")
			return true
	return frame > 900
