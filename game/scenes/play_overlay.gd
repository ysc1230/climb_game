extends RefCounted
## 플레이 화면 위 진행 UI(docs/28 §5·§6.1): 완등 결과, 튜토리얼 안내 줄·[도움말]·완료, 일시정지 [목록], [일시정지] 버튼.
## play_test가 _draw 끝에서 draw()를 부르고, 누른 위치를 tap()으로 넘겨 받은 동작 이름을 처리한다.
## 동작: "pause" "list" "retry" "next" "help" "skip". 색만으로 구분하지 않고 글자(✓, !)를 함께 쓴다(docs/05).

const CREAM := Color("f1d59a")
const INK := Color("302820")

var font: Font
## 비어 있지 않으면 결과 오버레이 {seconds, falls, no_fall, time, time_limit, next, saved}.
var result := {}
## 비어 있지 않으면 튜토리얼 시작 설명 카드 {title, purpose, when, how}. 탭하면 사라진다(그동안 플레이 멈춤).
var briefing := {}
var tutorial: TutorialRunner
var tutorial_done := false
var help_open := false
var can_skip := false     # 기본 조작 첫 실행: [건너뛰기]
var has_list := false     # Game이 있을 때만 [목록]
## 튜토리얼 목표 홀드의 화면 Y(없으면 −1). 안내 줄이 그 홀드를 덮지 않게 위·아래를 고른다.
var goal_screen_y := -1.0
var _help_step := -1
var _help_seen := 0       # 이 단계에서 이미 자동으로 열어 준 도움말 단계
var _buttons: Array = []  # [{rect, action}] 마지막으로 그린 버튼


## 결과·완료 화면이 떠 있어 플레이를 멈추는가.
func blocking() -> bool:
	return not result.is_empty() or tutorial_done or not briefing.is_empty()


## 마지막으로 그린 버튼 중 pos를 덮는 것의 동작. 없으면 "".
func tap(pos: Vector2) -> String:
	for i in range(_buttons.size() - 1, -1, -1):
		if (_buttons[i].rect as Rect2).has_point(pos):
			return _buttons[i].action
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
	if tutorial_done:
		_draw_done(ci, size, k)
		return
	if not briefing.is_empty() and not paused:
		_draw_briefing(ci, size, k)
		return
	if paused:
		if has_list:
			_button(ci, Rect2(Vector2(size.x * 0.5 - 110 * k, size.y * 0.5 + 50 * k), Vector2(220, 64) * k), "목록", "list", k)
		return
	_button(ci, Rect2(Vector2(16, 16) * k, Vector2(130, 46) * k), "일시정지", "pause", k, false, 20)
	if tutorial != null and not selecting:
		_draw_tutorial(ci, size, k)


func _draw_result(ci: CanvasItem, size: Vector2, k: float) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6))
	var panel := Rect2(Vector2(size.x * 0.5 - 330 * k, size.y * 0.5 - 220 * k), Vector2(660, 440) * k)
	ci.draw_rect(panel, Color(0.12, 0.11, 0.1, 0.95))
	ci.draw_rect(panel, CREAM, false, 3.0)
	var x := panel.position.x
	var w := panel.size.x
	var y := panel.position.y
	ci.draw_string(font, Vector2(x, y + 70 * k), "완등!", HORIZONTAL_ALIGNMENT_CENTER, w, int(46 * k), CREAM)
	ci.draw_string(font, Vector2(x, y + 130 * k), "시간 %s · 추락 %d번" % [format_seconds(result.seconds), result.falls], HORIZONTAL_ALIGNMENT_CENTER, w, int(26 * k), Color.WHITE)
	var limit: float = result.get("time_limit", 0.0)
	var time_label := "시간 메달(%s 안)" % format_seconds(limit) if limit > 0.0 else "시간 메달(기준 없음)"
	var medals := [["완등", true], ["무추락", result.no_fall], [time_label, result.time]]
	for i in medals.size():
		var got: bool = medals[i][1]
		var mark := "✓ 받음" if got else "– 못 받음"
		ci.draw_string(font, Vector2(x + 120 * k, y + (185 + i * 40) * k), medals[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, int(24 * k), Color.WHITE)
		ci.draw_string(font, Vector2(x, y + (185 + i * 40) * k), mark, HORIZONTAL_ALIGNMENT_RIGHT, w - 120 * k, int(24 * k), CREAM if got else Color(1, 1, 1, 0.6))
	if not result.get("saved", true):
		ci.draw_string(font, Vector2(x, y + 320 * k), "기록을 저장하지 못했어요", HORIZONTAL_ALIGNMENT_CENTER, w, int(20 * k), Color("ff8a6a"))
	var acts := []
	if str(result.get("next", "")) != "":
		acts.append(["다음", "next"])
	acts.append(["다시", "retry"])
	if has_list:
		acts.append(["목록", "list"])
	_button_row(ci, Rect2(Vector2(x, y + 350 * k), Vector2(w, 64 * k)), acts, k)


## 시작 설명 카드: 화면 가운데 큰 카드. 아무 데나 탭하면 닫힌다(전체 화면이 "brief" 버튼).
func _draw_briefing(ci: CanvasItem, size: Vector2, k: float) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
	var w := minf(size.x * 0.62, 1100.0 * k)
	var panel := Rect2(Vector2(size.x * 0.5 - w * 0.5, size.y * 0.5 - 250 * k), Vector2(w, 500 * k))
	ci.draw_rect(panel, Color(0.07, 0.06, 0.05, 0.97))
	ci.draw_rect(panel, CREAM, false, 3.0)
	var x := panel.position.x + 40 * k
	var tw := panel.size.x - 80 * k
	var y := panel.position.y + 72 * k
	ci.draw_string(font, Vector2(panel.position.x, y), str(briefing.get("title", "")), HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, int(44 * k), CREAM)
	y += 64 * k
	ci.draw_multiline_string(font, Vector2(x, y), str(briefing.get("purpose", "")), HORIZONTAL_ALIGNMENT_CENTER, tw, int(30 * k), 2, Color.WHITE)
	y += 90 * k
	for key in ["how", "when"]:
		var t := str(briefing.get(key, ""))
		if t != "":
			ci.draw_multiline_string(font, Vector2(x, y), t, HORIZONTAL_ALIGNMENT_LEFT, tw, int(24 * k), 3, Color(1, 1, 1, 0.85))
			y += 100 * k
	ci.draw_string(font, Vector2(panel.position.x, panel.end.y - 28 * k), "화면을 탭하면 시작해요", HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, int(26 * k), CREAM)
	_buttons.append({"rect": Rect2(Vector2.ZERO, size), "action": "brief"})


func _draw_done(ci: CanvasItem, size: Vector2, k: float) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6))
	ci.draw_string(font, Vector2(0, size.y * 0.42), "✓ 다 배웠어요", HORIZONTAL_ALIGNMENT_CENTER, size.x, int(44 * k), CREAM)
	var acts := [["목록", "list"]] if has_list else [["다시", "retry"]]
	_button_row(ci, Rect2(Vector2(size.x * 0.5 - 200 * k, size.y * 0.5), Vector2(400, 64) * k), acts, k)


## 목표 홀드 반짝임의 밝기(0~1). 약 1.4Hz로 계속 출렁인다.
static func pulse(t: float) -> float:
	return 0.5 + 0.5 * sin(TAU * 1.4 * t)


## 안내 줄을 위에 둘지. 목표 홀드가 화면 위쪽 절반에 있으면 아래로 내려 그 홀드를 덮지 않는다.
static func band_on_top(goal_y: float, screen_h: float) -> bool:
	return goal_y < 0.0 or goal_y >= screen_h * 0.5


## 안내 줄(위 가운데 또는 아래 가운데): 단계 문장 + [도움말](+[건너뛰기]). 도움말 줄은 안내 줄의 화면 안쪽에 붙인다.
## 읽기 쉽게 진한 바탕·밝은 테두리·큰 글자(28)를 쓴다.
func _draw_tutorial(ci: CanvasItem, size: Vector2, k: float) -> void:
	if tutorial.done:
		return
	if _help_step != tutorial.index:
		_help_step = tutorial.index
		help_open = false
		_help_seen = 0
	var step := tutorial.current()
	var band_h := 104.0 * k
	var top := band_on_top(goal_screen_y, size.y)
	var band_y := 148.0 * k if top else size.y - band_h - 44.0 * k
	var band := Rect2(Vector2(size.x * 0.20, band_y), Vector2(size.x * 0.60, band_h))
	ci.draw_rect(band, Color(0.06, 0.05, 0.04, 0.94))
	ci.draw_rect(band, Color(CREAM, 0.9), false, 2.0)
	var bw := 130.0 * k
	var by := band.position.y + (band_h - 56 * k) * 0.5
	var right := band.end.x - 12 * k
	if can_skip:
		_button(ci, Rect2(Vector2(right - bw, by), Vector2(bw, 56 * k)), "건너뛰기", "skip", k, false, 22)
		right -= bw + 10 * k
	var lvl := tutorial.help_level()
	if lvl > _help_seen:  # 도움말 단계가 오르면 한 번 열어 준다. 닫을 수 있고, 강조는 남는다.
		_help_seen = lvl
		help_open = true
	var help_label := "도움말 !" if lvl >= 1 else "도움말"  # 강조는 색과 "!" 함께
	_button(ci, Rect2(Vector2(right - bw, by), Vector2(bw, 56 * k)), help_label, "help", k, lvl >= 1, 22)
	right -= bw + 10 * k
	var fs := int(28 * k)
	var text_x := band.position.x + 78 * k
	ci.draw_string(font, Vector2(band.position.x + 16 * k, band.position.y + 40 * k), "%d/%d" % [tutorial.index + 1, tutorial.steps.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, int(22 * k), CREAM)
	ci.draw_multiline_string(font, Vector2(text_x, band.position.y + 40 * k), str(step.get("text_ko", "")), HORIZONTAL_ALIGNMENT_LEFT, right - text_x - 10 * k, fs, 2, Color.WHITE)
	if help_open:
		var h := help_line()
		if h != "":
			var hh := 50.0 * k
			var hy := band.end.y + 6 * k if top else band.position.y - hh - 6 * k
			var hb := Rect2(Vector2(band.position.x, hy), Vector2(band.size.x, hh))
			ci.draw_rect(hb, Color(CREAM, 0.96))
			ci.draw_string(font, Vector2(hb.position.x, hb.position.y + 34 * k), "도움말 · " + h, HORIZONTAL_ALIGNMENT_CENTER, hb.size.x, int(24 * k), INK)


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
		_button(ci, Rect2(Vector2(x, area.position.y), Vector2(bw, area.size.y)), a[0], a[1], k, a[1] == "next")
		x += bw + gap


func _button(ci: CanvasItem, r: Rect2, text: String, action: String, k: float, strong := false, fs := 26) -> void:
	ci.draw_rect(r, CREAM if strong else Color(0.1, 0.1, 0.1, 0.75))
	ci.draw_rect(r, Color(1, 1, 1, 0.7), false, 2.0)
	var size := int(fs * k)
	ci.draw_string(font, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + size * 0.35), text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, size, INK if strong else Color.WHITE)
	_buttons.append({"rect": r, "action": action})
