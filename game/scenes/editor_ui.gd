extends Node2D
## 문제 만들기 화면 UI(작업 6 §2, docs/superpowers/specs/2026-11-19-6-editor-design.md). 휴대폰 가로 기준.
## 위 줄: 나가기 · 이름 · 예상 등급 · 되돌리기 · 올라 보기 · 봇 검사 · 저장. 왼쪽: 도구, 높이 스크롤바. 가운데: 3D 벽(EditorView).
## 오른쪽: 홀드 종류 → 쓰임(손·발·탑)·고른 홀드(돌리기·벽 각도 도구는 아래에 조절 원). 아래: 홀드 수·높이·고칠 것.
## 2026-11-26 사용자 "명칭들이 직관적이지 않아", "홀드 종류가 기준이 된 후에 손 발 탑을 선택", "합손 … 노란 불이 들어오면 당연히 합손인줄".
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
const TOOLS := [["edit", "홀드 놓기"], ["wall", "벽 각도"], ["erase", "홀드 지우기"], ["start", "시작홀드 설정"]]
const LIMB_NAMES := {&"LH": "왼손", &"RH": "오른손", &"LF": "왼발", &"RF": "오른발"}
## 2026-11-27 사용자 "크고작은 발판홀드는 없애. 홀드종류를 선택한 뒤 손 발 탑 홀드로 사용할지 선택": 발판 종류는 고를 수 없다(옛 문제에서는 그대로 읽음)
const TYPES := ["jug", "crimp", "sloper", "pinch", "pocket", "volume"]  # volume: 볼륨(2026-11-28, 면에 홀드·모서리 잡기)
const SHAPE_KO := {"box": "상자", "wedge": "삼각"}
const THICK_KO := {0: "위", 90: "오른쪽", 180: "아래", 270: "왼쪽"}
const ROLES := [["hand", "손으로"], ["foot", "발로"], ["top", "탑으로"]]
const ROLE_KO := {"hand": "손", "foot": "발", "top": "탑"}
const SIZE_KO := {"S": "작게", "M": "보통", "L": "크게"}
const ZOOM_FOCUS := 3.0   # 점검 창 [보기]: 이 높이(m)만 보이게 조금 다가간다
const PICK_R := 0.13      # 홀드를 누른 것으로 보는 거리(m)
const BOT_MS := 15000     # [봇으로 확인] 길 찾기 시간 한도
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
var sel_type := "jug"
var sel_role := "hand"    # 놓을 쓰임: hand | foot | top
var sel_size := "M"       # 놓을 크기(2026-11-26 사용자 "홀드종류 먼저 선택 손 발 탑홀드 선택하고 크기 선택")
var sel_shape := "box"    # 놓을 볼륨 모양
var sel_vrot := 0         # 놓을 삼각 볼륨의 두꺼운 쪽(0 위 · 90 오른쪽 · 180 아래 · 270 왼쪽)
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
var _rebuild_cost := 0     # 지난번 벽 다시 접기에 걸린 시간(ms)
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
var _TUT_EDIT: int = EditorTutorial.STEPS.map(func(st): return st.id).find("tool_edit")  # 이 단계 전까지 시작 자리 번호를 보인다


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
		tut = EditorTutorial.new()  # 처음 새 문제를 열 때 한 번 저절로(begin은 3D가 생긴 뒤 _tut_start)
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
	if tut != null:
		_tut_start()


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
	_bad = draft.bad_holds() + draft.volume_issues().map(func(i): return str(i.get("hold", ""))).filter(func(id): return id != "")  # 볼륨 모서리에 걸친 홀드도 빨간 고리
	queue_redraw()


func _say(t: String) -> void:
	message = t
	_message_t = 3.0
	queue_redraw()


func _process(delta: float) -> void:
	# 각도를 끄는 동안 벽을 다시 접어 보인다. 다시 접는 데 걸린 시간의 두 배는 쉬어 그 사이 화면이 끊기지 않게(느린 폰·100m 벽, 2026-11-26)
	if _wall_dirty and view != null and Time.get_ticks_msec() - _rebuild_ms > maxi(80, _rebuild_cost * 2):
		_wall_dirty = false
		var t0 := Time.get_ticks_msec()
		view.rebuild(draft)
		_rebuild_ms = Time.get_ticks_msec()
		_rebuild_cost = _rebuild_ms - t0
	_name_edit.editable = tut == null or tut.target() == ["name", ""]  # 튜토리얼: 이름 단계에서만 이름 칸
	if tut != null:
		tut.typing = _name_edit.has_focus()
		match tut.update(draft, _problems, delta):
			"next":
				_tut_focus()
			"done":
				_tut_end()
				_say("내 문제가 만들어졌어요! [올라 보기]로 직접 올라 보세요")
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
	if tool in ["edit", "wall"] and pos.distance_to(dl[0]) <= dl[1] * 1.25 and _tut_edit_ok():
		_press = {"kind": "dial", "first": true}
		view.hold_cam = tool == "wall"  # 각도를 돌리는 동안 카메라(땅)는 그대로, 벽만 돈다
		_dial_to(pos)
		return
	if not _wall_rect().has_point(pos):
		return
	var w: Vector2 = view.screen_to_wall(pos)
	_press = {"kind": "wall", "pos": pos, "wall": w, "hold": _hold_at(w), "volume": _volume_at(w), "moved": false}


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
		if tool == "edit" and selected == "" and _press.hold != "" and _tut_edit_ok():
			selected = _press.hold  # 고른 홀드가 없으면 끌기 시작한 홀드를 옮긴다
		elif tool == "edit" and selected == "" and sel_type == "volume" and _press.volume != "" and _tut_edit_ok():
			selected = _press.volume
	if not _press.moved:
		return
	var vol := draft.volume(selected)
	if tool == "edit" and not vol.is_empty() and _tut_edit_ok():
		# 고른 볼륨을 끈다: 그 면의 홀드도 같이(벽 밖·바닥 아래로는 안 감)
		var hs := Volumes.side(vol) * 0.5
		var c := Volumes.center(vol)
		var to: Vector2 = c + view.screen_to_wall(pos) - _press.wall
		to = Vector2(clampf(to.x, -RouteDraft.WALL_HALF + hs, RouteDraft.WALL_HALF - hs), clampf(to.y, RouteDraft.Y_MIN + hs, maxf(RouteDraft.Y_MIN + hs, draft.max_y() - hs)))
		_preview = {"id": selected, "off": to - c, "rot": 0, "volume": true}
		view.preview_volume(selected, _preview.off, draft.holds.filter(func(h): return Volumes.contains(vol, Vector2(h.x, h.y))).map(func(h): return h.id))
		queue_redraw()
	elif tool == "edit" and selected != "" and _tut_edit_ok():
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
			var off: Vector2 = _preview.off
			if _preview.get("volume", false):
				var v := draft.volume(_preview.id)
				_preview = {}
				if off.length() >= 0.005:
					draft.move_volume(v.id, float(v.x) + off.x, float(v.y) + off.y)
			else:
				var h := draft.hold(_preview.id)
				_preview = {}
				if off.length() >= 0.005:
					draft.move(h.id, h.x + off.x, h.y + off.y)
			_changed()
		queue_redraw()
		return
	_tap_wall(p.wall, p.hold)


## 두 번째 손가락이 닿으면 하던 끌기를 그만둔다(옮기던 홀드는 제자리, 각도는 거기까지 반영).
func _cancel_press() -> void:
	if _press.get("kind", "") == "dial" and tool == "wall":
		_wall_dirty = false
		view.hold_cam = false
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
		if h.is_empty():
			return
		var d := posmod(int(round(a / 5.0)) * 5 - int(h.rot), 360)
		_preview = {"id": selected, "off": Vector2.ZERO, "rot": d}
		view.preview_hold(selected, Vector2.ZERO, d)
	else:
		var deg := clampi(int(round(a)), RouteDraft.WALL_DEG_MIN, RouteDraft.WALL_DEG_MAX)
		if deg != draft.wall_deg_at(sel_wall):
			draft.set_wall(sel_wall, deg, _press.get("first", false))
			_press.first = false
			_wall_dirty = true
	queue_redraw()


func _dial_end() -> void:
	if tool == "wall":
		_wall_dirty = false
		view.hold_cam = false
		_changed()
		return
	if _preview.is_empty():
		return
	var p := _preview
	_preview = {}
	if int(p.rot) != 0:
		draft.rotate(p.id, int(p.rot))
	_changed()


func _tap_wall(w: Vector2, hit: String) -> void:
	if tut != null and not _tut_edit_ok():
		var t := tut.target()
		# 벽을 누르는 단계(노란 원·고리 친 홀드)만: 다른 단계에서 벽을 누르거나 홀드를 고르면 예외가 생긴다
		if not (t.size() == 2 and t[0] in ["mark", "hold"]) or (t[0] == "mark" and hit != ""):
			_say("지금은 노란 고리가 있는 곳만 누를 수 있어요")
			return
	match tool:
		"edit":
			if hit != "":
				selected = "" if hit == selected else hit  # 고른 홀드를 다시 누르면 해제(끌면 화면 이동)
				if selected != "" and sel_type == "volume":  # 볼륨을 고른 채 홀드를 누르면 오른쪽 판도 그 홀드 종류로
					sel_type = draft.hold(selected).type
					if not RouteDraft.roles_for(sel_type).has(sel_role):
						sel_role = RouteDraft.roles_for(sel_type)[0]
			elif sel_type == "volume":
				# 볼륨: 놓인 볼륨을 누르면 고르고(다시 누르면 해제), 빈 벽을 누르면 놓는다. 볼륨 위에 홀드를 놓으려면 홀드 종류를 고른다
				var vid := _volume_at(w)
				if vid != "":
					selected = "" if vid == selected else vid
				else:
					var nid := draft.place_volume(sel_shape, w.x, w.y, sel_size, sel_vrot)
					if nid == "":
						_say("볼륨은 %d개까지 놓을 수 있어요" % Volumes.MAX)
					else:
						selected = nid
						_changed()
			else:
				if tut != null and not _tut_place_ok(w):
					return
				if tut != null and tut.mark(draft) != null and w.distance_to(tut.mark(draft)) <= EditorTutorial.MARK_R:
					w = tut.mark(draft)  # 원 안을 누르면 원 가운데에
				var id := draft.place(sel_type, w.x, w.y, sel_role, sel_size)
				if id == "":
					_say("홀드는 %d개까지 놓을 수 있어요" % RouteDraft.MAX_HOLDS)
				else:
					selected = id
					_changed()
		"wall":
			sel_wall = clampi(floori(w.y), 0, int(draft.max_y()))
		"erase":
			if hit != "":
				draft.remove(hit)
				if selected == hit:
					selected = ""
				_changed()
			elif _volume_at(w) != "":  # 볼륨은 지워도 그 면의 홀드는 벽에 남는다
				var vid := _volume_at(w)
				draft.remove_volume(vid)
				if selected == vid:
					selected = ""
				_changed()
		"start":
			var want: Dictionary = tut.start_want(draft) if tut != null else {}
			if not want.is_empty() and hit != "":
				if hit != want.hold:
					_say("노란 고리가 있는 홀드를 누르세요")
					return
				start_limb = want.limb
			if hit == "" and want.is_empty():
				hit = _volume_slot_at(w, start_limb)  # 볼륨 모서리·면도 시작 자리(2026-11-28)
			if hit != "":
				if draft.set_start(start_limb, hit):
					_changed()
					var order := [&"LH", &"RH", &"LF", &"RF"]
					start_limb = order[(order.find(start_limb) + 1) % 4]
				elif draft.hold(hit).get("role", "") == "face":
					_say("볼륨 면은 발로만 딛어요")
				elif draft.hold(hit).get("no_feet", false):
					_say("볼륨 아래 모서리는 발로 딛을 수 없어요")
				else:
					_say("탑은 시작홀드가 될 수 없어요")
	queue_redraw()


## 시작 자리로 고를 볼륨 모서리·면 id("V05/edge_t"): 모서리 선에서 9cm 안이면 그 모서리, 발이면 위를 보는 삼각 면 안. 없으면 "".
func _volume_slot_at(w: Vector2, limb: StringName) -> String:
	var best := ""
	var bd := 0.09
	for v in draft.volumes:
		var h := Volumes.side(v) * 0.5
		for e in Volumes.edges(v):
			var n: Vector2 = HoldTypes.rotate(Vector2(0, 1), float(e.rot))
			var along := Vector2(-n.y, n.x)
			var q: Vector2 = w - e.pos
			var d := Vector2(absf(q.dot(n)), maxf(0.0, absf(q.dot(along)) - h)).length()
			if d < bd:
				bd = d
				best = "%s/%s" % [v.id, e.slot_id]
	if best == "" and not PoseSolver.is_hand(limb):
		for v in draft.volumes:
			if not Volumes.face(v).is_empty() and Volumes.contains(v, w):
				return "%s/face" % v.id
	return best


## 벽 좌표 w의 볼륨 id(가장 앞으로 나온 것), 없으면 "".
func _volume_at(w: Vector2) -> String:
	return str(Volumes.at(draft.volumes, w).get("id", ""))


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


## 튜토리얼 중에는 가리키는 것만 된다(2026-11-27 사용자 "가이드하는 선택지 외에 다른걸 선택함으로써 발생할수있는 예외를 모두 없애.
## 가이드중인 스텝외에는 선택이 안되도록"). [끄기]·점검 창 버튼은 늘 되고, 자유롭게 놓기·점검 단계에서는 홀드 고치기가 된다.
func _tut_allows(action: String, arg: String) -> bool:
	if tut == null or action in ["tut", "check_close", "goto", "share_close", "copy"]:
		return true
	var t := tut.target()
	if t.size() == 2 and t[0] == action and str(t[1]) == arg:
		return true
	return _tut_edit_ok() and (action in ["type", "role", "size", "match", "rot", "delete", "undo", "shape", "vrot", "vtop"] or (action == "tool" and arg == "edit"))


## 튜토리얼에서 홀드를 마음대로 고쳐도 되는 단계(자유롭게 놓기, 점검: 막는 것을 고친다). 튜토리얼이 아니면 늘 된다.
func _tut_edit_ok() -> bool:
	return tut == null or tut.target() in [["tut_next", ""], ["check_open", ""]]


func _do(action: String, arg: String) -> void:
	if not _tut_allows(action, arg):
		_say("지금은 노란 고리가 있는 곳만 누를 수 있어요")
		return
	if action != "save":
		_tut_note("%s:%s" % [action, arg])  # 튜토리얼: 누른 버튼(저장은 된 뒤에)
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
		"type" when arg == "volume" or sel_type == "volume":  # 볼륨 ↔ 홀드: 고른 것은 놓는다(다른 쪽 크기 버튼이 바꾸지 않게)
			if (arg == "volume") != (not draft.volume(selected).is_empty()):
				selected = ""
			sel_type = arg
			if arg != "volume" and not RouteDraft.roles_for(arg).has(sel_role):
				sel_role = RouteDraft.roles_for(arg)[0]
			tool = "edit"
		"shape":
			sel_shape = arg
			var v := draft.volume(selected)
			if not v.is_empty():
				draft.set_volume(selected, arg, v.size, int(v.rot))
				_changed()
		"vtop":  # 고른 볼륨의 위 모서리를 탑으로(다시 누르면 풀림)
			var tid := selected + "/edge_t"
			if draft.top_edge == tid:
				draft.top_edge = ""
				_changed()
			elif draft.set_top_edge(tid):
				_changed()
			else:
				_say("위 모서리가 없는 볼륨이에요(삼각은 두꺼운 쪽이 위일 때)")
		"vrot":
			var v := draft.volume(selected)
			sel_vrot = posmod((int(v.rot) if not v.is_empty() else sel_vrot) + int(arg), 360)
			if not v.is_empty():
				draft.set_volume(selected, v.shape, v.size, sel_vrot)
				_changed()
		"type":  # 종류를 먼저 고른다. 발판 ↔ 다른 종류로 바뀌면 그 종류의 기본 쓰임(발판은 발로)
			var was_foot := HoldTypes.is_foot(sel_type)
			sel_type = arg
			var roles := RouteDraft.roles_for(arg)
			if not roles.has(sel_role) or was_foot != HoldTypes.is_foot(arg):
				sel_role = roles[0]
			tool = "edit"
		"role":
			if RouteDraft.roles_for(sel_type).has(arg):
				sel_role = arg
				tool = "edit"
			else:
				_say("%s 탑이 될 수 없어요(두 손으로 같이 잡을 수 없어요)" % _eun(HoldTypes.name_ko(sel_type)))
		"size" when not draft.volume(selected).is_empty():
			sel_size = arg
			var v := draft.volume(selected)
			draft.set_volume(selected, v.shape, arg, int(v.rot))
			_changed()
		"size":  # 놓을 크기. 고른 홀드가 있으면 그 홀드도
			sel_size = arg
			var h := draft.hold(selected)
			if h.get("role", "") == "top" and not HoldTypes.can_match(h.type, arg):
				_say("탑은 두 손으로 잡아야 해서 합손 되는 크기만 돼요. " + _match_hint(h.type))
			elif not h.is_empty():
				draft.set_size(selected, arg)
				_changed()
		"rot":
			draft.rotate(selected, int(arg))
			_changed()
		"tut":  # [만드는 법]: 켜기 / 끄기(카드의 [끄기]도 같음)
			if tut == null:
				tut = EditorTutorial.new()
				_tut_start()
			else:
				_tut_end()
		"wdeg":  # 화면 각도(180 − 오버행)로 더하기
			draft.set_wall(sel_wall, draft.wall_deg_at(sel_wall) - int(arg))
			_changed()
		"wdel":
			draft.remove_wall(sel_wall)
			_changed()
		"match":
			var h := draft.hold(selected)
			if not HoldTypes.can_match(h.type, h.size):
				_say(_match_hint(h.type))
			else:
				draft.set_matchable(selected, not bool(h.get("matchable", false)))
				_changed()
		"delete":
			if not draft.volume(selected).is_empty():
				draft.remove_volume(selected)
			else:
				draft.remove(selected)
			selected = ""
			_changed()
		"save":
			if not MyRoutes.save(draft):
				_say("저장하지 못했어요")
			else:
				_tut_note("save:")
				share_open = true
				share_code = str(game.progress.shared.get(draft.route_id, {}).get("code", "")) if game != null else ""
		"share_close":
			share_open = false
		"check_open":
			_checks = _check_items()
			check_open = true
		"check_close":
			check_open = false
		"goto":  # 점검 창 [보기]: 그 홀드를 고르고(홀드 놓기) 그 높이로 조금 다가가며 간다(2026-11-26 사용자)
			check_open = false
			var h := draft.hold(arg)
			var gv := draft.volume(arg)
			if not h.is_empty():
				tool = "edit"
				selected = arg
				_fly_to(h.y)
			elif not gv.is_empty():
				tool = "edit"
				sel_type = "volume"
				selected = arg
				_fly_to(float(gv.y))
			elif arg.is_valid_float():
				_fly_to(arg.to_float())
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
				# 2026-11-28: 홀드 12개 문제도 3~6초가 걸려 5초면 시간만 모자라 "못 찾음"이 됐다
				_bot_thread.start(func() -> Dictionary: return {"ok": PathExplorer.explore(r, {}, false, BOT_MS).ok})
				_say("봇이 길을 찾는 중… (최대 %d초)" % (BOT_MS / 1000))
	queue_redraw()


## 카메라를 높이 y로 0.5초 동안 옮기며 보이는 높이를 ZOOM_FOCUS까지 줄인다(이미 가까우면 그대로).
func _fly_to(y: float) -> void:
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(func(v: float) -> void: view.logic.cam_y = v, view.logic.cam_y, clampf(y, 0.8, draft.max_y()), 0.5)
	tw.tween_property(view, "zoom_h", minf(view.zoom_h, ZOOM_FOCUS), 0.5)


## 그 종류의 합손 되는 크기 안내(예 "크림프는 큰 것만 합손이 돼요").
static func _match_hint(type: String) -> String:
	var names := {"S": "작은 것", "M": "보통", "L": "큰 것"}
	var ok: Array = HoldTypes.SIZES.filter(func(sz): return HoldTypes.can_match(type, sz)).map(func(sz): return names[sz])
	var who := _eun(HoldTypes.name_ko(type))
	if ok.is_empty():
		return "%s 합손이 안 돼요" % who
	if ok.size() == HoldTypes.SIZES.size():
		return "%s 모든 크기가 합손이 돼요" % who
	return "%s %s만 합손이 돼요" % [who, "·".join(ok)]


## 받침에 맞는 은/는을 붙인다(저그는, 작은 발판은).
static func _eun(w: String) -> String:
	var c := w.unicode_at(w.length() - 1)
	return w + ("은" if c >= 0xAC00 and c <= 0xD7A3 and (c - 0xAC00) % 28 != 0 else "는")


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
				out.append({"level": "block", "text": "탑 홀드를 놓아 주세요. [홀드 놓기]에서 오른쪽의 종류와 [탑으로]를 고르고 벽을 누르세요.", "hold": ""})
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
			_ when draft.volume_issues().any(func(i): return i.text == p):
				for vi in draft.volume_issues():
					if vi.text == p:
						out.append({"level": "block", "text": p, "hold": str(vi.get("hold", vi.get("volume", ""))), "y": float(vi.y)})
						break
			_ when p == draft.wall_issue().get("text", ""):
				out.append({"level": "block", "text": p, "hold": "", "y": float(draft.wall_issue().y)})
			_:
				var errs: Array = draft.build().errors
				out.append({"level": "block", "text": p + (": " + str(errs[0]) if not errs.is_empty() else ""), "hold": ""})
	for w in _warn:
		out.append({"level": "warn", "text": w.text, "hold": w.hold, "y": w.y})
	if _bot_ok == 0:
		out.append({"level": "warn", "text": "봇이 길을 못 찾았어요. 직접 도움 없이 완등하면 올릴 수 있어요.", "hold": ""})
	if out.is_empty():
		out.append({"level": "ok", "text": "고칠 것도 살펴볼 것도 없어요. [올라 보기]로 직접 올라 보세요.", "hold": ""})
	return out


func _draw_check(size: Vector2) -> void:
	_buttons = []
	var box := Rect2(Vector2(size.x * 0.5 - 520 * k, size.y * 0.5 - 300 * k), Vector2(1040, 600) * k)
	_panel(box)
	var x := box.position.x + 30 * k
	var y := box.position.y + 52 * k
	_text(Vector2(x, y), "점검", 28, CHALK)
	_text(Vector2(x + 100 * k, y), "빨강: 고쳐야 저장·올라 보기를 할 수 있어요 · 주황: 그대로 둬도 되지만 살펴보세요", 17, DIM)
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
	_text_c(Rect2(Vector2(gx + 48 * k, 10 * k), Vector2(110, 52) * k), "난이도 " + draft.grade, 20, CHALK)
	_button(Rect2(Vector2(gx + 158 * k, 10 * k), Vector2(48, 52) * k), "▶", "grade", "1")
	_button(Rect2(Vector2(gx + 226 * k, 10 * k), Vector2(140, 52) * k), "만드는 법", "tut", "", 20, false)
	var x := size.x - 10 * k
	for b in [["저장", "save", 120], ["봇으로 확인", "bot", 150], ["올라 보기", "climb", 140], ["되돌리기", "undo", 120]]:
		x -= b[2] * k
		_button(Rect2(Vector2(x, 10 * k), Vector2(b[2], 52) * k), b[0], b[1], "", 22, b[1] == "climb" and _problems.is_empty())
		x -= 10 * k
	_draw_tools(size)
	_draw_panel(size)
	# 아래 상태
	_draw_scrollbar()
	draw_rect(Rect2(Vector2(0, size.y - 44 * k), Vector2(size.x, 44 * k)), Color(NIGHT, 0.86))
	draw_line(Vector2(0, size.y - 44 * k), Vector2(size.x, size.y - 44 * k), HAIR, 1.5 * k)
	var st := "홀드 %d/%d · %s벽 높이 %sm · 버전 %d · " % [draft.holds.size(), RouteDraft.MAX_HOLDS, "볼륨 %d/%d · " % [draft.volumes.size(), Volumes.MAX] if not draft.volumes.is_empty() else "", String.num(draft.wall_limit()), draft.version]
	st += "고칠 것 없음 — [올라 보기]를 할 수 있어요" if _problems.is_empty() else _problems[0]
	_text(Vector2(16 * k, size.y - 14 * k), st, 19, CHALK if _problems.is_empty() else WARN)
	var nw := _warn.size() + (1 if _bot_ok == 0 else 0)
	_button(Rect2(Vector2(size.x - 330 * k, size.y - 42 * k), Vector2(320, 40) * k), "점검 · 고칠 것 %d · 살펴볼 것 %d" % [_problems.size(), nw], "check_open", "", 18,
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
	# 보이는 높이 근처만 그린다(100m 벽 가장자리 선 800칸·홀드 300개를 매 프레임, 2026-11-26 최적화). 기울여 볼 때를 위해 넉넉히.
	var lo: float = view.logic.cam_y - view.zoom_h * 1.5 - 1.0
	var hi: float = view.logic.cam_y + view.zoom_h * 1.5 + 1.0
	for sx in [-RouteDraft.WALL_HALF, RouteDraft.WALL_HALF]:
		if hi > 0.0 and lo < top:
			_wall_line(Vector2(sx, maxf(0.0, lo)), Vector2(sx, minf(top, hi)), Color(CHALK, 0.35), 2.0)
	var lim := draft.wall_limit()
	if lim < top:
		_wall_line(Vector2(-RouteDraft.WALL_HALF, lim), Vector2(RouteDraft.WALL_HALF, lim), Color(CHALK, 0.5), 2.0)
		if view.in_view(Vector2(0, lim)):
			_outlined(w2s.call(Vector2(0, lim)) + Vector2(-210 * k, -10 * k), "벽 끝 %sm · 위에 놓으면 높아져요" % String.num(lim), 16, 420 * k)
	if tool == "wall":
		for wl in draft.walls:
			var y := float(wl.from_y)
			if y > 0.0 and y > lo and y < hi:
				_wall_line(Vector2(-RouteDraft.WALL_HALF, y), Vector2(RouteDraft.WALL_HALF, y), Color(0.55, 0.85, 1.0, 0.8), 2.0)
		for y in [float(sel_wall), float(sel_wall + 1)]:
			_wall_line(Vector2(-RouteDraft.WALL_HALF, y), Vector2(RouteDraft.WALL_HALF, y), SHOE, 4.0)
		if view.in_view(Vector2(RouteDraft.WALL_HALF, sel_wall + 0.5)):
			_outlined(w2s.call(Vector2(RouteDraft.WALL_HALF, sel_wall + 0.5)) + Vector2(10 * k, 6 * k), "%dm부터 %d°" % [sel_wall, 180 - draft.wall_deg_at(sel_wall)], 18, 0.0, HORIZONTAL_ALIGNMENT_LEFT)
	# 볼륨 테두리: 고른 것은 노랑, 막는 것이 있는 것은 빨강(겉면 네 모서리)
	var bad_vols := draft.volume_issues().map(func(i): return str(i.get("volume", "")))
	for v in draft.volumes:
		var sel: bool = v.id == selected
		if not (sel or bad_vols.has(v.id)) or float(v.y) < lo - 1.0 or float(v.y) > hi + 1.0:
			continue
		var c := Volumes.center(v) + (_preview.off as Vector2 if _preview.get("id", "") == v.id else Vector2.ZERO)
		var hs := Volumes.side(v) * 0.5
		var pts := [c + Vector2(-hs, -hs), c + Vector2(hs, -hs), c + Vector2(hs, hs), c + Vector2(-hs, hs)]
		if not pts.all(func(q): return view.in_view(q)):
			continue
		var sc := PackedVector2Array(pts.map(func(q): return w2s.call(q)))
		sc.append(sc[0])
		draw_polyline(sc, SHOE if sel else RED, (4.0 if sel else 3.0) * k, true)
	# 볼륨 모서리·면 시작 자리와 모서리 탑의 이름표(홀드 목록에 없어 따로)
	var vlabels := {}
	for l in draft.start:
		if String(draft.start[l]).contains("/"):
			vlabels[draft.start[l]] = LIMB_NAMES[l]
	if draft.top_edge != "":
		vlabels[draft.top_edge] = "탑"
	for id in vlabels:
		var vh := draft.hold(id)
		if not vh.is_empty() and view.in_view(Vector2(vh.x, vh.y)):
			_outlined(w2s.call(Vector2(vh.x, vh.y)) + Vector2(-60 * k, -22 * k), vlabels[id], 18, 120 * k)
	var start_of := {}
	for l in draft.start:
		if draft.start[l] != "":
			start_of[draft.start[l]] = LIMB_NAMES[l]
	for h in draft.holds:
		if (h.y < lo or h.y > hi) and _preview.get("id", "") != h.id:
			continue
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
		if h.role == "top":
			_outlined(c + Vector2(-60 * k, -r * 1.6), "탑", 20, 120 * k)
		if h.id == selected and h.role != "foot":
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
	# 1) 홀드 종류 2) 쓰임(손으로·발로·탑으로): 종류가 먼저, 그 종류가 못 쓰는 쓰임은 흐리게
	var y := 84 * k
	_text(Vector2(x, y + 16 * k), "홀드 종류", 16, DIM)
	y += 24 * k
	var cw := (w - 20 * k) / 3.0
	for i in TYPES.size():
		var r := Rect2(Vector2(x + (i % 3) * (cw + 10 * k), y + int(i / 3) * 54 * k), Vector2(cw, 46 * k))
		_button(r, "볼륨" if TYPES[i] == "volume" else HoldTypes.name_ko(TYPES[i]), "type", TYPES[i], 18, sel_type == TYPES[i] and tool == "edit")
	y += ceili(TYPES.size() / 3.0) * 54 * k + 2 * k
	if sel_type == "volume":
		_draw_volume_panel(size, x, w, y, cw)
		return
	_text(Vector2(x, y + 16 * k), "어떻게 쓸까요", 16, DIM)
	y += 24 * k
	var roles := RouteDraft.roles_for(sel_type)
	for i in ROLES.size():
		var ro: Array = ROLES[i]
		_button(Rect2(Vector2(x + i * (cw + 10 * k), y), Vector2(cw, 46 * k)), ro[1], "role", ro[0], 19, sel_role == ro[0] and tool == "edit", not roles.has(ro[0]))
	y += 56 * k
	# 3) 크기: 놓을 크기, 고른 홀드가 있으면 그 홀드의 크기(누르면 둘 다)
	var h := draft.hold(selected)
	_text(Vector2(x, y + 16 * k), "크기", 16, DIM)
	y += 24 * k
	var cur_size: String = h.size if not h.is_empty() else sel_size
	var top_type: String = h.type if not h.is_empty() and h.role == "top" else (sel_type if h.is_empty() and sel_role == "top" else "")
	for i in 3:
		var sz: String = HoldTypes.SIZES[i]
		_button(Rect2(Vector2(x + i * (cw + 10 * k), y), Vector2(cw, 46 * k)), SIZE_KO[sz], "size", sz, 19, cur_size == sz and tool == "edit",
			top_type != "" and not HoldTypes.can_match(top_type, sz))
	y += 56 * k
	if h.is_empty():
		_wrap(Vector2(x, y + 20 * k), "종류·쓰임·크기를 고르고 벽을 누르면 놓여요. 모든 홀드는 손으로도 발로도 써요. 놓인 홀드를 누르면 고르고, 끌면 옮기고, 아래 원으로 돌려요(잡는 면 방향).", w, 17, DIM)
		return
	var rot := int(h.rot) + (int(_preview.get("rot", 0)) if _preview.get("id", "") == selected else 0)
	_text(Vector2(x, y + 22 * k), "고른 홀드: %s · %s · 방향 %d°" % [HoldTypes.name_ko(h.type), ROLE_KO[h.role], posmod(rot, 360)], 20, CHALK)
	y += 34 * k
	if tool != "edit":
		return
	# 아래: 왼쪽 합손(켜면 노란 불)·지우기, 오른쪽 돌리기 원, 맨 아래 돌리기 버튼(원을 끄는 동안 홀드가 바로 돈다)
	var lw := w - 170 * k
	if h.role != "top":
		_button(Rect2(Vector2(x, y + 10 * k), Vector2(lw, 46 * k)), "합손", "match", "", 20, h.matchable, not HoldTypes.can_match(h.type, h.size))
	elif h.role == "top":
		_wrap(Vector2(x, y + 30 * k), "탑은 두 손으로 잡으면 끝나요", lw, 16, DIM)
	_button(Rect2(Vector2(x, y + 66 * k), Vector2(lw, 46 * k)), "이 홀드 지우기", "delete", "", 19)
	var bw := (w - 30 * k) / 4.0
	var btn_y := size.y - 44 * k - 58 * k
	for i in 4:
		var b: Array = [["-45°", "-45"], ["-5°", "-5"], ["+5°", "5"], ["+45°", "45"]][i]
		_button(Rect2(Vector2(x + i * (bw + 10 * k), btn_y), Vector2(bw, 46 * k)), b[0], "rot", b[1], 19)
	var dl := _dial()
	_draw_dial(dl[0], dl[1], true, rot)


## 볼륨을 고른 오른쪽 판(2026-11-28): 모양·크기(고른 볼륨이 있으면 그 볼륨도), 고른 볼륨의 정보·방향 돌리기·지우기.
func _draw_volume_panel(_size: Vector2, x: float, w: float, y: float, cw: float) -> void:
	var v := draft.volume(selected)
	_text(Vector2(x, y + 16 * k), "모양", 16, DIM)
	y += 24 * k
	var shape: String = v.shape if not v.is_empty() else sel_shape
	for i in Volumes.SHAPES.size():
		var sh: String = Volumes.SHAPES[i]
		_button(Rect2(Vector2(x + i * (cw + 10 * k), y), Vector2(cw, 46 * k)), SHAPE_KO[sh], "shape", sh, 19, shape == sh and tool == "edit")
	y += 56 * k
	_text(Vector2(x, y + 16 * k), "크기", 16, DIM)
	y += 24 * k
	var cur: String = v.size if not v.is_empty() else sel_size
	for i in 3:
		var sz: String = HoldTypes.SIZES[i]
		_button(Rect2(Vector2(x + i * (cw + 10 * k), y), Vector2(cw, 46 * k)), SIZE_KO[sz], "size", sz, 19, cur == sz and tool == "edit")
	y += 56 * k
	var rot := int(v.rot) if not v.is_empty() else sel_vrot
	if shape == "wedge":
		_text(Vector2(x, y + 16 * k), "두꺼운 쪽: %s" % THICK_KO[rot], 16, DIM)
		y += 24 * k
		_button(Rect2(Vector2(x, y), Vector2(cw * 1.5, 46 * k)), "↺ 90°", "vrot", "-90", 19)
		_button(Rect2(Vector2(x + cw * 1.5 + 10 * k, y), Vector2(cw * 1.5, 46 * k)), "↻ 90°", "vrot", "90", 19)
		y += 56 * k
	if v.is_empty():
		_wrap(Vector2(x, y + 20 * k), "모양·크기를 고르고 빈 벽을 누르면 볼륨이 놓여요. 볼륨 모서리는 손으로 잡고 발로 딛어요. 볼륨 위에 홀드를 놓으려면 홀드 종류를 고르고 볼륨을 누르세요. 놓인 볼륨은 [볼륨]을 고른 채 누르면 골라지고, 끌면 위의 홀드와 같이 옮겨져요.", w, 17, DIM)
		return
	var on := draft.holds.filter(func(h): return Volumes.contains(v, Vector2(h.x, h.y))).size()
	_text(Vector2(x, y + 22 * k), "고른 볼륨: %s · %s · 위 홀드 %d개" % [SHAPE_KO[v.shape], SIZE_KO[v.size], on], 20, CHALK)
	y += 34 * k
	_button(Rect2(Vector2(x, y + 10 * k), Vector2(w - 170 * k, 46 * k)), "이 볼륨 지우기", "delete", "", 19)
	var is_top: bool = draft.top_edge == str(v.id) + "/edge_t"
	_button(Rect2(Vector2(x, y + 66 * k), Vector2(w - 170 * k, 46 * k)), "위 모서리를 탑으로", "vtop", "", 19, is_top, draft.hold(v.id + "/edge_t").is_empty())


## 벽 각도 도구의 오른쪽 판: 설명, 고른 높이, 아래에 조절 원과 버튼(끄는 동안 3D 벽이 바로 접힌다).
func _draw_wall_panel(size: Vector2, x: float, w: float) -> void:
	var y := 84 * k
	var dl := _dial()
	var c: Vector2 = dl[0]
	var r: float = dl[1]
	var btn_y := size.y - 44 * k - 58 * k
	var bw := (w - 30 * k) / 4.0
	_text(Vector2(x, y + 24 * k), "벽 각도", 24, CHALK)
	_wrap(Vector2(x, y + 58 * k), "벽을 눌러 높이를 고른 뒤 원을 돌리세요. 그 높이부터 위가 기울어요(땅 기준). 90°는 천장, 180°는 수직, 270°는 뒤로 누운 벽, 300°까지 돼요.", w, 17, DIM)
	var deg := draft.wall_deg_at(sel_wall)
	_text(Vector2(x, c.y - r - 30 * k), "%dm부터 %d°" % [sel_wall, 180 - deg], 22, CHALK)
	if sel_wall > 0 and draft.walls.any(func(wl): return int(wl.from_y) == sel_wall):
		_button(Rect2(Vector2(x, c.y - r - 100 * k), Vector2(w, 44 * k)), "이 높이 꺾임 없애기(아래 벽과 같게)", "wdel", "", 18)
	for i in 4:
		var b: Array = [["-10°", "-10"], ["-1°", "-1"], ["+1°", "1"], ["+10°", "10"]][i]
		_button(Rect2(Vector2(x + i * (bw + 10 * k), btn_y), Vector2(bw, 46 * k)), b[0], "wdeg", b[1], 19)
	draw_line(c, c + Vector2(0, r * 0.9), Color(CHALK, 0.5), 5.0 * k)  # 땅에 수직인 아래쪽과 벽 사이 각이 화면 각도
	_draw_dial(c, r, true, deg)
	for t in [90, 180, 270]:  # 눈금 이름(화면 각도)
		var d := Vector2(sin(deg_to_rad(180 - t)), -cos(deg_to_rad(180 - t)))
		draw_string(font_m, c + d * (r + 18 * k) + Vector2(-30 * k, 6 * k), "%d°" % t, HORIZONTAL_ALIGNMENT_CENTER, 60 * k, int(14 * k), DIM)


## 조절 원: 눈금(돌리기 45°, 벽 각도는 오버행 −120~90°(화면 300~90°) 15°마다)과 손잡이(위 0, 시계 방향 + ang도).
func _draw_dial(c: Vector2, r: float, on: bool, ang: float) -> void:
	var col := Color(CHALK, 0.7) if on else Color(CHALK, 0.25)
	draw_circle(c, r, Color(NIGHT, 0.7))
	draw_arc(c, r, 0, TAU, 48, col, 3.0 * k)
	var ticks := range(0, 360, 45) if tool == "edit" else range(RouteDraft.WALL_DEG_MIN, RouteDraft.WALL_DEG_MAX + 1, 15)
	for t in ticks:
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


## 버튼(홈과 같음): 주(strong, 고른 것·켜진 것·누를 다음 것) = 노란 알약 + 남색 굵은 글자, 보조 = 반투명 남색 알약 + 가는 테두리 + 분필색 글자.
## dim: 지금은 안 되는 것(흐린 테두리·글자). 눌리면 왜 안 되는지 알려 준다.
func _button(r: Rect2, text: String, action: String, arg: String, fs := 22, strong := false, dim := false) -> void:
	var radius := r.size.y * 0.5 if r.size.y <= 72 * k else 22 * k
	draw_style_box(_box(SHOE if strong else Color(NIGHT, 0.5 if dim else 0.72), radius, Color(0, 0, 0, 0) if strong else Color(CHALK, 0.1 if dim else 0.26), 1.5), r)
	if text != "":
		var f: Font = font_b if strong else font_m
		draw_string(f, Vector2(r.position.x, _baseline(r, fs, f)), text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(fs * k), NIGHT if strong else Color(CHALK, 0.32 if dim else 1.0))
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


func _tut_start() -> void:
	tut.begin(draft)
	_tut_focus()


## 누를 곳(원·홀드)이 화면 밖이거나 안내 카드 밑이면 그 높이로 간다.
func _tut_focus() -> void:
	if tut == null or view == null:
		return
	var p = _tut_spot()
	var wr := _wall_rect()
	if p != null and not Rect2(wr.position + Vector2(0, 140 * k), wr.size - Vector2(0, 140 * k)).has_point(view.world_to_screen(p)):
		view.logic.cam_y = clampf(p.y, 0.8, draft.max_y())


## 지금 누를 벽 위 자리: 원 가운데 또는 가리키는 홀드. 없으면 null.
func _tut_spot() -> Variant:
	var t := tut.target()
	if t.size() == 2 and t[0] == "hold":
		var h := draft.hold(tut.spot_hold(draft, int(t[1])))
		return null if h.is_empty() else Vector2(h.x, h.y)
	return tut.mark(draft)


## 시작 자리 단계: 맞는 종류(손·발)로 노란 원 안에만 놓는다.
func _tut_place_ok(w: Vector2) -> bool:
	if not tut.mark_strict():
		return true
	if sel_role != tut.place_kind():
		_say("먼저 오른쪽 %s를 누르세요" % ("[크림프]와 [발로]" if tut.place_kind() == "foot" else "[저그]와 [손으로]"))
		return false
	if w.distance_to(tut.mark(draft)) > EditorTutorial.MARK_R:
		_say("노란 원 안을 누르세요")
		return false
	return true


## 벽 위 안내: 시작 자리 번호(1~4, 편집 단계 전까지), 지금 누를 노란 원(번호·"탑") 또는 홀드 고리. 모두 깜빡인다.
func _draw_tut_wall() -> void:
	var t := tut.target()
	var a := _pulse()
	if tut.index < _TUT_EDIT:
		for i in 4:
			var id := tut.spot_hold(draft, i)
			var p: Vector2 = EditorTutorial.SPOTS[i]
			if id != "" and view.in_view(p) and t != ["hold", i]:
				_outlined(view.world_to_screen(p) + Vector2(26, 8) * k, str(i + 1), 18, 0.0, HORIZONTAL_ALIGNMENT_LEFT)
	var m = tut.mark(draft)
	if m != null and view.in_view(m):
		var c: Vector2 = view.world_to_screen(m)
		var r: float = (view.world_to_screen(m + Vector2(EditorTutorial.MARK_R, 0)) - c).length()
		draw_circle(c, r, Color(SHOE, 0.16))
		draw_arc(c, r, 0, TAU, 48, Color(SHOE, a), 4.0 * k)
		var label := "탑" if int(t[1]) < 0 else str(int(t[1]) + 1)
		draw_string_outline(font_b, c + Vector2(-40 * k, 11 * k), label, HORIZONTAL_ALIGNMENT_CENTER, 80 * k, int(30 * k), int(6 * k), NIGHT)
		draw_string(font_b, c + Vector2(-40 * k, 11 * k), label, HORIZONTAL_ALIGNMENT_CENTER, 80 * k, int(30 * k), SHOE)
	elif t.size() == 2 and t[0] == "hold":
		var p = _tut_spot()
		if p != null and view.in_view(p):
			var c: Vector2 = view.world_to_screen(p)
			var r: float = (view.world_to_screen(p + Vector2(0.1, 0)) - c).length()
			draw_arc(c, r * 1.8, 0, TAU, 40, Color(SHOE, a), 4.5 * k)
			_outlined(c + Vector2(r * 1.8 + 8 * k, 8 * k), str(int(t[1]) + 1), 20, 0.0, HORIZONTAL_ALIGNMENT_LEFT)


## 안내 카드(플레이 튜토리얼 카드와 같은 모양): 벽 위 가운데에 단계 칩·할 일·도움말(15초 진행 없을 때)·[다음](자유 단계)·[끄기].
func _draw_tutorial() -> void:
	_draw_tut_wall()
	var wr := _wall_rect()
	var w := minf(wr.size.x - 24 * k, 860 * k)
	var free := tut.target() == ["tut_next", ""]
	var bw := 96 * k
	var nw := 110 * k if free else 0.0
	var tx := 92 * k
	var tw := w - tx - bw - nw - 36 * k
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
	if free:
		_button(Rect2(Vector2(r.end.x - bw - nw - 22 * k, r.position.y + 12 * k), Vector2(nw, 40 * k)), "다음", "tut_next", "", 19, true)


## 튜토리얼이 가리키는 곳: 깜빡이는 노란 고리(밝기는 0.1 단위라 모양 캐시가 커지지 않음).
func _ring(r: Rect2) -> void:
	var g := r.grow(5 * k)
	draw_style_box(_box(Color(0, 0, 0, 0), minf(g.size.y * 0.5, 26 * k), Color(SHOE, _pulse()), 3.0), g)


func _pulse() -> float:
	return snappedf(0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.006), 0.1)


func _exit_tree() -> void:
	if _bot_thread != null:
		_bot_thread.wait_to_finish()
