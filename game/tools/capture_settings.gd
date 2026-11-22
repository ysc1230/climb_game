extends SceneTree
## 설정 탭 화면 확인용(작업 2 몸 옮기기). 진행 기록은 건드리지 않는다(Progress를 메모리에서만 바꿈).
## godot --path game --resolution 1600x720 --script res://tools/capture_settings.gd -- <out_prefix>

var home: Node
var frame := 0
var prefix := "user://settings"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		prefix = args[0]


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s_%s.png" % [prefix, name])
	print("saved %s_%s.png" % [prefix, name])


func _process(_d: float) -> bool:
	frame += 1
	var g = root.get_node_or_null("Game")
	if frame == 1:
		if g != null:
			g.first_run_sent = true  # 첫 실행 튜토리얼로 넘어가지 않게(설정 탭만 찍음)
		if g != null and g.progress.level == "":
			g.progress.level = "intermediate"
		home = load("res://scenes/home.tscn").instantiate()
		root.add_child(home)
		return false
	if frame == 10:
		home.grade_card = ""  # 등급 설명 창은 일반 탭 것이라 닫는다
		home._set_tab("settings")
		home.queue_redraw()
	if frame == 20:
		_shot("drag")
		g.progress.control["body"] = "tilt"
		home.queue_redraw()
	if frame == 30:
		_shot("tilt")
		return true
	return false
