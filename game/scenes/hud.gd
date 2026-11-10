extends RefCounted
## 플레이 화면 위쪽 정보 패널(2026-11-08 사용자 참고 이미지): 일시정지 버튼, 문제 이름·목표 높이·진행 점,
## 현재 높이, 양손 팔 힘 게이지, 지지·손 하중·무브 상태 줄. 그리고 일시정지·이어하기 카운트다운 화면.
## play_test가 _draw에서 부른다(그리기만 하고 상태는 바꾸지 않는다). 색만으로 구분하지 않고 글자·숫자를 함께 쓴다(docs/05).

const PANEL := Color(0.17, 0.13, 0.10, 0.84)
const BORDER := Color(0.83, 0.70, 0.52, 0.55)
const CREAM := Color("fbeedd")
const GOLD := Color("f2c14e")
const MUTED := Color(0.98, 0.93, 0.86, 0.72)
const TRACK := Color(0.10, 0.08, 0.07, 0.92)
const GOOD := Color("7cc443")
const WARN := Color("f2c14e")
const BAD := Color("ff5a4a")
const DOT_OFF := Color(0.78, 0.76, 0.74)

var font: Font
var _boxes := {}


## 둥근 패널. radius·테두리는 k(화면 배율)에 맞춘다.
func panel(ci: CanvasItem, r: Rect2, k: float, fill := PANEL, border := BORDER, radius := 16.0) -> void:
	var key := "%s|%s|%d" % [fill, border, int(radius * k)]
	var sb: StyleBoxFlat = _boxes.get(key)
	if sb == null:
		sb = StyleBoxFlat.new()
		sb.bg_color = fill
		sb.border_color = border
		sb.set_border_width_all(maxi(1, int(2 * k)))
		sb.set_corner_radius_all(int(radius * k))
		sb.anti_aliasing = true
		_boxes[key] = sb
	sb.draw(ci.get_canvas_item(), r)


## 위쪽 정보 전체. info: {title, goal_height, height, best_height, stamina: {LH, RH}, phase, phase_name, phase_color,
## load_l, load_r, move, flag_ready, budget(0~1 또는 −1)}. 반환: 일시정지 버튼 사각형.
## 위쪽 한 줄(2026-11-10 사용자 HUD 개선 기획 §4): [일시정지][i 상세] 문제 이름 | 등반 진행 바(가운데 약 45%) | 현재/목표 높이.
## 진행 바에는 체크포인트가 없으므로 중간 점을 그리지 않는다(시작·끝 표시만). 반환 {pause, detail} 버튼 자리.
## info.detail이면 그 아래 상태 줄(지지·손 하중·무브)을 상시 그린다(상세 정보 모드, §6).
const TOP_H := 56.0


func draw_top(ci: CanvasItem, size: Vector2, k: float, info: Dictionary) -> Dictionary:
	var m := 12.0 * k
	var h := TOP_H * k
	var detail: bool = info.get("detail", false)
	var pause_r := Rect2(Vector2(m, m), Vector2(h, h))
	panel(ci, pause_r, k, PANEL, BORDER, 14)
	var bw := 8.0 * k
	var bh := 24.0 * k
	var c := pause_r.get_center()
	for dx in [-8.0 * k, 8.0 * k]:
		panel(ci, Rect2(c + Vector2(dx - bw * 0.5, -bh * 0.5), Vector2(bw, bh)), k, CREAM, Color(0, 0, 0, 0), 3)
	var det_r := Rect2(Vector2(pause_r.end.x + 8 * k, m), Vector2(h, h))
	if info.get("no_detail", false):  # 고급: 상세 정보(지지 상태 등) 버튼 없음
		det_r = Rect2(Vector2(pause_r.end.x, m), Vector2(0, h))
	else:
		panel(ci, det_r, k, Color(GOLD, 0.9) if detail else PANEL, BORDER, 14)
		ci.draw_string(font, Vector2(det_r.position.x, det_r.position.y + h * 0.5 + 9 * k), "i", HORIZONTAL_ALIGNMENT_CENTER, h, int(26 * k), Color("3a2a1c") if detail else CREAM)
	# 한 줄 반투명 띠(이름 ~ 높이)
	var strip := Rect2(Vector2(det_r.end.x + 8 * k, m), Vector2(size.x - m - det_r.end.x - 8 * k, h))
	panel(ci, strip, k, Color(PANEL, 0.72), Color(BORDER, 0.35), 14)
	var cy := strip.get_center().y
	# 오른쪽: 현재 / 목표 높이
	var ht := "%.1f / %.1f m" % [info.height, info.goal_height]
	var hfs := int(24 * k)
	var hw := font.get_string_size(ht, HORIZONTAL_ALIGNMENT_LEFT, -1, hfs).x
	var hx := strip.end.x - 18 * k - hw
	ci.draw_string_outline(font, Vector2(hx, cy + 8 * k), ht, HORIZONTAL_ALIGNMENT_LEFT, -1, hfs, int(5 * k), Color(0.08, 0.06, 0.05, 0.8))
	ci.draw_string(font, Vector2(hx, cy + 8 * k), ht, HORIZONTAL_ALIGNMENT_LEFT, -1, hfs, CREAM)
	_icon_mountains(ci, Vector2(hx - 24 * k, cy), 26 * k, GOLD)
	# 가운데: 진행 바(화면 너비의 약 45%)
	var pw := size.x * 0.45
	var pr := Rect2(Vector2(size.x * 0.5 - pw * 0.5, cy - 6 * k), Vector2(pw, 12 * k))
	pr.position.x = minf(pr.position.x, hx - 60 * k - pw)
	_progress(ci, pr, k, info.best_height / maxf(info.goal_height, 0.01), info.height / maxf(info.goal_height, 0.01))
	# 왼쪽: 문제 이름(남는 폭에 맞춰 자름)
	var tx := strip.position.x + 16 * k
	ci.draw_string(font, Vector2(tx, cy + 8 * k), str(info.title), HORIZONTAL_ALIGNMENT_LEFT, maxf(40 * k, pr.position.x - tx - 20 * k), int(21 * k), CREAM)
	if detail:
		_status_row(ci, size, k, info, strip.end.y + 8 * k)
	return {"pause": pause_r, "detail": det_r}


## 상세 정보 모드의 상태 줄(지지·손 하중·무브).
func _status_row(ci: CanvasItem, size: Vector2, k: float, info: Dictionary, y: float) -> void:
	var stw := minf(size.x * 0.56, 820 * k)
	var str_r := Rect2(Vector2((size.x - stw) * 0.5, y), Vector2(stw, 44 * k))
	panel(ci, str_r, k)
	var seg := stw / 3.0
	var cy := str_r.position.y + 22 * k
	var items := [
		["shield", "지지:", info.phase_name, info.phase_color],
		["load", "손 하중:", "L %d%%   R %d%%" % [info.load_l, info.load_r], CREAM],
		["shoe", "무브:", info.move, CREAM],
	]
	for i in items.size():
		var it: Array = items[i]
		var x0 := str_r.position.x + seg * i
		if i > 0:
			ci.draw_line(Vector2(x0, cy - 12 * k), Vector2(x0, cy + 12 * k), BORDER, maxf(1.0, 1.5 * k))
		var ic := Vector2(x0 + 26 * k, cy)
		match it[0]:
			"shield": _icon_shield(ci, ic, 18 * k, CREAM)
			"load": _icon_load(ci, ic, 18 * k, CREAM)
			"shoe": _icon_shoe(ci, ic, 20 * k, CREAM)
		var fs := int(18 * k)
		var lw := font.get_string_size(it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		ci.draw_string(font, Vector2(x0 + 46 * k, cy + 6 * k), it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, CREAM)
		ci.draw_string(font, Vector2(x0 + 54 * k + lw, cy + 6 * k), str(it[2]), HORIZONTAL_ALIGNMENT_LEFT, seg - 64 * k - lw, fs, it[3])


## 진행 바: 출발 → 깃발. 가장 높이 오른 곳까지 금색, 지금 높이에 흰 점. 체크포인트가 없으므로 중간 점은 그리지 않는다.
func _progress(ci: CanvasItem, r: Rect2, k: float, best: float, now: float) -> void:
	panel(ci, r, k, TRACK, Color(1, 1, 1, 0.18), 6)
	var b := clampf(best, 0.0, 1.0)
	if b > 0.0:
		panel(ci, Rect2(r.position, Vector2(maxf(r.size.y, r.size.x * b), r.size.y)), k, GOLD, Color(0, 0, 0, 0), 6)
	var y := r.get_center().y
	var p := Vector2(r.position.x + r.size.x * clampf(now, 0.0, 1.0), y)
	ci.draw_circle(p, 9 * k, Color("3a2a1c"))
	ci.draw_circle(p, 7 * k, Color.WHITE)
	var f := Vector2(r.end.x, y)
	ci.draw_line(f + Vector2(0, -2 * k), f + Vector2(0, -22 * k), CREAM, 2.5 * k)
	ci.draw_colored_polygon(PackedVector2Array([f + Vector2(0, -22 * k), f + Vector2(16 * k, -17 * k), f + Vector2(0, -12 * k)]), GOLD)


## 손 패드 바로 위 팔 힘 게이지(기획 §5). 입력은 받지 않는다. 좌우는 패드 테두리 색(side_col)으로 얇게 테두리.
## 정상: 바만 / 힘 부족(< 45): 숫자 + "!" / 위험(< 20): 빨강 + 굵은 테두리 / 회복 중: 위 화살표.
## plain(고급): 바만 그린다(숫자·"!"·빨간 테두리 경고 없음).
func draw_pad_stamina(ci: CanvasItem, pad_center: Vector2, pad_r: float, k: float, value: float, recovering: bool, side_col: Color, highlight := false, plain := false) -> void:
	var w := pad_r * 2.0
	var bh := 14.0 * k
	var r := Rect2(Vector2(pad_center.x - pad_r, pad_center.y - pad_r - 22 * k - bh), Vector2(w, bh))
	var low := value < 45.0 and not plain
	var danger := value < 20.0 and not plain
	panel(ci, r.grow(3 * k), k, Color(0.08, 0.06, 0.05, 0.75), Color(side_col, 0.9), 9)
	var f := clampf(value / 100.0, 0.0, 1.0)
	var col := GOOD if value >= 45.0 else (WARN if value >= 20.0 else BAD)
	if f > 0.0:
		panel(ci, Rect2(r.position, Vector2(maxf(4 * k, r.size.x * f), r.size.y)), k, col, Color(0, 0, 0, 0), 6)
	if danger or highlight:
		ci.draw_rect(r.grow(6 * k), Color(BAD, 0.9) if danger else Color(GOLD, 0.9), false, 2.5 * k)
	var ty := r.position.y - 8 * k
	if low:
		var t := "! %d" % roundi(value)
		ci.draw_string_outline(font, Vector2(r.position.x, ty), t, HORIZONTAL_ALIGNMENT_CENTER, w, int(20 * k), int(5 * k), Color(0.08, 0.06, 0.05, 0.9))
		ci.draw_string(font, Vector2(r.position.x, ty), t, HORIZONTAL_ALIGNMENT_CENTER, w, int(20 * k), col)
	if recovering and value < 99.5 and not plain:
		var a := Vector2(r.end.x + 14 * k, r.get_center().y)
		ci.draw_colored_polygon(PackedVector2Array([a + Vector2(0, -9 * k), a + Vector2(7 * k, 2 * k), a + Vector2(-7 * k, 2 * k)]), GOOD)
		ci.draw_rect(Rect2(a + Vector2(-2.5 * k, 2 * k), Vector2(5 * k, 6 * k)), GOOD)


# ---------- 일시정지·이어하기 ----------

## 일시정지 카드. prepare_left > 0이면 이어하기 카운트다운(3초). 반환: [{rect, action}] 버튼.
func draw_pause(ci: CanvasItem, size: Vector2, k: float, prepare_left: float, has_list: bool) -> Array:
	ci.draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.03, 0.02, 0.55))
	var buttons: Array = []
	var c := size * 0.5
	if prepare_left > 0.0:
		var r := 96.0 * k
		ci.draw_circle(c, r + 14 * k, Color(0.17, 0.13, 0.10, 0.88))
		ci.draw_arc(c, r, 0, TAU, 64, Color(1, 1, 1, 0.18), 10 * k, true)
		var frac := clampf(prepare_left / 3.0, 0.0, 1.0)
		ci.draw_arc(c, r, -PI / 2, -PI / 2 + TAU * frac, 64, GOLD, 10 * k, true)
		var num := str(ceili(prepare_left))
		var fs := int(84 * k)
		ci.draw_string(font, Vector2(c.x - r, c.y + fs * 0.35), num, HORIZONTAL_ALIGNMENT_CENTER, r * 2, fs, CREAM)
		var msg := "손가락을 패드에 편하게 올려 두세요"
		var mr := Rect2(Vector2(c.x - 300 * k, c.y + r + 34 * k), Vector2(600 * k, 56 * k))
		panel(ci, mr, k)
		ci.draw_string(font, Vector2(mr.position.x, mr.get_center().y + 8 * k), msg, HORIZONTAL_ALIGNMENT_CENTER, mr.size.x, int(22 * k), CREAM)
		return buttons
	var card := Rect2(c - Vector2(320, 170) * k, Vector2(640, 340) * k)
	panel(ci, card, k, Color(0.17, 0.13, 0.10, 0.94), BORDER, 24)
	# 일시정지 기호
	var ic := Vector2(c.x, card.position.y + 64 * k)
	ci.draw_circle(ic, 34 * k, Color(GOLD, 0.18))
	for dx in [-9.0 * k, 9.0 * k]:
		panel(ci, Rect2(ic + Vector2(dx - 5 * k, -15 * k), Vector2(10, 30) * k), k, GOLD, Color(0, 0, 0, 0), 3)
	ci.draw_string(font, Vector2(card.position.x, card.position.y + 142 * k), "잠깐 쉬는 중", HORIZONTAL_ALIGNMENT_CENTER, card.size.x, int(38 * k), CREAM)
	ci.draw_string(font, Vector2(card.position.x, card.position.y + 184 * k), "화면을 탭하면 3초 뒤 이어서 시작해요", HORIZONTAL_ALIGNMENT_CENTER, card.size.x, int(22 * k), MUTED)
	var bh := 64.0 * k
	var by := card.end.y - bh - 30 * k
	var acts := [["이어하기", "resume", true]]
	if has_list:
		acts.append(["목록으로", "list", false])
	var bw := 240.0 * k
	var gap := 20.0 * k
	var total := bw * acts.size() + gap * (acts.size() - 1)
	var x := c.x - total * 0.5
	for a in acts:
		var r := Rect2(Vector2(x, by), Vector2(bw, bh))
		var strong: bool = a[2]
		panel(ci, r, k, GOLD if strong else Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.0) if strong else BORDER, 32)
		var tc := Color("3a2a1c") if strong else CREAM
		if strong:
			var tri := r.position + Vector2(r.size.x * 0.5 - 62 * k, r.size.y * 0.5)
			ci.draw_colored_polygon(PackedVector2Array([tri + Vector2(-7, -11) * k, tri + Vector2(-7, 11) * k, tri + Vector2(11, 0) * k]), tc)
		ci.draw_string(font, Vector2(r.position.x + (14 * k if strong else 0.0), r.get_center().y + 9 * k), a[0], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(26 * k), tc)
		buttons.append({"rect": r, "action": a[1]})
		x += bw + gap
	return buttons


# ---------- 아이콘(단순 도형) ----------

func _icon_mountains(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-1.0, 0.6) * s, c + Vector2(-0.25, -0.55) * s, c + Vector2(0.45, 0.6) * s]), col)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.05, 0.6) * s, c + Vector2(0.45, -0.15) * s, c + Vector2(1.0, 0.6) * s]), Color(col, 0.75))
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.42, -0.29) * s, c + Vector2(-0.25, -0.55) * s, c + Vector2(-0.08, -0.29) * s, c + Vector2(-0.25, -0.2) * s]), Color.WHITE)


func _icon_flag_peak(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	_icon_mountains(ci, c + Vector2(0, 0.25) * s, s * 0.9, col)
	ci.draw_line(c + Vector2(-0.22, -0.3) * s, c + Vector2(-0.22, -1.0) * s, col, maxf(1.5, s * 0.08))
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.22, -1.0) * s, c + Vector2(0.3, -0.85) * s, c + Vector2(-0.22, -0.7) * s]), col)


func _icon_hand(ci: CanvasItem, c: Vector2, s: float, col: Color, mirror: bool) -> void:
	var w := maxf(2.0, s * 0.2)
	var mx := -1.0 if mirror else 1.0
	ci.draw_circle(c + Vector2(0, 0.25) * s, s * 0.42, col)
	for i in 4:
		var fx := (-0.33 + 0.22 * i) * mx
		var top := -0.55 - (0.15 if i == 1 or i == 2 else 0.0)
		ci.draw_line(c + Vector2(fx, 0.1) * s, c + Vector2(fx, top) * s, col, w, true)
		ci.draw_circle(c + Vector2(fx, top) * s, w * 0.5, col)
	ci.draw_line(c + Vector2(0.38 * mx, 0.3) * s, c + Vector2(0.62 * mx, -0.05) * s, col, w, true)


func _icon_shield(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -0.7) * s, c + Vector2(0.55, -0.45) * s, c + Vector2(0.5, 0.15) * s, c + Vector2(0, 0.7) * s, c + Vector2(-0.5, 0.15) * s, c + Vector2(-0.55, -0.45) * s])
	ci.draw_colored_polygon(pts, col)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -0.5) * s, c + Vector2(0.38, -0.32) * s, c + Vector2(0.34, 0.1) * s, c + Vector2(0, 0.5) * s]), Color(0, 0, 0, 0.25))


func _icon_load(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	ci.draw_arc(c + Vector2(0, -0.45) * s, s * 0.2, PI, TAU, 12, col, maxf(1.5, s * 0.1))
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.45, -0.3) * s, c + Vector2(0.45, -0.3) * s, c + Vector2(0.6, 0.65) * s, c + Vector2(-0.6, 0.65) * s]), col)
	ci.draw_string(font, c + Vector2(-0.4 * s, 0.45 * s), "kg", HORIZONTAL_ALIGNMENT_CENTER, 0.8 * s, int(s * 0.55), Color("3a2a1c"))


func _icon_shoe(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.75, -0.5) * s, c + Vector2(-0.3, -0.5) * s, c + Vector2(-0.15, -0.05) * s, c + Vector2(0.55, 0.12) * s, c + Vector2(0.8, 0.4) * s, c + Vector2(0.75, 0.55) * s, c + Vector2(-0.8, 0.55) * s]), col)
	ci.draw_line(c + Vector2(-0.8, 0.38) * s, c + Vector2(0.78, 0.38) * s, Color(0, 0, 0, 0.3), maxf(1.0, s * 0.08))
