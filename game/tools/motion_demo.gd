extends Node
## 시각 검수용 데모(MC01 성격): play_3d를 띄우고 LH 패드에서 원 드래그를 주입한다.
## 사용: godot --resolution 1600x900 --write-movie /tmp/x/f.png --fixed-fps 30 --quit-after 240 res://tools/motion_demo.tscn -- --no-auto-pause
## 맥 렌더 결과이며 기기 네 손가락 검증이 아니다.

var scene: Node
var frame := 0


func _ready() -> void:
	scene = load("res://scenes/play_3d.tscn").instantiate()
	add_child(scene)


func _physics_process(_delta: float) -> void:
	frame += 1
	var logic = scene.get_node("UI/PlayTest")
	var pad: Dictionary = logic.router.pads[&"LH"]
	var c: Vector2 = pad.center
	if frame == 20:
		_touch(0, c, true)
	elif frame > 20 and frame < 220:
		var a := (frame - 20) * 0.08
		_drag(0, c + Vector2(cos(a), sin(a)) * pad.radius * 1.4 + Vector2(0, -pad.radius * 0.3))
	elif frame == 220:
		_touch(0, c, false)
	if frame == 21:
		var sk: Skeleton3D = scene.skeleton
		print("skeleton global=", sk.global_transform if sk else "none")
	if frame % 20 == 0 and frame > 20:
		var l: Dictionary = logic.limbs[&"LH"]
		print("f%d LH state=%s angle=%.1f" % [frame, l.state, PoseSolver.limb_angle(logic.body.pos, logic.body.angle, &"LH", l.pos)])


func _touch(i: int, p: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = p
	e.pressed = pressed
	Input.parse_input_event(e)


func _drag(i: int, p: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = i
	e.position = p
	Input.parse_input_event(e)
