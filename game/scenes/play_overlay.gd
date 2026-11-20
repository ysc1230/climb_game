extends RefCounted
## 플레이 화면 위 진행 UI(docs/28 §5·§6.1): 완등 결과, 튜토리얼 안내 줄·[도움말]·완료, 일시정지 [목록], [일시정지] 버튼.
## play_test가 _draw 끝에서 draw()를 부르고, 누른 위치를 tap()으로 넘겨 받은 동작 이름을 처리한다.
## 동작: "pause" "list" "retry" "next" "help" "skip". 색만으로 구분하지 않고 글자(✓, !)를 함께 쓴다(docs/05).

const CREAM := Color("f1d59a")
const INK := Color("302820")

var font: Font
## 비어 있지 않으면 결과 오버레이 {seconds, falls, no_fall, time, time_limit, next, saved}.
var result := {}
var result_ms := 0
## 떨어진 뒤 조언 카드 {cause, advice}. 화면 어디를 눌러도 다시 시작.
var fall_card := {}  # 결과 카드가 뜬 시각(아래에서 0.25초 동안 올라옴)
## 비어 있지 않으면 튜토리얼 시작 설명 카드 {title, purpose, when, how}. 탭하면 사라진다(그동안 플레이 멈춤).
var tutorial: TutorialRunner
var tutorial_done := false
var next_course := {}     # 튜토리얼 완료 화면 [다음: 과정] {route_id, name}(docs/33 §4.1)
var dim_band := false     # 위험 경고 동안 안내 줄을 흐리게(docs/33 §3.5)
var help_open := false
var can_skip := false     # 기본 조작 첫 실행: [건너뛰기]
var has_list := false     # Game이 있을 때만 [목록]
## 튜토리얼 목표 홀드의 화면 Y(없으면 −1). 안내 줄이 그 홀드를 덮지 않게 위·아래를 고른다.
var goal_screen_y := -1.0
var _help_step := -1
var _help_seen := 0       # 이 단계에서 이미 자동으로 열어 준 도움말 단계
var _buttons: Array = []  # [{rect, action}] 마지막으로 그린 버튼
var pause_rect := Rect2()  # 위쪽 정보 패널(hud.gd)이 그린 일시정지 버튼 자리
var detail_rect := Rect2()  # 위쪽 [i] 상세 정보 버튼 자리


## 결과·완료 화면이 떠 있어 플레이를 멈추는가.
func blocking() -> bool:
	return not result.is_empty() or tutorial_done or not fall_card.is_empty() or not demo_bar.is_empty()


var help_rects: Array = []  # 위쪽 [힌트]·[시범 보기](hud.gd가 그림) [{rect, action}]
## 시범 보기 중 아래 조작 줄 {speed: 1|2, from_fall: bool, can_from_fall: bool}. 비면 시범 보기 아님.
var demo_bar := {}


## 다른 곳(hud.gd)이 그린 버튼을 누름 판정에 넣는다.
func add_buttons(list: Array) -> void:
	_buttons.append_array(list)


## 마지막으로 그린 버튼 중 pos를 덮는 것의 동작. 없으면 "".
func tap(pos: Vector2) -> String:
	if not fall_card.is_empty():
		return "fall_retry"
	for i in range(_buttons.size() - 1, -1, -1):
		var b: Dictionary = _buttons[i]
		if b.has("circle"):  # 동그란 버튼 [중심, 반지름](위험 게이지 자동 도움)
			if pos.distance_to(b.circle[0]) <= float(b.circle[1]):
				return b.action
		elif (b.rect as Rect2).has_point(pos):
			return b.action
	return ""


static func format_seconds(s: float) -> String:
	if s < 60.0:
		return "%.1f초" % s
	return "%d분 %.1f초" % [int(s) / 60, fmod(s, 60.0)]


## paused: 일시정지 화면 위, selecting: 기술 고르는 중(튜토리얼 줄 숨김).
func draw(ci: CanvasItem, size: Vector2, k: float, paused: bool, selecting: bool) -> void:
	_buttons = []
	if not result.is_empty():
		_draw_result(ci, size, k)
		return
	if not fall_card.is_empty():
		_draw_fall_card(ci, size, k)
		return
	if not demo_bar.is_empty():
		_draw_demo_bar(ci, size, k)
		return
	if tutorial_done:
		_draw_done(ci, size, k)
		return
		return
	if paused:
		return  # 일시정지 카드·버튼은 hud.gd(draw_pause)가 그리고 add_buttons로 넘긴다
	if pause_rect.has_area():
		_buttons.append({"rect": pause_rect, "action": "pause"})  # 버튼 모양은 hud.gd가 그린다
	if detail_rect.has_area():
		_buttons.append({"rect": detail_rect, "action": "detail"})
	_buttons.append_array(help_rects)
	if tutorial != null and not selecting:
		_draw_tutorial(ci, size, k)


## 결과 카드(작업 3 §3.2, 휴대폰 가로): 왼쪽 총점·다섯 항목 막대, 오른쪽 시간·메달 칩, 아래 버튼.
## result: {seconds, falls, no_fall, time, time_limit, saved, next, score?, parts?, helped?, flash?, new_best_score?, new_best_time?, best_score?, best_seconds?}
func _draw_result(ci: CanvasItem, size: Vector2, k: float) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6))
	var rise := 1.0 - ease(clampf((Time.get_ticks_msec() - result_ms) / 250.0, 0.0, 1.0), 0.4)
	var pw := minf(1040.0 * k, size.x - 40 * k)
	var ph := minf(560.0 * k, size.y - 30 * k)
	var panel := Rect2(Vector2(size.x * 0.5 - pw * 0.5, size.y * 0.5 - ph * 0.5 + rise * size.y * 0.6), Vector2(pw, ph))
	ci.draw_rect(panel, Color(0.12, 0.11, 0.1, 0.95))
	ci.draw_rect(panel, CREAM, false, 3.0)
	var x := panel.position.x
	var y := panel.position.y
	var lw := pw * 0.55
	ci.draw_string(font, Vector2(x + 36 * k, y + 58 * k), "완등!", HORIZONTAL_ALIGNMENT_LEFT, -1, int(40 * k), CREAM)
	if result.has("score"):
		_draw_score(ci, Vector2(x + 36 * k, y + 80 * k), lw - 60 * k, k)
	var rx := x + lw + 10 * k
	var rw := pw - lw - 46 * k
	var ty := y + 58 * k
	ci.draw_string(font, Vector2(rx, ty), "시간 %s" % format_seconds(result.seconds), HORIZONTAL_ALIGNMENT_LEFT, -1, int(28 * k), Color.WHITE)
	if bool(result.get("new_best_time", false)) and not bool(result.get("helped", false)):
		ci.draw_string(font, Vector2(rx, ty), "새 최고 시간", HORIZONTAL_ALIGNMENT_RIGHT, rw, int(20 * k), Color("8fe388"))
	elif float(result.get("best_seconds", -1.0)) > 0.0:
		ci.draw_string(font, Vector2(rx, ty + 32 * k), "내 최고 %s" % format_seconds(float(result.best_seconds)), HORIZONTAL_ALIGNMENT_LEFT, -1, int(20 * k), Color(1, 1, 1, 0.7))
	ty += 70 * k
	var limit: float = result.get("time_limit", 0.0)
	var chips := [["완등", true], ["플래시", bool(result.get("flash", false))], ["무추락", bool(result.no_fall)],
		["시간(%s 안)" % format_seconds(limit) if limit > 0.0 else "시간(기준 없음)", bool(result.time)]]
	for c in chips:
		var got: bool = c[1]
		var r := Rect2(Vector2(rx, ty), Vector2(rw, 46 * k))
		ci.draw_rect(r, CREAM if got else Color(1, 1, 1, 0.06))
		ci.draw_rect(r, Color(CREAM, 0.6), false, 2.0)
		ci.draw_string(font, Vector2(r.position.x + 16 * k, r.position.y + 32 * k), ("✓ " if got else "– ") + str(c[0]), HORIZONTAL_ALIGNMENT_LEFT, rw - 20 * k, int(22 * k), Color(0.1, 0.08, 0.06) if got else Color(1, 1, 1, 0.55))
		ty += 56 * k
	if bool(result.get("flash", false)):
		ci.draw_string(font, Vector2(rx, ty + 16 * k), "처음 시도에 한 번에 올랐어요!", HORIZONTAL_ALIGNMENT_LEFT, rw, int(19 * k), CREAM)
	if not result.get("saved", true):
		ci.draw_string(font, Vector2(x, panel.end.y - 96 * k), "기록을 저장하지 못했어요", HORIZONTAL_ALIGNMENT_CENTER, pw, int(20 * k), Color("ff8a6a"))
	var acts := []
	if str(result.get("next", "")) != "":
		acts.append(["다음", "next"])
	acts.append(["다시", "retry"])
	if has_list:
		acts.append(["목록", "list"])
	_button_row(ci, Rect2(Vector2(x + pw * 0.2, panel.end.y - 80 * k), Vector2(pw * 0.6, 60 * k)), acts, k)


const SCORE_ROWS := [["energy", "힘 아끼기", 30], ["stable", "안정", 25], ["precise", "정확한 손발", 20], ["technique", "기술", 15], ["finish", "마무리", 10]]


## 총점(크게) / 100 + 도움·새 최고 + 다섯 항목 막대.
func _draw_score(ci: CanvasItem, at: Vector2, w: float, k: float) -> void:
	var helped := bool(result.get("helped", false))
	var total := ScoreCalc.format(float(result.score))
	ci.draw_string(font, at + Vector2(0, 74 * k), total, HORIZONTAL_ALIGNMENT_LEFT, -1, int(80 * k), Color.WHITE)
	var tw := font.get_string_size(total, HORIZONTAL_ALIGNMENT_LEFT, -1, int(80 * k)).x
	ci.draw_string(font, at + Vector2(tw + 10 * k, 74 * k), "/ 100", HORIZONTAL_ALIGNMENT_LEFT, -1, int(28 * k), Color(1, 1, 1, 0.6))
	var tag := ""
	if helped:
		tag = "도움 — 최고 기록에 들어가지 않아요"
	elif bool(result.get("new_best_score", false)):
		tag = "새 최고 점수"
	elif float(result.get("best_score", -1)) >= 0.0:
		tag = "내 최고 %s" % ScoreCalc.format(float(result.best_score))
	ci.draw_string(font, at + Vector2(tw + 110 * k, 74 * k), tag, HORIZONTAL_ALIGNMENT_LEFT, w - tw - 110 * k, int(20 * k), Color("ffb070") if helped else Color("8fe388"))
	var parts: Dictionary = result.get("parts", {})
	var y := at.y + 112 * k
	for row in SCORE_ROWS:
		var v := float(parts.get(row[0], 0))
		ci.draw_string(font, Vector2(at.x, y + 22 * k), row[1], HORIZONTAL_ALIGNMENT_LEFT, -1, int(21 * k), Color.WHITE)
		var bar := Rect2(Vector2(at.x + 150 * k, y + 6 * k), Vector2(w - 250 * k, 18 * k))
		if row[0] == "technique" and v < 0:
			ci.draw_string(font, Vector2(bar.position.x, y + 22 * k), "이 문제는 기술 점수가 없어요", HORIZONTAL_ALIGNMENT_LEFT, -1, int(18 * k), Color(1, 1, 1, 0.5))
		else:
			ci.draw_rect(bar, Color(1, 1, 1, 0.1))
			ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(float(v) / float(row[2]), 0.0, 1.0), bar.size.y)), CREAM)
			ci.draw_string(font, Vector2(bar.end.x + 12 * k, y + 22 * k), "%s / %d" % [ScoreCalc.format(v), row[2]], HORIZONTAL_ALIGNMENT_LEFT, -1, int(20 * k), Color(1, 1, 1, 0.85))
		y += 44 * k


## 시범 보기 중: 위에 안내 한 줄, 아래 [1배/2배] [처음부터/떨어진 곳부터] [그만 보기].
func _draw_demo_bar(ci: CanvasItem, size: Vector2, k: float) -> void:
	ci.draw_string_outline(font, Vector2(0, 110 * k), "시범 보기 — 정답 순서로 오르는 모습이에요", HORIZONTAL_ALIGNMENT_CENTER, size.x, int(26 * k), int(6 * k), Color(0.08, 0.06, 0.05, 0.9))
	ci.draw_string(font, Vector2(0, 110 * k), "시범 보기 — 정답 순서로 오르는 모습이에요", HORIZONTAL_ALIGNMENT_CENTER, size.x, int(26 * k), CREAM)
	var acts := [["2배속" if int(demo_bar.get("speed", 1)) == 1 else "1배속", "demo_speed"]]
	if demo_bar.get("can_from_fall", false):
		acts.append(["처음부터" if demo_bar.get("from_fall", false) else "떨어진 곳부터", "demo_from"])
	acts.append(["그만 보기", "demo_close"])
	var w := 220.0 * k * acts.size()
	_button_row(ci, Rect2(Vector2(size.x * 0.5 - w * 0.5, size.y - 92 * k), Vector2(w, 64 * k)), acts, k)


## 튜토리얼 완료 화면.
func _draw_done(ci: CanvasItem, size: Vector2, k: float) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6))
	ci.draw_string(font, Vector2(0, size.y * 0.42), "✓ 다 배웠어요", HORIZONTAL_ALIGNMENT_CENTER, size.x, int(44 * k), CREAM)
	# 튜토리얼 완료: [나가기] + [다음](다음 수업이 있을 때만, 2026-11-14 사용자)
	var acts := [["나가기", "list"]] if has_list else [["다시", "retry"]]
	var w := 400.0
	if not next_course.is_empty():
		acts.append(["다음 수업", "next_course"])
		w = 560.0
	if has_list:  # 수업 뒤 일반 문제 V0부터(작업 3 §3.7, [내 문제 만들기]는 작업 6 뒤)
		acts.append(["일반 문제 V0부터", "general_v0"])
		w += 240.0
	_button_row(ci, Rect2(Vector2(size.x * 0.5 - w * 0.5 * k, size.y * 0.5), Vector2(w, 64) * k), acts, k)


## 목표 홀드 반짝임의 밝기(0~1). 약 1.4Hz로 계속 출렁인다.
static func pulse(t: float) -> float:
	return 0.5 + 0.5 * sin(TAU * 1.4 * t)


## 안내 줄을 위에 둘지. 목표 홀드가 화면 위쪽 절반에 있으면 아래로 내려 그 홀드를 덮지 않는다.
static func band_on_top(goal_y: float, screen_h: float) -> bool:
	return goal_y < 0.0 or goal_y >= screen_h * 0.5


## 튜토리얼 안내 카드(2026-11-10 HUD 개선 기획 §7): 양발 패드 사이 아래 가운데의 작은 카드.
## [단계 n/N] 한 문장 [?](+첫 실행 [건너뛰기]). 캐릭터·다음 홀드를 가리지 않게 화면 아래에 둔다.
## 도움말 단계가 오르면 [?]를 강조만 하고(자동으로 펼치지 않음), 펼치면 게임이 멈춘다(play_test).
func _draw_tutorial(ci: CanvasItem, size: Vector2, k: float) -> void:
	if tutorial.done:
		return
	if _help_step != tutorial.index:
		_help_step = tutorial.index
		help_open = false
		_help_seen = 0
	var step := tutorial.current()
	var a := 0.35 if dim_band else 1.0
	var w := minf(size.x * 0.52, 860 * k)
	var h := 78.0 * k
	var card := Rect2(Vector2(size.x * 0.5 - w * 0.5, size.y - h - 12 * k), Vector2(w, h))
	ci.draw_rect(card, Color(0.06, 0.05, 0.04, 0.88 * a))
	ci.draw_rect(card, Color(CREAM, 0.8 * a), false, 2.0)
	var chip := Rect2(card.position + Vector2(12, 12) * k, Vector2(64, h - 24 * k))
	ci.draw_rect(chip, Color(CREAM, 0.18 * a))
	ci.draw_string(font, Vector2(chip.position.x, chip.get_center().y + 8 * k), "%d/%d" % [tutorial.index + 1, tutorial.steps.size()], HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, int(22 * k), Color(CREAM, a))
	var right := card.end.x - 10 * k
	var lvl := tutorial.help_level()
	var qr := Rect2(Vector2(right - 56 * k, card.get_center().y - 28 * k), Vector2(56, 56) * k)
	_button(ci, qr, "?!" if lvl >= 1 else "?", "help", k, lvl >= 1 or help_open, 26)
	right = qr.position.x - 8 * k
	if can_skip:
		var sr := Rect2(Vector2(right - 110 * k, qr.position.y), Vector2(110 * k, 56 * k))
		_button(ci, sr, "건너뛰기", "skip", k, false, 20)
		right = sr.position.x - 8 * k
	var tx := chip.end.x + 14 * k
	ci.draw_multiline_string(font, Vector2(tx, card.position.y + 34 * k), str(step.get("text_ko", "")), HORIZONTAL_ALIGNMENT_LEFT, right - tx - 6 * k, int(22 * k), 2, Color(1, 1, 1, a))
	if help_open:
		var hl := help_line()
		if hl != "":
			var hh := 50.0 * k
			var hb := Rect2(Vector2(card.position.x, card.position.y - hh - 8 * k), Vector2(card.size.x, hh))
			ci.draw_rect(hb, Color(CREAM, 0.96))
			ci.draw_string(font, Vector2(hb.position.x, hb.position.y + 34 * k), "도움말 · " + hl + "   (탭하면 닫혀요)", HORIZONTAL_ALIGNMENT_CENTER, hb.size.x, int(22 * k), INK)
			_buttons.append({"rect": hb, "action": "help"})


## 보여 줄 도움말: 단계(1 "움직일 팔다리", 2 "누를 버튼과 홀드")에 맞는 help_ko. 직접 열었는데 단계가 0이면 첫 줄.
func help_line() -> String:
	if tutorial == null:
		return ""
	var t := tutorial.help_text()
	if t != "":
		return t
	var h: Array = tutorial.current().get("help_ko", [])
	return str(h[0]) if help_open and not h.is_empty() else ""


func _button_row(ci: CanvasItem, area: Rect2, acts: Array, k: float) -> void:
	var gap := 16.0 * k
	var bw := minf(200.0 * k, (area.size.x - 40 * k - gap * (acts.size() - 1)) / acts.size())
	var total := bw * acts.size() + gap * (acts.size() - 1)
	var x := area.position.x + (area.size.x - total) * 0.5
	for a in acts:
		_button(ci, Rect2(Vector2(x, area.position.y), Vector2(bw, area.size.y)), a[0], a[1], k, a[1] in ["next", "next_course"])
		x += bw + gap


func _button(ci: CanvasItem, r: Rect2, text: String, action: String, k: float, strong := false, fs := 26) -> void:
	ci.draw_rect(r, CREAM if strong else Color(0.1, 0.1, 0.1, 0.75))
	ci.draw_rect(r, Color(1, 1, 1, 0.7), false, 2.0)
	var size := int(fs * k)
	ci.draw_string(font, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + size * 0.35), text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, size, INK if strong else Color.WHITE)
	_buttons.append({"rect": r, "action": action})


## 떨어진 뒤 조언 카드(화면 위쪽 가운데): 원인 한 줄 + 다음에 할 일 한 줄 + "눌러서 다시".
func _draw_fall_card(ci: CanvasItem, size: Vector2, k: float) -> void:
	var w := minf(900.0 * k, size.x - 40 * k)
	var tip := str(fall_card.get("tip", ""))
	var h := ((150.0 if str(fall_card.get("advice", "")) != "" else 110.0) + (36.0 if tip != "" else 0.0)) * k
	var panel := Rect2(Vector2((size.x - w) * 0.5, 110 * k), Vector2(w, h))  # 위쪽: 매트에 떨어진 캐릭터를 가리지 않게
	ci.draw_rect(panel, Color(0.12, 0.11, 0.1, 0.94))
	ci.draw_rect(panel, CREAM, false, 3.0)
	var x := panel.position.x + 28 * k
	var tw := w - 56 * k
	var y := panel.position.y + 44 * k
	ci.draw_string(font, Vector2(x, y), "! " + str(fall_card.cause), HORIZONTAL_ALIGNMENT_LEFT, tw, int(24 * k), Color("ff9a7a"))
	if str(fall_card.get("advice", "")) != "":
		y += 40 * k
		ci.draw_string(font, Vector2(x, y), "→ " + str(fall_card.advice), HORIZONTAL_ALIGNMENT_LEFT, tw, int(24 * k), Color.WHITE)
	if tip != "":
		y += 38 * k
		ci.draw_string(font, Vector2(x, y), "※ " + tip, HORIZONTAL_ALIGNMENT_LEFT, tw, int(21 * k), Color("f1d59a"))
	ci.draw_string(font, Vector2(x, panel.end.y - 18 * k), "화면을 누르면 처음부터 다시", HORIZONTAL_ALIGNMENT_RIGHT, tw, int(18 * k), Color(1, 1, 1, 0.6))
