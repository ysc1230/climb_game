extends SceneTree
## 작업 1 화면 확인용: 오른손·발을 떼어 떨어뜨린 장면, 조언 카드, 손 힘 위험 경고.
## godot --path game --resolution 1600x720 --script res://tools/capture_fall.gd -- <out_prefix>

var play: Node
var frame := 0
var prefix := "user://fall"
var t_fall := -1


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		prefix = args[0]


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s_%s.png" % [prefix, name])
	print("saved %s_%s.png" % [prefix, name])


func _process(_d: float) -> bool:
	frame += 1
	if frame == 1:
		var g = root.get_node_or_null("Game")
		if g != null:
			g.current_route_id = "G_V3_11"
		play = load("res://scenes/play_3d.tscn").instantiate()
		root.add_child(play)
		return false
	var logic = play.get_node("UI/PlayTest")
	logic.paused = false
	logic.prepare_left = 0.0
	var s: ClimbSession = logic.session
	if frame == 150:  # 손 힘 위험 경고: 왼손 힘을 15로
		s.rules.stamina[&"LH"] = 15.0
	if frame == 175:
		_shot("grip_low")
	if frame == 200:
		s.rules.stamina[&"LH"] = 100.0
		s.apply_input([{"type": "detach", "limb": &"LH"}, {"type": "detach", "limb": &"LF"}, {"type": "detach", "limb": &"RF"}])
	if t_fall < 0 and s.falling:
		t_fall = frame
		print("fall at %d cause=%s" % [frame, logic._fall_advice])
	for f in [18, 40, 60, 85, 110]:
		if t_fall > 0 and frame == t_fall + f:
			_shot("landing_%d" % f)
	if t_fall > 0 and frame == t_fall + 200:
		_shot("advice")
		return true
	return frame > 900
