extends Node2D
## 문제 만들기 화면 UI(작업 6 §2, docs/superpowers/specs/2026-11-19-6-editor-design.md). 휴대폰 가로 기준.
## 위 줄: 나가기 · 이름 · 예상 등급 · 되돌리기 · 올라 보기 · 봇 검사 · 저장. 왼쪽: 도구, 높이 스크롤바. 가운데: 3D 벽(EditorView).
## 오른쪽: 홀드 목록·고른 홀드(돌리기·벽 각도 도구는 아래에 조절 원). 아래: 홀드 수·높이·막는 것.
## 초안(RouteDraft)을 고치고, 고칠 때마다 3D를 다시 만들고 저장 상태·막는 것을 다시 센다. 끄는 동안은 그 홀드만 옮겨 그린다(실시간).
## 2026-11-25 사용자: 옮기기는 고른 홀드를 화면 어디서든 끌어서, 돌리기는 오른쪽 아래 조절 원으로, 벽 각도 탭(180°~90°, 1m·1°),
## 두 손가락 시점, 100m까지 높아지는 벽, 왼쪽 높이 스크롤바(눈금 8개 이하).

## 색·글꼴은 홈(home.gd)과 같다(2026-11-25 사용자 "전체적인 홈 화면과 유사한 UI로"): 남색 반투명 둥근 판, 분필색 글자,
## 강조는 노랑 하나(고른 것·누를 다음 것). 막는 것은 빨강, 주의는 주황.
const NIGHT := Color("0d1620")
const CHALK := Color("f6f2ea")
const SHOE := Color("ffc93c")
const CREAM := Color("f1d59a")   # 보조 정보
const HAIR := Color(0.965, 0.95, 0.92, 0.14)
const DIM := Color(0.965, 0.95, 0.92, 0.66)
const RED := Color("ff5a4a")
const WARN := Color(1, 0.75, 0.6)
const GOOD := Color("7cc443")
## 2026-11-25 사용자 "놓기 옮기기 돌리기를 하나로 하고 벽 각도는 따로", "시작 지정이 아니라 시작홀드 설정".
## 편집: 빈 벽을 누르면 고른 종류를 놓고, 홀드를 누르면 고르고(다시 누르면 해제), 끌면 고른 홀드를 옮기고, 오른쪽 아래 원으로 돌린다.
const TOOLS := [["edit", "편집"], ["wall", "벽 각도"], ["erase", "지우기"], ["start", "시작홀드 설정"]]
const LIMB_NAMES := {&"LH": "왼손", &"RH": "오른손", &"LF": "왼발", &"RF": "오른발"}
const LIST := {"hand": ["jug", "crimp", "sloper", "pinch", "pocket"], "foot": ["foot_chip", "foot_big"], "goal": ["goal"]}
const PICK_R := 0.13      # 홀드를 누른 것으로 보는 거리(m)
const DRAG_PX := 14.0     # 이보다 움직이면 누르기가 아니라 끌기

var view                  # EditorView
var game: Node
var font: Font      # 본문(400)
var font_m: Font    # 버튼(600)
var font_b: Font    # 제목·이름표(750)
var _boxes := {}    # 둥근 판 모양 캐시
var k := 1.0
var draft: RouteDraft
var tool := "edit"
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
var _press := {}          # {kind: "wall"(pos, hold, wall, moved) | "scroll" | "dial"(first)}
var _pinch_d := 0.0
var _mid := Vector2.ZERO  # 두 손가락 가운데(시점 돌리기)
var _multi := false       # 두 손가락을 댄 뒤 모두 뗄 때까지: 뗌을 누르기로 보지 않는다
var _preview := {}        # 끄는 중인 홀드 {id, off(벽 좌표 m), rot(더 돌린 도)}
var sel_wall := 0         # 벽 각도 도구: 고른 높이(m, 그 높이부터 위)
var _wall_dirty := false  # 벽 각도 조절 원을 끄는 중: 3D를 곧 다시 만든다
var _rebuild_ms := 0
var _bot_thread: Thread
var _bot_result := {}
var check_open := false   # 점검 창(못 만드는 이유·주의할 것, 2026-11-25 사용자)
var _checks: Array = []    # 점검 창 줄 [{level: "block"|"warn"|"ok", text, hold, y}]
var _warn: Array = []      # 주의할 것(고칠 때마다 RouteDraft.warnings)
var _bot_ok := -1          # 봇 검사 결과: -1 모름, 0 못 찾음, 1 찾음(고치면 -1)
var share_open := false   # 저장·공유 창
var share_busy := false
var share_code := ""
var tut: EditorTutorial     # 만들기 튜토리얼(따라 하기, 2026-11-26). null이면 꺼짐
var _tut_rect := Rect2()   # 안내 카드(누르면 벽으로 가지 않음)


func _ready() -> void:
	font = UiFont.get_font(400)
	font_m = UiFont.get_font(600)
	font_b = UiFont.get_font(750)
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
	if game != null and draft.holds.is_empty() and not game.progress.tutorial_done(EditorTutorial.ID):
		tut = EditorTutorial.new()  # 처음 새 문제를 열 때 한 번 저절로
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
	UiFont.style_line_edit(_name_edit, k, 22, 52 * k)
	queue_redraw()


## 고친 뒤: 3D를 다시 만들고(rebuild) 막는 것·간격 위반을 다시 센다.
func _changed(rebuild := true) -> void:
	if rebuild and view != null:
		view.rebuild(draft)
	if rebuild:
		_bot_ok = -1
	_problems = draft.problems()
	_warn = draft.warnings()
	_bad = draft.bad_holds()
	queue_redraw()


func _say(t: String) -> void:
	message = t
	_message_t = 3.0
	queue_redraw()


func _process(delta: float) -> void:
	if _wall_dirty and view != null and Time.get_ticks_msec() - _rebuild_ms > 80:  # 각도를 끄는 동안 벽을 다시 접어 보인다
		_wall_dirty = false
		_rebuild_ms = Time.get_ticks_msec()
		view.rebuild(draft)
	if tut != null and tut.update(draft, _problems, delta) == "done":
		_tut_end()
		_say("다 됐어요! [올라 보기]로 직접 올라 보세요. 벽 각도 도구로 벽을 기울일 수도 있어요")
		_message_t = 7.0
	if _message_t > 0.0:
		_message_t -= delta
		if _message_t <= 0.0:
			message = ""
			queue_redraw()
	if _bot_thread != null and not _bot_thread.is_alive():
		var res: Dictionary = _bot_thread.wait_to_finish()
		_bot_thread = null
		_bot_ok = 1 if res.get("ok", false) else 0
		_say("깰 수 있어요(봇이 길을 찾았어요)" if res.get("ok", false) else "봇은 길을 못 찾았어요 — 직접 완등했다면 올릴 수 있어요")
	queue_redraw()


# ---------- 입력 ----------

func _wall_rect() -> Rect2:
	var size := get_viewport_rect().size
	return Rect2(Vector2(206 * k, 74 * k), Vector2(size.x - 586 * k, size.y - 74 * k - 46 * k))


## 왼쪽 높이 스크롤바(도구 판 오른쪽).
func _scroll_rect() -> Rect2:
	var size := get_viewport_rect().size
	return Rect2(Vector2(144 * k, 90 * k), Vector2(58 * k, size.y - 90 * k - 64 * k))


## 오른쪽 아래 조절 원 [가운데, 반지름]. 편집: 고른 홀드 방향(판 오른쪽 아래, 작게), 벽 각도: 고른 높이부터의 기울기.
func _dial() -> Array:
	var size := get_viewport_rect().size
	if tool == "edit":
		var re := 64.0 * k
		return [Vector2(size.x - 84 * k, size.y - 44 * k - 58 * k - 12 * k - re), re]
	var r := 88.0 * k
	return [Vector2(size.x - 190 * k, size.y - 44 * k - 58 * k - 14 * k - r), r]


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
				_cancel_press()
				_multi = true
				_pinch_d = _pinch_dist()
				_mid = _pinch_mid()
		else:
			_touches.erase(event.index)
			_pinch_d = _pinch_dist()
			_mid = _pinch_mid()
			if _multi:
				_multi = not _touches.is_empty()
			elif event.index == 0 or _touches.is_empty():
				_up(event.position)
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			# 두 손가락: 벌리고 오므리면 확대·축소, 같이 끌면 시점 돌리기
			var d := _pinch_dist()
			var m := _pinch_mid()
			if _pinch_d > 0.0 and d > 0.0 and view != null:
				view.zoom_h = clampf(view.zoom_h * _pinch_d / d, view.ZOOM_MIN, view.ZOOM_MAX)
				view.turn(m - _mid)
			_pinch_d = d
			_mid = m
		elif not _multi:
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
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT and view != null:
		view.turn(event.relative)  # 데스크톱: 오른쪽 끌기 = 시점


func _pinch_dist() -> float:
	var ps: Array = _touches.values()
	return (ps[0] as Vector2).distance_to(ps[1]) if ps.size() >= 2 else 0.0


func _pinch_mid() -> Vector2:
	var ps: Array = _touches.values()
	return ((ps[0] as Vector2) + ps[1]) * 0.5 if ps.size() >= 2 else Vector2.ZERO


func _down(pos: Vector2) -> void:
	_press = {}
	if share_open or check_open or _hit_button(pos) >= 0 or view == null or (tut != null and _tut_rect.has_point(pos)):
		return
	if _scroll_rect().has_point(pos):
		_press = {"kind": "scroll"}
		_scroll_to(pos.y)
		return
	var dl := _dial()
	if tool in ["edit", "wall"] and pos.distance_to(dl[0]) <= dl[1] * 1.25:
		_press = {"kind": "dial", "first": true}
		_dial_to(pos)
		return
	if not _wall_rect().has_point(pos):
		return
	var w: Vector2 = view.screen_to_wall(pos)
	_press = {"kind": "wall", "pos": pos, "wall": w, "hold": _hold_at(w), "moved": false}


func _drag(pos: Vector2, rel: Vector2) -> void:
	if _press.is_empty():
		return
	if _press.kind == "scroll":
		_scroll_to(pos.y)
		return
	if _press.kind == "dial":
		_dial_to(pos)
		return
	if not _press.moved and pos.distance_to(_press.pos) > DRAG_PX * k:
		_press.moved = true
		if tool == "edit" and selected == "" and _press.hold != "":
			selected = _press.hold  # 고른 홀드가 없으면 끌기 시작한 홀드를 옮긴다
	if not _press.moved:
		return
	if tool == "edit" and selected != "":
		# 고른 홀드를 손가락이 움직인 만큼 옮겨 그린다(어디서 끌든, 벽 밖·놓을 수 있는 높이 밖으로는 안 감)
		var h := draft.hold(selected)
		var to: Vector2 = Vector2(h.x, h.y) + view.screen_to_wall(pos) - _press.wall
		to = Vector2(clampf(to.x, -RouteDraft.WALL_HALF, RouteDraft.WALL_HALF), clampf(to.y, RouteDraft.Y_MIN, draft.max_y()))
		_preview = {"id": selected, "off": to - Vector2(h.x, h.y), "rot": 0}
		view.preview_hold(selected, _preview.off, 0)
		queue_redraw()
	else:
		# 빈 벽을 끌면 위아래 이동
		var px_per_m: float = get_viewport_rect().size.y / view.zoom_h
		view.logic.cam_y = clampf(view.logic.cam_y + rel.y / px_per_m, 0.8, draft.max_y())


func _up(pos: Vector2) -> void:
	var b := _hit_button(pos)
	if b >= 0 and _press.is_empty():
		_do(_buttons[b].action, _buttons[b].arg)
		return
	if _press.is_empty():
		return
	var p := _press
	_press = {}
	if p.kind == "dial":
		_dial_end()
		return
	if p.kind != "wall":
		return
	if p.moved:
		if not _preview.is_empty():
			var h := draft.hold(_preview.id)
			var off: Vector2 = _preview.off
			_preview = {}
			if off.length() >= 0.005:
				draft.move(h.id, h.x + off.x, h.y + off.y)
				_tut_note("move")
			_changed()
		queue_redraw()
		return
	_tap_wall(p.wall, p.hold)


## 두 번째 손가락이 닿으면 하던 끌기를 그만둔다(옮기던 홀드는 제자리, 각도는 거기까지 반영).
func _cancel_press() -> void:
	if _press.get("kind", "") == "dial" and tool == "wall":
		_wall_dirty = false
		_changed()
	elif not _preview.is_empty() and view != null:
		view.preview_hold(_preview.id, Vector2.ZERO, 0)
	_preview = {}
	_press = {}
	queue_redraw()


## 스크롤바의 화면 높이 → 그 높이로 바로 이동.
func _scroll_to(sy: float) -> void:
	var r := _scroll_rect()
	view.logic.cam_y = clampf((r.end.y - sy) / r.size.y * draft.max_y(), 0.8, draft.max_y())


## 조절 원: 위가 0, 시계 방향 +. 돌리기는 고른 홀드 방향(5°), 벽 각도는 고른 높이부터의 기울기(오버행 0~90, 1°).
func _dial_to(pos: Vector2) -> void:
	var dl := _dial()
	var v: Vector2 = pos - dl[0]
	if v.length() < 10.0 * k:
		return
	var a := rad_to_deg(atan2(v.x, -v.y))
	if tool == "edit":
		var h := draft.hold(selected)
		if h.is_empty() or h.type == "goal":
			return
		var d := posmod(int(round(a / 5.0)) * 5 - int(h.rot), 360)
		_preview = {"id": selected, "off": Vector2.ZERO, "rot": d}
		view.preview_hold(selected, Vector2.ZERO, d)
	else:
		var deg := clampi(int(round(a)), 0, 90)
		if deg != draft.wall_deg_at(sel_wall):
			draft.set_wall(sel_wall, deg, _press.get("first", false))
			_press.first = false
			_wall_dirty = true
	queue_redraw()


func _dial_end() -> void:
	if tool == "wall":
		_wall_dirty = false
		_changed()
		return
	if _preview.is_empty():
		return
	var p := _preview
	_preview = {}
	if int(p.rot) != 0:
		draft.rotate(p.id, int(p.rot))
		_tut_note("rotate")
	_changed()


func _tap_wall(w: Vector2, hit: String) -> void:
	match tool:
		"edit":
			if hit != "":
				selected = "" if hit == selected else hit  # 고른 홀드를 다시 누르면 해제(끌면 화면 이동)
			else:
				var id := draft.place(sel_type, w.x, w.y)
				if id == "":
					_say("홀드는 %d개까지 놓을 수 있어요" % RouteDraft.MAX_HOLDS)
				else:
					selected = id
					_tut_note("place_" + ("goal" if sel_type == "goal" else ("foot" if HoldTypes.is_foot(sel_type) else "hand")))
					_changed()
		"wall":
			sel_wall = clampi(floori(w.y), 0, int(draft.max_y()))
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
			_preview = {}
		"limb":
			start_limb = StringName(arg)
		"list":
			list_tab = arg
			sel_type = LIST[arg][0]
			tool = "edit"
		"type":
			sel_type = arg
			tool = "edit"
		"size":
			draft.set_size(selected, arg)
			_changed()
		"rot":
			draft.rotate(selected, int(arg))
			_tut_note("rotate")
			_changed()
		"tut":  # [만드는 법]: 켜기 / 끄기(카드의 [끄기]도 같음)
			if tut == null:
				tut = EditorTutorial.new()
			else:
				_tut_end()
		"wdeg":  # 화면 각도(180 − 오버행)로 더하기
			draft.set_wall(sel_wall, draft.wall_deg_at(sel_wall) - int(arg))
			_changed()
		"wdel":
			draft.remove_wall(sel_wall)
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
		"check_open":
			_checks = _check_items()
			check_open = true
		"check_close":
			check_open = false
		"goto":  # 점검 창 [보기]: 그 홀드를 고르고(편집) 그 높이로
			check_open = false
			var h := draft.hold(arg)
			if not h.is_empty():
				tool = "edit"
				selected = arg
				view.logic.cam_y = clampf(h.y, 0.8, draft.max_y())
			elif arg.is_valid_float():
				view.logic.cam_y = clampf(arg.to_float(), 0.8, draft.max_y())
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


## 점검 창 줄: 막는 것(저장·올라 보기를 막음)은 고칠 곳까지, 주의할 것은 만들 수는 있지만 문제가 될 수 있는 것.
func _check_items() -> Array:
	var out: Array = []
	for p in _problems:
		match p:
			RouteDraft.P_NAME:
				out.append({"level": "block", "text": "문제 이름을 적어 주세요. 위쪽 이름 칸을 누르면 써요.", "hold": ""})
			RouteDraft.P_START:
				var miss: Array = []
				for l in [&"LH", &"RH", &"LF", &"RF"]:
					if draft.start[l] == "":
						miss.append(LIMB_NAMES[l])
				out.append({"level": "block", "text": "시작홀드를 정해 주세요: %s 자리가 비었어요. [시작홀드 설정]에서 손발을 고르고 홀드를 누르세요." % "·".join(miss), "hold": ""})
			RouteDraft.P_GOAL:
				out.append({"level": "block", "text": "탑 홀드를 놓아 주세요. [편집]에서 오른쪽 목록의 [탑]을 고르고 벽을 누르세요.", "hold": ""})
			RouteDraft.P_POSE:
				var fix := draft.start_fix()
				if not fix.is_empty():
					out.append({"level": "block", "text": "시작 자세를 만들 수 없어요. " + fix.text + ".", "hold": fix.hold})
				elif draft.start_pose().ok:
					out.append({"level": "block", "text": "시작 자세는 되지만 버티지 못해요(무게중심이 발 밖). 두 발을 두 손 아래 가운데 쪽으로 모아 보세요.", "hold": draft.start[&"LF"]})
				else:
					out.append({"level": "block", "text": "시작 자세를 만들 수 없어요. 한 홀드만 옮겨서는 안 돼요. 손은 발보다 1.2~1.5m 위, 손 사이 0.4~0.8m, 발 사이 0.3~0.5m쯤으로 놓아 보세요.", "hold": draft.start[&"LH"]})
			RouteDraft.P_SPACING:
				for v in draft.spacing_details():
					out.append({"level": "block", "text": v.text, "hold": v.hold})
			_:
				var errs: Array = draft.build().errors
				out.append({"level": "block", "text": p + (": " + str(errs[0]) if not errs.is_empty() else ""), "hold": ""})
	for w in _warn:
		out.append({"level": "warn", "text": w.text, "hold": w.hold, "y": w.y})
	if _bot_ok == 0:
		out.append({"level": "warn", "text": "봇이 길을 못 찾았어요. 직접 도움 없이 완등하면 올릴 수 있어요.", "hold": ""})
	if out.is_empty():
		out.append({"level": "ok", "text": "막는 것도 주의할 것도 없어요. [올라 보기]로 직접 올라 보세요.", "hold": ""})
	return out


func _draw_check(size: Vector2) -> void:
	_buttons = []
	var box := Rect2(Vector2(size.x * 0.5 - 520 * k, size.y * 0.5 - 300 * k), Vector2(1040, 600) * k)
	_panel(box)
	var x := box.position.x + 30 * k
	var y := box.position.y + 52 * k
	_text(Vector2(x, y), "점검", 28, CHALK)
	_text(Vector2(x + 100 * k, y), "빨강: 이것 때문에 저장·올라 보기를 못 해요 · 주황: 만들 수는 있지만 문제가 될 수 있어요", 17, DIM)
	y += 30 * k
	var row_h := 72 * k
	var rows := int((box.end.y - 90 * k - y) / row_h)
	for i in mini(_checks.size(), rows):
		var c: Dictionary = _checks[i]
		var col := RED if c.level == "block" else (WARN if c.level == "warn" else GOOD)
		draw_circle(Vector2(x + 10 * k, y + 22 * k), 9 * k, col)
		_wrap(Vector2(x + 32 * k, y + 28 * k), c.text, 820 * k, 18, CHALK)
		var target: String = c.hold if c.hold != "" else (str(c.y) if float(c.get("y", -1.0)) >= 0.0 else "")
		if target != "":
			_button(Rect2(Vector2(box.end.x - 140 * k, y + 4 * k), Vector2(110, 46) * k), "보기", "goto", target, 20)
		y += row_h
	if _checks.size() > rows:
		_text(Vector2(x, y + 20 * k), "그 밖에 %d개 — 위의 것을 고치면 보여요" % (_checks.size() - rows), 18, DIM)
	_button(Rect2(Vector2(box.end.x - 180 * k, box.end.y - 70 * k), Vector2(150, 52) * k), "닫기", "check_close", "", 22)


func _draw_share(size: Vector2) -> void:
	_buttons = []
	var box := Rect2(Vector2(size.x * 0.5 - 380 * k, size.y * 0.5 - 200 * k), Vector2(760, 400) * k)
	_panel(box)
	var x := box.position.x + 30 * k
	var y := box.position.y + 56 * k
	_text(Vector2(x, y), "이 기기에 저장했어요", 26, CHALK)
	y += 44 * k
	var can: bool = game != null and draft.can_publish(game.progress)
	if share_code != "":
		_text(Vector2(x, y), "공유 코드", 20, DIM)
		_text(Vector2(x, y + 64 * k), share_code, 56, CHALK)
		_button(Rect2(Vector2(x + 330 * k, y + 14 * k), Vector2(150, 56) * k), "복사", "copy", "", 22)
		y += 100 * k
	if game == null or not game.share().enabled():
		_wrap(Vector2(x, y + 10 * k), "공유 서버가 아직 준비되지 않았어요. 만든 문제는 이 기기에서 계속 올라 볼 수 있어요.", 700 * k, 20, DIM)
	elif not can:
		var why: String = _problems[0] if not _problems.is_empty() else "직접 도움 없이 한 번 완등해야 올릴 수 있어요([올라 보기])"
		_wrap(Vector2(x, y + 10 * k), "아직 올릴 수 없어요: " + why, 700 * k, 20, WARN)
	elif share_busy:
		_text(Vector2(x, y + 30 * k), "올리는 중…", 24, CHALK)
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
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, 72 * k)), Color(NIGHT, 0.86))
	draw_line(Vector2(0, 72 * k), Vector2(size.x, 72 * k), HAIR, 1.5 * k)
	_button(Rect2(Vector2(10, 10) * k, Vector2(130, 52) * k), "나가기", "exit", "")
	var gx := 470 * k
	_button(Rect2(Vector2(gx, 10 * k), Vector2(48, 52) * k), "◀", "grade", "-1")
	_text_c(Rect2(Vector2(gx + 48 * k, 10 * k), Vector2(110, 52) * k), "예상 " + draft.grade, 22, CHALK)
	_button(Rect2(Vector2(gx + 158 * k, 10 * k), Vector2(48, 52) * k), "▶", "grade", "1")
	_button(Rect2(Vector2(gx + 226 * k, 10 * k), Vector2(140, 52) * k), "만드는 법", "tut", "", 20, false)
	var x := size.x - 10 * k
	for b in [["저장", "save", 120], ["봇 검사", "bot", 130], ["올라 보기", "climb", 150], ["되돌리기", "undo", 130]]:
		x -= b[2] * k
		_button(Rect2(Vector2(x, 10 * k), Vector2(b[2], 52) * k), b[0], b[1], "", 22, b[1] == "climb" and _problems.is_empty())
		x -= 10 * k
	_draw_tools(size)
	_draw_panel(size)
	# 아래 상태
	_draw_scrollbar()
	draw_rect(Rect2(Vector2(0, size.y - 44 * k), Vector2(size.x, 44 * k)), Color(NIGHT, 0.86))
	draw_line(Vector2(0, size.y - 44 * k), Vector2(size.x, size.y - 44 * k), HAIR, 1.5 * k)
	var st := "홀드 %d/%d · 벽 %sm · 판 %d · " % [draft.holds.size(), RouteDraft.MAX_HOLDS, String.num(draft.wall_limit()), draft.version]
	st += "막는 것 없음 — 올라 볼 수 있어요" if _problems.is_empty() else _problems[0]
	_text(Vector2(16 * k, size.y - 14 * k), st, 19, CHALK if _problems.is_empty() else WARN)
	var nw := _warn.size() + (1 if _bot_ok == 0 else 0)
	_button(Rect2(Vector2(size.x - 330 * k, size.y - 42 * k), Vector2(320, 40) * k), "점검 · 막는 것 %d · 주의 %d" % [_problems.size(), nw], "check_open", "", 18,
		not _problems.is_empty() or nw > 0)
	if tut != null:
		_draw_tutorial()
	if share_open:
		_draw_share(size)
	if check_open:
		_draw_check(size)
	if message != "":
		var tw := font_b.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, int(22 * k)).x + 56 * k
		var my := _tut_rect.end.y + 10 * k if tut != null else 90 * k
		var r := Rect2(Vector2(size.x * 0.5 - tw * 0.5, my), Vector2(tw, 54 * k))
		draw_style_box(_box(Color(NIGHT, 0.94), r.size.y * 0.5, Color(CHALK, 0.24), 1.5), r)
		draw_string(font_b, Vector2(r.position.x, _baseline(r, 22, font_b)), message, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(22 * k), CHALK)


## 벽 위 표시: 편집 범위 선(접힌 벽을 따라), 벽 끝(그 위에 놓으면 높아짐), 시작 자리 이름표, 탑, 간격 위반(빨강), 고른 홀드(노랑),
## 손홀드 잡는 방향, 벽 각도 도구의 구간 경계·고른 높이. 끄는 중인 홀드는 옮긴 자리·돌린 방향으로.
func _draw_wall_overlay(_size: Vector2) -> void:
	var w2s: Callable = view.world_to_screen
	var top := draft.max_y()
	for sx in [-RouteDraft.WALL_HALF, RouteDraft.WALL_HALF]:
		_wall_line(Vector2(sx, 0.0), Vector2(sx, top), Color(CHALK, 0.35), 2.0)
	var lim := draft.wall_limit()
	if lim < top:
		_wall_line(Vector2(-RouteDraft.WALL_HALF, lim), Vector2(RouteDraft.WALL_HALF, lim), Color(CHALK, 0.5), 2.0)
		if view.in_view(Vector2(0, lim)):
			_outlined(w2s.call(Vector2(0, lim)) + Vector2(-210 * k, -10 * k), "벽 끝 %sm · 위에 놓으면 높아져요" % String.num(lim), 16, 420 * k)
	if tool == "wall":
		for wl in draft.walls:
			var y := float(wl.from_y)
			if y > 0.0:
				_wall_line(Vector2(-RouteDraft.WALL_HALF, y), Vector2(RouteDraft.WALL_HALF, y), Color(0.55, 0.85, 1.0, 0.8), 2.0)
		for y in [float(sel_wall), float(sel_wall + 1)]:
			_wall_line(Vector2(-RouteDraft.WALL_HALF, y), Vector2(RouteDraft.WALL_HALF, y), SHOE, 4.0)
		if view.in_view(Vector2(RouteDraft.WALL_HALF, sel_wall + 0.5)):
			_outlined(w2s.call(Vector2(RouteDraft.WALL_HALF, sel_wall + 0.5)) + Vector2(10 * k, 6 * k), "%dm부터 %d°" % [sel_wall, 180 - draft.wall_deg_at(sel_wall)], 18, 0.0, HORIZONTAL_ALIGNMENT_LEFT)
	var start_of := {}
	for l in draft.start:
		if draft.start[l] != "":
			start_of[draft.start[l]] = LIMB_NAMES[l]
	for h in draft.holds:
		var hp := Vector2(h.x, h.y)
		var rot := int(h.rot)
		if _preview.get("id", "") == h.id:
			hp += _preview.off
			rot += int(_preview.rot)
		if not view.in_view(hp):
			continue
		var c: Vector2 = w2s.call(hp)
		var r: float = (view.world_to_screen(hp + Vector2(0.1, 0.0)) - c).length()
		if _bad.has(h.id):
			draw_arc(c, r * 1.2, 0, TAU, 32, RED, 4.0 * k)
		if h.id == selected:
			draw_arc(c, r * 1.35, 0, TAU, 32, SHOE, 3.5 * k)
		if start_of.has(h.id):
			_outlined(c + Vector2(-60 * k, -r * 1.3), start_of[h.id], 18, 120 * k)
		if h.type == "goal":
			_outlined(c + Vector2(-60 * k, -r * 1.6), "탑", 20, 120 * k)
		elif h.id == selected and RouteDraft.is_hand_type(h.type):
			# 잡는 힘 방향(손이 버티는 쪽): rot 0 = 위
			var tip: Vector2 = w2s.call(hp + HoldTypes.rotate(Vector2(0, 1), rot) * 0.16)
			draw_line(c, tip, SHOE, 3.5 * k)


## 벽면을 따라 a에서 b까지(같은 x면 접힌 벽을 따라 25cm마다 꺾어) 선을 긋는다. 카메라 뒤 부분은 뺀다.
func _wall_line(a: Vector2, b: Vector2, col: Color, width: float) -> void:
	var n := maxi(1, ceili(absf(b.y - a.y) / 0.25))
	var prev := Vector2.INF
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		if not view.in_view(p):
			prev = Vector2.INF
			continue
		var q: Vector2 = view.world_to_screen(p)
		if prev != Vector2.INF:
			draw_line(prev, q, col, width * k)
		prev = q


## 왼쪽 높이 스크롤바: 0m~놓을 수 있는 높이, 눈금 tick_step m마다(8개 이하), 지금 보이는 범위(밝은 칸). 누르거나 끌면 그 높이로.
func _draw_scrollbar() -> void:
	var r := _scroll_rect()
	var top := draft.max_y()
	var bar := Rect2(Vector2(r.end.x - 16 * k, r.position.y), Vector2(12 * k, r.size.y))
	draw_style_box(_box(Color(NIGHT, 0.8), 16 * k, HAIR, 1.5), Rect2(Vector2(r.position.x - 2 * k, r.position.y - 10 * k), Vector2(r.size.x + 4 * k, r.size.y + 20 * k)))
	draw_style_box(_box(Color(CHALK, 0.16), bar.size.x * 0.5), bar)
	var to_y := func(m: float) -> float: return r.end.y - clampf(m / top, 0.0, 1.0) * r.size.y
	var half: float = view.zoom_h * 0.5
	var a: float = to_y.call(view.logic.cam_y + half)
	var b: float = to_y.call(view.logic.cam_y - half)
	var thumb := Rect2(Vector2(bar.position.x - 3 * k, a), Vector2(bar.size.x + 6 * k, maxf(b - a, 12 * k)))
	draw_style_box(_box(SHOE, thumb.size.x * 0.5), thumb)
	var lim: float = to_y.call(draft.wall_limit())
	draw_line(Vector2(bar.position.x - 6 * k, lim), Vector2(bar.end.x + 2 * k, lim), Color(CHALK, 0.6), 2.0 * k)
	var step := tick_step(top)
	for i in floori(top / step) + 1:
		var y: float = to_y.call(i * step)
		draw_line(Vector2(bar.position.x - 5 * k, y), Vector2(bar.position.x, y), Color(CHALK, 0.8), 2.0 * k)
		draw_string(font_m, Vector2(r.position.x, y + 5 * k), "%dm" % (i * step), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 22 * k, int(14 * k), DIM)


func _draw_tools(size: Vector2) -> void:
	draw_style_box(_box(Color(NIGHT, 0.8), 18 * k, HAIR, 1.5), Rect2(Vector2(4 * k, 80 * k), Vector2(136 * k, size.y - 132 * k)))
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
	draw_style_box(_box(Color(NIGHT, 0.8), 18 * k, HAIR, 1.5), Rect2(Vector2(x - 12 * k, 80 * k), Vector2(378 * k, size.y - 132 * k)))
	if tool == "wall":
		_draw_wall_panel(size, x, w)
		return
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
		_button(r, HoldTypes.name_ko(types[i]), "type", types[i], 20, sel_type == types[i] and tool == "edit")
	y += ceili(types.size() / 2.0) * 58 * k + 10 * k
	var h := draft.hold(selected)
	if h.is_empty():
		_wrap(Vector2(x, y + 20 * k), "목록에서 종류를 고르고 벽을 누르면 놓여요. 놓인 홀드를 누르면 고르고, 끌면 옮기고, 아래 원으로 돌려요. 다시 누르면 고르기를 풀어요.", w, 17, DIM)
		return
	var rot := int(h.rot) + (int(_preview.get("rot", 0)) if _preview.get("id", "") == selected else 0)
	_text(Vector2(x, y + 24 * k), "고른 홀드: %s" % HoldTypes.name_ko(h.type) + ("" if h.type == "goal" else " · 방향 %d°" % posmod(rot, 360)), 21, CHALK)
	y += 40 * k
	if h.type == "goal":
		_button(Rect2(Vector2(x, y), Vector2(w, 46 * k)), "지우기", "delete", "", 20)
		return
	if tool != "edit":
		return
	var sw := (w - 20 * k) / 3.0
	for i in 3:
		var s: String = HoldTypes.SIZES[i]
		_button(Rect2(Vector2(x + i * (sw + 10 * k), y), Vector2(sw, 46 * k)), "크기 " + s, "size", s, 20, h.size == s)
	y += 56 * k
	# 아래: 왼쪽 합손·지우기, 오른쪽 돌리기 원, 맨 아래 돌리기 버튼(원을 끄는 동안 홀드가 바로 돈다)
	var lw := w - 170 * k
	if RouteDraft.is_hand_type(h.type):
		_button(Rect2(Vector2(x, y + 10 * k), Vector2(lw, 46 * k)), "합손 " + ("켜짐" if h.matchable else "꺼짐"), "match", "", 19, h.matchable)
	_button(Rect2(Vector2(x, y + 66 * k), Vector2(lw, 46 * k)), "지우기", "delete", "", 20)
	var bw := (w - 30 * k) / 4.0
	var btn_y := size.y - 44 * k - 58 * k
	for i in 4:
		var b: Array = [["-45°", "-45"], ["-5°", "-5"], ["+5°", "5"], ["+45°", "45"]][i]
		_button(Rect2(Vector2(x + i * (bw + 10 * k), btn_y), Vector2(bw, 46 * k)), b[0], "rot", b[1], 19)
	var dl := _dial()
	_draw_dial(dl[0], dl[1], true, rot)


## 벽 각도 도구의 오른쪽 판: 설명, 고른 높이, 아래에 조절 원과 버튼(끄는 동안 3D 벽이 바로 접힌다).
func _draw_wall_panel(size: Vector2, x: float, w: float) -> void:
	var y := 84 * k
	var dl := _dial()
	var c: Vector2 = dl[0]
	var r: float = dl[1]
	var btn_y := size.y - 44 * k - 58 * k
	var bw := (w - 30 * k) / 4.0
	_text(Vector2(x, y + 24 * k), "벽 각도", 24, CHALK)
	_wrap(Vector2(x, y + 58 * k), "벽을 눌러 높이를 고른 뒤 원을 돌리세요. 그 높이부터 위가 기울어요. 180°는 수직, 90°는 천장이에요.", w, 17, DIM)
	var deg := draft.wall_deg_at(sel_wall)
	_text(Vector2(x, c.y - r - 30 * k), "%dm부터 %d°" % [sel_wall, 180 - deg], 22, CHALK)
	if sel_wall > 0 and draft.walls.any(func(wl): return int(wl.from_y) == sel_wall):
		_button(Rect2(Vector2(x, c.y - r - 100 * k), Vector2(w, 44 * k)), "이 높이의 꺾임 지우기", "wdel", "", 18)
	for i in 4:
		var b: Array = [["-10°", "-10"], ["-1°", "-1"], ["+1°", "1"], ["+10°", "10"]][i]
		_button(Rect2(Vector2(x + i * (bw + 10 * k), btn_y), Vector2(bw, 46 * k)), b[0], "wdeg", b[1], 19)
	draw_line(c, c + Vector2(0, r * 0.9), Color(CHALK, 0.5), 5.0 * k)  # 아래 벽(곧게 아래로)과 위 벽 사이 각이 화면 각도
	_draw_dial(c, r, true, deg)


## 조절 원: 눈금(돌리기 45°, 벽 각도 0~90° 15°마다)과 손잡이(위 0, 시계 방향 + ang도).
func _draw_dial(c: Vector2, r: float, on: bool, ang: float) -> void:
	var col := Color(CHALK, 0.7) if on else Color(CHALK, 0.25)
	draw_circle(c, r, Color(NIGHT, 0.7))
	draw_arc(c, r, 0, TAU, 48, col, 3.0 * k)
	for t in range(0, 360, 45 if tool == "edit" else 15):
		if tool == "wall" and t > 90:
			break
		var d := Vector2(sin(deg_to_rad(t)), -cos(deg_to_rad(t)))
		draw_line(c + d * r * 0.86, c + d * r, col, 2.0 * k)
	if on:
		var d := Vector2(sin(deg_to_rad(ang)), -cos(deg_to_rad(ang)))
		draw_line(c, c + d * r * 0.9, SHOE, 6.0 * k)
		draw_circle(c + d * r * 0.9, 12 * k, SHOE)
		draw_circle(c, 6 * k, SHOE)


# ---------- 도우미 ----------

## 스크롤바 눈금 간격(m): 0m부터 h까지 눈금이 8개 이하가 되는 가장 작은 간격(2026-11-25 사용자 "최대 8개, 1m·2m·5m·10m·15m").
static func tick_step(h: float) -> int:
	for st in [1, 2, 5, 10]:
		if floori(h / st) + 1 <= 8:
			return st
	return 15


## 글자. 21 이상은 제목·이름으로 보고 굵게(홈과 같은 글꼴).
func _text(pos: Vector2, s: String, fs: int, col: Color) -> void:
	draw_string(font_b if fs >= 21 else font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * k), col)


func _text_c(r: Rect2, s: String, fs: int, col: Color) -> void:
	draw_string(font_m, Vector2(r.position.x, _baseline(r, fs, font_m)), s, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(fs * k), col)


## r 안에서 글자를 세로 가운데에 두는 기준선.
func _baseline(r: Rect2, fs: int, f: Font) -> float:
	var px := int(fs * k)
	return r.position.y + (r.size.y + f.get_ascent(px) - f.get_descent(px)) * 0.5


## 둥근 판 모양(채움·모서리·테두리, 홈과 같은 식). 같은 모양은 한 번만 만든다(매 프레임 다시 그림).
func _box(fill: Color, radius: float, border := Color(0, 0, 0, 0), bw := 0.0) -> StyleBoxFlat:
	var key := "%s|%d|%s|%.1f|%.3f" % [fill, int(radius), border, bw, k]
	if _boxes.has(key):
		return _boxes[key]
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(radius))
	if bw > 0.0 and border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(maxi(1, roundi(bw * k)))
	sb.anti_aliasing = true
	_boxes[key] = sb
	return sb


## 창(점검·저장): 거의 불투명한 남색 둥근 판(홈 _panel).
func _panel(r: Rect2) -> void:
	draw_style_box(_box(Color(NIGHT, 0.97), 26 * k, Color(CHALK, 0.2), 1.5), r)


func _wrap(pos: Vector2, s: String, w: float, fs: int, col: Color) -> void:
	draw_multiline_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, w, int(fs * k), 5, col)


## 벽 위 이름표: 남색 알약 위 분필색 굵은 글자(플레이 화면 안내와 같은 모양). pos는 기준선, w 안에서 가운데(0이면 왼쪽 맞춤).
func _outlined(pos: Vector2, s: String, fs: int, w: float, align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var px := int(fs * k)
	var tw := font_b.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var x0 := pos.x + (w - tw) * 0.5 if align == HORIZONTAL_ALIGNMENT_CENTER and w > 0.0 else pos.x
	var pill := Rect2(Vector2(x0 - px * 0.6, pos.y - px * 1.05), Vector2(tw + px * 1.2, px * 1.5))
	draw_style_box(_box(Color(NIGHT, 0.82), pill.size.y * 0.5, Color(CHALK, 0.2), 1.0), pill)
	draw_string(font_b, Vector2(x0, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, CHALK)


## 버튼(홈과 같음): 주(strong, 고른 것·누를 다음 것) = 노란 알약 + 남색 굵은 글자, 보조 = 반투명 남색 알약 + 가는 테두리 + 분필색 글자.
func _button(r: Rect2, text: String, action: String, arg: String, fs := 22, strong := false) -> void:
	var radius := r.size.y * 0.5 if r.size.y <= 72 * k else 22 * k
	draw_style_box(_box(SHOE if strong else Color(NIGHT, 0.72), radius, Color(0, 0, 0, 0) if strong else Color(CHALK, 0.26), 1.5), r)
	if text != "":
		var f: Font = font_b if strong else font_m
		draw_string(f, Vector2(r.position.x, _baseline(r, fs, f)), text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(fs * k), NIGHT if strong else CHALK)
	_buttons.append({"rect": r, "action": action, "arg": arg})
	if tut != null and tut.target() == [action, arg]:
		_ring(r)


# ---------- 만들기 튜토리얼 ----------


func _tut_note(ev: String) -> void:
	if tut != null:
		tut.note(ev)


## 끝내거나 끄면 다시 저절로 열리지 않게 기록한다([만드는 법]으로 다시 볼 수 있음).
func _tut_end() -> void:
	tut = null
	if game != null and not game.progress.tutorial_done(EditorTutorial.ID):
		game.progress.record_tutorial(EditorTutorial.ID)
		SaveStore.save(game.progress, game.get_flow().save_path)


## 안내 카드(플레이 튜토리얼 카드와 같은 모양): 벽 위 가운데에 단계 칩·할 일·도움말(15초 진행 없을 때)·[끄기].
func _draw_tutorial() -> void:
	var wr := _wall_rect()
	var w := minf(wr.size.x - 24 * k, 860 * k)
	var bw := 96 * k
	var tx := 92 * k
	var tw := w - tx - bw - 26 * k
	var text := str(tut.current().text)
	var help := tut.help_text()
	var th := font_b.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, tw, int(21 * k)).y
	var hh := font.get_multiline_string_size(help, HORIZONTAL_ALIGNMENT_LEFT, tw, int(18 * k)).y + 8 * k if help != "" else 0.0
	var r := Rect2(Vector2(wr.get_center().x - w * 0.5, 84 * k), Vector2(w, maxf(th + hh + 28 * k, 64 * k)))
	_tut_rect = r
	draw_style_box(_box(Color(NIGHT, 0.95), 18 * k, Color(SHOE, 0.55), 2.0), r)
	var chip := Rect2(r.position + Vector2(14, 14) * k, Vector2(64, 36) * k)
	draw_style_box(_box(SHOE, chip.size.y * 0.5), chip)
	draw_string(font_b, Vector2(chip.position.x, _baseline(chip, 20, font_b)), "%d/%d" % [tut.index + 1, tut.steps.size()], HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, int(20 * k), NIGHT)
	var y := r.position.y + 14 * k + font_b.get_ascent(int(21 * k))
	draw_multiline_string(font_b, Vector2(r.position.x + tx, y), text, HORIZONTAL_ALIGNMENT_LEFT, tw, int(21 * k), -1, CHALK)
	if help != "":
		draw_multiline_string(font, Vector2(r.position.x + tx, y + th + 8 * k), help, HORIZONTAL_ALIGNMENT_LEFT, tw, int(18 * k), -1, CREAM)
	if tut.target() == ["name", ""]:
		_ring(Rect2(_name_edit.position, _name_edit.size))
	_button(Rect2(Vector2(r.end.x - bw - 12 * k, r.position.y + 12 * k), Vector2(bw, 40 * k)), "끄기", "tut", "", 18)


## 튜토리얼이 가리키는 곳: 깜빡이는 노란 고리(밝기는 0.1 단위라 모양 캐시가 커지지 않음).
func _ring(r: Rect2) -> void:
	var a := snappedf(0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.006), 0.1)
	var g := r.grow(5 * k)
	draw_style_box(_box(Color(0, 0, 0, 0), minf(g.size.y * 0.5, 26 * k), Color(SHOE, a), 3.0), g)


func _exit_tree() -> void:
	if _bot_thread != null:
		_bot_thread.wait_to_finish()
