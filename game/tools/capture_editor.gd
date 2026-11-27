extends SceneTree
## 문제 만들기 화면 확인용(작업 6). 시험 초안을 넣고(저장 안 함) 홀드 하나를 고른 화면을 찍는다.
## godot --path game --resolution 1600x720 --script res://tools/capture_editor.gd -- <out.png> [start]

var ed: Node
var frame := 0
var out := "user://editor.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]


func _sample() -> RouteDraft:
	var d := RouteDraft.new()
	d.route_id = "U_CAPTURE01"
	d.name = "첫 문제"
	d.grade = "V2"
	var f1 := d.place("crimp", -0.15, 0.1, "foot")
	var f2 := d.place("crimp", 0.18, 0.1, "foot")
	var h1 := d.place("jug", -0.3, 1.5)
	var h2 := d.place("jug", 0.3, 1.5)
	d.place("jug", -0.25, 0.55, "foot", "S")
	d.place("jug", 0.3, 0.6, "foot", "S")
	d.place("crimp", -0.35, 1.95, "hand", "L", 90)
	d.place("pinch", 0.35, 2.05)
	d.place("sloper", 0.0, 2.5)
	d.place("jug", 0.05, 1.55)  # 일부러 너무 가깝게(빨간 표시 확인)
	d.place("goal", 0.05, 2.95)
	d.set_start(&"LH", h1)
	d.set_start(&"RH", h2)
	d.set_start(&"LF", f1)
	d.set_start(&"RF", f2)
	return d


func _process(_d: float) -> bool:
	frame += 1
	if frame == 1:
		ed = load("res://scenes/editor.tscn").instantiate()
		root.add_child(ed)
		return false
	if frame == 10:
		var ui = ed.get_node("UI/EditorUI")
		ui.draft = _sample()
		ui._name_edit.text = ui.draft.name
		ui.selected = "H07"
		if OS.get_cmdline_user_args().has("start"):
			ui.tool = "start"
		ui._changed()
	if frame == 50:
		root.get_texture().get_image().save_png(out)
		print("saved ", out)
		return true
	return false
