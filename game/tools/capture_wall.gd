extends SceneTree
## 벽·홀드 전체 확인용 캡처(작업 4 §4.3): 문제 하나를 열어 시작 화면을 저장한다. gray면 흑백(홀드가 벽보다 먼저 읽히는지).
## godot --path game --resolution 1600x720 --script res://tools/capture_wall.gd -- <out.png> <route_id> [gray] [tags] [ai] [cam_y]
## ai: AI 고스트를 켜고(메모리에서만) 8초 장면을 찍는다.
## tags: 처음 보는 홀드 종류 이름표가 떠 있을 때(1.5초) 찍는다. 이 PC 저장의 seen_tips에 남는다.

var play: Node
var frame := 0
var out := "user://wall.png"
var route_id := "G_V3_03"
var gray := false
var cam_y := NAN
var args_tags := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	if args.size() > 1:
		route_id = args[1]
	gray = args.has("gray")
	args_tags = args.has("tags")
	for a in args:
		if a.is_valid_float() and args.find(a) > 1:
			cam_y = float(a)


func _process(_d: float) -> bool:
	var args := OS.get_cmdline_user_args()
	frame += 1
	if frame == 1:
		var g = root.get_node_or_null("Game")
		if g != null:
			g.current_route_id = route_id
			if args.has("ai"):
				g.progress.display["ai_ghost"] = true
		play = load("res://scenes/play_3d.tscn").instantiate()
		root.add_child(play)
		return false
	var logic = play.get_node("UI/PlayTest")
	logic.route_preview = null
	logic.paused = false
	logic.prepare_left = 0.0
	if not is_nan(cam_y):
		logic.cam_y = cam_y
	if args.has("ai") and frame > 100:
		logic.attempt.seconds = 8.0
		logic.queue_redraw()
	if frame == (90 if args_tags else 150):
		var img := root.get_texture().get_image()
		if gray:
			img.convert(Image.FORMAT_L8)
		img.save_png(out)
		print("saved ", out)
		return true
	return false
