extends Node2D
## 홈 화면(docs/28 §5.2–5.4). 위 탭 일반/기술(마지막 탭 기억), 일반: 등급 줄 + 문제 카드, 기술: 과정 카드 → 과정 화면.
## 진행·콘텐츠는 자동 로드 Game에서 읽는다. 플레이 화면처럼 직접 그리고 누른 위치로 동작을 고른다
## (터치→마우스 흉내를 끈 프로젝트라 Control 버튼 대신). 잠금·완료는 색만이 아니라 글자·자물쇠로 함께 보인다(docs/05).
## 문제 파일이 아직 없는 과정 슬롯은 "준비 중"으로 보이고 시작할 수 없다.

## 색(2026-11-22 사용자: "밤티스러워 → 깔끔하지만 세련되고 가독성 좋게"). 배경 그림에서 뽑았다:
## 판은 그늘진 먼 산의 남색 반투명, 글자는 초크 흰색, 강조는 암벽화 노랑 하나(누를 다음 것·고른 것·얻은 메달에만).
const NIGHT := Color("0d1620")
const CHALK := Color("f6f2ea")
const SHOE := Color("ffc93c")
const HAIR := Color(0.965, 0.95, 0.92, 0.14)
const CREAM := Color("f1d59a")   # 보조 정보(사암 밝은 면)
const INK := Color("302820")     # 캐릭터 미리보기 외곽선
const BG := NIGHT
const DIM := Color(0.965, 0.95, 0.92, 0.66)
## 스포츠 블록(2026-11-26 사용자 "디자인 요소가 old해 보여서 끌리지 않는다" → 스포츠 블록, 홈부터): 테두리 알약 대신 단단한 면,
## 등급마다 실제 암장 테이프 색, 고른 등급은 큰 숫자. 테두리 선은 쓰지 않는다.
const SLATE := Color("172431")    # 카드·보조 버튼 면
const BLOCK_R := 8.0              # 블록 모서리(배율 전)
const SKEW := 0.22                # 주 버튼 기울기
## 2026-11-26 사용자 "v0부터 v10까지 … 빨 주 노 초 파 남 보 갈 검 흰색 순서로"(V0 빨강부터, 남는 V10은 회색).
const GRADE_TAPE := {"V0": Color("ff4b4b"), "V1": Color("ff8a3d"), "V2": Color("ffd23f"), "V3": Color("39c46a"),
	"V4": Color("3f8cff"), "V5": Color("4c5fd7"), "V6": Color("9a6bff"), "V7": Color("a0703c"), "V8": Color("141414"),
	"V9": Color("f4f1ea"), "V10": Color("9aa0a6")}
const MARGIN := 64.0
const APP_NAME := "OVERHANG"
const SLOT_NAMES := {"tutorial": "튜토리얼", "easy": "쉬움", "normal": "보통", "hard": "어려움"}
## 홈 배경 그림(2026-11-22 사용자: "메인화면은 이걸로 바꿔줘", 사용자가 준 그림). 클라이머가 오른쪽이라 왼쪽·위를 더 어둡게 덮는다.
const KEY_ART := preload("res://art/ui/home_key_art.jpg")

var game: Node
var font: Font      # 본문(400)
var font_m: Font    # 탭·알약(600)
var font_b: Font    # 제목·이름·주 버튼(750)
var k := 1.0
var tab := "general"
var grade := ""
var course_id := ""   # 비어 있지 않으면 기술 탭에서 그 과정 화면
var tech_view := "learn"  # 기술 탭 안: "learn" 처음 배우기(수업) / "dict" 기술 사전(docs/42 §4.1)
var tech_id := ""         # 비어 있지 않으면 기술 사전에서 그 기술 카드
const GROUP_NAMES := [["foot", "발"], ["hand", "손"], ["body", "몸"]]
var _buttons: Array = []  # [{rect, action, arg}]
var _techs := TechniqueJudge.defs()
var _look_ok := false        # 지금 몸 비율에 맞는 캐릭터 모델이 있을 때만 [캐릭터] 버튼(2026-11-11)
var choosing_look := false   # 캐릭터 고르기 창(docs/34 §7). 오른쪽 위 [캐릭터] 버튼
var look := {}               # 고르는 중인 외형(저장 전)
var _asm: CharacterAssembler
var _pv: SubViewport         # 3D 미리보기(창이 열린 동안만)
var _pv_model: Node3D
var _pv_cam: Camera3D
var _pv_rect := Rect2()      # 화면에 그린 미리보기 자리(손짓을 받는 곳)
var _pv_touch := {}          # 미리보기 안에서 시작한 손가락: index → 위치
var _pv_mouse := false       # 미리보기 안에서 누른 마우스(PC)
var _pv_dist := LOOK_DIST_MAX
var _pv_y := 0.0
## 미리보기 카메라 거리(m): 가까이(얼굴·옷 확대) ~ 멀리(전신). 2026-11-23 사용자 "줌인 줌아웃도 내가 하게".
const LOOK_DIST_MIN := 1.1
const LOOK_DIST_MAX := 3.6
const LOOK_ROWS := [["body", "캐릭터"], ["hair", "헤어"], ["top", "상의"], ["bottom", "하의"], ["chalk", "초크백"], ["shoes", "클라이밍화"]]
var choosing_level := false  # 난이도(초급·중급) 고르기 창. 처음 시작할 때와 오른쪽 위 [난이도] 버튼
const LEVEL_INFO := {
	"beginner": {"name": "초급", "desc": ["떨어지기 전 버틸 시간 10배", "어떻게 버틸지 화면에 안내", "위험 게이지 눌러 자동 도움 3번"]},
	"advanced": {"name": "고급", "desc": ["경고·알림이 없어요", "손 게이지와 몸의 균형만 보고", "스스로 판단해요"]},
	"intermediate": {"name": "중급", "desc": ["경고와 안내를 보여 줘요", "손을 다 놓으면 1.5초 뒤 떨어져요", "손에 익은 분께"]},
}


func _ready() -> void:
	font = UiFont.get_font(400)
	font_m = UiFont.get_font(600)
	font_b = UiFont.get_font(750)
	game = get_node_or_null("/root/Game")
	if game == null:
		push_error("홈: 자동 로드 Game이 없어요")
		return
	var progress: Progress = game.progress
	tab = progress.last_tab if progress.last_tab in ["general", "technique", "make", "settings"] else "general"
	var focus: Dictionary = game.home_focus
	game.home_focus = {}
	if focus.has("tab"):
		_set_tab(str(focus.tab))
	grade = str(focus.get("grade", _default_grade()))
	if not grade in game.index.grades():
		grade = _default_grade()
	course_id = str(focus.get("course", ""))
	if tab != "technique":
		course_id = ""
	if str(focus.get("view", "")) in ["dict", "holds"]:
		tech_view = "dict"
		course_id = ""
	_look_ok = CharacterAssembler.load_catalog().model_compatible()
	get_viewport().size_changed.connect(queue_redraw)
	# 처음 시작: 난이도부터 고른다(2026-11-08). 고른 뒤 첫 실행이면 기본 조작 튜토리얼로.
	choosing_level = progress.level == ""
	if not choosing_level:
		_first_run_tutorial()
	_maybe_grade_card()
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
	_close_input()  # 만들기 탭의 코드·별명 입력칸(LineEdit)이 다른 탭 위에 남지 않게(2026-11-25 사용자 "텍스트박스 같은 게 계속 떠 있어")
	game.get_flow().set_last_tab(t)
	_maybe_grade_card()


## 등급 설명 카드(작업 3 §3.6): 일반 탭에서 열린 등급을 처음 볼 때 한 번(Progress.seen_tips).
var grade_card := ""
## 기록 지우기 확인 창의 문제 ID("" = 닫힘, 작업 3 §3.3).
var wipe_ask := ""


func _maybe_grade_card() -> void:
	if game == null or tab != "general" or choosing_level or grade == "" or not game.progress.grade_unlocked(grade, game.index):
		return
	if not game.progress.seen_tips.has(GradeInfo.tip_id(grade)):
		grade_card = grade


## 창(등급 설명·기록 지우기 확인): 그 창의 버튼만 누를 수 있다.
func _draw_modals(size: Vector2) -> void:
	if grade_card == "" and wipe_ask == "":
		return
	_buttons = []
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.04, 0.06, 0.66))
	var w := 820.0 * k
	var h := 330.0 * k
	var p := Rect2(Vector2(size.x * 0.5 - w * 0.5, size.y * 0.5 - h * 0.5), Vector2(w, h))
	_panel(p)
	var x := p.position.x + 40 * k
	var tw := w - 80 * k
	if grade_card != "":
		draw_string(font_b, Vector2(x, p.position.y + 70 * k), "%s %s" % [grade_card, GradeInfo.name_of(grade_card)], HORIZONTAL_ALIGNMENT_LEFT, tw, int(38 * k), CHALK)
		draw_multiline_string(font, Vector2(x, p.position.y + 130 * k), GradeInfo.text(grade_card), HORIZONTAL_ALIGNMENT_LEFT, tw, int(26 * k), 3, Color.WHITE)
		_button(Rect2(Vector2(p.get_center().x - 120 * k, p.end.y - 90 * k), Vector2(240, 64) * k), "시작해요", "grade_card_ok", "", 24, true)
		return
	var r: RouteDef = game.index.route(wipe_ask)
	draw_string(font_b, Vector2(x, p.position.y + 64 * k), "%s 기록을 지울까요?" % (_route_name(r) if r != null else wipe_ask), HORIZONTAL_ALIGNMENT_LEFT, tw, int(30 * k), CHALK)
	draw_multiline_string(font, Vector2(x, p.position.y + 114 * k), "완등·최고 점수·최고 시간·고스트·떨어진 횟수가 지워져요. 플래시에 다시 도전할 수 있어요.\n이 문제 완등이 지워져서 다음 등급이 다시 잠길 수 있어요.", HORIZONTAL_ALIGNMENT_LEFT, tw, int(21 * k), 4, Color.WHITE)
	_button(Rect2(Vector2(p.get_center().x - 260 * k, p.end.y - 90 * k), Vector2(240, 64) * k), "지우기", "wipe_yes", wipe_ask, 24, true)
	_button(Rect2(Vector2(p.get_center().x + 20 * k, p.end.y - 90 * k), Vector2(240, 64) * k), "취소", "wipe_no", "", 24)


# ---------- 입력 ----------

func _input(event: InputEvent) -> void:
	if game == null:
		return
	if choosing_look and _look_gesture(event):
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
			if arg == "body":  # 캐릭터(몸)를 바꾸면 그 몸의 기본 헤어로(나머지는 유지)
				look.hair = str(_asm.body(look.body).get("defaults", {}).get("hair", look.get("hair", "")))
			look = _asm.normalize(look)
			if arg == "body":  # 몸마다 모델이 다르다(여성 2026-11-12)
				_load_preview_model()
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
			_maybe_grade_card()
		"grade_card_ok":
			game.get_flow().mark_tip(GradeInfo.tip_id(grade_card))
			grade_card = ""
		"wipe_ask":
			wipe_ask = arg
		"wipe_yes":
			game.get_flow().wipe_route(arg)
			wipe_ask = ""
		"wipe_no":
			wipe_ask = ""
		"course":
			course_id = arg
		"courses":
			course_id = ""
		"view":
			tech_view = arg
			course_id = ""
			tech_id = ""
		"tech":
			tech_id = arg
		"learn":
			_set_tab("technique")
			course_id = arg
		"play":
			game.play(arg)
			return
		"edit":
			game.edit(arg)
			return
		"play_mine":
			if not game.play_custom(arg):
				make_msg = "이 문제는 아직 올라 볼 수 없어요(만들기 화면의 [점검]에서 고칠 것을 확인해 주세요)"
		"mine_delete_ask":
			mine_delete = arg
		"mine_delete_yes":
			MyRoutes.remove(arg)
			mine_delete = ""
		"mine_delete_no":
			mine_delete = ""
		"make_view":
			make_view = arg
			make_msg = ""
			_close_input()
			if arg == "browse" and browse_rows.is_empty():
				_browse_load(false)
		"browse_sort":
			browse_sort = arg
			_browse_load(false)
		"browse_grade":
			browse_grade = arg
			_browse_load(false)
		"browse_more":
			_browse_load(true)
		"shared_play":
			_fetch_and_play(arg)
		"star":
			_star(int(arg))
		"report":
			_report(int(arg))
		"input_open":
			_open_input(arg)
		"input_go":
			_input_go()
		"input_close":
			_close_input()
		"display":
			game.get_flow().set_display(arg, not game.progress.display_on(arg))
		"control":
			var kv := arg.split("=")
			game.get_flow().set_control(kv[0], (kv[1] == "1") if kv[0] == "tilt_with_drag" else (kv[1] if kv[0] == "body" else float(kv[1])))
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
	_draw_key_art(size)
	# 게임 버전(오른쪽 아래, 작고 흐리게 — 2026-11-19 사용자: 시작 화면 모서리에 버전). 밝은 바위 위라 테두리를 두른다
	var vp := Vector2(0, size.y - 16 * k)
	draw_string_outline(font_m, vp, AppVersion.text(), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 20 * k, int(16 * k), int(4 * k), Color(NIGHT, 0.6))
	draw_string(font_m, vp, AppVersion.text(), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 20 * k, int(16 * k), Color(CHALK, 0.7))
	if game == null:
		return
	_draw_tabs(size)
	if tab == "general":
		_draw_general(size)
	elif tab == "settings":
		_draw_settings(size)
	elif tab == "make":
		_draw_make(size)
	elif course_id != "":
		_draw_course(size)
	else:
		_draw_views(size)
		if tech_view == "dict":
			_draw_dict(size)
		else:
			_draw_courses(size)
	if not choosing_level and _look_ok:
		_button(Rect2(Vector2(size.x - MARGIN * k - 400 * k, 32 * k), Vector2(170, 52) * k), "캐릭터", "look_open", "", 21)
	var lv: String = game.progress.level
	if lv != "":
		var r := Rect2(Vector2(size.x - MARGIN * k - 214 * k, 32 * k), Vector2(214, 52) * k)
		_button(r, "난이도 " + str(LEVEL_INFO[lv].name), "level_open", "", 21)
	if choosing_level:
		_draw_level_choice(size)
	elif choosing_look:
		_draw_look(size)
	else:
		_draw_modals(size)


## 그림을 화면을 빈틈 없이 덮는 크기로(비율 유지). 넘치는 위아래는 위 10% : 아래 90%로 잘라 위로 뻗은 손이 덜 잘린다.
static func cover_rect(tex: Vector2, size: Vector2) -> Rect2:
	var d := tex * maxf(size.x / tex.x, size.y / tex.y)
	return Rect2(Vector2((size.x - d.x) * 0.5, (size.y - d.y) * 0.1), d)


## 배경 그림 + 글자가 읽히게 덮는 남색. 일반 탭은 왼쪽 글 열(화면 절반)까지 진하고 오른쪽 클라이머 쪽은 옅게,
## 다른 탭은 글자가 화면 전체에 있어 고르게 진하게. 위쪽 탭 띠는 한 번 더.
func _draw_key_art(size: Vector2) -> void:
	draw_texture_rect(KEY_ART, cover_rect(Vector2(KEY_ART.get_size()), size), false)
	var stops := [[0.0, 0.86], [0.46, 0.80], [0.64, 0.22], [1.0, 0.12]] if tab == "general" else [[0.0, 0.88], [1.0, 0.76]]
	for i in stops.size() - 1:
		var x0: float = size.x * float(stops[i][0])
		var x1: float = size.x * float(stops[i + 1][0])
		var a := Color(NIGHT, float(stops[i][1]))
		var b := Color(NIGHT, float(stops[i + 1][1]))
		draw_polygon(PackedVector2Array([Vector2(x0, 0), Vector2(x1, 0), Vector2(x1, size.y), Vector2(x0, size.y)]), PackedColorArray([a, b, b, a]))
	var top := Color(NIGHT, 0.5)
	var clear := Color(NIGHT, 0.0)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), Vector2(size.x, 120 * k), Vector2(0, 120 * k)]), PackedColorArray([top, top, clear, clear]))


## 난이도 고르기 창. 다른 버튼을 덮고(앞서 등록된 버튼은 지움) 카드 두 장만 누를 수 있다.
func _draw_level_choice(size: Vector2) -> void:
	_buttons = []
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.04, 0.06, 0.74))
	var cur: String = game.progress.level
	var title := "난이도를 골라 주세요" if cur == "" else "난이도 바꾸기"
	draw_string(font_b, Vector2(0, size.y * 0.5 - 250 * k), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, int(44 * k), CHALK)
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
		sb.bg_color = Color(NIGHT, 0.94)
		sb.border_color = SHOE if on else HAIR
		sb.set_border_width_all(maxi(1, int((3 if on else 1.5) * k)))
		sb.set_corner_radius_all(int(24 * k))
		sb.anti_aliasing = true
		draw_style_box(sb, r)
		var info: Dictionary = LEVEL_INFO[lv]
		var accent: Color = {"beginner": Color("8cc8ff"), "intermediate": Color("f1d59a"), "advanced": Color("ff9a7a")}[lv]
		draw_string(font_b, Vector2(r.position.x, r.position.y + 78 * k), ("✓ " if on else "") + str(info.name), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(52 * k), accent)
		var y := r.position.y + 140 * k
		for line in info.desc:
			draw_string(font, Vector2(r.position.x, y), line, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(24 * k), Color.WHITE if line != info.desc[-1] else DIM)
			y += 38 * k
		_buttons.append({"rect": r, "action": "level", "arg": lv})
		x += cw + gap
	if cur != "":
		var br := Rect2(Vector2(size.x * 0.5 - 100 * k, size.y * 0.5 + 180 * k), Vector2(200, 56) * k)
		_button(br, "닫기", "level_close", "", 22)


## 위 줄: 왼쪽 앱 이름, 그 옆 탭 글자. 고른 탭은 굵은 흰 글자 + 노란 밑줄(색만으로 구분하지 않음). 누르는 자리는 글자보다 넉넉하게.
const TABS := [["general", "일반"], ["technique", "기술"], ["make", "만들기"], ["settings", "설정"]]


func _draw_tabs(_size: Vector2) -> void:
	var row := Rect2(Vector2(MARGIN * k, 26 * k), Vector2(0, 64 * k))
	var x := row.position.x
	draw_string(font_b, Vector2(x, _baseline(row, 30, font_b)), APP_NAME, HORIZONTAL_ALIGNMENT_LEFT, -1, int(30 * k), CHALK)
	x += font_b.get_string_size(APP_NAME, HORIZONTAL_ALIGNMENT_LEFT, -1, int(30 * k)).x + 60 * k
	for t in TABS:
		var on: bool = tab == t[0]
		var f: Font = font_b if on else font_m
		var tw := f.get_string_size(t[1], HORIZONTAL_ALIGNMENT_LEFT, -1, int(26 * k)).x
		var r := Rect2(Vector2(x - 18 * k, row.position.y), Vector2(tw + 36 * k, row.size.y))
		var by := _baseline(r, 26, f)
		draw_string(f, Vector2(x, by), t[1], HORIZONTAL_ALIGNMENT_LEFT, -1, int(26 * k), CHALK if on else DIM)
		if on:
			draw_rect(Rect2(Vector2(x - 4 * k, by + 12 * k), Vector2(tw + 8 * k, 6 * k)), SHOE)
		_buttons.append({"rect": r, "action": "tab", "arg": t[0]})
		x += tw + 44 * k


# ---------- 일반 탭 ----------

## 일반 탭(2026-11-22 다시 그림, 사용자 "밤티스러워 → 깔끔·세련·가독성"): 왼쪽 열(화면 절반)에 등급 줄 → 고른 등급 제목·설명 →
## 문제 줄(가이드북처럼 한 줄에 한 문제). 오른쪽은 배경 그림의 클라이머가 보이게 비운다.
func _content_w(size: Vector2) -> float:
	return minf(maxf(size.x * 0.5, 900 * k), size.x - 2 * MARGIN * k)


func _draw_general(size: Vector2) -> void:
	var idx: ContentIndex = game.index
	var progress: Progress = game.progress
	var gs: Array[String] = idx.grades()
	var x0 := MARGIN * k
	var cw := _content_w(size)
	var y := 120.0 * k
	if gs.is_empty():
		_text(Vector2(x0, y + 60 * k), "아직 문제가 없어요", 26, DIM)
		return
	# 등급 타일: 아래에 테이프 색 띠. 고른 등급은 테이프 색으로 채움, 잠긴 등급은 흐리게 + 자물쇠, 다 깬 등급은 오른쪽 위 점
	var pw := minf(92.0 * k, (cw - (gs.size() - 1) * 8 * k) / gs.size())
	var x := x0
	for g in gs:
		var open := progress.grade_unlocked(g, idx)
		var on := g == grade
		var tc := tape(g)
		var r := Rect2(Vector2(x, y), Vector2(pw, 60 * k))
		draw_style_box(_box(tc if on else Color(SLATE, 0.9 if open else 0.55), BLOCK_R * k, tape_edge(g) if on else Color(0, 0, 0, 0), 2.0), r)
		if not on:
			_tape_bar(Rect2(Vector2(r.position.x + 10 * k, r.end.y - 7 * k), Vector2(r.size.x - 20 * k, 4 * k)), g, 1.0 if open else 0.35)
		var fc := ink_on(tc) if on else (CHALK if open else DIM)
		draw_string(font_b, Vector2(r.position.x, _baseline(r, 24, font_b) - 2 * k), g, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(24 * k), fc)
		if not open:
			_lock(Vector2(r.end.x - 16 * k, r.position.y + 20 * k), fc)
		elif idx.general(g).size() > 0 and progress.cleared_count(g, idx) >= idx.general(g).size():
			draw_circle(Vector2(r.end.x - 13 * k, r.position.y + 13 * k), 5 * k, fc if on else SHOE)
		_buttons.append({"rect": r, "action": "grade", "arg": g})
		x += pw + 8 * k
	# 고른 등급: 테이프 색 큰 숫자 + 이름 + 완등 칸(문제 수만큼) + 한 줄 설명(잠겼으면 여는 방법)
	var routes: Array[RouteDef] = idx.general(grade)
	y += 60 * k + 118 * k
	var big := int(112 * k)
	if tape_edge(grade).a > 0.0:  # 검정 테이프: 어두운 화면에서 보이게 테두리
		draw_string_outline(font_b, Vector2(x0 - 4 * k, y), grade, HORIZONTAL_ALIGNMENT_LEFT, -1, big, int(3 * k), tape_edge(grade))
	draw_string(font_b, Vector2(x0 - 4 * k, y), grade, HORIZONTAL_ALIGNMENT_LEFT, -1, big, tape(grade))
	var tx := x0 + font_b.get_string_size(grade, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x + 22 * k
	draw_string(font_b, Vector2(tx, y - 52 * k), GradeInfo.name_of(grade), HORIZONTAL_ALIGNMENT_LEFT, -1, int(36 * k), CHALK)
	var done := progress.cleared_count(grade, idx)
	var seg := 34.0 * k
	for i in routes.size():
		draw_style_box(_box(tape(grade) if i < done else Color(CHALK, 0.14), 3 * k, tape_edge(grade) if i < done else Color(0, 0, 0, 0), 1.0), Rect2(Vector2(tx + i * (seg + 6 * k), y - 24 * k), Vector2(seg, 10 * k)))
	draw_string(font_m, Vector2(tx + routes.size() * (seg + 6 * k) + 8 * k, y - 13 * k), "%d/%d 완등" % [done, routes.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, int(20 * k), DIM)
	y += 40 * k
	var lock := progress.grade_lock_text(grade, idx)
	if lock != "":
		_lock(Vector2(x0 + 9 * k, y - 8 * k), CREAM)
		draw_string(font_m, Vector2(x0 + 28 * k, y), lock, HORIZONTAL_ALIGNMENT_LEFT, cw - 28 * k, int(22 * k), CREAM)
		if progress.first_run_locked(idx):  # 기본 조작 파일이 없어 바로 못 갔을 때도 길을 남긴다
			var lw := font_m.get_string_size(lock, HORIZONTAL_ALIGNMENT_LEFT, -1, int(22 * k)).x
			_button(Rect2(Vector2(x0 + 48 * k + lw, y - 34 * k), Vector2(200, 48) * k), "배우러 가기", "learn", Progress.BASIC_COURSE, 21, true)
		y += 26 * k
	else:
		var desc := GradeInfo.text(grade)
		if desc.begins_with(GradeInfo.name_of(grade) + ". "):
			desc = desc.substr(GradeInfo.name_of(grade).length() + 2)  # 제목에 이미 있는 "쉬움." 빼기
		draw_multiline_string(font, Vector2(x0, y), desc, HORIZONTAL_ALIGNMENT_LEFT, cw, int(22 * k), 2, DIM)
		y += font.get_multiline_string_size(desc, HORIZONTAL_ALIGNMENT_LEFT, cw, int(22 * k), 2).y - 6 * k
	# 문제 줄: 남은 높이에 맞춰(최대 150)
	y += 18 * k
	var gap := 14.0 * k
	var rh := 150.0 * k
	if routes.size() > 0:
		rh = clampf((size.y - y - 36 * k - gap * (routes.size() - 1)) / routes.size(), 96 * k, 150 * k)
	for route in routes:
		_draw_problem_row(Rect2(Vector2(x0, y), Vector2(cw, rh)), route)
		y += rh + gap


## 문제 한 줄: 이름 + 벽 각도 칩 / 필요 기술 / 메달·최고 기록. 오른쪽에 [시작](잠겼으면 여는 방법·[배우러 가기]).
func _draw_problem_row(r: Rect2, route: RouteDef) -> void:
	var idx: ContentIndex = game.index
	var progress: Progress = game.progress
	var lock := progress.route_lock_text(route, idx)
	_card(r, lock != "")
	_tape_bar(Rect2(r.position, Vector2(8 * k, r.size.y)), route.grade, 0.35 if lock != "" else 1.0)
	var pad := 32.0 * k
	var x := r.position.x + pad
	var b := Rect2(Vector2(r.end.x - pad - 164 * k, r.position.y + r.size.y * 0.5 - 30 * k), Vector2(164, 60) * k)
	var w := b.position.x - x - 24 * k
	var s := r.size.y / (150.0 * k)  # 줄이 낮으면 세로 간격만 줄인다
	var ty := r.position.y + 48 * k * s
	var name := _route_name(route)
	draw_string(font_b, Vector2(x, ty), name, HORIZONTAL_ALIGNMENT_LEFT, w, int(30 * k), CHALK if lock == "" else DIM)
	if route.mode == "general" or not route.wall_sections.is_empty():  # 벽 각도(땅 기준), 꺾이는 벽은 "벽 150° → 120°"
		_chip(Vector2(x + minf(font_b.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, int(30 * k)).x, w) + 14 * k, ty), "벽 " + route.wall_desc(), CREAM)
	draw_string(font, Vector2(x, ty + 36 * k * s), "필요 기술 " + _tech_names(route.required_techniques), HORIZONTAL_ALIGNMENT_LEFT, w, int(21 * k), DIM)
	var my := ty + 78 * k * s
	if lock != "":
		_lock(Vector2(x + 9 * k, my - 8 * k), CREAM)
		draw_string(font_m, Vector2(x + 28 * k, my), lock, HORIZONTAL_ALIGNMENT_LEFT, w - 28 * k, int(20 * k), CREAM)
		var learn := _locked_button_course(route)
		if learn != "" and progress.grade_unlocked(route.grade, idx):
			_button(b, "배우러 가기", "learn", learn, 21, true)
		return
	var mx := _draw_medals(Vector2(x, my), route)
	var best := _best_text(route)
	if best != "":
		draw_string(font_m, Vector2(mx + 6 * k, my), best, HORIZONTAL_ALIGNMENT_LEFT, maxf(x + w - mx - 6 * k, 1.0), int(20 * k), CHALK if not best.begins_with("이전") else DIM)
	_button(b, "시작", "play", route.route_id, 24, true)
	if not progress.cleared.get(route.route_id, {}).is_empty() or progress.stats.has(route.route_id):
		var wr := Rect2(Vector2(b.position.x, b.end.y), Vector2(b.size.x, r.end.y - b.end.y))
		draw_string(font, Vector2(wr.position.x, wr.end.y - 13 * k), "기록 지우기", HORIZONTAL_ALIGNMENT_CENTER, wr.size.x, int(17 * k), DIM)
		_buttons.append({"rect": wr, "action": "wipe_ask", "arg": route.route_id})


## 작은 테두리 알약 글자(벽 각도 등). pos.y는 옆 글자의 기준선.
func _chip(pos: Vector2, text: String, col: Color) -> float:
	var fs := int(17 * k)
	var r := Rect2(Vector2(pos.x, pos.y - 24 * k), Vector2(font_m.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 22 * k, 30 * k))
	draw_style_box(_box(Color(col, 0.18), 5 * k), r)
	draw_string(font_m, Vector2(r.position.x, _baseline(r, 17, font_m)), text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, col)
	return r.end.x


## 최고 점수·최고 시간 한 줄(없으면 이전 판 최고 점수, 그것도 없으면 "").
func _best_text(route: RouteDef) -> String:
	var rec: Dictionary = game.progress.cleared.get(route.route_id, {})
	var parts := []
	if rec.has("best_score"):
		parts.append("최고 %s점" % ScoreCalc.format(float(rec.best_score)))
	if rec.has("best_seconds"):
		parts.append(preload("res://scenes/play_overlay.gd").format_seconds(float(rec.best_seconds)))
	if parts.is_empty() and rec.get("prev", {}).has("best_score"):
		return "이전 판 최고 %s점" % ScoreCalc.format(float(rec.prev.best_score))
	return "  ".join(parts)


## 메달 네 개를 작은 알약으로: 얻은 것은 노란 테두리 + 체크, 못 얻은 것은 흐린 글자(색만이 아니라 체크 모양으로도 구분).
## pos.y는 기준선. 반환: 마지막 알약의 오른쪽 끝 x.
func _draw_medals(pos: Vector2, route: RouteDef) -> float:
	var rec: Dictionary = game.progress.cleared.get(route.route_id, {})
	var medals := [["완등", not rec.is_empty()], ["플래시", rec.get("flash", false)], ["무추락", rec.get("no_fall", false)], ["시간", rec.get("time", false)]]
	var x := pos.x
	var fs := int(18 * k)
	for m in medals:
		var got: bool = m[1]
		var tw := font_m.get_string_size(str(m[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var r := Rect2(Vector2(x, pos.y - 23 * k), Vector2(tw + (40 if got else 22) * k, 30 * k))
		draw_style_box(_box(SHOE if got else Color(CHALK, 0.07), 5 * k), r)
		var tx := r.position.x + 11 * k
		if got:
			var c := Vector2(r.position.x + 18 * k, r.get_center().y)
			draw_polyline(PackedVector2Array([c + Vector2(-6, 0) * k, c + Vector2(-2, 4) * k, c + Vector2(6, -5) * k]), NIGHT, 2.4 * k, true)
			tx += 18 * k
		draw_string(font_b if got else font_m, Vector2(tx, _baseline(r, 18, font_m)), str(m[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, NIGHT if got else DIM)
		x = r.end.x + 8 * k
	return x


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

## 기술 탭 안 두 갈래: 처음 배우기(따라 하는 수업) / 기술 사전(아는 사람이 찾아보는 카드).
func _draw_views(size: Vector2) -> void:
	var w := 240.0 * k
	var x := 60.0 * k
	for v in [["learn", "처음 배우기"], ["dict", "기술 사전"]]:
		var on: bool = tech_view == v[0]
		_button(Rect2(Vector2(x, 116 * k), Vector2(w, 52 * k)), v[1], "view", v[0], 22, on)
		x += w + 12 * k
	var hint: String = {"dict": "기술이나 홀드를 고르면 오른쪽에 그림으로 보여요"}.get(tech_view, "순서대로 따라 하며 배워요")
	draw_string(font, Vector2(x + 12 * k, 145 * k), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, int(20 * k), DIM)


func _draw_courses(size: Vector2) -> void:
	var all: Array[Dictionary] = game.index.courses()
	var basic := all.filter(func(c): return c.get("group", "basic") != "technique")
	var tech := all.filter(func(c): return c.get("group", "basic") == "technique")
	var ch := 190.0 * k
	var cw := (size.x - 120 * k - 3 * 20 * k) / 4
	for i in basic.size():
		_draw_course_card(Rect2(Vector2(60 * k + i * (cw + 20 * k), 184 * k), Vector2(cw, ch)), basic[i], i + 1)
	if tech.is_empty():
		return
	var y := 184 * k + ch + 50 * k
	draw_string(font, Vector2(60 * k, y - 14 * k), "기술 수업 · 먼저 기술 없이 해 보고, 기술을 써서 다시 해요", HORIZONTAL_ALIGNMENT_LEFT, -1, int(22 * k), CREAM)
	var tw := (size.x - 120 * k - (tech.size() - 1) * 14 * k) / tech.size()
	for i in tech.size():
		_draw_course_card(Rect2(Vector2(60 * k + i * (tw + 14 * k), y), Vector2(tw, ch)), tech[i])


## 기술 사전(2026-11-28 사용자 "좌우측으로 분할하여 좌측에는 상하단으로 … 상단에는 기술 목록들, 하단에는 사전 항목들 우측에는
## 선택한 기술들에 대한 설명 … 이미지들", "하이스텝, 풋스왑, 플래그, 매치, 크로스 락오프 휴식 다이노 만 남긴다. 설명이 너무 많고 가독성 떨어진다"):
## 왼쪽 위 기술 8개, 왼쪽 아래 홀드(사전 항목), 오른쪽은 고른 것의 한 줄 설명과 단계 그림(게임 화면을 찍은 것, art/dict).
const DICT_TECHS := [&"T_HIGH_STEP", &"T_FOOT_SWAP", &"T_FLAG", &"T_MATCH", &"T_CROSS", &"T_LOCK_OFF", &"T_REST", &"T_DYNO"]
const HOLD_DICT_ORDER := ["jug", "crimp", "sloper", "pinch", "pocket", "volume", "volume_face"]
var _dict_tex := {}


func _dict_img(name: String) -> Texture2D:
	if not _dict_tex.has(name):
		var path := "res://art/dict/%s.png" % name
		_dict_tex[name] = load(path) if ResourceLoader.exists(path) else null
	return _dict_tex[name]


func _draw_dict(size: Vector2) -> void:
	var sel := tech_id if tech_id != "" else str(DICT_TECHS[0])
	var x0 := 60.0 * k
	var lw := minf(560.0 * k, (size.x - 120 * k) * 0.36)
	var bw := (lw - 12 * k) / 2
	var bh := 50.0 * k
	var y := 196.0 * k
	for part in [["기술", DICT_TECHS.map(func(id): return [str(id), str(_techs[id].name_ko)])],
			["홀드", HOLD_DICT_ORDER.map(func(t): return ["hold:" + t, str(HoldTypes.types()[t].name_ko)])]]:
		draw_string(font_b, Vector2(x0, y + 22 * k), part[0], HORIZONTAL_ALIGNMENT_LEFT, -1, int(24 * k), CREAM)
		y += 36 * k
		var items: Array = part[1]
		for i in items.size():
			var r := Rect2(Vector2(x0 + (i % 2) * (bw + 12 * k), y + (i / 2) * (bh + 10 * k)), Vector2(bw, bh))
			_button(r, items[i][1], "tech", items[i][0], 22, items[i][0] == sel)
		y += ceili(items.size() / 2.0) * (bh + 10 * k) + 18 * k
	var pr := Rect2(Vector2(x0 + lw + 28 * k, 184 * k), Vector2(size.x - 60 * k - (x0 + lw + 28 * k), size.y - 184 * k - 40 * k))
	_card(pr)
	if sel.begins_with("hold:"):
		_draw_hold_entry(pr, sel.substr(5))
	else:
		_draw_tech_entry(pr, StringName(sel))


## 오른쪽: 기술 이름·한 줄 설명, 단계마다 그림과 한 줄. 수업이 있으면 [연습하기].
func _draw_tech_entry(pr: Rect2, id: StringName) -> void:
	var t: Dictionary = _techs.get(id, {})
	if t.is_empty():
		return
	var d: Dictionary = t.get("dict_ko", {})
	var x := pr.position.x + 32 * k
	var w := pr.size.x - 64 * k
	_text(Vector2(x, pr.position.y + 58 * k), str(t.name_ko), 36, Color.WHITE)
	draw_string(font_m, Vector2(x, pr.position.y + 100 * k), str(d.get("what", t.purpose_ko)), HORIZONTAL_ALIGNMENT_LEFT, w, int(23 * k), CREAM)
	for c in game.index.courses():
		if c.get("group", "") == "technique" and id in c.techniques and c.tutorial != "":
			_button(Rect2(Vector2(pr.end.x - 32 * k - 200 * k, pr.position.y + 22 * k), Vector2(200, 56) * k), "연습하기", "play", c.tutorial, 24, true)
			break
	var steps: Array = d.get("steps", [])
	if steps.is_empty():
		return
	var top := pr.position.y + 132 * k
	var cap_h := 64.0 * k
	var ih := pr.end.y - 24 * k - cap_h - top
	var iw := ih * 300.0 / 378.0
	var gap := 28.0 * k
	iw = minf(iw, (w - gap * (steps.size() - 1)) / steps.size())
	ih = iw * 378.0 / 300.0
	for i in steps.size():
		var ix := x + i * (iw + gap)
		var tex := _dict_img(str(steps[i].img))
		var ir := Rect2(Vector2(ix, top), Vector2(iw, ih))
		if tex != null:
			draw_texture_rect(tex, ir, false)
		draw_rect(ir, Color(CHALK, 0.25), false, maxf(1.0, k))
		var num := "%d  " % (i + 1) if steps.size() > 1 else ""
		draw_multiline_string(font_m, Vector2(ix, ir.end.y + 30 * k), num + str(steps[i].text), HORIZONTAL_ALIGNMENT_LEFT, iw, int(21 * k), 2, Color.WHITE)


## 오른쪽: 홀드 이름·손 힘(발 몫), 그림, 버티는 방향·특징.
func _draw_hold_entry(pr: Rect2, type: String) -> void:
	var t: Dictionary = HoldTypes.types().get(type, {})
	if t.is_empty():
		return
	var x := pr.position.x + 32 * k
	var w := pr.size.x - 64 * k
	var foot: bool = t.limb == "foot"
	_text(Vector2(x, pr.position.y + 58 * k), str(t.name_ko), 36, Color.WHITE)
	var stat := "발 몫 ×%.2f" % float(t.get("foot_share", 1.0)) if foot else "손 힘 빠짐 ×%.2f %s" % [float(t.fatigue), _drain_word(float(t.fatigue))]
	draw_string(font_m, Vector2(x, pr.position.y + 100 * k), stat, HORIZONTAL_ALIGNMENT_LEFT, w, int(23 * k), CREAM)
	var side := minf(300.0 * k, pr.size.y - 170 * k)
	var ir := Rect2(Vector2(x, pr.position.y + 132 * k), Vector2(side, side))
	var tex := _dict_img("h_" + type)
	if tex != null:
		draw_texture_rect(tex, ir, false)
	draw_rect(ir, Color(CHALK, 0.25), false, maxf(1.0, k))
	var tx := ir.end.x + 32 * k
	var tw := pr.end.x - 32 * k - tx
	draw_string(font_m, Vector2(tx, ir.position.y + 26 * k), "버티는 방향", HORIZONTAL_ALIGNMENT_LEFT, -1, int(20 * k), CREAM)
	draw_multiline_string(font_m, Vector2(tx, ir.position.y + 60 * k), str(t.dir_ko), HORIZONTAL_ALIGNMENT_LEFT, tw, int(22 * k), 3, Color.WHITE)
	draw_string(font_m, Vector2(tx, ir.position.y + 160 * k), "특징", HORIZONTAL_ALIGNMENT_LEFT, -1, int(20 * k), CREAM)
	draw_multiline_string(font_m, Vector2(tx, ir.position.y + 194 * k), str(t.feat_ko), HORIZONTAL_ALIGNMENT_LEFT, tw, int(22 * k), 4, Color.WHITE)


static func _drain_word(f: float) -> String:
	if f < 0.9:
		return "(느림)"
	if f > 1.35:
		return "(아주 빠름)"
	if f > 1.05:
		return "(빠름)"
	return ""


func _draw_course_card(r: Rect2, c: Dictionary, n := 0) -> void:
	var progress: Progress = game.progress
	_card(r)
	_buttons.append({"rect": r, "action": "course", "arg": c.course_id})
	var x := r.position.x + 18 * k
	var w := r.size.x - 36 * k
	draw_string(font, Vector2(x, r.position.y + 44 * k), ("%d. " % n if n > 0 else "") + str(c.name_ko), HORIZONTAL_ALIGNMENT_LEFT, w, int(26 * k), Color.WHITE)
	draw_multiline_string(font, Vector2(x, r.position.y + 76 * k), str(c.get("text_ko", {}).get("purpose", "")), HORIZONTAL_ALIGNMENT_LEFT, w, int(18 * k), 2, DIM)
	draw_string(font, Vector2(x, r.position.y + 140 * k), _course_progress(c), HORIZONTAL_ALIGNMENT_LEFT, w, int(21 * k), CREAM)
	if c.kind == "button":
		var open := progress.tutorial_done(c.tutorial)
		var t := "✓ 버튼 열림" if open else "버튼 잠김 · 튜토리얼을 마치면 열려요"
		if not open:
			_lock(Vector2(x + 8 * k, r.position.y + 166 * k), DIM)
		draw_string(font, Vector2(x + (0.0 if open else 26 * k), r.position.y + 174 * k), t, HORIZONTAL_ALIGNMENT_LEFT, w, int(19 * k), CREAM if open else DIM)
	draw_string(font, Vector2(x, r.end.y - 14 * k), "열기 ›", HORIZONTAL_ALIGNMENT_RIGHT, w, int(19 * k), DIM)


## "✓ 배웠어요 · 문제 2/3". 기본 조작을 건너뛰었으면 "건너뜀".
func _course_progress(c: Dictionary) -> String:
	var progress: Progress = game.progress
	var t := "– 아직"
	if progress.tutorial_done(c.tutorial):
		t = "✓ 배웠어요"
	elif c.course_id == Progress.BASIC_COURSE and progress.basic_skipped:
		t = "건너뜀"
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
	_button(Rect2(Vector2(60, 120) * k, Vector2(200, 52) * k), "‹ 수업 목록", "courses", "", 22)
	if c.is_empty():
		_text(Vector2(60 * k, 230 * k), "과정을 찾지 못했어요", 24, DIM)
		return
	var x := 60.0 * k
	var w := size.x - 120 * k
	_text(Vector2(x, 225 * k), str(c.name_ko), 32, Color.WHITE)
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
	_card(r)
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


# ---------- 만들기 탭(작업 6) ----------

var make_msg := ""
var mine_delete := ""


var make_view := "mine"     # "mine" 내 문제 / "browse" 둘러보기(공개 목록)
var browse_rows: Array = []
var browse_sort := "stars"
var browse_grade := ""
var browse_busy := false
var browse_more := false
var my_stars := {}           # 서버 문제 id → true(내가 준 별)
var _input_edit: LineEdit
var input_mode := ""         # "code" 코드로 열기 / "nick" 별명 바꾸기


func _draw_make(size: Vector2) -> void:
	var x := 80.0 * k
	var y := 130.0 * k
	for v in [["mine", "내 문제"], ["browse", "둘러보기"]]:
		_button(Rect2(Vector2(x, y), Vector2(170, 56) * k), v[1], "make_view", v[0], 22, make_view == v[0])
		x += 186 * k
	_button(Rect2(Vector2(x, y), Vector2(190, 56) * k), "코드로 열기", "input_open", "code", 22)
	x += 206 * k
	var nick: String = game.progress.nickname if game.progress.nickname != "" else "(처음 올릴 때 정해요)"
	_text(Vector2(x + 10 * k, y + 36 * k), "별명: " + nick, 19, DIM)
	_button(Rect2(Vector2(size.x - 250 * k, y), Vector2(170, 56) * k), "별명 바꾸기", "input_open", "nick", 20)
	x = 80.0 * k
	y += 80 * k
	if input_mode != "":
		_draw_input(size)
		return
	if make_view == "browse":
		_draw_browse(size, Vector2(x, y))
		return
	_button(Rect2(Vector2(x, y), Vector2(240, 64) * k), "+ 새 문제", "edit", "", 26, true)
	_text(Vector2(x + 270 * k, y + 40 * k), "벽에 홀드를 놓아 문제를 만들고 직접 올라 봐요. 인터넷 없이 이 기기에 저장돼요.", 19, DIM)
	y += 124 * k
	_text(Vector2(x, y), "내 문제", 26, CREAM)
	y += 20 * k
	var mine := MyRoutes.list()
	if mine.is_empty():
		_text(Vector2(x, y + 40 * k), "아직 만든 문제가 없어요.", 21, DIM)
	var cw := 440.0 * k
	var ch := 170.0 * k
	for i in mini(mine.size(), 6):
		var m: Dictionary = mine[i]
		var r := Rect2(Vector2(x + (i % 3) * (cw + 20 * k), y + int(i / 3) * (ch + 20 * k)), Vector2(cw, ch))
		_card(r)
		var nm: String = m.name if m.name != "" else "(이름 없음)"
		_text(r.position + Vector2(16, 40) * k, nm, 24, Color.WHITE)
		var c: Dictionary = game.progress.cleared.get(m.route_id, {})
		var done := int(c.get("content_version", -1)) == int(m.version) and c.has("best_seconds")
		_text(r.position + Vector2(16, 72) * k, "예상 %s · 판 %d · %s" % [m.grade, m.version, "직접 완등함" if done else "아직 완등 전"], 18, CREAM if done else DIM)
		var bw := (cw - 52 * k) / 3.0
		var by := r.end.y - 62 * k
		_button(Rect2(Vector2(r.position.x + 16 * k, by), Vector2(bw, 48 * k)), "고치기", "edit", m.route_id, 20)
		_button(Rect2(Vector2(r.position.x + 26 * k + bw, by), Vector2(bw, 48 * k)), "올라 보기", "play_mine", m.route_id, 20, true)
		_button(Rect2(Vector2(r.position.x + 36 * k + bw * 2, by), Vector2(bw, 48 * k)), "지우기", "mine_delete_ask", m.route_id, 20)
	if make_msg != "":
		_text(Vector2(x, size.y - 40 * k), make_msg, 19, Color(1, 0.75, 0.6))
	if mine_delete != "":
		var box := Rect2(Vector2(size.x * 0.5 - 300 * k, size.y * 0.5 - 110 * k), Vector2(600, 220) * k)
		_buttons = []
		_panel(box)
		_text(box.position + Vector2(30, 60) * k, "이 문제를 지울까요? 되돌릴 수 없어요.", 24, Color.WHITE)
		_button(Rect2(box.position + Vector2(30, 130) * k, Vector2(250, 60) * k), "지우기", "mine_delete_yes", mine_delete, 24, true)
		_button(Rect2(box.position + Vector2(320, 130) * k, Vector2(250, 60) * k), "그만두기", "mine_delete_no", "", 24)


func _draw_browse(size: Vector2, at: Vector2) -> void:
	var x := at.x
	var y := at.y
	if not game.share().enabled():
		_text(Vector2(x, y + 40 * k), "공유 서버가 아직 준비되지 않았어요.", 22, DIM)
		return
	for s in [["stars", "별 많은 순"], ["new", "최신"]]:
		_button(Rect2(Vector2(x, y), Vector2(150, 48) * k), s[1], "browse_sort", s[0], 19, browse_sort == s[0])
		x += 160 * k
	x += 20 * k
	for g in ["", "V0", "V1", "V2", "V3", "V4", "V5", "V6", "V7"]:
		_button(Rect2(Vector2(x, y), Vector2(66, 48) * k), "전체" if g == "" else g, "browse_grade", g, 17, browse_grade == g)
		x += 72 * k
	y += 64 * k
	if browse_busy and browse_rows.is_empty():
		_text(Vector2(at.x, y + 40 * k), "서버 연결 중…", 22, DIM)
		return
	if browse_rows.is_empty():
		_text(Vector2(at.x, y + 40 * k), make_msg if make_msg != "" else "아직 공개된 문제가 없어요.", 21, DIM)
		return
	var cw := 470.0 * k
	var ch := 150.0 * k
	var cols := 3
	var shown := mini(browse_rows.size(), 6)
	for i in shown:
		var row: Dictionary = browse_rows[i]
		var r := Rect2(Vector2(at.x + (i % cols) * (cw + 16 * k), y + int(i / cols) * (ch + 16 * k)), Vector2(cw, ch))
		_card(r)
		_text(r.position + Vector2(16, 36) * k, str(row.get("name", "")), 23, Color.WHITE)
		_text(r.position + Vector2(16, 66) * k, "%s · %s · ★%d · 완등 %d" % [row.get("grade", ""), row.get("author_name", ""), int(row.get("stars", 0)), int(row.get("clears", 0))], 17, CREAM)
		var by := r.end.y - 58 * k
		var starred: bool = my_stars.has(str(row.get("id", "")))
		_button(Rect2(Vector2(r.position.x + 16 * k, by), Vector2(170, 46) * k), "올라 보기", "shared_play", str(row.get("code", "")), 19, true)
		_button(Rect2(Vector2(r.position.x + 196 * k, by), Vector2(130, 46) * k), ("★ 별 줌" if starred else "☆ 별"), "star", str(i), 18, starred)
		_button(Rect2(Vector2(r.position.x + 336 * k, by), Vector2(118, 46) * k), "신고", "report", str(i), 18)
	if browse_more:
		_button(Rect2(Vector2(at.x, size.y - 90 * k), Vector2(200, 50) * k), "더 받기", "browse_more", "", 20)
	if make_msg != "":
		_text(Vector2(at.x + 230 * k, size.y - 58 * k), make_msg, 19, Color(1, 0.75, 0.6))


func _draw_input(size: Vector2) -> void:
	var box := Rect2(Vector2(size.x * 0.5 - 340 * k, 240 * k), Vector2(680, 250) * k)
	_panel(box)
	_text(box.position + Vector2(30, 50) * k, "공유 코드 6글자를 넣어 주세요" if input_mode == "code" else "별명(최대 12자)", 22, Color.WHITE)
	_input_edit.position = box.position + Vector2(30, 80) * k
	_input_edit.size = Vector2(620, 60) * k
	_button(Rect2(box.position + Vector2(30, 170) * k, Vector2(290, 56) * k), "열기" if input_mode == "code" else "바꾸기", "input_go", "", 22, true)
	_button(Rect2(box.position + Vector2(360, 170) * k, Vector2(290, 56) * k), "그만두기", "input_close", "", 22)
	if make_msg != "":
		_text(box.position + Vector2(30, 290) * k, make_msg, 19, Color(1, 0.75, 0.6))


func _open_input(mode: String) -> void:
	input_mode = mode
	make_msg = ""
	if _input_edit == null:
		_input_edit = LineEdit.new()
		add_child(_input_edit)
	_input_edit.visible = true
	UiFont.style_line_edit(_input_edit, k, 28, 60 * k)  # 기본 회색 상자 대신 홈 알약 모양
	_input_edit.max_length = 6 if mode == "code" else 12
	_input_edit.text = "" if mode == "code" else game.progress.nickname
	_input_edit.grab_focus()


func _close_input() -> void:
	input_mode = ""
	if _input_edit != null:
		_input_edit.visible = false


func _input_go() -> void:
	var t := _input_edit.text
	if input_mode == "nick":
		if game.get_flow().set_nickname(t):
			_close_input()
		else:
			make_msg = "별명에 쓸 수 없는 말이 있거나 비어 있어요"
		queue_redraw()
		return
	var code := ShareCode.normalize(t)
	if not ShareCode.is_valid(code):
		make_msg = "코드는 6글자예요(0·O·1·I는 쓰지 않아요)"
		queue_redraw()
		return
	_fetch_and_play(code)


func _browse_load(more: bool) -> void:
	if browse_busy:
		return
	browse_busy = true
	make_msg = ""
	if not more:
		browse_rows = []
	queue_redraw()
	var share: ShareClient = game.share()
	var off := browse_rows.size()
	var res: Dictionary = await share.rows(func(): return share.api.browse(browse_sort, browse_grade, off))
	if res.ok:
		browse_rows += res.rows
		browse_more = res.rows.size() >= ShareApi.PAGE
		var st: Dictionary = await share.rows(func(): return share.api.my_stars())
		if st.ok:
			my_stars = {}
			for r in st.rows:
				my_stars[str(r.get("route_id", ""))] = true
	else:
		make_msg = res.error
	browse_busy = false
	queue_redraw()


## 코드로 문제 전체를 받아 이 기기에 두고 연다(이미 받아 둔 같은 판이면 서버 없이).
func _fetch_and_play(code: String) -> void:
	make_msg = "받는 중…"
	queue_redraw()
	var share: ShareClient = game.share()
	var res: Dictionary = await share.rows(func(): return share.api.by_code(code))
	if not res.ok:
		if not SharedRoutes.load_entry(code).is_empty() and game.play_shared(code):
			return  # 서버가 안 되면 받아 둔 판으로
		make_msg = res.error
		queue_redraw()
		return
	if res.rows.is_empty():
		make_msg = "그 코드의 문제를 찾지 못했어요"
		queue_redraw()
		return
	var row: Dictionary = res.rows[0]
	var data = row.get("data")
	if not data is Dictionary or SharedRoutes.too_new(data):
		make_msg = "앱을 업데이트해 주세요(더 새 판의 문제예요)"
		queue_redraw()
		return
	var meta := {"id": str(row.get("id", "")), "code": code, "name": str(row.get("name", "")), "grade": str(row.get("grade", "")),
		"author_name": str(row.get("author_name", "")), "version": int(row.get("version", 1))}
	if not SharedRoutes.save(code, meta, data) or not game.play_shared(code):
		make_msg = "이 문제를 열 수 없어요"
		queue_redraw()


## 별: 완등한 사람만(서버가 확인). 다시 누르면 거둔다.
func _star(i: int) -> void:
	if i < 0 or i >= browse_rows.size():
		return
	var row: Dictionary = browse_rows[i]
	var id := str(row.get("id", ""))
	if not game.progress.is_cleared(SharedRoutes.local_id(str(row.get("code", "")))):
		make_msg = ShareApi.E_CLEAR
		queue_redraw()
		return
	var on := not my_stars.has(id)
	var share: ShareClient = game.share()
	var res: Dictionary = await share.rows(func(): return share.api.set_star(id, on))
	if res.ok:
		if on:
			my_stars[id] = true
		else:
			my_stars.erase(id)
		row["stars"] = int(res.rows[0]) if not res.rows.is_empty() and (res.rows[0] is float or res.rows[0] is int) else int(row.get("stars", 0)) + (1 if on else -1)
	else:
		make_msg = res.error
	queue_redraw()


func _report(i: int) -> void:
	if i < 0 or i >= browse_rows.size():
		return
	var share: ShareClient = game.share()
	var id := str(browse_rows[i].get("id", ""))
	var res: Dictionary = await share.rows(func(): return share.api.report(id, ""))
	make_msg = "신고했어요. 고마워요" if res.ok else res.error
	queue_redraw()


# ---------- 도우미 ----------

## 글자. 26 이상은 제목으로 보고 굵게.
func _text(pos: Vector2, s: String, fs: int, col: Color) -> void:
	draw_string(font_b if fs >= 26 else font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * k), col)


## 둥근 판 모양(채움·모서리·테두리). bw는 배율 전 두께.
func _box(fill: Color, radius: float, border := Color(0, 0, 0, 0), bw := 0.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(radius))
	if bw > 0.0 and border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(maxi(1, roundi(bw * k)))
	sb.anti_aliasing = true
	return sb


## 카드(문제·수업·홀드 등): 단단한 슬레이트 블록(선 없음). dim이면 더 옅게(잠김).
func _card(r: Rect2, dim := false) -> void:
	draw_style_box(_box(Color(SLATE, 0.62 if dim else 0.92), BLOCK_R * k), r)


## 등급 테이프 색(없으면 노랑).
static func tape(grade: String) -> Color:
	return GRADE_TAPE.get(grade, SHOE)


## 어두운 테이프(검정)의 테두리 색. 그 밖에는 투명.
static func tape_edge(grade: String) -> Color:
	return Color(CHALK, 0.55) if tape(grade).get_luminance() < 0.15 else Color(0, 0, 0, 0)


## 테이프 색 띠(검정이면 테두리도).
func _tape_bar(r: Rect2, grade: String, alpha := 1.0) -> void:
	draw_rect(r, Color(tape(grade), alpha))
	if tape_edge(grade).a > 0.0:
		draw_rect(r, Color(tape_edge(grade), tape_edge(grade).a * alpha), false, maxf(1.0, k))


## 바탕색 위 글자색: 밝은 바탕이면 남색, 어두우면 흰색.
static func ink_on(c: Color) -> Color:
	return NIGHT if c.get_luminance() > 0.55 else CHALK


## 창(확인·입력·설명): 거의 불투명한 남색 둥근 판.
func _panel(r: Rect2) -> void:
	draw_style_box(_box(Color(SLATE, 0.98), BLOCK_R * 1.5 * k), r)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 6 * k)), SHOE)


## r 안에서 글자를 세로 가운데에 두는 기준선.
func _baseline(r: Rect2, fs: int, f: Font) -> float:
	var px := int(fs * k)
	return r.position.y + (r.size.y + f.get_ascent(px) - f.get_descent(px)) * 0.5


## 버튼: 주(strong) = 비스듬히 기운 노란 블록 + 남색 굵은 글자, 보조 = 선 없는 슬레이트 블록 + 흰 글자.
func _button(r: Rect2, text: String, action: String, arg: String, fs := 24, strong := false) -> void:
	var sb := _box(SHOE if strong else Color(SLATE, 0.9), BLOCK_R * k)
	if strong:
		sb.skew = Vector2(SKEW, 0)
	draw_style_box(sb, r)
	if text != "":
		var f: Font = font_b if strong else font_m
		draw_string(f, Vector2(r.position.x, _baseline(r, fs, f)), text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(fs * k), NIGHT if strong else CHALK)
	_buttons.append({"rect": r, "action": action, "arg": arg})


## 자물쇠 그림(색이 아닌 모양으로 잠김 표시).
func _lock(c: Vector2, col: Color) -> void:
	draw_arc(c + Vector2(0, -4 * k), 5 * k, PI, TAU, 10, col, 2.0 * k)
	draw_rect(Rect2(c + Vector2(-7, -4) * k, Vector2(14, 11) * k), col)


# ---------- 설정(docs/49) ----------

## 화면 표시 켜고 끄기. 난이도와 상관없이 여기서만 정한다(2026-11-19 사용자).
const DISPLAY_ROWS := [
	["balance", "무게중심", "몸 가운데 점과 늘어진 줄, 딛은 발 아래 받침을 보여 줘요. 점의 줄이 두 발 위에 떨어지면 초록(가만히 있으면 손 힘이 차요), 아니면 노랑(손 힘이 빠져요), 위험하면 주황."],
	["balance_hint", "몸 옮길 쪽 안내", "무게중심이 노랑일 때 몸을 옮길 쪽 화살표와 한 줄 안내를 보여 줘요. 무게중심을 켰을 때만 보여요."],
	["ghost", "내 최고 기록 고스트", "그 문제를 가장 빨리 오른 내 기록이 흰 막대 사람으로 같이 올라요. 도움 없이 깬 기록만 남아요."],
	["ai_ghost", "AI 고스트", "AI(검사 봇)가 정답 순서로 오른 기록이 하늘색 막대 사람으로 같이 올라요. 길을 미리 보여 주니 스스로 읽고 싶으면 꺼 두세요."],
	["dev_info", "개발 정보 보이기", "플레이 화면 아래에 FPS·화면 크기·패드 크기 같은 개발용 글자를 보여 줘요. 보통은 꺼 두세요."],
	["loads", "팔다리 힘 분포", "팔다리를 막대로 그리고 그 손발이 받치는 몸무게 몫(%)으로 색을 입혀요. 회색 → 초록 → 노랑 → 빨강일수록 많이 받쳐요. 몫이 큰 손발을 떼면 다른 손발이 그만큼 더 받쳐야 해요."],
]


func _draw_settings(size: Vector2) -> void:
	var x := 100.0 * k
	var y := 140.0 * k
	draw_string(font_b, Vector2(x, y), "화면 표시", HORIZONTAL_ALIGNMENT_LEFT, -1, int(30 * k), CHALK)
	y += 20 * k
	var w := size.x * 0.5 - 130 * k  # 왼쪽 칸(오른쪽 칸은 몸 옮기기)
	for row in DISPLAY_ROWS:
		var on: bool = game.progress.display_on(row[0])
		var dim: bool = row[0] == "balance_hint" and not game.progress.display_on("balance")
		draw_string(font, Vector2(x, y + 36 * k), row[1], HORIZONTAL_ALIGNMENT_LEFT, -1, int(25 * k), DIM if dim else Color.WHITE)
		draw_multiline_string(font, Vector2(x, y + 62 * k), row[2], HORIZONTAL_ALIGNMENT_LEFT, w - 170 * k, int(17 * k), 3, DIM)
		_button(Rect2(Vector2(x + w - 140 * k, y + 14 * k), Vector2(140, 52) * k), "켜짐" if on else "꺼짐", "display", row[0], 22, on)
		y += 108 * k
	_draw_control_settings(Vector2(size.x * 0.5 + 40 * k, 150 * k), size.x * 0.5 - 140 * k)


## 몸 옮기기(작업 2): 가운데 끌기 / 휴대폰 기울이기. 기울이기일 때만 민감도·반응 시작 각도·함께 쓰기.
func _draw_control_settings(at: Vector2, w: float) -> void:
	var p: Progress = game.progress
	var x := at.x
	var y := at.y
	draw_string(font_b, Vector2(x, y), "몸 옮기기", HORIZONTAL_ALIGNMENT_LEFT, -1, int(30 * k), CHALK)
	y += 30 * k
	var tilt: bool = p.control_get("body") == "tilt"
	var sensor := TiltMapper.available(Input.get_gravity())
	var bw := (w - 20 * k) * 0.5
	_button(Rect2(Vector2(x, y), Vector2(bw, 64 * k)), "가운데 끌기", "control", "body=drag", 22, not tilt)
	if sensor or tilt:
		_button(Rect2(Vector2(x + bw + 20 * k, y), Vector2(bw, 64 * k)), "휴대폰 기울이기", "control", "body=tilt", 22, tilt)
	else:
		var r := Rect2(Vector2(x + bw + 20 * k, y), Vector2(bw, 64 * k))
		draw_style_box(_box(Color(NIGHT, 0.4), r.size.y * 0.5, HAIR, 1.5), r)
		draw_string(font_m, Vector2(r.position.x, _baseline(r, 22, font_m)), "휴대폰 기울이기", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(22 * k), DIM)
	y += 64 * k
	if not sensor:
		draw_string(font, Vector2(x, y + 30 * k), "이 기기는 기울기 센서가 없어요", HORIZONTAL_ALIGNMENT_LEFT, w, int(18 * k), Color("ff9a7a"))
		y += 36 * k
	if not tilt:
		draw_multiline_string(font, Vector2(x, y + 34 * k), "네 패드 사이 가운데를 끌어서 몸(무게중심)을 옮겨요.", HORIZONTAL_ALIGNMENT_LEFT, w, int(17 * k), 2, DIM)
		return
	draw_multiline_string(font, Vector2(x, y + 34 * k), "좌우로 기울이면 몸이 좌우로, 위쪽을 앞으로 숙이면 위로 가요. 기울인 동안만 옮기고, 문제를 시작할 때마다 그때 기울기를 0으로 잡아요.", HORIZONTAL_ALIGNMENT_LEFT, w, int(17 * k), 3, DIM)
	y += 100 * k
	var sens := int(p.control_get("tilt_sens"))
	var dead := float(p.control_get("tilt_dead"))
	for row in [["민감도", "%d / %d" % [sens, Progress.TILT_SENS_MAX], "tilt_sens", sens, 1.0], ["반응 시작 각도", "%d°" % int(dead), "tilt_dead", dead, 1.0]]:
		draw_string(font, Vector2(x, y + 40 * k), row[0], HORIZONTAL_ALIGNMENT_LEFT, -1, int(24 * k), Color.WHITE)
		var bx := x + w - 250 * k
		_button(Rect2(Vector2(bx, y + 4 * k), Vector2(64, 56) * k), "−", "control", "%s=%s" % [row[2], float(row[3]) - float(row[4])], 28)
		draw_string(font, Vector2(bx + 64 * k, y + 42 * k), row[1], HORIZONTAL_ALIGNMENT_CENTER, 122 * k, int(26 * k), CREAM)
		_button(Rect2(Vector2(bx + 186 * k, y + 4 * k), Vector2(64, 56) * k), "+", "control", "%s=%s" % [row[2], float(row[3]) + float(row[4])], 28)
		y += 72 * k
	var both: bool = p.control_get("tilt_with_drag")
	draw_string(font, Vector2(x, y + 40 * k), "가운데 끌기도 함께 쓰기", HORIZONTAL_ALIGNMENT_LEFT, -1, int(24 * k), Color.WHITE)
	_button(Rect2(Vector2(x + w - 150 * k, y + 4 * k), Vector2(150, 56) * k), "켜짐" if both else "꺼짐", "control", "tilt_with_drag=%d" % (0 if both else 1), 22, both)


# ---------- 캐릭터 고르기(docs/34 §7) ----------

func _open_look() -> void:
	_asm = CharacterAssembler.load_catalog()
	look = _asm.normalize(game.progress.look)
	var path := _asm.model_path(str(look.body))
	if path == "" or not ResourceLoader.exists(path):
		return
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
	env.environment.ambient_light_energy = 0.3   # 2026-11-22: 흰 옷·피부가 하얗게 날아가 게임 화면(play_3d)만큼 낮춤
	_pv.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 25, 0)
	sun.light_energy = 0.8
	_pv.add_child(sun)
	_load_preview_model()
	_pv_cam = Camera3D.new()
	_pv_cam.fov = 38
	_pv.add_child(_pv_cam)
	_pv_cam.current = true
	_pv_dist = LOOK_DIST_MAX
	_pv_y = 0.0
	_pv_touch.clear()
	_pv_mouse = false
	_look_cam()
	choosing_look = true
	queue_redraw()


## 고른 몸의 모델로 미리보기를 (다시) 만든다. 돌려 둔 각도는 이어 간다. 팔은 내린 자세(T자 아님).
func _load_preview_model() -> void:
	var path := _asm.model_path(str(look.body))
	if path == "" or not ResourceLoader.exists(path):
		return
	var rot := PI  # 앞(−Z, 벽 쪽)이 카메라를 보게
	if _pv_model != null:
		rot = _pv_model.rotation.y
		_pv_model.queue_free()
	_pv_model = load(path).instantiate()
	_pv.add_child(_pv_model)
	_pv_model.rotation.y = rot
	_asm.apply(_pv_model, look)
	CharacterAssembler.style(_pv_model, preload("res://art/shaders/toon.gdshader"), preload("res://art/shaders/outline.gdshader"), INK)
	CharacterAssembler.relax_arms(_pv_model)


## 미리보기 카메라 거리·높이를 범위 안으로. 멀수록(전신) 높이는 가운데로 모인다: 다 보일 때는 옮길 필요가 없고,
## 가까이 갔을 때만 머리~발까지 위아래로 옮겨 볼 수 있다.
static func look_view(dist: float, cam_y: float) -> Vector2:
	var d := clampf(dist, LOOK_DIST_MIN, LOOK_DIST_MAX)
	var room := 1.0 - (d - LOOK_DIST_MIN) / (LOOK_DIST_MAX - LOOK_DIST_MIN)
	return Vector2(d, clampf(cam_y, -0.75 * room, 0.68 * room))


func _look_cam() -> void:
	var v := look_view(_pv_dist, _pv_y)
	_pv_dist = v.x
	_pv_y = v.y
	if _pv_cam != null:
		_pv_cam.position = Vector3(0, _pv_y, _pv_dist)
	queue_redraw()


## 미리보기 손짓(2026-11-23 사용자 "회전은 멈춰 있어, 내가 할 수 있도록"): 한 손가락(마우스) 끌기 = 좌우로 돌리기·위아래로
## 옮기기, 두 손가락 벌리기·오므리기(휠·트랙패드) = 확대·축소. 미리보기 안에서 시작한 손짓은 버튼 누르기로 넘기지 않는다.
func _look_gesture(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		if event.pressed and _pv_rect.has_point(event.position):
			_pv_touch[event.index] = event.position
			return true
		if not event.pressed and _pv_touch.has(event.index):
			_pv_touch.erase(event.index)
			return true
	elif event is InputEventScreenDrag and _pv_touch.has(event.index):
		if _pv_touch.size() >= 2:
			var other: Vector2 = _pv_touch[_pv_touch.keys().filter(func(i): return i != event.index)[0]]
			var before := other.distance_to(_pv_touch[event.index])
			var after := other.distance_to(event.position)
			if before > 1.0 and after > 1.0:
				_look_zoom(before / after)  # 벌리면 가까이
		else:
			_look_drag(event.relative)
		_pv_touch[event.index] = event.position
		return true
	elif event is InputEventMouseButton and (_pv_mouse or _pv_rect.has_point(event.position)):
		if event.button_index == MOUSE_BUTTON_LEFT:
			_pv_mouse = event.pressed
			return true
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_look_zoom(0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.9)
			return true
	elif event is InputEventMouseMotion and _pv_mouse:
		_look_drag(event.relative)
		return true
	elif event is InputEventMagnifyGesture and _pv_rect.has_point(event.position):
		_look_zoom(1.0 / maxf(event.factor, 0.01))
		return true
	return false


func _look_drag(rel: Vector2) -> void:
	if _pv_model != null:
		_pv_model.rotation.y += rel.x / maxf(_pv_rect.size.x, 1.0) * TAU * 0.75  # 미리보기 폭만큼 끌면 3/4 바퀴
	_pv_y += rel.y / maxf(_pv_rect.size.y, 1.0) * 0.69 * _pv_dist  # 손가락을 따라 몸이 움직이게(화면 높이 = 거리 × 0.69)
	_look_cam()


func _look_zoom(f: float) -> void:
	_pv_dist *= f
	_look_cam()


func _close_look() -> void:
	choosing_look = false
	if _pv != null:
		_pv.queue_free()
	_pv = null
	_pv_model = null
	_pv_cam = null
	_pv_touch.clear()
	_pv_mouse = false
	queue_redraw()


var _sensor_seen := false


func _process(_delta: float) -> void:
	# 기울기 센서 값은 시작 뒤 조금 늦게 들어온다: 바뀌면 설정 탭을 다시 그린다
	if tab == "settings" and TiltMapper.available(Input.get_gravity()) != _sensor_seen:
		_sensor_seen = not _sensor_seen
		queue_redraw()
	if choosing_look and _pv_model != null:
		queue_redraw()  # 미리보기 화면 갱신(돌리기는 사용자가 한다)


## 왼쪽 3D 미리보기(손가락으로 돌리기·확대), 오른쪽 슬롯마다 [◀ 이름 ▶]. 대안이 하나뿐인 슬롯은 화살표를 흐리게 하고 "1종"을 붙인다.
func _draw_look(size: Vector2) -> void:
	_buttons = []
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	draw_string(font, Vector2(0, 70 * k), "캐릭터", HORIZONTAL_ALIGNMENT_CENTER, size.x, int(40 * k), CREAM)
	var pvh := size.y - 160 * k
	var pvw := pvh * 560.0 / 760.0
	var pr := Rect2(Vector2(size.x * 0.30 - pvw * 0.5, 100 * k), Vector2(pvw, pvh))
	draw_rect(pr, Color(1, 1, 1, 0.05))
	_pv_rect = pr
	if _pv != null:
		draw_texture_rect(_pv.get_texture(), pr, false)
	draw_string(font, Vector2(pr.position.x, pr.end.y + 34 * k), "끌어서 돌리기 · 두 손가락으로 확대", HORIZONTAL_ALIGNMENT_CENTER, pr.size.x, int(18 * k), DIM)
	var x := size.x * 0.52
	var y := 130 * k
	var rw := 560.0 * k
	for row in LOOK_ROWS:
		var sid: String = row[0]
		var count: int = _asm.bodies().size() if sid == "body" else _asm.parts_for(sid, str(look.get("body", ""))).size()
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
	draw_string(font, Vector2(x, y + 130 * k), "남성은 기본 착장 한 벌이에요. 옷 갈아입기는 지금 여성 캐릭터만 돼요.", HORIZONTAL_ALIGNMENT_LEFT, -1, int(18 * k), DIM)
