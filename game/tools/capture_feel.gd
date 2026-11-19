extends SceneTree
## 작업 1 화면 확인용 캡처: 루트 읽기 중간, 완등 축하. 실행(창 필요):
## godot --path game --resolution 1600x720 --script res://tools/capture_feel.gd -- <out_prefix>

var play: Node
var frame := 0
var prefix := "user://feel"


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
			g.current_route_id = "G_V3_03"
		play = load("res://scenes/play_3d.tscn").instantiate()
		root.add_child(play)
		return false
	var logic = play.get_node("UI/PlayTest")
	logic.paused = false  # 캡처 창이 포커스를 잃어 생기는 일시정지 무시
	logic.prepare_left = 0.0
	if frame == 40:
		_shot("preview")
	if frame == 200:
		var r: RouteDef = logic.route
		var bot := SessionBot.new()
		bot.route = r
		bot.session = ClimbSession.new(r)
		bot.session.hold_on_clear = true
		bot._play(r.intended_moves)
		print("bot ok=%s halted=%s" % [bot.ok(), bot.session.halted])
		logic.session = bot.session
		logic.route_preview = null
		logic.cam_y = bot.session.body.pos.y + 0.12 * 3.8
		logic._celebrate()
	if frame == 230:
		_shot("clear")
	if frame == 330:
		_shot("result")
		return true
	return false
