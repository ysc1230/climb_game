extends SceneTree
## 홀드 종류 확인용 캡처(작업 4 §4.2): 플레이 화면의 벽·조명·재질로 종류 8개(M), 크기 S/M/L, 방향 0·90·180·270을 늘어놓는다.
## godot --path game --resolution 1600x720 --script res://tools/capture_holds.gd -- <out.png> [gray]
## gray: 흑백으로 바꿔 저장(벽 대비 확인).

var play: Node
var frame := 0
var out := "user://holds.png"
var gray := false
const Y0 := 4.9


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	gray = args.has("gray")


func _slot(type: String, size: String, rot: int, pos: Vector2, matchable := false) -> Dictionary:
	var foot := HoldTypes.is_foot(type)
	var slot := {"pos": pos, "allowed": [&"LF"] if foot else [&"LH"]}
	var s := {"hold_type": type, "size": size, "rot_deg": rot, "hand_area": {"matchable": matchable}}
	HoldTypes.fill(slot, s)
	return slot


func _put(slot: Dictionary, goal := false) -> void:
	var P3 := preload("res://scenes/play_3d.gd")
	var name: String = P3.hold_variant(str(slot.pos), slot, goal)
	var mesh: Mesh = play._hold_mesh(name)
	var hand: bool = slot.has("hand_area")
	var kind := "goal" if goal else ("foot" if not hand else ("match" if slot.hand_area.matchable else "hand"))
	var cols: Array = P3.HOLD_COLORS[kind]
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mats := [play._toon(cols[0], cols[0].darkened(0.45)), play._toon(cols[1], cols[1].darkened(0.35)), play._toon(cols[0].darkened(0.62), P3.INK)]
	for m in mats.slice(0, 2):
		m.set_shader_parameter("speckle", true)
	for si in mesh.get_surface_count():
		var role: int = P3.surface_role(mesh, si)
		mats[role].next_pass.set_shader_parameter("width", 0.006)
		mi.set_surface_override_material(si, mats[role])
	var ang: float = (slot.hand_area.dir as Vector2).angle() if hand else (slot.foot_area.up as Vector2).angle() - PI / 2.0
	mi.position = Vector3(slot.pos.x, slot.pos.y, 0.0)
	mi.rotation = Vector3(0, 0, ang)
	mi.scale = Vector3.ONE * P3.hold_view_scale(slot, mesh, goal)
	play.add_child(mi)
	var label := Label3D.new()
	label.text = "%s %s %d°" % [HoldTypes.name_ko(str(slot.hold_type)), slot.size, slot.rot_deg]
	label.font_size = 28
	label.pixel_size = 0.0012
	label.modulate = Color(1, 1, 1)
	label.outline_size = 8
	label.position = Vector3(slot.pos.x, slot.pos.y - 0.13, 0.05)
	play.add_child(label)


func _process(_d: float) -> bool:
	frame += 1
	if frame == 1:
		var g = root.get_node_or_null("Game")
		if g != null:
			g.current_route_id = "G_V3_03"
		play = load("res://scenes/play_3d.tscn").instantiate()
		root.add_child(play)
		return false
	if frame == 30:
		var types := ["jug", "crimp", "sloper", "pinch", "pocket", "foot_chip", "foot_big", "goal"]
		for i in types.size():
			var x := -1.05 + i * 0.3
			if types[i] == "goal":
				_put({"pos": Vector2(x, Y0 + 0.35), "hold_type": &"goal", "size": "M", "rot_deg": 0, "hand_area": {"dir": Vector2(1, 0), "half_width": 0.12, "matchable": false}}, true)
			else:
				_put(_slot(types[i], "M", 0, Vector2(x, Y0 + 0.35), types[i] == "jug" and false))
		var row2 := [["jug", "S", 0], ["jug", "M", 0], ["jug", "L", 0], ["crimp", "M", 0], ["crimp", "M", 90], ["crimp", "M", 180], ["crimp", "M", 270], ["sloper", "L", 45]]
		for i in row2.size():
			_put(_slot(row2[i][0], row2[i][1], row2[i][2], Vector2(-1.05 + i * 0.3, Y0 - 0.1)))
		_put(_slot("jug", "L", 0, Vector2(1.35, Y0 + 0.12), true))
		play.set_process(false)
		play.camera.position = Vector3(0.15, Y0 + 0.12, 2.1)
		play.camera.look_at(Vector3(0.15, Y0 + 0.12, 0.0))
		var ui = play.get_node_or_null("UI")
		if ui != null:
			ui.visible = false
	if frame == 60:
		var img := root.get_texture().get_image()
		if gray:
			img.convert(Image.FORMAT_L8)
		img.save_png(out)
		print("saved ", out)
		return true
	return false
