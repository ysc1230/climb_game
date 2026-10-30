extends Node2D
## 1A/2단계 시험 장면. R01 회색 박스 벽과 2D 막대 인형을 네 패드로 조작한다.
## 판정은 PoseSolver/Fatigue/InputRouter를 사용하고, 이 노드는 상태를 들고 그리기만 한다.
## 아직 단순화한 부분: GripSystem 동시 거래 대신 release 즉시 단일 판정, 결과 화면 없음(자동 재시작).

const LIMB_COLORS := {&"LH": Color("4fa3d9"), &"RH": Color("e08a3c"), &"LF": Color("4fa3d9"), &"RF": Color("e08a3c")}
const DEADZONE_MM := 2.5  # docs/23 제안 시작값. 04의 10논리단위와 함께 비교 대상
const PLAY_W := 3.4
const PLAY_H := 3.8

var route: RouteDef
var router := InputRouter.new()
var body: BodyState
var limbs := {}  # limb -> {state, key, pos(실제 말단), req(요청 목표)}
var feet: Array[StringName] = []
var stamina := {&"LH": 100.0, &"RH": 100.0}
var unsupported := 0
var goal_ticks := 0
var falling := false
var fall_ticks := 0
var paused := false
var prepare_left := 0.0
var message := ""
var message_ticks := 0
var cam_y := 1.9
var clears := 0
var falls := 0
var font: Font
var ui_k := 1.0
var px_per_m := 100.0
var wall_origin := Vector2.ZERO  # 월드 (0, cam_y)가 놓일 화면 위치
var log_lines: PackedStringArray = []
## false이면 벽·홀드·인형을 그리지 않고 패드·HUD만 그린다(3D 표현 계층이 월드를 그림).
var draw_world := true


func _ready() -> void:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Noto Sans CJK KR", "Noto Sans KR", "Apple SD Gothic Neo", "sans-serif"])
	font = sf
	route = RouteDef.load_json("res://data/routes/R01.json")
	get_viewport().size_changed.connect(_layout)
	_layout()
	_reset("시작")


func _layout() -> void:
	var size := get_viewport_rect().size
	ui_k = maxf(minf(size.x / 1600.0, size.y / 900.0), 0.25)
	var pad_d := 160.0 * ui_k
	router.set_pad(&"LH", Vector2(0.11, 0.30) * size, pad_d)
	router.set_pad(&"LF", Vector2(0.11, 0.72) * size, pad_d)
	router.set_pad(&"RH", Vector2(0.89, 0.30) * size, pad_d)
	router.set_pad(&"RF", Vector2(0.89, 0.72) * size, pad_d)
	var dpi := float(DisplayServer.screen_get_dpi())
	router.deadzone_px = maxf(10.0 * ui_k, DEADZONE_MM / 25.4 * dpi)
	px_per_m = maxf(minf(size.x * 0.56 / PLAY_W, size.y / PLAY_H), 10.0)
	wall_origin = Vector2(size.x * 0.5, size.y * 0.5)
	_log("화면 %dx%d dpi %.0f k %.2f 패드 %.0fpx 데드존 %.1fpx" % [size.x, size.y, dpi, ui_k, pad_d, router.deadzone_px])


func _reset(reason: String) -> void:
	router.cancel_all()
	body = BodyState.new(route.start_pelvis, route.start_angle)
	limbs.clear()
	for limb in PoseSolver.LIMBS:
		var key: String = route.start_slots[limb]
		var p := route.slot_pos(key)
		limbs[limb] = {"state": "Attached", "key": key, "pos": p, "req": p}
	stamina = {&"LH": 100.0, &"RH": 100.0}
	feet = PoseSolver.supporting_feet(body.pos, body.angle, _attached())
	unsupported = 0
	goal_ticks = 0
	falling = false
	cam_y = body.pos.y + 0.12 * PLAY_H
	_flash(reason)


func _flash(text: String) -> void:
	message = text
	message_ticks = 120


func _log(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > 6:
		log_lines.remove_at(0)


func _attached() -> Dictionary:
	var d := {}
	for limb in limbs:
		if limbs[limb].state == "Attached" or limbs[limb].state == "Armed":
			d[limb] = route.slot_pos(limbs[limb].key)
	return d


func _occupied(key: String, except: StringName) -> bool:
	for limb in limbs:
		if limb != except and limbs[limb].key == key and limbs[limb].state in ["Attached", "Armed"]:
			return true
	return false


# ---------- 입력 ----------

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.canceled:
			_apply(router.cancel_all())
			return
		if paused:
			if not event.pressed and prepare_left <= 0.0:
				prepare_left = 3.0
			return
		if falling:
			return
		if event.pressed:
			var limb := router._pad_at(event.position)
			var attached_now: bool = limb != &"" and limbs[limb].state == "Attached"
			_apply(router.touch_down(event.index, event.position, attached_now))
		else:
			_apply(router.touch_up(event.index))
	elif event is InputEventScreenDrag and not paused and not falling:
		_apply(router.touch_drag(event.index, event.position))


func _apply(cmds: Array) -> void:
	for c in cmds:
		var l: Dictionary = limbs[c.limb]
		match c.type:
			"arm":
				l.state = "Armed"
			"disarm":
				if l.state == "Armed":
					l.state = "Attached"
			"detach":
				l.state = "Dragging"
				l.req = l.pos
			"move":
				l.req = _clamp_to_reach(c.limb, l.req + c.delta)
			"release":
				_try_grab(c.limb)
			"cancel":
				if l.state == "Armed":
					l.state = "Attached"
				elif l.state == "Dragging":
					l.state = "Free"


func _clamp_to_reach(limb: StringName, p: Vector2) -> Vector2:
	var j := PoseSolver.joint_position(body.pos, body.angle, limb)
	var r := PoseSolver.reach_of(limb)
	var v := p - j
	return j + v.limit_length(r.y)


func _candidate(limb: StringName) -> String:
	var l: Dictionary = limbs[limb]
	var radius := Tuning.HAND_CANDIDATE_RADIUS if PoseSolver.is_hand(limb) else Tuning.FOOT_CANDIDATE_RADIUS
	var best := ""
	var best_d := INF
	for key in route.slots:
		if not route.slots[key].allowed.has(limb) or _occupied(key, limb):
			continue
		var sp := route.slot_pos(key)
		var d: float = l.pos.distance_to(sp)
		if d > radius or d >= best_d:
			continue
		var with_new := _attached()
		with_new[limb] = sp
		if PoseSolver.is_valid(body.pos, body.angle, with_new):
			best = key
			best_d = d
	return best


func _try_grab(limb: StringName) -> void:
	var l: Dictionary = limbs[limb]
	var key := _candidate(limb)
	if key.is_empty():
		l.state = "Free"
		return
	l.state = "Attached"
	l.key = key
	l.pos = route.slot_pos(key)
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(20)


# ---------- 고정 틱 ----------

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		_pause()


func _pause() -> void:
	if paused or OS.get_cmdline_user_args().has("--no-auto-pause"):
		return
	_apply(router.cancel_all())
	paused = true
	prepare_left = 0.0


func _physics_process(_delta: float) -> void:
	if message_ticks > 0:
		message_ticks -= 1
	if paused:
		if prepare_left > 0.0:
			prepare_left -= _delta
			if prepare_left <= 0.0:
				paused = false
		queue_redraw()
		return
	if falling:
		_fall_tick()
		queue_redraw()
		return
	_move_endpoints()
	var attached := _attached()
	var hands := int(attached.has(&"LH")) + int(attached.has(&"RH"))
	var platform := _on_platform(attached)
	if hands > 0 or platform:
		unsupported = 0
		PoseSolver.step_body(body, attached, feet)
		feet = PoseSolver.supporting_feet(body.pos, body.angle, attached, feet)
	else:
		unsupported += 1
		if unsupported >= Tuning.UNSUPPORTED_GRACE_TICKS:
			_start_fall("지지를 잃었어요")
			return
	var speed := body.vel.length()
	for hand in [&"LH", &"RH"]:
		var rate := Fatigue.FREE_HAND_RATE
		if attached.has(hand):
			rate = Fatigue.attached_hand_rate(platform and speed <= Fatigue.STABLE_SPEED, feet.size(), hands, speed)
		stamina[hand] = Fatigue.apply(stamina[hand], rate, Tuning.DT)
		if attached.has(hand) and stamina[hand] <= 0.0:
			limbs[hand].state = "Free"
			_flash("손이 미끄러졌어요")
	_goal_tick()
	_camera_tick()
	queue_redraw()


func _move_endpoints() -> void:
	for limb in limbs:
		var l: Dictionary = limbs[limb]
		if l.state in ["Attached", "Armed"]:
			l.pos = route.slot_pos(l.key)
			continue
		var target: Vector2 = l.req
		if l.state == "Free":
			var side := -1.0 if limb in [&"LH", &"LF"] else 1.0
			target = body.pos + (Vector2(0.30 * side, 0.18) if PoseSolver.is_hand(limb) else Vector2(0.25 * side, -0.70))
		target = _clamp_to_reach(limb, target)
		l.pos = l.pos.move_toward(target, 2.5 * Tuning.DT)
		l.pos = _clamp_to_reach(limb, l.pos)


func _on_platform(attached: Dictionary) -> bool:
	if not (attached.has(&"LF") and attached.has(&"RF")) or feet.size() < 2:
		return false
	for p in route.platforms:
		if p.foot_slot_keys.has(limbs[&"LF"].key) and p.foot_slot_keys.has(limbs[&"RF"].key):
			var a: Vector2 = attached[&"LF"]
			var b: Vector2 = attached[&"RF"]
			return body.pos.x >= minf(a.x, b.x) - 0.10 and body.pos.x <= maxf(a.x, b.x) + 0.10
	return false


func _goal_tick() -> void:
	var held := 0
	for limb in [&"LH", &"RH"]:
		if limbs[limb].state in ["Attached", "Armed"] and route.goal_slots.has(limbs[limb].key):
			held += 1
	goal_ticks = goal_ticks + 1 if held == 2 else 0
	if goal_ticks >= Tuning.GOAL_DWELL_TICKS:
		clears += 1
		_log("완등 %d회" % clears)
		_reset("완등! 다시 시작해요")


func _start_fall(reason: String) -> void:
	falls += 1
	falling = true
	fall_ticks = 0
	_apply(router.cancel_all())
	for limb in limbs:
		limbs[limb].state = "Free"
	_flash(reason)


func _fall_tick() -> void:
	fall_ticks += 1
	body.vel.y -= 9.8 * Tuning.DT
	body.pos += body.vel * Tuning.DT
	for limb in limbs:
		limbs[limb].pos += body.vel * Tuning.DT
	if fall_ticks >= 60 or body.pos.y < route.fail_line_y:
		_reset("떨어졌어요. 처음부터")


func _camera_tick() -> void:
	var screen_frac := 0.5 - (body.pos.y - cam_y) * px_per_m / get_viewport_rect().size.y
	if screen_frac < 0.50 or screen_frac > 0.68:
		var goal := body.pos.y + 0.12 * PLAY_H
		cam_y += clampf((goal - cam_y) * 8.0 * Tuning.DT, -2.0 * Tuning.DT, 2.0 * Tuning.DT)


# ---------- 그리기 ----------

func w2s(p: Vector2) -> Vector2:
	return wall_origin + Vector2(p.x, cam_y - p.y) * px_per_m


func _draw() -> void:
	var size := get_viewport_rect().size
	if not draw_world:
		_draw_pads(size)
		_draw_hud(size)
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color("2b2622"))
	var tl := w2s(Vector2(-PLAY_W / 2, cam_y + PLAY_H / 2))
	draw_rect(Rect2(tl, Vector2(PLAY_W, PLAY_H) * px_per_m), Color("8a5a40"))
	draw_line(w2s(Vector2(-1.7, 0)), w2s(Vector2(1.7, 0)), Color("3a3028"), 4.0)
	for key in route.slots:
		var sp := route.slot_pos(key)
		var is_goal := route.goal_slots.has(key)
		var is_hand_slot: bool = route.slots[key].allowed.has(&"LH")
		var col := Color("f1d59a") if is_goal else (Color("c97a5c") if is_hand_slot else Color("7d7f5c"))
		draw_circle(w2s(sp), 0.07 * px_per_m, col)
		draw_arc(w2s(sp), 0.07 * px_per_m, 0, TAU, 20, Color("302820"), 2.0)
	for limb in limbs:
		if limbs[limb].state == "Dragging":
			var c := _candidate(limb)
			if not c.is_empty():
				draw_arc(w2s(route.slot_pos(c)), 0.11 * px_per_m, 0, TAU, 24, Color("fff2c8"), 3.0)
			var j := PoseSolver.joint_position(body.pos, body.angle, limb)
			draw_arc(w2s(j), PoseSolver.reach_of(limb).y * px_per_m, 0, TAU, 64, Color(1, 1, 1, 0.15), 1.5)
	_draw_body()
	_draw_pads(size)
	_draw_hud(size)


func _draw_body() -> void:
	var pel := w2s(body.pos)
	var neck := w2s(body.pos + Vector2(0, 0.62).rotated(deg_to_rad(body.angle)))
	var ink := Color("302820")
	draw_line(pel, neck, Color("4f6a68"), 0.22 * px_per_m)
	draw_circle(w2s(body.pos + Vector2(0, 0.78).rotated(deg_to_rad(body.angle))), 0.12 * px_per_m, Color("c7b79b"))
	for limb in limbs:
		var j := PoseSolver.joint_position(body.pos, body.angle, limb)
		var e: Vector2 = limbs[limb].pos
		var hand := PoseSolver.is_hand(limb)
		var a := Tuning.ARM_UPPER if hand else Tuning.LEG_UPPER
		var b := Tuning.ARM_LOWER if hand else Tuning.LEG_LOWER
		var side := -1.0 if limb in [&"LH", &"LF"] else 1.0
		var mid := _two_bone(j, e, a, b, side if hand else side)
		var col: Color = LIMB_COLORS[limb]
		draw_line(w2s(j), w2s(mid), col, 0.07 * px_per_m)
		draw_line(w2s(mid), w2s(e), col, 0.06 * px_per_m)
		var state: String = limbs[limb].state
		var tip := Color.WHITE if state == "Dragging" else (ink if state in ["Attached", "Armed"] else Color("aaaaaa"))
		draw_circle(w2s(e), 0.045 * px_per_m, tip)


## 2D 두 뼈 IK. side 방향(바깥쪽)으로 관절을 꺾는다.
func _two_bone(root: Vector2, end: Vector2, a: float, b: float, side: float) -> Vector2:
	var v := end - root
	var d := clampf(v.length(), absf(a - b) + 0.001, a + b - 0.001)
	var dir := v.normalized() if v.length() > 0.0001 else Vector2.DOWN
	var x := (a * a - b * b + d * d) / (2.0 * d)
	var h := sqrt(maxf(a * a - x * x, 0.0))
	var perp := Vector2(-dir.y, dir.x)
	if perp.x * side < 0:
		perp = -perp
	return root + dir * x + perp * h


func _draw_pads(size: Vector2) -> void:
	for limb in router.pads:
		var p: Dictionary = router.pads[limb]
		var active := router.active_limbs().has(limb)
		var col: Color = LIMB_COLORS[limb]
		draw_circle(p.center, p.radius, Color(col, 0.45 if active else 0.22))
		draw_arc(p.center, p.radius, 0, TAU, 40, Color(col, 0.9), 3.0)
		var label := "%s %s" % [limb, "손" if PoseSolver.is_hand(limb) else "발"]
		draw_string(font, p.center + Vector2(-p.radius, 8), label, HORIZONTAL_ALIGNMENT_CENTER, p.radius * 2, int(26 * ui_k), Color.WHITE)
		if PoseSolver.is_hand(limb):
			var s: float = stamina[limb]
			draw_arc(p.center, p.radius + 8 * ui_k, -PI / 2, -PI / 2 + TAU * s / 100.0, 48, Color("f1d59a") if s > 25 else Color("ff5a4a"), 6.0 * ui_k)


func _draw_hud(size: Vector2) -> void:
	var fs := int(22 * ui_k)
	var height := maxf(body.pos.y - route.start_pelvis.y, 0.0)
	draw_string(font, Vector2(size.x * 0.25, 40 * ui_k), "R01 시험 빌드 · 높이 %.1fm · 완등 %d · 추락 %d" % [height, clears, falls], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	var y := size.y - 20 * ui_k
	for i in range(log_lines.size() - 1, -1, -1):
		draw_string(font, Vector2(size.x * 0.25, y), log_lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * ui_k), Color(1, 1, 1, 0.6))
		y -= 18 * ui_k
	if message_ticks > 0:
		draw_string(font, Vector2(0, size.y * 0.18), message, HORIZONTAL_ALIGNMENT_CENTER, size.x, int(34 * ui_k), Color("fff2c8"))
	if paused:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
		var t := "손가락을 편하게 올려주세요 %d" % ceili(prepare_left) if prepare_left > 0.0 else "일시정지 · 화면을 탭하면 3초 뒤 이어서 시작해요"
		draw_string(font, Vector2(0, size.y * 0.5), t, HORIZONTAL_ALIGNMENT_CENTER, size.x, int(34 * ui_k), Color.WHITE)
