extends Node
## 시각 검수용 데모(MC01 성격): play_3d를 띄우고 LH 패드에서 원 드래그를 주입한다.
## 사용: godot --resolution 1600x900 --write-movie /tmp/x/f.png --fixed-fps 30 --quit-after 240 res://tools/motion_demo.tscn -- --no-auto-pause
## 이어서(frame 300~): 세션을 처음 자세로 되돌리고 기술 버튼 흐름을 주입한다(docs/27 §6):
## "기술" 버튼 → 발 탭의 하이스텝 → 왼쪽 → F03 홀드 탭(누른 채 미리보기 → 떼면 실행).
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
	# 오른발을 고관절 높이까지 올려 "붙었지만 하중 없음" 표시 확인(MC07)
	var rf: Dictionary = logic.router.pads[&"RF"]
	if frame == 240:
		_touch(1, rf.center, true)
	elif frame > 240 and frame < 300:
		_drag(1, rf.center + Vector2(0, -(frame - 240) * 2.2))
	_tech_flow(logic)
	if frame == 21:
		var sk: Skeleton3D = scene.skeleton
		print("skeleton global=", sk.global_transform if sk else "none")
	if frame % 20 == 0 and frame > 20:
		var l: Dictionary = logic.session.limbs[&"LH"]
		print("f%d LH state=%s angle=%.1f phase=%s u=%s loaded=%s" % [frame, l.state, PoseSolver.limb_angle(logic.session.body.pos, logic.session.body.angle, &"LH", l.pos), logic.session.rules.phase_name(), logic.session.rules.last.get("u", {}), logic.session.rules.loaded_feet])
		if frame == 60:
			var fm = scene.foot_marks[&"LF"]
			print("  LF mark visible filled=%s hollow=%s pos=%s" % [fm[0].visible, fm[1].visible, fm[0].global_position])


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


const F03 := "G_V0_01/F03/foot_1"


## 기술 선택 흐름 주입(물리 틱 기준). 좌표는 play_test의 레이아웃·카메라 변환으로 구한다.
func _tech_flow(logic) -> void:
	var size: Vector2 = logic.get_viewport_rect().size
	match frame:
		300:
			_touch(1, logic.router.pads[&"RF"].center, false)
			logic._reset("기술 시험")
		340:
			_tap(logic._btn_rect(size).get_center())
		360:
			_tap(logic._entry_rect(size, 3).get_center())  # 발 탭의 네 번째 = 하이스텝
		380:
			_tap(logic._side_rect(&"left").get_center())
		400:
			_touch(2, logic.w2s(logic.route.slot_pos(F03)), true)  # 누르는 동안 품질 미리보기
		430:
			_touch(2, logic.w2s(logic.route.slot_pos(F03)), false)
			print("tech: selecting=%s active=%s" % [logic.session.selecting, logic.session.runner.active.get("id", "")])
		470:
			print("tech: LF=%s %s log=%s" % [logic.session.limbs[&"LF"].state, logic.session.limbs[&"LF"].key, logic.session.technique_log.map(func(e): return e.type)])
	if frame in [345, 365, 385, 410, 440]:
		print("tech f%d: mode=%d selecting=%s tick=%d" % [frame, logic.ui_mode, logic.session.selecting, logic.session.tick_count])


func _tap(p: Vector2) -> void:
	_touch(2, p, true)
	_touch(2, p, false)
