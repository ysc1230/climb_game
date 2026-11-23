extends RefCounted
## 플레이 화면 위 진행 UI(docs/28 §5·§6.1): 완등 결과, 튜토리얼 안내 줄·[도움말]·완료, 일시정지 [목록], [일시정지] 버튼.
## play_test가 _draw 끝에서 draw()를 부르고, 누른 위치를 tap()으로 넘겨 받은 동작 이름을 처리한다.
## 동작: "pause" "list" "retry" "next" "help" "skip". 색만으로 구분하지 않고 글자(✓, !)를 함께 쓴다(docs/05).

const CREAM := Color("f1d59a")
const INK := Color("0d1620")   # 노란 버튼 위 글자(홈 NIGHT, 2026-11-24 홈과 같은 UI)
const NIGHT := Color("0d1620")
const CHALK := Color("f6f2ea")
const SHOE := Color("ffc93c")
const LINE := Color(0.965, 0.95, 0.92, 0.24)

var font: Font
var font_b: Font   # 굵게(제목·점수·버튼)
var _sb := {}


## 홈과 같은 둥근 판(남색 반투명 + 가는 분필색 선).
func _box(ci: CanvasItem, r: Rect2, k: float, fill := Color(0.051, 0.086, 0.125, 0.96), border := LINE, radius := 26.0) -> void:
	var key := "%s|%s|%d" % [fill, border, int(radius * k)]
	var sb: StyleBoxFlat = _sb.get(key)
	if sb == null:
		sb = StyleBoxFlat.new()
		sb.bg_color = fill
		sb.border_color = border
		sb.set_border_width_all(maxi(1, int(1.5 * k)) if border.a > 0.0 else 0)
		sb.set_corner_radius_all(int(radius * k))
		sb.anti_aliasing = true
		_sb[key] = sb
	sb.draw(ci.get_canvas_item(), r)
## 비어 있지 않으면 결과 오버레이 {seconds, falls, no_fall, time, time_limit, next, saved}.
var result := {}
var result_ms := 0
## 떨어진 뒤 조언 카드 {cause, advice}. 화면 어디를 눌러도 다시 시작.
var fall_card := {}  # 결과 카드가 뜬 시각(아래에서 0.25초 동안 올라옴)
var fall_left := 0.0  # 조언 카드가 저절로 다시 시작하기까지 남은 초
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
	var ph := minf(600.0 * k, size.y - 30 * k)
	var panel := Rect2(Vector2(size.x * 0.5 - pw * 0.5, size.y * 0.5 - ph * 0.5 + rise * size.y * 0.6), Vector2(pw, ph))
	_box(ci, panel, k, Color(NIGHT, 0.97), LINE, 30)
	var x := panel.position.x
	var y := panel.position.y
	var lw := pw * 0.55
	ci.draw_string(font_b, Vector2(x + 36 * k, y + 62 * k), "완등!", HORIZONTAL_ALIGNMENT_LEFT, -1, int(48 * k), SHOE)
	if result.has("score"):
		_draw_score(ci, Vector2(x + 36 * k, y + 80 * k), lw - 60 * k, k)
	var rx := x + lw + 10 * k
	var rw := pw - lw - 46 * k
	var ty := y + 58 * k
	ci.draw_string(font_b, Vector2(rx, ty), "시간 %s" % format_seconds(result.seconds), HORIZONTAL_ALIGNMENT_LEFT, -1, int(32 * k), CHALK)
	if bool(result.get("new_best_time", false)) and not bool(result.get("helped", false)):
		ci.draw_string(font_b, Vector2(rx, ty), "새 최고 시간", HORIZONTAL_ALIGNMENT_RIGHT, rw, int(24 * k), Color("8fe388"))
	elif float(result.get("best_seconds", -1.0)) > 0.0:
		ci.draw_string(font, Vector2(rx, ty + 36 * k), "내 최고 %s" % format_seconds(float(result.best_seconds)), HORIZONTAL_ALIGNMENT_LEFT, -1, int(23 * k), Color(1, 1, 1, 0.72))
	ty += 74 * k
	var limit: float = result.get("time_limit", 0.0)
	var chips := [["완등", true], ["플래시", bool(result.get("flash", false))], ["무추락", bool(result.no_fall)],
		["시간(%s 안)" % format_seconds(limit) if limit > 0.0 else "시간(기준 없음)", bool(result.time)]]
	for c in chips:
		var got: bool = c[1]
		var r := Rect2(Vector2(rx, ty), Vector2(rw, 52 * k))
		_box(ci, r, k, SHOE if got else Color(1, 1, 1, 0.05), Color(0, 0, 0, 0) if got else LINE, 26)
		ci.draw_string(font_b if got else font, Vector2(r.position.x + 18 * k, r.position.y + 35 * k), ("✓ " if got else "– ") + str(c[0]), HORIZONTAL_ALIGNMENT_LEFT, rw - 24 * k, int(25 * k), NIGHT if got else Color(1, 1, 1, 0.55))
		ty += 62 * k
	if bool(result.get("flash", false)):
		ci.draw_string(font_b, Vector2(rx, ty + 18 * k), "처음 시도에 한 번에 올랐어요!", HORIZONTAL_ALIGNMENT_LEFT, rw, int(22 * k), CREAM)
	if not result.get("saved", true):
		ci.draw_string(font_b, Vector2(x, panel.end.y - 100 * k), "기록을 저장하지 못했어요", HORIZONTAL_ALIGNMENT_CENTER, pw, int(23 * k), Color("ff8a6a"))
	var acts := []
	if str(result.get("next", "")) != "":
		acts.append(["다음", "next"])
	acts.append(["다시", "retry"])
	if has_list:
		acts.append(["목록", "list"])
	_button_row(ci, Rect2(Vector2(x + pw * 0.15, panel.end.y - 90 * k), Vector2(pw * 0.7, 68 * k)), acts, k)


const SCORE_ROWS := [["energy", "힘 아끼기", 30], ["stable", "안정", 25], ["precise", "정확한 손발", 20], ["technique", "기술", 15], ["finish", "마무리", 10]]


## 총점(크게) / 100 + 도움·새 최고 + 다섯 항목 막대.
func _draw_score(ci: CanvasItem, at: Vector2, w: float, k: float) -> void:
	var helped := bool(result.get("helped", false))
	var total := ScoreCalc.format(float(result.score))
	ci.draw_string(font_b, at + Vector2(0, 80 * k), total, HORIZONTAL_ALIGNMENT_LEFT, -1, int(88 * k), CHALK)
	var tw := font_b.get_string_size(total, HORIZONTAL_ALIGNMENT_LEFT, -1, int(88 * k)).x
	ci.draw_string(font, at + Vector2(tw + 10 * k, 80 * k), "/ 100", HORIZONTAL_ALIGNMENT_LEFT, -1, int(30 * k), Color(1, 1, 1, 0.6))
	var tag := ""
	if helped:
		tag = "도움 — 최고 기록에 들어가지 않아요"
	elif bool(result.get("new_best_score", false)):
		tag = "새 최고 점수"
	elif float(result.get("best_score", -1)) >= 0.0:
		tag = "내 최고 %s" % ScoreCalc.format(float(result.best_score))
	ci.draw_string(font_b, at + Vector2(tw + 120 * k, 80 * k), tag, HORIZONTAL_ALIGNMENT_LEFT, w - tw - 120 * k, int(23 * k), Color("ffb070") if helped else Color("8fe388"))
	var parts: Dictionary = result.get("parts", {})
	var y := at.y + 118 * k
	for row in SCORE_ROWS:
		var v := float(parts.get(row[0], 0))
		ci.draw_string(font_b, Vector2(at.x, y + 24 * k), row[1], HORIZONTAL_ALIGNMENT_LEFT, -1, int(24 * k), CHALK)
		var bar := Rect2(Vector2(at.x + 170 * k, y + 7 * k), Vector2(w - 280 * k, 20 * k))
		if row[0] == "technique" and v < 0:
			ci.draw_string(font, Vector2(bar.position.x, y + 24 * k), "이 문제는 기술 점수가 없어요", HORIZONTAL_ALIGNMENT_LEFT, -1, int(21 * k), Color(1, 1, 1, 0.55))
		else:
			_box(ci, bar, k, Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 10)
			if v > 0:
				_box(ci, Rect2(bar.position, Vector2(maxf(bar.size.y, bar.size.x * clampf(float(v) / float(row[2]), 0.0, 1.0)), bar.size.y)), k, SHOE, Color(0, 0, 0, 0), 10)
			ci.draw_string(font_b, Vector2(bar.end.x + 14 * k, y + 24 * k), "%s / %d" % [ScoreCalc.format(v), row[2]], HORIZONTAL_ALIGNMENT_LEFT, -1, int(23 * k), Color(1, 1, 1, 0.88))
		y += 48 * k


## 시범 보기 중: 위에 안내 한 줄, 아래 [1배/2배] [처음부터/떨어진 곳부터] [그만 보기].
func _draw_demo_bar(ci: CanvasItem, size: Vector2, k: float) -> void:
	var dt := "시범 보기 · 정답 순서로 오르는 모습이에요"
	var dw := font_b.get_string_size(dt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(28 * k)).x + 56 * k
	_box(ci, Rect2(Vector2(size.x * 0.5 - dw * 0.5, 90 * k), Vector2(dw, 56 * k)), k, Color(NIGHT, 0.82), LINE, 28)
	ci.draw_string(font_b, Vector2(0, 128 * k), dt, HORIZONTAL_ALIGNMENT_CENTER, size.x, int(28 * k), CHALK)
	var acts := [["2배속" if int(demo_bar.get("speed", 1)) == 1 else "1배속", "demo_speed"]]
	if demo_bar.get("can_from_fall", false):
		acts.append(["처음부터" if demo_bar.get("from_fall", false) else "떨어진 곳부터", "demo_from"])
	acts.append(["그만 보기", "demo_close"])
	var w := 220.0 * k * acts.size()
	_button_row(ci, Rect2(Vector2(size.x * 0.5 - w * 0.5, size.y - 96 * k), Vector2(w, 68 * k)), acts, k)


## 튜토리얼 완료 화면.
func _draw_done(ci: CanvasItem, size: Vector2, k: float) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6))
	ci.draw_string(font_b, Vector2(0, size.y * 0.42), "✓ 다 배웠어요", HORIZONTAL_ALIGNMENT_CENTER, size.x, int(52 * k), SHOE)
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
	var h := 94.0 * k
	var card := Rect2(Vector2(size.x * 0.5 - w * 0.5, size.y - h - 12 * k), Vector2(w, h))
	_box(ci, card, k, Color(NIGHT, 0.9 * a), Color(LINE, LINE.a * a), 24)
	var chip := Rect2(card.position + Vector2(14, 14) * k, Vector2(72, h - 28 * k))
	_box(ci, chip, k, Color(SHOE, 0.9 * a), Color(0, 0, 0, 0), 16)
	ci.draw_string(font_b, Vector2(chip.position.x, chip.get_center().y + 9 * k), "%d/%d" % [tutorial.index + 1, tutorial.steps.size()], HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, int(25 * k), Color(NIGHT, a))
	var right := card.end.x - 10 * k
	var lvl := tutorial.help_level()
	var qr := Rect2(Vector2(right - 64 * k, card.get_center().y - 32 * k), Vector2(64, 64) * k)
	_button(ci, qr, "?!" if lvl >= 1 else "?", "help", k, lvl >= 1 or help_open, 26)
	right = qr.position.x - 8 * k
	if can_skip:
		var sr := Rect2(Vector2(right - 130 * k, qr.position.y), Vector2(130 * k, 64 * k))
		_button(ci, sr, "건너뛰기", "skip", k, false, 23)
		right = sr.position.x - 8 * k
	var tx := chip.end.x + 14 * k
	ci.draw_multiline_string(font_b, Vector2(tx, card.position.y + 40 * k), str(step.get("text_ko", "")), HORIZONTAL_ALIGNMENT_LEFT, right - tx - 6 * k, int(26 * k), 2, Color(CHALK, a))
	if help_open:
		var hl := help_line()
		if hl != "":
			var hh := 60.0 * k
			var hb := Rect2(Vector2(card.position.x, card.position.y - hh - 10 * k), Vector2(card.size.x, hh))
			_box(ci, hb, k, Color(SHOE, 0.97), Color(0, 0, 0, 0), 24)
			ci.draw_string(font_b, Vector2(hb.position.x, hb.position.y + 40 * k), "도움말 · " + hl + "   (탭하면 닫혀요)", HORIZONTAL_ALIGNMENT_CENTER, hb.size.x, int(25 * k), INK)
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
	var bw := minf(230.0 * k, (area.size.x - 40 * k - gap * (acts.size() - 1)) / acts.size())
	var total := bw * acts.size() + gap * (acts.size() - 1)
	var x := area.position.x + (area.size.x - total) * 0.5
	for a in acts:
		_button(ci, Rect2(Vector2(x, area.position.y), Vector2(bw, area.size.y)), a[0], a[1], k, a[1] in ["next", "next_course"])
		x += bw + gap


## 버튼(홈과 같음): 주 = 노란 알약 + 남색 굵은 글자, 보조 = 반투명 남색 알약 + 가는 선 + 흰 글자.
func _button(ci: CanvasItem, r: Rect2, text: String, action: String, k: float, strong := false, fs := 29) -> void:
	_box(ci, r, k, SHOE if strong else Color(NIGHT, 0.72), Color(0, 0, 0, 0) if strong else Color(CHALK, 0.3), minf(r.size.y * 0.5 / k, 36.0))
	var size := int(fs * k)
	ci.draw_string(font_b, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + size * 0.36), text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, size, INK if strong else CHALK)
	_buttons.append({"rect": r, "action": action})


## 떨어진 뒤 조언 카드(화면 위쪽 가운데): 원인 한 줄 + 다음에 할 일 한 줄 + "눌러서 다시".
func _draw_fall_card(ci: CanvasItem, size: Vector2, k: float) -> void:
	var w := minf(1000.0 * k, size.x - 40 * k)
	var tip := str(fall_card.get("tip", ""))
	var h := ((176.0 if str(fall_card.get("advice", "")) != "" else 128.0) + (44.0 if tip != "" else 0.0)) * k
	var panel := Rect2(Vector2((size.x - w) * 0.5, 104 * k), Vector2(w, h))  # 위쪽: 매트에 떨어진 캐릭터를 가리지 않게
	_box(ci, panel, k, Color(NIGHT, 0.95), LINE, 26)
	var x := panel.position.x + 32 * k
	var tw := w - 64 * k
	var y := panel.position.y + 52 * k
	ci.draw_string(font_b, Vector2(x, y), "! " + str(fall_card.cause), HORIZONTAL_ALIGNMENT_LEFT, tw, int(29 * k), Color("ff9a7a"))
	if str(fall_card.get("advice", "")) != "":
		y += 48 * k
		ci.draw_string(font_b, Vector2(x, y), "→ " + str(fall_card.advice), HORIZONTAL_ALIGNMENT_LEFT, tw, int(28 * k), CHALK)
	if tip != "":
		y += 44 * k
		ci.draw_string(font, Vector2(x, y), "※ " + tip, HORIZONTAL_ALIGNMENT_LEFT, tw, int(25 * k), CREAM)
	ci.draw_string(font, Vector2(x, panel.end.y - 20 * k), "%d초 뒤 처음부터 다시 · 누르면 바로" % ceili(maxf(fall_left, 0.0)), HORIZONTAL_ALIGNMENT_RIGHT, tw, int(21 * k), Color(1, 1, 1, 0.65))
