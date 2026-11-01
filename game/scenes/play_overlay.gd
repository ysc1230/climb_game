extends RefCounted
## 플레이 화면 위 진행 UI(docs/28 §5·§6.1): 완등 결과, 튜토리얼 안내 줄·[도움말]·완료, 일시정지 [목록], [일시정지] 버튼.
## play_test가 _draw 끝에서 draw()를 부르고, 누른 위치를 tap()으로 넘겨 받은 동작 이름을 처리한다.
## 동작: "pause" "list" "retry" "next" "help" "skip". 색만으로 구분하지 않고 글자(✓, !)를 함께 쓴다(docs/05).

const CREAM := Color("f1d59a")
const INK := Color("302820")

var font: Font
## 비어 있지 않으면 결과 오버레이 {seconds, falls, no_fall, time, time_limit, next, saved}.
var result := {}
var tutorial: TutorialRunner
var tutorial_done := false
var help_open := false
var can_skip := false     # 기본 조작 첫 실행: [건너뛰기]
var has_list := false     # Game이 있을 때만 [목록]
var _help_step := -1
var _buttons: Array = []  # [{rect, action}] 마지막으로 그린 버튼


## 결과·완료 화면이 떠 있어 플레이를 멈추는가.
func blocking() -> bool:
	return not result.is_empty() or tutorial_done


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


func _draw_done(ci: CanvasItem, size: Vector2, k: float) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6))
	ci.draw_string(font, Vector2(0, size.y * 0.42), "✓ 다 배웠어요", HORIZONTAL_ALIGNMENT_CENTER, size.x, int(44 * k), CREAM)
	var acts := [["목록", "list"]] if has_list else [["다시", "retry"]]
	_button_row(ci, Rect2(Vector2(size.x * 0.5 - 200 * k, size.y * 0.5), Vector2(400, 64) * k), acts, k)


## 위 가운데(기술 버튼 아래) 안내 줄: 단계 문장 + [도움말](+[건너뛰기]). 도움말을 열면 그 아래에 한 줄.
func _draw_tutorial(ci: CanvasItem, size: Vector2, k: float) -> void:
	if tutorial.done:
		return
	if _help_step != tutorial.index:
		_help_step = tutorial.index
		help_open = false
	var step := tutorial.current()
	var band := Rect2(Vector2(size.x * 0.22, 148 * k), Vector2(size.x * 0.56, 84 * k))
	ci.draw_rect(band, Color(0.08, 0.07, 0.06, 0.8))
	var bw := 130.0 * k
	var right := band.end.x - 10 * k
	if can_skip:
		_button(ci, Rect2(Vector2(right - bw, band.position.y + 16 * k), Vector2(bw, 52 * k)), "건너뛰기", "skip", k, false, 20)
		right -= bw + 10 * k
	var lvl := tutorial.help_level()
	var help_label := "도움말 !" if lvl >= 1 else "도움말"  # 강조는 색과 "!" 함께
	_button(ci, Rect2(Vector2(right - bw, band.position.y + 16 * k), Vector2(bw, 52 * k)), help_label, "help", k, lvl >= 1, 20)
	right -= bw + 10 * k
	var text_w := right - band.position.x - 20 * k
	ci.draw_string(font, Vector2(band.position.x + 18 * k, band.position.y + 34 * k), "%d/%d" % [tutorial.index + 1, tutorial.steps.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, int(18 * k), Color(1, 1, 1, 0.6))
	ci.draw_multiline_string(font, Vector2(band.position.x + 70 * k, band.position.y + 34 * k), str(step.get("text_ko", "")), HORIZONTAL_ALIGNMENT_LEFT, text_w - 50 * k, int(22 * k), 2, Color.WHITE)
	if help_open or lvl >= 1:
		var h := help_line()
		if h != "":
			var hb := Rect2(Vector2(band.position.x, band.end.y + 6 * k), Vector2(band.size.x, 44 * k))
			ci.draw_rect(hb, Color(CREAM, 0.92))
			ci.draw_string(font, Vector2(hb.position.x, hb.position.y + 30 * k), "도움말 · " + h, HORIZONTAL_ALIGNMENT_CENTER, hb.size.x, int(20 * k), INK)


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
