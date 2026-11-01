extends Node2D
## 플레이 장면. 회색 박스 벽과 2D 막대 인형을 네 패드로 조작한다.
## 판정은 PoseSolver/Fatigue/InputRouter를 사용하고, 이 노드는 상태를 들고 그리기만 한다.
## 문제는 자동 로드 Game의 current_route_id에서 받는다(docs/28 §5). Game이 없거나 비면 G_V0_01과 모든 버튼.
## 완등 결과·튜토리얼 안내·일시정지 [목록]은 PlayOverlay가 그리고, 여기서는 받은 동작만 처리한다.
## 아직 단순화한 부분: GripSystem 동시 거래 대신 release 즉시 단일 판정.

const LIMB_COLORS := {&"LH": Color("4fa3d9"), &"RH": Color("e08a3c"), &"LF": Color("4fa3d9"), &"RF": Color("e08a3c")}
const DEADZONE_MM := 2.5  # docs/23 제안 시작값. 04의 10논리단위와 함께 비교 대상
const PLAY_W := 3.4
const PLAY_H := 3.8
const DEFAULT_ROUTE := "res://data/routes/general/G_V0_01.json"
const PlayOverlay := preload("res://scenes/play_overlay.gd")

var session: ClimbSession
var route: RouteDef
var router := InputRouter.new()
var paused := false
var prepare_left := 0.0
var message := ""
var message_ticks := 0
var cam_y := 1.9
var font: Font
var ui_k := 1.0
var px_per_m := 100.0
var wall_origin := Vector2.ZERO  # 월드 (0, cam_y)가 놓일 화면 위치
var log_lines: PackedStringArray = []
## false이면 벽·홀드·인형을 그리지 않고 패드·HUD만 그린다(3D 표현 계층이 월드를 그림).
var draw_world := true
## 월드(m) ↔ 화면(px) 변환. play_3d가 카메라 투영으로 덮어쓴다. 비면 2D 변환을 쓴다.
var w2s_fn := Callable()
var s2w_fn := Callable()
## 자동 로드 Game(없으면 null). 이름으로 직접 부르지 않는다(헤드리스 테스트에서 자동 로드가 없을 수 있음).
var game: Node
var overlay := PlayOverlay.new()
var tutorial: TutorialRunner
var run_seconds := 0.0      # 이번 시도 시간(문제를 연 뒤 또는 [다시] 뒤, 일시정지 제외)
var run_falls_from := 0     # 이번 시도가 시작될 때의 session.falls
var _tutorial_wait := false # 추락 뒤 단계 다시 시작을 추락 연출(respawn)까지 미룸
var _swallow := {}          # 오버레이 버튼을 누른 터치(떼기 입력도 버린다)

# ---------- 기술 선택 UI 상태(docs/27 §6, 05 v0.6) ----------
enum UI { NONE, PANEL, SIDE, HOLD }
const CHECK_INTERVAL := 0.2  # 패널 흐림 검사 주기(초)
const HOLD_PICK_RADIUS := 0.12  # 탭이 홀드 영역에서 이만큼 안이면 그 홀드를 누른 것(m)
const STAGE_TEXT := {&"check": "준비 중", &"move": "옮기는 중", &"yaw": "자세를 유지하는 중"}
const ENTRY_COLS := 4
## 패널에 보여 줄 버튼 기술(docs/28 §5.5). 비면 기술 버튼을 그리지도 받지도 않는다(패드만으로 진행).
var allowed_buttons: Array[StringName] = TechniqueDefs.button_ids()
var ui_mode := UI.NONE
var sel_tech := &""
var sel_side := &""
var side_judge := {}       # side -> {available, reason, text} (쪽 선택 단계)
var hold_targets: Array = []
var dim := {}              # tech_id -> true(지금 안 될 것 같음)
var preview := {}          # 홀드 탭 미리보기 {key, ok, point, quality, text}
var _hold_index := -2      # 홀드 미리보기를 누르고 있는 터치(-2 없음)
var _check_timer := 0.0
var _techs := TechniqueJudge.defs()


func _ready() -> void:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Noto Sans CJK KR", "Noto Sans KR", "Apple SD Gothic Neo", "sans-serif"])
	font = sf
	overlay.font = sf
	game = get_node_or_null("/root/Game")
	if game != null and game.current_route_id != "":
		route = game.index.route(game.current_route_id)
	if route == null:
		route = RouteDef.load_json(DEFAULT_ROUTE)
	else:
		overlay.has_list = true
	session = ClimbSession.new(route)
	_start_tutorial()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_after_reset("시작")


## 문제가 튜토리얼이면 단계 실행기를 만들고 첫 단계를 시작한다. 기술 버튼도 정한다.
func _start_tutorial() -> void:
	tutorial = null
	_tutorial_wait = false
	overlay.can_skip = false
	if overlay.has_list and route.course_slot == "tutorial" and not route.tutorial_steps.is_empty():
		tutorial = TutorialRunner.new(route)
		tutorial.begin_step(session)
		overlay.can_skip = route.route_id == Progress.BASIC_TUTORIAL and game.progress.is_first_run()
	overlay.tutorial = tutorial
	overlay.tutorial_done = false
	_refresh_buttons()


func _refresh_buttons() -> void:
	if overlay.has_list:
		allowed_buttons = game.allowed_buttons_for(route, tutorial)


## 튜토리얼 단계 규칙(피로 감소 끄기·시작 체력)을 기본값으로 되돌린다.
func _end_tutorial_rules() -> void:
	session.rules.fatigue_disabled = false
	for hand in [PoseSolver.LH, PoseSolver.RH]:
		session.rules.stamina[hand] = 100.0


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
	session.reset()
	_after_reset(reason)


## 세션이 다시 시작된 뒤 표시 쪽 정리(입력 초기화·카메라·문구).
func _after_reset(reason: String) -> void:
	_close_ui()
	router.cancel_all()
	cam_y = session.body.pos.y + 0.12 * PLAY_H
	_flash(reason)


func _flash(text: String) -> void:
	message = text
	message_ticks = 120


func _log(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > 6:
		log_lines.remove_at(0)


# ---------- 입력 ----------

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and _overlay_event(event.index, event.position, event.pressed):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and _overlay_event(-1, event.position, event.pressed):
		return
	if event is InputEventScreenTouch:
		if event.canceled:
			_apply(router.cancel_all())
			return
		if paused:
			if not event.pressed and prepare_left <= 0.0:
				prepare_left = 3.0
			return
		if session.falling:
			return
		if _ui_event(event.index, event.position, event.pressed):
			return
		if event.pressed:
			var limb := router._pad_at(event.position)
			var attached_now: bool = limb != &"" and session.limbs[limb].state == "Attached"
			_apply(router.touch_down(event.index, event.position, attached_now))
		else:
			_apply(router.touch_up(event.index))
	elif event is InputEventScreenDrag and not paused and not session.falling:
		if session.selecting:
			_ui_drag(event.index, event.position)
			return
		_apply(router.touch_drag(event.index, event.position))
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not paused and not session.falling:
		_ui_event(-1, event.position, event.pressed)  # 데스크톱 시험: 마우스는 기술 UI만
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and session.selecting:
		_ui_drag(-1, event.position)


## 오버레이 버튼(일시정지·목록·다시·다음·도움말·건너뛰기). 결과·완료 화면이 떠 있으면 모든 입력을 받아 쓴다.
func _overlay_event(index: int, pos: Vector2, pressed: bool) -> bool:
	if not pressed:
		if _swallow.has(index):
			_swallow.erase(index)
			return true
		return overlay.blocking()
	var act := overlay.tap(pos)
	if act == "":
		return overlay.blocking()
	_swallow[index] = true
	_overlay_action(act)
	return true


func _overlay_action(act: String) -> void:
	match act:
		"pause":
			_pause(true)
		"help":
			overlay.help_open = not overlay.help_open
		"retry":
			_retry()
		"next":
			game.play(str(overlay.result.next))
		"list":
			_end_tutorial_rules()
			if overlay.can_skip and overlay.tutorial_done:
				game.home({"tab": "general", "grade": "V0"})  # 첫 실행 기본 조작 직후는 일반 탭(28 §5.2)
			else:
				game.home()
		"skip":
			_end_tutorial_rules()
			game.skip_basic()
			game.home({"tab": "general", "grade": "V0"})


## 같은 문제를 처음부터(시간·추락 새로 셈, 튜토리얼은 첫 단계부터).
func _retry() -> void:
	overlay.result = {}
	paused = false
	_end_tutorial_rules()
	session.reset()
	run_seconds = 0.0
	run_falls_from = session.falls
	_start_tutorial()
	_after_reset("다시 시작")


func _apply(cmds: Array) -> void:
	var was_dragging := {}
	for c in cmds:
		was_dragging[c.limb] = session.limbs[c.limb].state == "Dragging"
	session.apply_input(cmds)
	for c in cmds:
		if c.type == "release" and was_dragging[c.limb] and session.limbs[c.limb].state == "Attached" and OS.has_feature("mobile"):
			Input.vibrate_handheld(20)
	_take_messages()


## 세션이 쌓은 안내 문구를 화면 문구로 옮기고 비운다.
func _take_messages() -> void:
	for m in session.messages:
		_flash(m)
	session.messages.clear()


# ---------- 고정 틱 ----------

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		_pause()


func _pause(manual := false) -> void:
	if paused or overlay.blocking() or (not manual and OS.get_cmdline_user_args().has("--no-auto-pause")):
		return
	_close_ui()
	_apply(router.cancel_all())
	paused = true
	prepare_left = 0.0


func _physics_process(_delta: float) -> void:
	if message_ticks > 0:
		message_ticks -= 1
	if ui_mode == UI.PANEL:
		_check_timer -= _delta
		if _check_timer <= 0.0:
			_refresh_dim()
	if paused:
		if prepare_left > 0.0:
			prepare_left -= _delta
			if prepare_left <= 0.0:
				paused = false
		queue_redraw()
		return
	if overlay.blocking():
		queue_redraw()
		return
	var result := session.step()
	_take_messages()
	run_seconds += Tuning.DT
	if tutorial != null and _tutorial_tick(result):
		queue_redraw()
		return
	match result:
		"fall:NO_SUPPORT":
			_apply(router.cancel_all())
			_flash("지지를 잃었어요")
			queue_redraw()
			return
		"fall:BALANCE_LOST", "fall:DEADPOINT_MISS":
			_apply(router.cancel_all())
			_flash("균형을 잃었어요")
			queue_redraw()
			return
		"unresolved":
			_log("힘 계산 실패: 일시정지")
			_pause()
			return
		"respawn":
			_after_reset("떨어졌어요. 처음부터")
			queue_redraw()
			return
		"clear":
			_log("완등 %d회" % session.clears)
			_after_reset("")
			_show_result()
			queue_redraw()
			return
	if session.falling:
		queue_redraw()
		return
	if not session.selecting:
		_camera_tick()  # 고르는 중에는 카메라도 멈춘다
	queue_redraw()


## 튜토리얼 단계 진행(28 §6.1). 추락 뒤 다시 시작은 추락 연출이 끝난 respawn에서 한다. 처리했으면 true.
func _tutorial_tick(result: String) -> bool:
	if _tutorial_wait:
		if result != "respawn":
			return false
		_tutorial_wait = false
		tutorial.begin_step(session)
		_refresh_buttons()
		_after_reset("이 단계를 다시 해 봐요")
		return true
	var act := tutorial.observe(session, result, Tuning.DT)
	match act:
		"next", "restart":
			if result.begins_with("fall:"):
				_tutorial_wait = true
				return false
			tutorial.begin_step(session)
			_refresh_buttons()
			_after_reset("" if act == "next" else "이 단계를 다시 해 봐요")
			return true
		"done":
			_end_tutorial_rules()
			overlay.tutorial_done = true
			if overlay.has_list:
				game.finish_tutorial()
			_after_reset("")
			return true
	if result == "clear":  # 목표가 완등이 아닌 단계에서 정상을 잡음: 세션이 처음으로 돌아갔으니 그 단계를 다시 놓는다
		tutorial.begin_step(session)
		_after_reset("")
		return true
	return false


## 완등 결과 오버레이(28 §5). Game이 있으면 기록·저장하고 [다음]을 정한다.
func _show_result() -> void:
	var falls := session.falls - run_falls_from
	var r := {"seconds": run_seconds, "falls": falls, "no_fall": falls == 0, "time_limit": route.time_medal_seconds,
		"time": route.time_medal_seconds > 0.0 and run_seconds <= route.time_medal_seconds, "next": "", "saved": true}
	if overlay.has_list:
		var rec: Dictionary = game.finish_clear(run_seconds, falls)
		r.saved = rec.get("saved", true)
		var flow: PlayFlow = game.get_flow()
		var nid := flow.next_route_id(route.route_id)
		if nid != "" and game.progress.route_lock_text(game.index.route(nid), game.index) == "":
			r.next = nid
	overlay.result = r
	run_seconds = 0.0
	run_falls_from = session.falls


func _camera_tick() -> void:
	var screen_frac := 0.5 - (session.body.pos.y - cam_y) * px_per_m / get_viewport_rect().size.y
	if screen_frac < 0.50 or screen_frac > 0.68:
		var goal := session.body.pos.y + 0.12 * PLAY_H
		cam_y += clampf((goal - cam_y) * 8.0 * Tuning.DT, -2.0 * Tuning.DT, 2.0 * Tuning.DT)


# ---------- 그리기 ----------

func w2s(p: Vector2) -> Vector2:
	if w2s_fn.is_valid():
		return w2s_fn.call(p)
	return _w2s_2d(p)


func s2w(s: Vector2) -> Vector2:
	if s2w_fn.is_valid():
		return s2w_fn.call(s)
	var q := (s - wall_origin) / px_per_m
	return Vector2(q.x, cam_y - q.y)


func _w2s_2d(p: Vector2) -> Vector2:
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
	for limb in session.limbs:
		if session.limbs[limb].state == "Dragging":
			var c: Dictionary = session.limbs[limb].cand
			if not c.is_empty():
				draw_arc(w2s(c.point), 0.11 * px_per_m, 0, TAU, 24, Color("fff2c8"), 3.0)
			var j := PoseSolver.joint_position(session.body.pos, session.body.angle, limb, session.body.yaw)
			draw_arc(w2s(j), PoseSolver.reach_of(limb).y * px_per_m, 0, TAU, 64, Color(1, 1, 1, 0.15), 1.5)
	_draw_body()
	_draw_pads(size)
	_draw_hud(size)


func _draw_body() -> void:
	var pel := w2s(session.body.pos)
	var neck := w2s(session.body.pos + Vector2(0, 0.62).rotated(deg_to_rad(session.body.angle)))
	var ink := Color("302820")
	draw_line(pel, neck, Color("4f6a68"), 0.22 * px_per_m)
	draw_circle(w2s(session.body.pos + Vector2(0, 0.78).rotated(deg_to_rad(session.body.angle))), 0.12 * px_per_m, Color("c7b79b"))
	for limb in session.limbs:
		var j := PoseSolver.joint_position(session.body.pos, session.body.angle, limb, session.body.yaw)
		var e: Vector2 = session.limbs[limb].pos
		var hand := PoseSolver.is_hand(limb)
		var a := Tuning.ARM_UPPER if hand else Tuning.LEG_UPPER
		var b := Tuning.ARM_LOWER if hand else Tuning.LEG_LOWER
		var side := -1.0 if limb in [&"LH", &"LF"] else 1.0
		var mid := _two_bone(j, e, a, b, side if hand else side)
		var col: Color = LIMB_COLORS[limb]
		draw_line(w2s(j), w2s(mid), col, 0.07 * px_per_m)
		draw_line(w2s(mid), w2s(e), col, 0.06 * px_per_m)
		var state: String = session.limbs[limb].state
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
			var s: float = session.rules.stamina[limb]
			draw_arc(p.center, p.radius + 8 * ui_k, -PI / 2, -PI / 2 + TAU * s / 100.0, 48, Color("f1d59a") if s > 25 else Color("ff5a4a"), 6.0 * ui_k)


func _draw_hud(size: Vector2) -> void:
	var fs := int(22 * ui_k)
	var height := maxf(session.body.pos.y - route.start_pelvis.y, 0.0)
	draw_string(font, Vector2(size.x * 0.25, 40 * ui_k), "%s · 높이 %.1fm · 추락 %d" % [route.name_ko if route.name_ko != "" else route.route_id, height, session.falls - run_falls_from], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	# 지지 상태(docs/25 피드백): 색만이 아니라 문구와 막대로 표시
	var names := ["안정", "부담 큼", "균형 회복 중", "지지 없음"]
	var colors := [Color("cfe3c8"), Color("f1d59a"), Color("ff8a6a"), Color("ff5a4a")]
	var ph: int = session.rules.phase
	var status := "지지: %s" % names[ph]
	var hu: Dictionary = session.rules.last.get("u", {})
	status += " · 손 하중 L%d%% R%d%%" % [roundi(hu.get(&"LH", 0.0) * 100), roundi(hu.get(&"RH", 0.0) * 100)]
	draw_rect(Rect2(Vector2(size.x * 0.25 - 6 * ui_k, 50 * ui_k), Vector2(size.x * 0.5 + 12 * ui_k, 26 * ui_k)), Color(0.16, 0.18, 0.17, 0.6))
	status += " · 무브: %s" % session.rules.moves.korean()
	if not session.rules.flag_ready.is_empty():
		status += " · 놓으면 균형 발"
	draw_string(font, Vector2(size.x * 0.25, 70 * ui_k), status, HORIZONTAL_ALIGNMENT_LEFT, -1, int(21 * ui_k), colors[ph])
	if ph == ClimbRules.Phase.REBALANCING or ph == ClimbRules.Phase.GRACE:
		var budget := ClimbRules.IMBALANCE_BUDGET_TICKS if ph == ClimbRules.Phase.REBALANCING else Tuning.UNSUPPORTED_GRACE_TICKS
		var used := session.rules.imbalance_ticks if ph == ClimbRules.Phase.REBALANCING else session.rules.unsupported_ticks
		var w := 220.0 * ui_k
		var left := clampf(1.0 - float(used) / budget, 0.0, 1.0)
		draw_rect(Rect2(Vector2(size.x * 0.25, 80 * ui_k), Vector2(w, 8 * ui_k)), Color(0, 0, 0, 0.4))
		draw_rect(Rect2(Vector2(size.x * 0.25, 80 * ui_k), Vector2(w * left, 8 * ui_k)), colors[ph])
	var y := size.y - 20 * ui_k
	for i in range(log_lines.size() - 1, -1, -1):
		if tutorial != null:
			break  # 튜토리얼 중에는 시험 기록 줄을 숨긴다
		draw_string(font, Vector2(size.x * 0.25, y), log_lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * ui_k), Color(1, 1, 1, 0.6))
		y -= 18 * ui_k
	if message_ticks > 0:
		draw_string(font, Vector2(0, size.y * (0.30 if session.selecting or tutorial != null else 0.18)), message, HORIZONTAL_ALIGNMENT_CENTER, size.x, int(34 * ui_k), Color("fff2c8"))
	_draw_tech_ui(size)
	if paused:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
		var t := "손가락을 편하게 올려주세요 %d" % ceili(prepare_left) if prepare_left > 0.0 else "일시정지 · 화면을 탭하면 3초 뒤 이어서 시작해요"
		draw_string(font, Vector2(0, size.y * 0.5), t, HORIZONTAL_ALIGNMENT_CENTER, size.x, int(34 * ui_k), Color.WHITE)
	overlay.draw(self, size, ui_k, paused, session.selecting)


# ---------- 기술 선택 UI (docs/27 §6, 05 v0.6, 18 v0.6) ----------

func _close_ui() -> void:
	if session != null and session.selecting:
		session.close_select()
	ui_mode = UI.NONE
	hold_targets = []
	preview = {}
	_hold_index = -2


func _cancel_select(with_message: bool) -> void:
	_close_ui()
	if with_message:
		_flash("기술을 취소했어요")


func _view_size() -> Vector2:
	return get_viewport_rect().size


func _btn_rect(size: Vector2) -> Rect2:
	var w := 240.0 * ui_k
	return Rect2(Vector2(size.x * 0.5 - w * 0.5, 94.0 * ui_k), Vector2(w, 44.0 * ui_k))


func _panel_rect(size: Vector2) -> Rect2:
	var b := _btn_rect(size)
	var rows := maxi(1, ceili(float(_panel_techs().size()) / ENTRY_COLS))
	return Rect2(Vector2(size.x * 0.5 - 400.0 * ui_k, b.end.y + 8.0 * ui_k), Vector2(800.0 * ui_k, rows * 64.0 * ui_k + 12.0 * ui_k))


func _entry_rect(size: Vector2, i: int) -> Rect2:
	var p := _panel_rect(size)
	var cw := (776.0 - 24.0) / ENTRY_COLS
	return Rect2(p.position + Vector2((12.0 + (i % ENTRY_COLS) * (cw + 8.0)) * ui_k, (10.0 + (i / ENTRY_COLS) * 64.0) * ui_k), Vector2(cw, 56.0) * ui_k)


## 쪽 버튼: 왼쪽은 LH·LF 패드 사이, 오른쪽은 RH·RF 패드 사이.
func _side_rect(side: StringName) -> Rect2:
	var a: Vector2 = router.pads[&"LH" if side == &"left" else &"RH"].center
	var b: Vector2 = router.pads[&"LF" if side == &"left" else &"RF"].center
	var sz := Vector2(150.0, 76.0) * ui_k
	return Rect2((a + b) * 0.5 - sz * 0.5, sz)


## 패널에 그릴 기술 id 목록(allowed 순서, 정의가 있는 버튼 기술만).
static func panel_techs_for(allowed: Array[StringName], defs: Dictionary) -> Array:
	var out := []
	for id in allowed:
		if defs.has(id) and defs[id].input == &"button":
			out.append(id)
	return out


## 기술 버튼을 보이고 받을지(28 §5.5). 버튼 기술이 하나도 없으면 숨긴다.
static func shows_tech_button(allowed: Array[StringName], defs: Dictionary) -> bool:
	return not panel_techs_for(allowed, defs).is_empty()


func _panel_techs() -> Array:
	return panel_techs_for(allowed_buttons, _techs)


## 가벼운 검사(0.2초마다): 두 쪽 다 안 되면 흐리게. 흐려도 누를 수는 있다.
func _refresh_dim() -> void:
	_check_timer = CHECK_INTERVAL
	var snap := ClimbSnapshot.from_session(session)
	for id in _panel_techs():
		var j := TechniqueJudge.light_judge(snap, id)
		dim[id] = not j.values().any(func(r): return r.available)


## 기술 UI 입력. 선택 중이면 항상 받아 쓴다(패드 입력 없음). 쓴 입력이면 true.
func _ui_event(index: int, pos: Vector2, pressed: bool) -> bool:
	if not shows_tech_button(allowed_buttons, _techs):
		return false  # 버튼 기술이 없으면 기술 버튼·홀드 탭 입력을 받지 않는다
	var size := _view_size()
	var btn := _btn_rect(size)
	if not session.selecting:
		if pressed and btn.has_point(pos):
			if session.cancel_technique():  # 실행 중이면 버튼은 "풀기"
				_flash("기술을 취소했어요")
			else:
				_open_select()
			return true
		return false
	if pressed and btn.has_point(pos):
		_cancel_select(ui_mode != UI.PANEL)  # 같은 버튼: 닫기(시간 재개)
		return true
	if ui_mode == UI.HOLD:
		if pressed:
			_hold_index = index
			_hold_preview(pos)
		elif index == _hold_index:
			_hold_index = -2
			_hold_commit(pos)
		return true
	if not pressed:
		return true
	if router._pad_at(pos) != &"":
		return true  # 패드는 선택 중 입력을 받지 않는다
	match ui_mode:
		UI.PANEL:
			_panel_tap(size, pos)
		UI.SIDE:
			_side_tap(pos)
	return true


func _ui_drag(index: int, pos: Vector2) -> void:
	if ui_mode == UI.HOLD and index == _hold_index:
		_hold_preview(pos)


func _open_select() -> void:
	if session.is_dragging() or not session.runner.active.is_empty() or session.falling or not session.deadpoint.is_empty():
		return
	if session.open_select():
		_apply(router.cancel_all())  # 입력 세대 증가, 눌러 둔 터치 정리
		ui_mode = UI.PANEL
		_refresh_dim()


func _panel_tap(size: Vector2, pos: Vector2) -> void:
	var ids := _panel_techs()
	for i in ids.size():
		if _entry_rect(size, i).has_point(pos):
			_pick_tech(ids[i])
			return
	if not _panel_rect(size).has_point(pos):
		_cancel_select(false)  # 빈 벽 탭: 닫기


func _pick_tech(id: StringName) -> void:
	sel_tech = id
	side_judge = TechniqueJudge.judge(ClimbSnapshot.from_session(session), id)
	ui_mode = UI.SIDE


func _side_tap(pos: Vector2) -> void:
	for side in [&"left", &"right"]:
		if not _side_rect(side).has_point(pos):
			continue
		if not side_judge.has(side):
			continue
		var j: Dictionary = side_judge[side]
		if not j.available:
			_flash(j.text if not j.text.is_empty() else String(j.reason))  # 불가능: 이유 한 줄
			return
		if TechniqueJudge.uses_hold(sel_tech):
			sel_side = side
			hold_targets = TechniqueJudge.hold_targets(ClimbSnapshot.from_session(session), sel_tech, side)
			preview = {}
			ui_mode = UI.HOLD
		else:
			_start_technique(side, "", Vector2.INF)
		return
	_cancel_select(true)  # 빈 벽 탭: 취소


func _start_technique(side: StringName, key: String, point: Vector2) -> void:
	var r := session.choose(sel_tech, side, key, point)
	if r != &"":
		var text := TechniqueJudge.text_for(r)
		_flash(text if not text.is_empty() else String(r))
		return
	_close_ui()


## 탭 위치에서 가장 가까운 홀드 슬롯 키(영역 선분까지 거리 HOLD_PICK_RADIUS 이내). 없으면 "".
func _slot_at(p: Vector2) -> String:
	var best := ""
	var best_d := HOLD_PICK_RADIUS
	var limb := TechniqueJudge.limb_for(sel_tech, sel_side)
	for key in route.slots:
		var seg := _area_segment(route.slots[key], PoseSolver.is_hand(limb))
		var d := _dist_to_segment(p, seg[0], seg[1])
		if d < best_d or (is_equal_approx(d, best_d) and best == ""):
			best = key
			best_d = d
	return best


## 홀드의 잡기/디딤 영역 선분 [a, b]. 손 기술은 hand_area, 발 기술은 foot_area(없으면 한 점).
func _area_segment(slot: Dictionary, hand: bool) -> Array:
	if hand and slot.has("hand_area"):
		return [slot.pos - slot.hand_area.dir * slot.hand_area.half_width, slot.pos + slot.hand_area.dir * slot.hand_area.half_width]
	if not hand and slot.has("foot_area"):
		return [slot.pos - slot.foot_area.up * slot.foot_area.half_height, slot.pos + slot.foot_area.up * slot.foot_area.half_height]
	return [slot.pos, slot.pos]


func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := 0.0 if ab.length_squared() < 0.000001 else clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _hold_preview(pos: Vector2) -> void:
	var p := s2w(pos)
	var key := _slot_at(p)
	if key.is_empty():
		preview = {}
		return
	var c := TechniqueJudge.check_hold(ClimbSnapshot.from_session(session), sel_tech, sel_side, key, p)
	preview = {"key": key, "ok": c.ok, "point": c.point if c.ok else p, "quality": c.quality, "text": c.text}


func _hold_commit(pos: Vector2) -> void:
	var p := s2w(pos)
	preview = {}
	var key := _slot_at(p)
	if key.is_empty():
		_cancel_select(true)  # 빈 벽 탭: 취소
		return
	var c := TechniqueJudge.check_hold(ClimbSnapshot.from_session(session), sel_tech, sel_side, key, p)
	if not c.ok:
		_flash(c.text if not c.text.is_empty() else String(c.reason))  # 후보가 아닌 홀드: 이유
		return
	_start_technique(sel_side, key, p)


func _quality_label(q: float) -> String:
	return "잘 잡음" if q >= 0.85 else ("보통" if q >= 0.5 else "끝을 잡음")


func _quality_color(q: float) -> Color:
	return Color("b8e0a0") if q >= 0.85 else (Color("f1d59a") if q >= 0.5 else Color("ff9a6a"))


## 색과 함께 모양으로도 구분: 좋음 = 동그라미, 보통 = 마름모, 끝 = 삼각형.
func _draw_quality_glyph(c: Vector2, q: float, r: float) -> void:
	var col := _quality_color(q)
	var ink := Color("302820")
	var pts := PackedVector2Array()
	if q >= 0.85:
		draw_circle(c, r, col)
		draw_arc(c, r, 0, TAU, 20, ink, 2.0)
		return
	if q >= 0.5:
		pts = PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
	else:
		pts = PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, r), c + Vector2(-r, r)])
	draw_colored_polygon(pts, col)
	pts.append(pts[0])
	draw_polyline(pts, ink, 2.0)


func _draw_lock(c: Vector2, k: float, col: Color) -> void:
	draw_arc(c + Vector2(0, -4 * k), 5 * k, PI, TAU, 10, col, 2.0 * k)
	draw_rect(Rect2(c + Vector2(-7, -4) * k, Vector2(14, 11) * k), col)


func _draw_button(r: Rect2, text: String, fs: int, fill: Color, text_col: Color, outline: Color = Color(1, 1, 1, 0.5)) -> void:
	draw_rect(r, fill)
	draw_rect(r, outline, false, 2.0)
	draw_string(font, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + fs * 0.35), text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, text_col)


func _screen_r(p: Vector2, meters: float) -> float:
	return w2s(p).distance_to(w2s(p + Vector2(meters, 0)))


func _draw_tech_ui(size: Vector2) -> void:
	var k := ui_k
	var btn := _btn_rect(size)
	var running: Dictionary = session.runner.active
	if session.deadpoint_window() and not session.falling and running.is_empty() and not session.selecting:
		draw_string(font, Vector2(btn.position.x - 60 * k, btn.end.y + 24 * k), "지금 뻗으면 탄력으로 잡을 수 있어요", HORIZONTAL_ALIGNMENT_CENTER, btn.size.x + 120 * k, int(18 * k), Color("a8d8d0"))
	if not shows_tech_button(allowed_buttons, _techs):
		return  # 버튼 기술이 없으면 기술 버튼을 그리지 않는다
	var disabled := (session.is_dragging() or session.falling) and running.is_empty()
	var label := "기술"
	if not running.is_empty():
		var stage: String = STAGE_TEXT.get(running.step, "")
		label = "풀기 · %s" % _techs[running.id].name_ko  # 실행 중 같은 버튼은 풀기(27 §6 5)
		if not stage.is_empty():
			label += " · " + stage
	var open := session.selecting
	_draw_button(btn, label, int(20 * k), Color("f1d59a", 0.9) if open else Color(0.1, 0.1, 0.1, 0.6 if not disabled else 0.35),
		Color("302820") if open else Color(1, 1, 1, 0.45 if disabled else 1.0))
	if session.is_dragging() and running.is_empty():
		_draw_lock(btn.position + Vector2(btn.size.x - 20 * k, btn.size.y * 0.5), k, Color(1, 1, 1, 0.5))
	if not open:
		return
	draw_string(font, Vector2(btn.end.x + 14 * k, btn.position.y + btn.size.y * 0.5 + 8 * k), "고르는 중 · 시간 멈춤", HORIZONTAL_ALIGNMENT_LEFT, -1, int(24 * k), Color("fff2c8"))
	match ui_mode:
		UI.PANEL:
			_draw_panel(size)
		UI.SIDE:
			_draw_prompt(btn, "%s · 쪽을 골라 주세요" % _techs[sel_tech].name_ko)
			for side in [&"left", &"right"]:
				if side_judge.has(side):
					_draw_side_button(side)
		UI.HOLD:
			_draw_prompt(btn, "%s · 쓸 홀드를 눌러 주세요" % _techs[sel_tech].name_ko)
			_draw_hold_select(size)


func _draw_prompt(btn: Rect2, text: String) -> void:
	draw_string(font, Vector2(btn.position.x - 160 * ui_k, btn.end.y + 30 * ui_k), text, HORIZONTAL_ALIGNMENT_CENTER, btn.size.x + 320 * ui_k, int(24 * ui_k), Color.WHITE)


func _draw_panel(size: Vector2) -> void:
	var k := ui_k
	draw_rect(_panel_rect(size), Color(0.08, 0.07, 0.06, 0.7))
	var ids := _panel_techs()
	for i in ids.size():
		var r := _entry_rect(size, i)
		var is_dim: bool = dim.get(ids[i], false)
		_draw_button(r, _techs[ids[i]].name_ko, int(19 * k), Color(0.18, 0.2, 0.2, 0.35 if is_dim else 0.9), Color(1, 1, 1, 0.5 if is_dim else 1.0), Color(1, 1, 1, 0.25 if is_dim else 0.6))
		if is_dim:
			_draw_lock(r.position + Vector2(r.size.x - 14 * k, 14 * k), k * 0.8, Color(1, 1, 1, 0.6))  # 색 말고 아이콘으로도 표시


func _draw_side_button(side: StringName) -> void:
	var k := ui_k
	var r := _side_rect(side)
	var j: Dictionary = side_judge[side]
	var ok: bool = j.available
	_draw_button(r, "왼쪽" if side == &"left" else "오른쪽", int(26 * k), Color("4fa3d9" if side == &"left" else "e08a3c", 0.9 if ok else 0.25),
		Color(1, 1, 1, 1.0 if ok else 0.5), Color(1, 1, 1, 0.9 if ok else 0.3))
	if not ok:
		_draw_lock(r.position + Vector2(r.size.x * 0.5, r.size.y - 16 * k), k, Color(1, 1, 1, 0.75))


func _draw_dashed_circle(c: Vector2, r: float, col: Color, width: float) -> void:
	var n := 12
	for i in n:
		var a0 := TAU * i / n
		draw_arc(c, r, a0, a0 + TAU / n * 0.55, 6, col, width)


func _draw_hold_select(size: Vector2) -> void:
	var k := ui_k
	var hand := PoseSolver.is_hand(TechniqueJudge.limb_for(sel_tech, sel_side))
	var solid := Color("fff2c8")
	var shift := Color("a8d8d0")
	for t in hold_targets:
		var slot: Dictionary = route.slots[t.key]
		var col := shift if t.needs_shift else solid
		var c := w2s(slot.pos)
		var rr := _screen_r(slot.pos, 0.11)
		var ink := Color(0.19, 0.16, 0.13, 0.85)  # 밝은 벽에서도 보이게 어두운 밑선을 깐다
		draw_arc(c, rr, 0, TAU, 28, ink, 7.0 * k)
		if t.needs_shift:
			_draw_dashed_circle(c, rr, col, 4.0 * k)  # 점선 = 체중을 옮긴 뒤 도달
		else:
			draw_arc(c, rr, 0, TAU, 28, col, 4.0 * k)  # 실선 = 지금 바로
		var seg := _area_segment(slot, hand)
		var a := w2s(seg[0])
		var b := w2s(seg[1])
		if hand:
			draw_line(a, b, ink, 9.0 * k)
			draw_line(a, b, Color(col, 0.95), 5.0 * k)  # 잡기 영역 선분
			for e in [a, b]:
				draw_circle(e, 4.0 * k, col)
		else:
			var n := (b - a).orthogonal().normalized() * _screen_r(slot.pos, 0.05)  # 디딤 면
			draw_colored_polygon(PackedVector2Array([a + n, b + n, b - n, a - n]), Color(col, 0.45))
			draw_polyline(PackedVector2Array([a + n, b + n, b - n, a - n, a + n]), ink, 5.0 * k)
			draw_polyline(PackedVector2Array([a + n, b + n, b - n, a - n, a + n]), col, 2.5 * k)
	draw_string(font, Vector2(0, size.y - 52 * k), "실선 = 바로 가능 · 점선 = 몸을 옮겨야 닿아요", HORIZONTAL_ALIGNMENT_CENTER, size.x, int(18 * k), Color(1, 1, 1, 0.8))
	if preview.is_empty():
		return
	var pc := w2s(preview.point)
	if preview.ok:
		_draw_quality_glyph(pc, preview.quality, 11.0 * k)
		var qp := pc + Vector2(-70 * k, -20 * k)
		draw_string_outline(font, qp, _quality_label(preview.quality), HORIZONTAL_ALIGNMENT_CENTER, 140 * k, int(20 * k), 6, Color("302820"))
		draw_string(font, qp, _quality_label(preview.quality), HORIZONTAL_ALIGNMENT_CENTER, 140 * k, int(20 * k), _quality_color(preview.quality))
	else:
		draw_line(pc + Vector2(-8, -8) * k, pc + Vector2(8, 8) * k, Color("ff8a6a"), 3.0 * k)
		draw_line(pc + Vector2(-8, 8) * k, pc + Vector2(8, -8) * k, Color("ff8a6a"), 3.0 * k)
		draw_string(font, pc + Vector2(-140 * k, -20 * k), preview.text, HORIZONTAL_ALIGNMENT_CENTER, 280 * k, int(18 * k), Color("ff8a6a"))
