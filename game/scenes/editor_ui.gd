extends Node2D
## 문제 만들기 화면 UI(작업 6 §2, docs/superpowers/specs/2026-11-19-6-editor-design.md). 휴대폰 가로 기준.
## 위 줄: 나가기 · 이름 · 예상 등급 · 되돌리기 · 올라 보기 · 봇 검사 · 저장. 왼쪽: 도구. 가운데: 3D 벽(EditorView). 오른쪽: 홀드 목록·고른 홀드.
## 아래: 홀드 수·높이·막는 것. 초안(RouteDraft)을 고치고, 고칠 때마다 3D를 다시 만들고 저장 상태·막는 것을 다시 센다.

const CREAM := Color("f1d59a")
const INK := Color("302820")
const PANEL := Color(0.12, 0.11, 0.10, 0.88)
const DIM := Color(1, 1, 1, 0.6)
const RED := Color(1.0, 0.3, 0.25)
const TOOLS := [["place", "놓기"], ["move", "옮기기"], ["rotate", "돌리기"], ["erase", "지우기"], ["start", "시작 지정"]]
const LIMB_NAMES := {&"LH": "왼손", &"RH": "오른손", &"LF": "왼발", &"RF": "오른발"}
const LIST := {"hand": ["jug", "crimp", "sloper", "pinch", "pocket"], "foot": ["foot_chip", "foot_big"], "goal": ["goal"]}
const PICK_R := 0.13      # 홀드를 누른 것으로 보는 거리(m)
const DRAG_PX := 14.0     # 이보다 움직이면 누르기가 아니라 끌기

var view                  # EditorView
var game: Node
var font: Font
var k := 1.0
var draft: RouteDraft
var tool := "place"
var start_limb: StringName = &"LH"
var list_tab := "hand"
var sel_type := "jug"
var selected := ""
var message := ""
var _message_t := 0.0
var _problems: Array = []
var _bad: Array = []
var _buttons: Array = []
var _name_edit: LineEdit
var _touches := {}        # index → 위치
var _press := {}          # {pos, hold, wall(Vector2), moved}
var _pinch_d := 0.0
var _bot_thread: Thread
var _bot_result := {}
var share_open := false   # 저장·공유 창
var share_busy := false
var share_code := ""


func _ready() -> void:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Noto Sans CJK KR", "Noto Sans KR", "Apple SD Gothic Neo", "sans-serif"])
	font = sf
	game = get_node_or_null("/root/Game")
	var id: String = game.editing_route_id if game != null else ""
	draft = MyRoutes.load_draft(id) if id != "" else null
	if draft == null:
		draft = RouteDraft.new()
		draft.route_id = id if id != "" else MyRoutes.new_id()
		draft.name = ""
		if game != null:
			game.editing_route_id = draft.route_id
	elif game != null and (game.progress.cleared.has(draft.route_id) or game.get_flow().is_published(draft.route_id)):
		draft.freeze()  # 완등·올린 판을 고치면 새 판(§3)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "문제 이름"
	_name_edit.max_length = RouteDraft.NAME_MAX
	_name_edit.text = draft.name
	_name_edit.text_changed.connect(func(t: String) -> void:
		draft.set_name(t)
		_changed(false))
	add_child(_name_edit)
	get_viewport().size_changed.connect(_layout)
	_layout()
	await get_tree().process_frame
	if view != null:
		view.logic.cam_y = 1.6
		view.rebuild(draft)
	_changed(false)


func _layout() -> void:
	var size := get_viewport_rect().size
	k = maxf(minf(size.x / 1600.0, size.y / 720.0), 0.3)
	_name_edit.position = Vector2(150, 10) * k
	_name_edit.size = Vector2(300, 52) * k
	_name_edit.add_theme_font_size_override("font_size", int(24 * k))
	queue_redraw()


## 고친 뒤: 3D를 다시 만들고(rebuild) 막는 것·간격 위반을 다시 센다.
func _changed(rebuild := true) -> void:
	if rebuild and view != null:
		view.rebuild(draft)
	_problems = draft.problems()
	_bad = draft.bad_holds()
	queue_redraw()


func _say(t: String) -> void:
	message = t
	_message_t = 3.0
	queue_redraw()


func _process(delta: float) -> void:
	if _message_t > 0.0:
		_message_t -= delta
		if _message_t <= 0.0:
			message = ""
			queue_redraw()
	if _bot_thread != null and not _bot_thread.is_alive():
		var res: Dictionary = _bot_thread.wait_to_finish()
		_bot_thread = null
		_say("깰 수 있어요(봇이 길을 찾았어요)" if res.get("ok", false) else "봇은 길을 못 찾았어요 — 직접 완등했다면 올릴 수 있어요")
	queue_redraw()


# ---------- 입력 ----------

func _wall_rect() -> Rect2:
	var size := get_viewport_rect().size
	return Rect2(Vector2(150 * k, 74 * k), Vector2(size.x - 530 * k, size.y - 74 * k - 46 * k))


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		# 폰 터치는 마우스로 바뀌지 않아(emulate_mouse_from_touch=false) 이름 칸이 눌림을 못 받는다: 직접 글쓰기를 시작·끝낸다.
		if event.pressed and _name_edit.get_global_rect().has_point(event.position):
			_name_edit.edit()
			return
		if event.pressed and _name_edit.has_focus():
			_name_edit.release_focus()
		if event.pressed:
			_touches[event.index] = event.position
			if _touches.size() == 1:
				_down(event.position)
			else:
				_press = {}
				_pinch_d = _pinch_dist()
		else:
			_touches.erase(event.index)
			if event.index == 0 or _touches.is_empty():
				_up(event.position)
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			var d := _pinch_dist()
			if _pinch_d > 0.0 and d > 0.0 and view != null:
				view.zoom_h = clampf(view.zoom_h * _pinch_d / d, view.ZOOM_MIN, view.ZOOM_MAX)
			_pinch_d = d
		else:
			_drag(event.position, event.relative)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_down(event.position)
			else:
				_up(event.position)
		elif event.pressed and view != null and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			view.zoom_h = clampf(view.zoom_h * (0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), view.ZOOM_MIN, view.ZOOM_MAX)
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_drag(event.position, event.relative)


func _pinch_dist() -> float:
	var ps: Array = _touches.values()
	return (ps[0] as Vector2).distance_to(ps[1]) if ps.size() >= 2 else 0.0


func _down(pos: Vector2) -> void:
	_press = {}
	if share_open or _hit_button(pos) >= 0 or not _wall_rect().has_point(pos) or view == null:
		return
	var w: Vector2 = view.screen_to_wall(pos)
	_press = {"pos": pos, "wall": w, "hold": _hold_at(w), "moved": false}


func _drag(pos: Vector2, rel: Vector2) -> void:
	if _press.is_empty():
		return
	if not _press.moved and pos.distance_to(_press.pos) > DRAG_PX * k:
		_press.moved = true
	if not _press.moved:
		return
	if tool == "move" and _press.hold != "":
		_press["to"] = view.screen_to_wall(pos)
		queue_redraw()
	elif tool == "rotate" and _press.hold != "":
		_press["rot"] = int(round((pos.x - _press.pos.x) / (6.0 * k)))
		queue_redraw()
	else:
		# 빈 벽을 끌면 위아래 이동
		var px_per_m: float = get_viewport_rect().size.y / view.zoom_h
		view.logic.cam_y = clampf(view.logic.cam_y + rel.y / px_per_m, 0.8, RouteDraft.WALL_H)


func _up(pos: Vector2) -> void:
	var b := _hit_button(pos)
	if b >= 0 and _press.is_empty():
		_do(_buttons[b].action, _buttons[b].arg)
		return
	if _press.is_empty():
		return
	var p := _press
	_press = {}
	if p.moved:
		if tool == "move" and p.hold != "" and p.has("to"):
			draft.move(p.hold, p.to.x, p.to.y)
			selected = p.hold
			_changed()
		elif tool == "rotate" and p.hold != "" and p.has("rot"):
			draft.rotate(p.hold, int(p.rot) * 5)
			selected = p.hold
			_changed()
		queue_redraw()
		return
	_tap_wall(p.wall, p.hold)


func _tap_wall(w: Vector2, hit: String) -> void:
	match tool:
		"place":
			if hit != "":
				selected = hit
			else:
				var id := draft.place(sel_type, w.x, w.y)
				if id == "":
					_say("홀드는 %d개까지 놓을 수 있어요" % RouteDraft.MAX_HOLDS)
				else:
					selected = id
					_changed()
		"move", "rotate":
			selected = hit
		"erase":
			if hit != "":
				draft.remove(hit)
				if selected == hit:
					selected = ""
				_changed()
		"start":
			if hit != "":
				if draft.set_start(start_limb, hit):
					_changed()
					var order := [&"LH", &"RH", &"LF", &"RF"]
					start_limb = order[(order.find(start_limb) + 1) % 4]
				else:
					_say("손 시작은 손홀드에만 정할 수 있어요")
	queue_redraw()


func _hold_at(w: Vector2) -> String:
	var best := ""
	var best_d := PICK_R
	for h in draft.holds:
		var d := w.distance_to(Vector2(h.x, h.y))
		if d < best_d:
			best_d = d
			best = h.id
	return best


func _hit_button(pos: Vector2) -> int:
	for i in range(_buttons.size() - 1, -1, -1):
		if (_buttons[i].rect as Rect2).has_point(pos):
			return i
	return -1


func _do(action: String, arg: String) -> void:
	match action:
		"exit":
			if not draft.holds.is_empty():  # 빈 초안은 남기지 않는다
				MyRoutes.save(draft)
			if game != null:
				game.editing_route_id = ""
				game.home({"tab": "make"})
			return
		"undo":
			if draft.undo():
				_changed()
		"grade":
			var i := RouteDraft.GRADES.find(draft.grade) + int(arg)
			draft.grade = RouteDraft.GRADES[clampi(i, 0, RouteDraft.GRADES.size() - 1)]
		"tool":
			tool = arg
		"limb":
			start_limb = StringName(arg)
		"list":
			list_tab = arg
			sel_type = LIST[arg][0]
			tool = "place"
		"type":
			sel_type = arg
			tool = "place"
		"size":
			draft.set_size(selected, arg)
			_changed()
		"rot":
			draft.rotate(selected, int(arg))
			_changed()
		"match":
			draft.set_matchable(selected, not bool(draft.hold(selected).get("matchable", false)))
			_changed()
		"delete":
			draft.remove(selected)
			selected = ""
			_changed()
		"save":
			if not MyRoutes.save(draft):
				_say("저장하지 못했어요")
			else:
				share_open = true
				share_code = str(game.progress.shared.get(draft.route_id, {}).get("code", "")) if game != null else ""
		"share_close":
			share_open = false
		"publish":
			_publish(arg)
		"copy":
			DisplayServer.clipboard_set(share_code)
			_say("코드를 복사했어요")
		"climb":
			if not _problems.is_empty():
				_say(_problems[0])
			elif MyRoutes.save(draft) and game != null:
				game.play_custom(draft.route_id)
				return
		"bot":
			if not _problems.is_empty():
				_say(_problems[0])
			elif _bot_thread == null:
				var r := draft.build()
				_bot_thread = Thread.new()
				_bot_thread.start(func() -> Dictionary: return {"ok": PathExplorer.explore(r, {}, false, 5000).ok})
				_say("봇이 길을 찾는 중… (최대 5초)")
	queue_redraw()


## 올리기(§3·§4): 서버에 문제 JSON을 올리고 공유 코드를 받는다. vis: "link" 친구에게 코드로 / "public" 모두에게 공개.
func _publish(vis: String) -> void:
	if share_busy or game == null:
		return
	if not WordFilter.ok(draft.name):
		_say("문제 이름에 쓸 수 없는 말이 있어요")
		return
	share_busy = true
	queue_redraw()
	var flow = game.get_flow()
	var nick: String = flow.nickname()
	var data := draft.to_route_dict()
	var c: Dictionary = game.progress.cleared.get(draft.route_id, {})
	data["author_run"] = {"seconds": float(c.get("best_seconds", 0.0)), "score": c.get("best_score", -1), "version": draft.version}
	var d := draft
	var res: Dictionary = await game.share().rows(func(): return game.share().api.publish(d.route_id, d.name, nick, d.grade, data, d.version, vis))
	share_busy = false
	if not res.ok:
		_say(res.error)
		return
	var row: Dictionary = res.rows[0] if not res.rows.is_empty() else {}
	share_code = str(row.get("code", ""))
	flow.set_shared(draft.route_id, {"code": share_code, "id": str(row.get("id", "")), "visibility": vis, "version": draft.version})
	draft.freeze()
	_say("올렸어요! 코드 " + share_code)
	queue_redraw()


func _draw_share(size: Vector2) -> void:
	_buttons = []
	var box := Rect2(Vector2(size.x * 0.5 - 380 * k, size.y * 0.5 - 200 * k), Vector2(760, 400) * k)
	draw_rect(box, Color(0.1, 0.09, 0.08, 0.97))
	draw_rect(box, CREAM, false, 3.0)
	var x := box.position.x + 30 * k
	var y := box.position.y + 56 * k
	_text(Vector2(x, y), "이 기기에 저장했어요", 26, CREAM)
	y += 44 * k
	var can: bool = game != null and draft.can_publish(game.progress)
	if share_code != "":
		_text(Vector2(x, y), "공유 코드", 20, DIM)
		_text(Vector2(x, y + 64 * k), share_code, 56, Color.WHITE)
		_button(Rect2(Vector2(x + 330 * k, y + 14 * k), Vector2(150, 56) * k), "복사", "copy", "", 22)
		y += 100 * k
	if game == null or not game.share().enabled():
		_wrap(Vector2(x, y + 10 * k), "공유 서버가 아직 준비되지 않았어요. 만든 문제는 이 기기에서 계속 올라 볼 수 있어요.", 700 * k, 20, DIM)
	elif not can:
		var why: String = _problems[0] if not _problems.is_empty() else "직접 도움 없이 한 번 완등해야 올릴 수 있어요([올라 보기])"
		_wrap(Vector2(x, y + 10 * k), "아직 올릴 수 없어요: " + why, 700 * k, 20, Color(1, 0.75, 0.6))
	elif share_busy:
		_text(Vector2(x, y + 30 * k), "올리는 중…", 24, Color.WHITE)
	else:
		_button(Rect2(Vector2(x, y + 10 * k), Vector2(330, 64) * k), "친구에게 코드로", "publish", "link", 22)
		_button(Rect2(Vector2(x + 360 * k, y + 10 * k), Vector2(330, 64) * k), "모두에게 공개", "publish", "public", 22, true)
	_button(Rect2(Vector2(box.end.x - 180 * k, box.end.y - 76 * k), Vector2(150, 56) * k), "닫기", "share_close", "", 22)


# ---------- 그리기 ----------

func _draw() -> void:
	_buttons = []
	var size := get_viewport_rect().size
	if view == null:
		return
	_draw_wall_overlay(size)
	# 위 줄
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, 72 * k)), PANEL)
	_button(Rect2(Vector2(10, 10) * k, Vector2(130, 52) * k), "나가기", "exit", "")
	var gx := 470 * k
	_button(Rect2(Vector2(gx, 10 * k), Vector2(48, 52) * k), "◀", "grade", "-1")
	_text_c(Rect2(Vector2(gx + 48 * k, 10 * k), Vector2(110, 52) * k), "예상 " + draft.grade, 22, CREAM)
	_button(Rect2(Vector2(gx + 158 * k, 10 * k), Vector2(48, 52) * k), "▶", "grade", "1")
	var x := size.x - 10 * k
	for b in [["저장", "save", 120], ["봇 검사", "bot", 130], ["올라 보기", "climb", 150], ["되돌리기", "undo", 130]]:
		x -= b[2] * k
		_button(Rect2(Vector2(x, 10 * k), Vector2(b[2], 52) * k), b[0], b[1], "", 22, b[1] == "climb" and _problems.is_empty())
		x -= 10 * k
	_draw_tools(size)
	_draw_panel(size)
	# 아래 상태
	var top_y := 0.0
	for h in draft.holds:
		top_y = maxf(top_y, h.y)
	draw_rect(Rect2(Vector2(0, size.y - 44 * k), Vector2(size.x, 44 * k)), PANEL)
	var st := "홀드 %d/%d · 높이 %.1fm · 판 %d · " % [draft.holds.size(), RouteDraft.MAX_HOLDS, top_y, draft.version]
	st += "막는 것 없음 — 올라 볼 수 있어요" if _problems.is_empty() else _problems[0]
	_text(Vector2(16 * k, size.y - 14 * k), st, 19, CREAM if _problems.is_empty() else Color(1, 0.75, 0.6))
	if share_open:
		_draw_share(size)
	if message != "":
		var r := Rect2(Vector2(size.x * 0.5 - 330 * k, 90 * k), Vector2(660, 54) * k)
		draw_rect(r, Color(0, 0, 0, 0.8))
		_text_c(r, message, 22, Color.WHITE)


## 벽 위 표시: 편집 범위 선, 높이 눈금, 시작 자리 이름표, 탑, 간격 위반(빨강), 고른 홀드(노랑), 손홀드 잡는 방향.
func _draw_wall_overlay(_size: Vector2) -> void:
	var w2s: Callable = view.world_to_screen
	for sx in [-RouteDraft.WALL_HALF, RouteDraft.WALL_HALF]:
		draw_line(w2s.call(Vector2(sx, 0.0)), w2s.call(Vector2(sx, RouteDraft.WALL_H)), Color(1, 1, 1, 0.35), 2.0 * k)
	for i in range(0, 10):
		var y := i * 0.5
		var p: Vector2 = w2s.call(Vector2(-RouteDraft.WALL_HALF, y))
		draw_line(p, p + Vector2(-14 * k, 0), Color(1, 1, 1, 0.5), 2.0 * k)
		_text(p + Vector2(-60 * k, 6 * k), "%.1fm" % y, 15, Color(1, 1, 1, 0.65))
	var start_of := {}
	for l in draft.start:
		if draft.start[l] != "":
			start_of[draft.start[l]] = LIMB_NAMES[l]
	for h in draft.holds:
		var c: Vector2 = w2s.call(Vector2(h.x, h.y))
		var r: float = (view.world_to_screen(Vector2(h.x + 0.1, h.y)) - c).x
		if _bad.has(h.id):
			draw_arc(c, r * 1.2, 0, TAU, 32, RED, 4.0 * k)
		if h.id == selected:
			draw_arc(c, r * 1.35, 0, TAU, 32, CREAM, 3.0 * k)
		if start_of.has(h.id):
			_outlined(c + Vector2(-60 * k, -r * 1.3), start_of[h.id], 18, 120 * k)
		if h.type == "goal":
			_outlined(c + Vector2(-60 * k, -r * 1.6), "탑", 20, 120 * k)
		elif h.id == selected and RouteDraft.is_hand_type(h.type):
			# 잡는 힘 방향(손이 버티는 쪽): rot 0 = 위
			var axis := HoldTypes.rotate(Vector2(0, 1), h.rot)
			draw_line(c, c + Vector2(axis.x, -axis.y) * r * 1.6, CREAM, 3.0 * k)
	# 끌고 있는 홀드·돌리는 중 미리보기
	if _press.get("to") is Vector2:
		draw_arc(w2s.call(_press.to), 24 * k, 0, TAU, 32, CREAM, 3.0 * k)
	if _press.has("rot") and _press.hold != "":
		var h := draft.hold(_press.hold)
		_outlined(w2s.call(Vector2(h.x, h.y)) + Vector2(-60 * k, 40 * k), "%d°" % posmod(int(h.rot) + int(_press.rot) * 5, 360), 20, 120 * k)


func _draw_tools(size: Vector2) -> void:
	draw_rect(Rect2(Vector2(0, 72 * k), Vector2(140 * k, size.y - 116 * k)), PANEL)
	var y := 84 * k
	for t in TOOLS:
		_button(Rect2(Vector2(10 * k, y), Vector2(120, 52) * k), t[1], "tool", t[0], 20, tool == t[0])
		y += 60 * k
	if tool == "start":
		y += 6 * k
		for l in [&"LH", &"RH", &"LF", &"RF"]:
			var who: String = LIMB_NAMES[l] + (" ✓" if draft.start[l] != "" else "")
			_button(Rect2(Vector2(10 * k, y), Vector2(120, 44) * k), who, "limb", String(l), 18, start_limb == l)
			y += 50 * k


func _draw_panel(size: Vector2) -> void:
	var x := size.x - 370 * k
	var w := 360 * k
	draw_rect(Rect2(Vector2(x - 10 * k, 72 * k), Vector2(380 * k, size.y - 116 * k)), PANEL)
	var y := 84 * k
	var tw := (w - 20 * k) / 3.0
	for i in 3:
		var t: Array = [["hand", "손홀드"], ["foot", "발홀드"], ["goal", "탑"]][i]
		_button(Rect2(Vector2(x + i * (tw + 10 * k), y), Vector2(tw, 46 * k)), t[1], "list", t[0], 20, list_tab == t[0])
	y += 58 * k
	var cw := (w - 10 * k) / 2.0
	var types: Array = LIST[list_tab]
	for i in types.size():
		var r := Rect2(Vector2(x + (i % 2) * (cw + 10 * k), y + int(i / 2) * 58 * k), Vector2(cw, 50 * k))
		_button(r, HoldTypes.name_ko(types[i]), "type", types[i], 20, sel_type == types[i] and tool == "place")
	y += ceili(types.size() / 2.0) * 58 * k + 10 * k
	var h := draft.hold(selected)
	if h.is_empty():
		_wrap(Vector2(x, y + 20 * k), "목록에서 종류를 고르고 벽을 누르면 놓여요. 놓인 홀드를 누르면 여기서 크기·방향을 바꿔요.", w, 17, DIM)
		return
	_text(Vector2(x, y + 24 * k), "고른 홀드: %s" % HoldTypes.name_ko(h.type), 21, CREAM)
	y += 40 * k
	if h.type == "goal":
		_button(Rect2(Vector2(x, y), Vector2(w, 46 * k)), "지우기", "delete", "", 20)
		return
	var sw := (w - 20 * k) / 3.0
	for i in 3:
		var s: String = HoldTypes.SIZES[i]
		_button(Rect2(Vector2(x + i * (sw + 10 * k), y), Vector2(sw, 46 * k)), "크기 " + s, "size", s, 20, h.size == s)
	y += 56 * k
	_text(Vector2(x, y + 30 * k), "방향 %d°" % h.rot, 21, Color.WHITE)
	var bw := 56 * k
	var bx := x + 130 * k
	for b in [["-45", "-45"], ["-5", "-5"], ["+5", "5"], ["+45", "45"]]:
		_button(Rect2(Vector2(bx, y), Vector2(bw, 46 * k)), b[0], "rot", b[1], 18)
		bx += bw + 6 * k
	y += 56 * k
	if RouteDraft.is_hand_type(h.type):
		_button(Rect2(Vector2(x, y), Vector2(w, 46 * k)), "합손(두 손 같이): " + ("켜짐" if h.matchable else "꺼짐"), "match", "", 19, h.matchable)
		y += 56 * k
	_button(Rect2(Vector2(x, y), Vector2(w, 46 * k)), "지우기", "delete", "", 20)


# ---------- 도우미 ----------

func _text(pos: Vector2, s: String, fs: int, col: Color) -> void:
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * k), col)


func _text_c(r: Rect2, s: String, fs: int, col: Color) -> void:
	var px := int(fs * k)
	draw_string(font, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + px * 0.35), s, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, px, col)


func _wrap(pos: Vector2, s: String, w: float, fs: int, col: Color) -> void:
	draw_multiline_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, w, int(fs * k), 5, col)


func _outlined(pos: Vector2, s: String, fs: int, w: float) -> void:
	var px := int(fs * k)
	draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_CENTER, w, px, maxi(4, int(px * 0.2)), Color(0, 0, 0, 0.8))
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_CENTER, w, px, Color.WHITE)


func _button(r: Rect2, text: String, action: String, arg: String, fs := 22, strong := false) -> void:
	draw_rect(r, CREAM if strong else Color(0.1, 0.1, 0.1, 0.8))
	draw_rect(r, Color(1, 1, 1, 0.7), false, 2.0)
	_text_c(r, text, fs, INK if strong else Color.WHITE)
	_buttons.append({"rect": r, "action": action, "arg": arg})


func _exit_tree() -> void:
	if _bot_thread != null:
		_bot_thread.wait_to_finish()
