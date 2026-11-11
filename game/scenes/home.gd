extends Node2D
## 홈 화면(docs/28 §5.2–5.4). 위 탭 일반/기술(마지막 탭 기억), 일반: 등급 줄 + 문제 카드, 기술: 과정 카드 → 과정 화면.
## 진행·콘텐츠는 자동 로드 Game에서 읽는다. 플레이 화면처럼 직접 그리고 누른 위치로 동작을 고른다
## (터치→마우스 흉내를 끈 프로젝트라 Control 버튼 대신). 잠금·완료는 색만이 아니라 글자·자물쇠로 함께 보인다(docs/05).
## 문제 파일이 아직 없는 과정 슬롯은 "준비 중"으로 보이고 시작할 수 없다.

const CREAM := Color("f1d59a")
const INK := Color("302820")
const BG := Color("2b2622")
const CARD := Color(0.16, 0.15, 0.13)
const DIM := Color(1, 1, 1, 0.55)
const SLOT_NAMES := {"tutorial": "튜토리얼", "easy": "쉬움", "normal": "보통", "hard": "어려움"}

var game: Node
var font: Font
var k := 1.0
var tab := "general"
var grade := ""
var course_id := ""   # 비어 있지 않으면 기술 탭에서 그 과정 화면
var _buttons: Array = []  # [{rect, action, arg}]
var _techs := TechniqueJudge.defs()
var _look_ok := false        # 지금 몸 비율에 맞는 캐릭터 모델이 있을 때만 [캐릭터] 버튼(2026-11-11)
var choosing_look := false   # 캐릭터 고르기 창(docs/34 §7). 오른쪽 위 [캐릭터] 버튼
var look := {}               # 고르는 중인 외형(저장 전)
var _asm: CharacterAssembler
var _pv: SubViewport         # 3D 미리보기(창이 열린 동안만)
var _pv_model: Node3D
const LOOK_ROWS := [["body", "성별"], ["hair", "헤어"], ["top", "상의"], ["bottom", "하의"], ["chalk", "초크백"], ["shoes", "클라이밍화"]]
var choosing_level := false  # 난이도(초급·중급) 고르기 창. 처음 시작할 때와 오른쪽 위 [난이도] 버튼
const LEVEL_INFO := {
	"beginner": {"name": "초급", "desc": ["떨어지기 전 버틸 시간 10배", "어떻게 버틸지 화면에 안내", "위험 게이지 눌러 자동 도움 3번"]},
	"advanced": {"name": "고급", "desc": ["경고·알림이 없어요", "손 게이지와 몸의 균형만 보고", "스스로 판단해요"]},
	"intermediate": {"name": "중급", "desc": ["경고와 안내를 보여 줘요", "손을 다 놓으면 1.5초 뒤 떨어져요", "손에 익은 분께"]},
}


func _ready() -> void:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Noto Sans CJK KR", "Noto Sans KR", "Apple SD Gothic Neo", "sans-serif"])
	font = sf
	game = get_node_or_null("/root/Game")
	if game == null:
		push_error("홈: 자동 로드 Game이 없어요")
		return
	var progress: Progress = game.progress
	tab = progress.last_tab if progress.last_tab in ["general", "technique"] else "general"
	var focus: Dictionary = game.home_focus
	game.home_focus = {}
	if focus.has("tab"):
		_set_tab(str(focus.tab))
	grade = str(focus.get("grade", _default_grade()))
	course_id = str(focus.get("course", ""))
	if tab != "technique":
		course_id = ""
	_look_ok = CharacterAssembler.load_catalog().model_compatible()
	get_viewport().size_changed.connect(queue_redraw)
	# 처음 시작: 난이도부터 고른다(2026-11-08). 고른 뒤 첫 실행이면 기본 조작 튜토리얼로.
	choosing_level = progress.level == ""
	if not choosing_level:
		_first_run_tutorial()
	queue_redraw()


## 첫 실행: 기본 조작 튜토리얼로 바로(28 §5.1). 파일이 없으면 홈에 남아 [배우러 가기]/[건너뛰기]로 진행.
func _first_run_tutorial() -> void:
	if game.progress.is_first_run() and not game.first_run_sent and game.index.route(Progress.BASIC_TUTORIAL) != null:
		game.first_run_sent = true
		game.play.call_deferred(Progress.BASIC_TUTORIAL)


## 열린 등급 중 가장 높은 것(없으면 첫 등급).
func _default_grade() -> String:
	var gs: Array[String] = game.index.grades()
	var best := gs[0] if not gs.is_empty() else "V0"
	for g in gs:
		if game.progress.grade_unlocked(g, game.index):
			best = g
	return best


func _set_tab(t: String) -> void:
	tab = t
	game.get_flow().set_last_tab(t)


# ---------- 입력 ----------

func _input(event: InputEvent) -> void:
	if game == null:
		return
	if event is InputEventScreenTouch and not event.pressed and not event.canceled:
		_tap(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_tap(event.position)


func _tap(pos: Vector2) -> void:
	for i in range(_buttons.size() - 1, -1, -1):
		var b: Dictionary = _buttons[i]
		if (b.rect as Rect2).has_point(pos):
			_do(b.action, b.arg)
			return


func _do(action: String, arg: String) -> void:
	match action:
		"level":
			game.get_flow().set_level(arg)
			choosing_level = false
			_first_run_tutorial()
		"level_open":
			choosing_level = true
		"look_open":
			_open_look()
		"look_prev", "look_next":
			look[arg] = _asm.cycle(look, arg, -1 if action == "look_prev" else 1)
			if arg == "body":  # 성별을 바꾸면 그 몸의 기본 헤어로(나머지는 유지)
				look.hair = str(_asm.body(look.body).get("defaults", {}).get("hair", look.get("hair", "")))
			look = _asm.normalize(look)
			_asm.apply(_pv_model, look)
		"look_save":
			game.get_flow().set_look(look)
			_close_look()
		"look_cancel":
			_close_look()
		"level_close":
			choosing_level = game.progress.level == ""
		"tab":
			_set_tab(arg)
			course_id = ""
		"grade":
			grade = arg
		"course":
			course_id = arg
		"courses":
			course_id = ""
		"learn":
			_set_tab("technique")
			course_id = arg
		"play":
			game.play(arg)
			return
		"skip":
			game.skip_basic()
			_set_tab("general")
			course_id = ""
			grade = _default_grade()
	queue_redraw()


# ---------- 그리기 ----------

func _draw() -> void:
	_buttons = []
	var size := get_viewport_rect().size
	k = maxf(minf(size.x / 1600.0, size.y / 900.0), 0.25)
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	if game == null:
		return
	_draw_tabs(size)
	if tab == "general":
		_draw_general(size)
	elif course_id != "":
		_draw_course(size)
	else:
		_draw_courses(size)
	if not choosing_level and _look_ok:
		_button(Rect2(Vector2(size.x - 490 * k, 24 * k), Vector2(220, 56) * k), "캐릭터", "look_open", "", 22)
	var lv: String = game.progress.level
	if lv != "":
		var r := Rect2(Vector2(size.x - 250 * k, 24 * k), Vector2(220, 56) * k)
		_button(r, "난이도: " + str(LEVEL_INFO[lv].name), "level_open", "", 22)
	if choosing_level:
		_draw_level_choice(size)
	elif choosing_look:
		_draw_look(size)


## 난이도 고르기 창. 다른 버튼을 덮고(앞서 등록된 버튼은 지움) 카드 두 장만 누를 수 있다.
func _draw_level_choice(size: Vector2) -> void:
	_buttons = []
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.72))
	var cur: String = game.progress.level
	var title := "난이도를 골라 주세요" if cur == "" else "난이도 바꾸기"
	draw_string(font, Vector2(0, size.y * 0.5 - 250 * k), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, int(44 * k), CREAM)
	draw_string(font, Vector2(0, size.y * 0.5 - 200 * k), "언제든 오른쪽 위 [난이도]에서 바꿀 수 있어요", HORIZONTAL_ALIGNMENT_CENTER, size.x, int(22 * k), DIM)
	var cw := 420.0 * k
	var ch := 300.0 * k
	var gap := 40.0 * k
	var lvs := ["beginner", "intermediate", "advanced"]
	cw = minf(cw, (size.x - 80 * k - gap * (lvs.size() - 1)) / lvs.size())
	var x := size.x * 0.5 - (cw * lvs.size() + gap * (lvs.size() - 1)) * 0.5
	for lv in lvs:
		var r := Rect2(Vector2(x, size.y * 0.5 - 150 * k), Vector2(cw, ch))
		var on: bool = lv == cur
		var sb := StyleBoxFlat.new()
		sb.bg_color = {"beginner": Color("3b3128"), "intermediate": Color("2f3036"), "advanced": Color("2a2226")}[lv]
		sb.border_color = CREAM if on else Color(1, 1, 1, 0.25)
		sb.set_border_width_all(maxi(2, int((4 if on else 2) * k)))
		sb.set_corner_radius_all(int(24 * k))
		sb.anti_aliasing = true
		draw_style_box(sb, r)
		var info: Dictionary = LEVEL_INFO[lv]
		var accent: Color = {"beginner": Color("8cc8ff"), "intermediate": Color("f1d59a"), "advanced": Color("ff9a7a")}[lv]
		draw_string(font, Vector2(r.position.x, r.position.y + 78 * k), ("✓ " if on else "") + str(info.name), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(52 * k), accent)
		var y := r.position.y + 140 * k
		for line in info.desc:
			draw_string(font, Vector2(r.position.x, y), line, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(24 * k), Color.WHITE if line != info.desc[-1] else DIM)
			y += 38 * k
		_buttons.append({"rect": r, "action": "level", "arg": lv})
		x += cw + gap
	if cur != "":
		var br := Rect2(Vector2(size.x * 0.5 - 100 * k, size.y * 0.5 + 180 * k), Vector2(200, 56) * k)
		_button(br, "닫기", "level_close", "", 22)


## 위 탭 두 개. 고른 탭은 채운 바탕 + 아래 막대 + "●" 표시(색만으로 구분하지 않음).
func _draw_tabs(size: Vector2) -> void:
	var w := 220.0 * k
	var h := 64.0 * k
	var x := size.x * 0.5 - w - 8 * k
	for t in [["general", "일반"], ["technique", "기술"]]:
		var on: bool = tab == t[0]
		var r := Rect2(Vector2(x, 20 * k), Vector2(w, h))
		_button(r, ("● " if on else "") + t[1], "tab", t[0], 28, on)
		if on:
			draw_rect(Rect2(Vector2(r.position.x, r.end.y + 4 * k), Vector2(w, 5 * k)), CREAM)
		x += w + 16 * k


# ---------- 일반 탭 ----------

func _draw_general(size: Vector2) -> void:
	var idx: ContentIndex = game.index
	var progress: Progress = game.progress
	var gs: Array[String] = idx.grades()
	var x := 60.0 * k
	var y := 120.0 * k
	for g in gs:
		var open := progress.grade_unlocked(g, idx)
		var r := Rect2(Vector2(x, y), Vector2(150, 76) * k)
		var sub := "완료 %d/%d" % [progress.cleared_count(g, idx), idx.general(g).size()] if open else "잠김"
		_button(r, "", "grade", g, 26, g == grade)
		var tc := INK if g == grade else (Color.WHITE if open else DIM)
		draw_string(font, Vector2(r.position.x, r.position.y + 34 * k), g, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(28 * k), tc)
		draw_string(font, Vector2(r.position.x, r.position.y + 62 * k), sub, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(18 * k), tc)
		if not open:
			_lock(r.position + Vector2(18, 18) * k, tc)
		if g == grade:
			draw_rect(Rect2(Vector2(r.position.x, r.end.y + 4 * k), Vector2(r.size.x, 5 * k)), CREAM)
		x += r.size.x + 14 * k
	if gs.is_empty():
		_text(Vector2(60 * k, 160 * k), "아직 문제가 없어요", 24, DIM)
		return
	y += 100 * k
	var lock := progress.grade_lock_text(grade, idx)
	if lock != "":
		_lock(Vector2(72 * k, y - 8 * k), CREAM)
		_text(Vector2(92 * k, y), lock, 24, CREAM)
		if progress.first_run_locked(idx):  # 기본 조작 파일이 없어 바로 못 갔을 때도 길을 남긴다
			_button(Rect2(Vector2(92 * k + font.get_string_size(lock, HORIZONTAL_ALIGNMENT_LEFT, -1, int(24 * k)).x + 24 * k, y - 34 * k), Vector2(200, 48) * k),
				"배우러 가기", "learn", Progress.BASIC_COURSE, 22, true)
		y += 30 * k
	var routes: Array[RouteDef] = idx.general(grade)
	var cw := (size.x - 120 * k - 3 * 20 * k) / 4.0
	for i in routes.size():
		var r := Rect2(Vector2(60 * k + (i % 4) * (cw + 20 * k), y + 20 * k + (i / 4) * 330 * k), Vector2(cw, 310 * k))
		_draw_problem_card(r, routes[i])


func _draw_problem_card(r: Rect2, route: RouteDef) -> void:
	var idx: ContentIndex = game.index
	var progress: Progress = game.progress
	var lock := progress.route_lock_text(route, idx)
	draw_rect(r, CARD)
	draw_rect(r, Color(1, 1, 1, 0.35 if lock != "" else 0.7), false, 2.0)
	var x := r.position.x + 18 * k
	var w := r.size.x - 36 * k
	var y := r.position.y + 44 * k
	draw_string(font, Vector2(x, y), _route_name(route), HORIZONTAL_ALIGNMENT_LEFT, w, int(26 * k), Color.WHITE)
	y += 40 * k
	draw_multiline_string(font, Vector2(x, y), "필요 기술: " + _tech_names(route.required_techniques), HORIZONTAL_ALIGNMENT_LEFT, w, int(18 * k), 2, DIM)
	y += 56 * k
	_draw_medals(Vector2(x, y), route)
	y += 40 * k
	if lock != "":
		_lock(Vector2(x + 8 * k, y + 2 * k), CREAM)
		draw_multiline_string(font, Vector2(x + 26 * k, y + 10 * k), lock, HORIZONTAL_ALIGNMENT_LEFT, w - 26 * k, int(20 * k), 2, CREAM)
		var learn := _locked_button_course(route)
		if learn != "" and progress.grade_unlocked(route.grade, idx):
			_button(Rect2(Vector2(x, r.end.y - 70 * k), Vector2(w, 54 * k)), "배우러 가기", "learn", learn, 22, true)
		return
	_button(Rect2(Vector2(x, r.end.y - 70 * k), Vector2(w, 54 * k)), "▶ 시작", "play", route.route_id, 24, true)


## 메달 3개를 글자로: "✓ 완등  – 무추락  – 시간".
func _draw_medals(pos: Vector2, route: RouteDef) -> void:
	var rec: Dictionary = game.progress.cleared.get(route.route_id, {})
	var medals := [["완등", not rec.is_empty()], ["무추락", rec.get("no_fall", false)], ["시간", rec.get("time", false)]]
	var x := pos.x
	for m in medals:
		var got: bool = m[1]
		var t: String = ("✓ " if got else "– ") + str(m[0])
		draw_string(font, Vector2(x, pos.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(19 * k), CREAM if got else DIM)
		x += font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(19 * k)).x + 16 * k


## 문제가 요구하는 버튼 기술 중 아직 잠긴 것을 가르치는 과정 ID(없으면 "").
func _locked_button_course(route: RouteDef) -> String:
	var open: Array[StringName] = game.progress.unlocked_buttons(game.index)
	for t in route.required_techniques:
		if _techs.has(t) and _techs[t].input == &"button" and not t in open:
			for c in game.index.courses():
				if c.kind == "button" and t in c.techniques:
					return c.course_id
	return ""


func _tech_names(ids: Array) -> String:
	if ids.is_empty():
		return "없음"
	var names := PackedStringArray()
	for t in ids:
		if _techs.has(t):
			names.append(str(_techs[t].name_ko) + (" (버튼)" if _techs[t].input == &"button" else ""))
		else:
			names.append(str(t))
	return ", ".join(names)


func _route_name(route: RouteDef) -> String:
	return route.name_ko if route.name_ko != "" else route.route_id


# ---------- 기술 탭 ----------

func _draw_courses(size: Vector2) -> void:
	var list: Array[Dictionary] = game.index.courses()
	var cols := 3
	var cw := (size.x - 120 * k - (cols - 1) * 20 * k) / cols
	var ch := 200.0 * k
	for i in list.size():
		var r := Rect2(Vector2(60 * k + (i % cols) * (cw + 20 * k), 130 * k + (i / cols) * (ch + 20 * k)), Vector2(cw, ch))
		_draw_course_card(r, list[i])


func _draw_course_card(r: Rect2, c: Dictionary) -> void:
	var progress: Progress = game.progress
	draw_rect(r, CARD)
	draw_rect(r, Color(1, 1, 1, 0.7), false, 2.0)
	_buttons.append({"rect": r, "action": "course", "arg": c.course_id})
	var x := r.position.x + 18 * k
	var w := r.size.x - 36 * k
	draw_string(font, Vector2(x, r.position.y + 44 * k), c.name_ko, HORIZONTAL_ALIGNMENT_LEFT, w, int(26 * k), Color.WHITE)
	draw_string(font, Vector2(x, r.position.y + 78 * k), "버튼 기술" if c.kind == "button" else "패드 기술", HORIZONTAL_ALIGNMENT_LEFT, w, int(19 * k), DIM)
	draw_string(font, Vector2(x, r.position.y + 116 * k), _course_progress(c), HORIZONTAL_ALIGNMENT_LEFT, w, int(21 * k), CREAM)
	if c.kind == "button":
		var open := progress.tutorial_done(c.tutorial)
		var t := "✓ 버튼 열림" if open else "버튼 잠김 · 튜토리얼을 마치면 열려요"
		if not open:
			_lock(Vector2(x + 8 * k, r.position.y + 150 * k), DIM)
		draw_string(font, Vector2(x + (0.0 if open else 26 * k), r.position.y + 158 * k), t, HORIZONTAL_ALIGNMENT_LEFT, w, int(19 * k), CREAM if open else DIM)
	draw_string(font, Vector2(x, r.end.y - 14 * k), "열기 ›", HORIZONTAL_ALIGNMENT_RIGHT, w, int(19 * k), DIM)


## "튜토리얼 ✓ · 문제 2/3". 기본 조작을 건너뛰었으면 "튜토리얼 건너뜀".
func _course_progress(c: Dictionary) -> String:
	var progress: Progress = game.progress
	var t := "튜토리얼 –"
	if progress.tutorial_done(c.tutorial):
		t = "튜토리얼 ✓"
	elif c.course_id == Progress.BASIC_COURSE and progress.basic_skipped:
		t = "튜토리얼 건너뜀"
	if c.problems.is_empty():
		return t
	var n := 0
	for id in c.problems:
		if progress.is_cleared(id):
			n += 1
	return "%s · 문제 %d/%d" % [t, n, c.problems.size()]


func _draw_course(size: Vector2) -> void:
	var c: Dictionary = game.index.course(course_id)
	var progress: Progress = game.progress
	_button(Rect2(Vector2(60, 120) * k, Vector2(200, 52) * k), "‹ 과정 목록", "courses", "", 22)
	if c.is_empty():
		_text(Vector2(60 * k, 230 * k), "과정을 찾지 못했어요", 24, DIM)
		return
	var x := 60.0 * k
	var w := size.x - 120 * k
	_text(Vector2(x, 225 * k), "%s · %s" % [c.name_ko, "버튼 기술" if c.kind == "button" else "패드 기술"], 32, Color.WHITE)
	var y := 270.0 * k
	var texts := _course_texts(c)
	for row in [["목적", "purpose"], ["쓰는 때", "when"], ["방법", "how"]]:
		var s := str(texts.get(row[1], ""))
		if s == "":
			continue
		draw_string(font, Vector2(x, y), row[0], HORIZONTAL_ALIGNMENT_LEFT, -1, int(19 * k), CREAM)
		draw_multiline_string(font, Vector2(x + 110 * k, y), s, HORIZONTAL_ALIGNMENT_LEFT, w - 110 * k, int(20 * k), 2, Color.WHITE)
		y += 58 * k
	y += 10 * k
	var slots := [["tutorial", str(c.tutorial)]]
	for i in c.problems.size():
		var id: String = c.problems[i]
		var r: RouteDef = game.index.route(id)
		var slot: String = r.course_slot if r != null and r.course_slot != "" else Progress.SLOT_ORDER[mini(i + 1, 3)]
		slots.append([slot, id])
	for s in slots:
		if s[1] == "":
			continue
		_draw_slot_row(Rect2(Vector2(x, y), Vector2(w, 70 * k)), s[0], s[1])
		y += 80 * k
	if course_id == Progress.BASIC_COURSE and progress.is_first_run():
		_button(Rect2(Vector2(x, y + 6 * k), Vector2(220, 56) * k), "건너뛰기", "skip", "", 22)


## 과정 설명: courses.json text_ko가 있으면 그것, 없으면 첫 기술의 purpose_ko·when_ko·how_ko.
func _course_texts(c: Dictionary) -> Dictionary:
	if c.has("text_ko"):
		return c.text_ko
	for t in c.techniques:
		if _techs.has(t):
			return {"purpose": _techs[t].purpose_ko, "when": _techs[t].when_ko, "how": _techs[t].how_ko}
	return {}


func _draw_slot_row(r: Rect2, slot: String, route_id: String) -> void:
	var progress: Progress = game.progress
	var route: RouteDef = game.index.route(route_id)
	draw_rect(r, CARD)
	draw_rect(r, Color(1, 1, 1, 0.5), false, 2.0)
	var x := r.position.x + 20 * k
	var cy := r.position.y + r.size.y * 0.5 + 8 * k
	var label: String = SLOT_NAMES.get(slot, slot)
	if route != null and route.grade != "" and slot != "tutorial":
		label += " · " + route.grade
	draw_string(font, Vector2(x, cy), label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(24 * k), Color.WHITE)
	var sx := x + 220 * k
	if route == null:
		draw_string(font, Vector2(sx, cy), "준비 중", HORIZONTAL_ALIGNMENT_LEFT, -1, int(20 * k), DIM)
		return
	var lock := progress.route_lock_text(route, game.index)
	if lock != "":
		_lock(Vector2(sx + 8 * k, cy - 8 * k), CREAM)
		draw_string(font, Vector2(sx + 26 * k, cy), lock, HORIZONTAL_ALIGNMENT_LEFT, -1, int(20 * k), CREAM)
		return
	if slot == "tutorial":
		var done := progress.tutorial_done(route_id)
		draw_string(font, Vector2(sx, cy), "✓ 완료" if done else "– 아직", HORIZONTAL_ALIGNMENT_LEFT, -1, int(20 * k), CREAM if done else DIM)
	else:
		_draw_medals(Vector2(sx, cy), route)
	_button(Rect2(Vector2(r.end.x - 200 * k, r.position.y + 9 * k), Vector2(180 * k, r.size.y - 18 * k)), "▶ 시작", "play", route_id, 22, true)


# ---------- 도우미 ----------

func _text(pos: Vector2, s: String, fs: int, col: Color) -> void:
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * k), col)


func _button(r: Rect2, text: String, action: String, arg: String, fs := 24, strong := false) -> void:
	draw_rect(r, CREAM if strong else Color(0.1, 0.1, 0.1, 0.75))
	draw_rect(r, Color(1, 1, 1, 0.7), false, 2.0)
	if text != "":
		var size := int(fs * k)
		draw_string(font, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + size * 0.35), text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, size, INK if strong else Color.WHITE)
	_buttons.append({"rect": r, "action": action, "arg": arg})


## 자물쇠 그림(색이 아닌 모양으로 잠김 표시).
func _lock(c: Vector2, col: Color) -> void:
	draw_arc(c + Vector2(0, -4 * k), 5 * k, PI, TAU, 10, col, 2.0 * k)
	draw_rect(Rect2(c + Vector2(-7, -4) * k, Vector2(14, 11) * k), col)


# ---------- 캐릭터 고르기(docs/34 §7) ----------

func _open_look() -> void:
	_asm = CharacterAssembler.load_catalog()
	var path := _asm.model_path()
	if path == "" or not ResourceLoader.exists(path):
		return
	look = _asm.normalize(game.progress.look)
	_pv = SubViewport.new()
	_pv.size = Vector2i(560, 760)
	_pv.own_world_3d = true
	_pv.transparent_bg = true
	_pv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_pv)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.55
	_pv.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 25, 0)
	_pv.add_child(sun)
	_pv_model = load(path).instantiate()
	_pv.add_child(_pv_model)
	_pv_model.rotation.y = PI  # 앞(−Z, 벽 쪽)이 카메라를 보게
	_asm.apply(_pv_model, look)
	CharacterAssembler.style(_pv_model, preload("res://art/shaders/toon.gdshader"), preload("res://art/shaders/outline.gdshader"), INK)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.0, 3.6)
	cam.fov = 38
	_pv.add_child(cam)
	cam.current = true
	choosing_look = true
	queue_redraw()


func _close_look() -> void:
	choosing_look = false
	if _pv != null:
		_pv.queue_free()
	_pv = null
	_pv_model = null
	queue_redraw()


func _process(delta: float) -> void:
	if choosing_look and _pv_model != null:
		_pv_model.rotation.y += delta * 0.6
		queue_redraw()


## 왼쪽 3D 미리보기(천천히 돎), 오른쪽 슬롯마다 [◀ 이름 ▶]. 대안이 하나뿐인 슬롯은 화살표를 흐리게 하고 "1종"을 붙인다.
func _draw_look(size: Vector2) -> void:
	_buttons = []
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	draw_string(font, Vector2(0, 70 * k), "캐릭터", HORIZONTAL_ALIGNMENT_CENTER, size.x, int(40 * k), CREAM)
	var pvh := size.y - 160 * k
	var pvw := pvh * 560.0 / 760.0
	var pr := Rect2(Vector2(size.x * 0.30 - pvw * 0.5, 100 * k), Vector2(pvw, pvh))
	draw_rect(pr, Color(1, 1, 1, 0.05))
	if _pv != null:
		draw_texture_rect(_pv.get_texture(), pr, false)
	var x := size.x * 0.52
	var y := 130 * k
	var rw := 560.0 * k
	for row in LOOK_ROWS:
		var sid: String = row[0]
		var count: int = _asm.bodies().size() if sid == "body" else _asm.slot(sid).get("parts", []).size()
		if count == 0:  # 파츠가 없는 슬롯(통짜 모델, docs/36)은 줄을 그리지 않는다
			continue
		draw_string(font, Vector2(x, y + 38 * k), row[1], HORIZONTAL_ALIGNMENT_LEFT, -1, int(24 * k), DIM)
		var bx := x + 150 * k
		var one := count <= 1
		var lb := Rect2(Vector2(bx, y), Vector2(60, 56) * k)
		var nb := Rect2(Vector2(bx + rw - 210 * k, y), Vector2(60, 56) * k)
		_button(lb, "◀", "look_prev" if not one else "", sid, 26)
		_button(nb, "▶", "look_next" if not one else "", sid, 26)
		var nm := _asm.part_name(sid, str(look.get(sid, "")))
		draw_string(font, Vector2(lb.end.x, y + 38 * k), nm + ("  (1종)" if one else ""), HORIZONTAL_ALIGNMENT_CENTER, nb.position.x - lb.end.x, int(24 * k), DIM if one else Color.WHITE)
		y += 76 * k
	_button(Rect2(Vector2(x + 150 * k, y + 20 * k), Vector2(200, 60) * k), "저장", "look_save", "", 24, true)
	_button(Rect2(Vector2(x + 370 * k, y + 20 * k), Vector2(200, 60) * k), "취소", "look_cancel", "", 24)
	draw_string(font, Vector2(x, y + 130 * k), "옷·머리·신발 바꾸기와 여성 캐릭터는 다음 단계에서 나와요.", HORIZONTAL_ALIGNMENT_LEFT, -1, int(18 * k), DIM)
