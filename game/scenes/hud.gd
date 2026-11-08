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
func draw_top(ci: CanvasItem, size: Vector2, k: float, info: Dictionary) -> Rect2:
	var m := 14.0 * k
	var pause_r := Rect2(Vector2(m, m), Vector2(84, 84) * k)
	panel(ci, pause_r, k, PANEL, BORDER, 20)
	var bw := 11.0 * k
	var bh := 34.0 * k
	var c := pause_r.get_center()
	for dx in [-11.0 * k, 11.0 * k]:
		panel(ci, Rect2(c + Vector2(dx - bw * 0.5, -bh * 0.5), Vector2(bw, bh)), k, CREAM, Color(0, 0, 0, 0), 4)
	# 현재 높이(오른쪽 위)
	var hw := 250.0 * k
	var hr := Rect2(Vector2(size.x - m - hw, m), Vector2(hw, 84 * k))
	panel(ci, hr, k)
	_icon_mountains(ci, hr.position + Vector2(40, 42) * k, 30 * k, GOLD)
	ci.draw_string(font, hr.position + Vector2(78 * k, 32 * k), "현재 높이", HORIZONTAL_ALIGNMENT_LEFT, -1, int(19 * k), MUTED)
	ci.draw_string(font, hr.position + Vector2(78 * k, 72 * k), "%.1f m" % info.height, HORIZONTAL_ALIGNMENT_LEFT, -1, int(36 * k), CREAM)
	# 문제 이름·목표 높이·진행 점(가운데)
	var sx := pause_r.end.x + m
	var sr := Rect2(Vector2(sx, m), Vector2(hr.position.x - m - sx, 84 * k))
	panel(ci, sr, k)
	_icon_flag_peak(ci, sr.position + Vector2(34, 30) * k, 26 * k, GOLD)
	var title: String = info.title
	ci.draw_string(font, sr.position + Vector2(62 * k, 38 * k), title, HORIZONTAL_ALIGNMENT_LEFT, sr.size.x * 0.55, int(25 * k), CREAM)
	var goal_txt := "%.1f m" % info.goal_height
	var gx := sr.end.x - 24 * k - font.get_string_size(goal_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(23 * k)).x
	ci.draw_string(font, Vector2(gx, sr.position.y + 38 * k), goal_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(23 * k), CREAM)
	var lbl_w := font.get_string_size("목표 높이", HORIZONTAL_ALIGNMENT_LEFT, -1, int(19 * k)).x
	ci.draw_string(font, Vector2(gx - lbl_w - 10 * k, sr.position.y + 37 * k), "목표 높이", HORIZONTAL_ALIGNMENT_LEFT, -1, int(19 * k), GOLD)
	ci.draw_line(Vector2(gx - lbl_w - 24 * k, sr.position.y + 18 * k), Vector2(gx - lbl_w - 24 * k, sr.position.y + 44 * k), BORDER, maxf(1.0, 1.5 * k))
	_progress(ci, Rect2(sr.position + Vector2(40, 58) * k, Vector2(sr.size.x - 80 * k, 16 * k)), k, info.best_height / maxf(info.goal_height, 0.01), info.height / maxf(info.goal_height, 0.01))
	# 팔 힘(두 번째 줄)
	var row2 := m + 84 * k + 10 * k
	var aw := (size.x - 2 * m - 12 * k) * 0.5
	aw = minf(aw, 560 * k)
	for hand in [&"LH", &"RH"]:
		var x := m if hand == &"LH" else size.x - m - aw
		_stamina(ci, Rect2(Vector2(x, row2), Vector2(aw, 56 * k)), k, "왼손 팔 힘" if hand == &"LH" else "오른손 팔 힘", float(info.stamina[hand]), hand == &"RH")
	# 상태 줄(세 번째 줄, 가운데)
	var row3 := row2 + 56 * k + 10 * k
	var stw := minf(size.x - 2 * m, 860 * k)
	var str_r := Rect2(Vector2((size.x - stw) * 0.5, row3), Vector2(stw, 48 * k))
	panel(ci, str_r, k)
	var seg := stw / 3.0
	var cy := str_r.position.y + 24 * k
	var items := [
		["shield", "지지:", info.phase_name, info.phase_color],
		["load", "손 하중:", "L %d%%   R %d%%" % [info.load_l, info.load_r], CREAM],
		["shoe", "무브:", info.move, CREAM],
	]
	for i in items.size():
		var it: Array = items[i]
		var x0 := str_r.position.x + seg * i
		if i > 0:
			ci.draw_line(Vector2(x0, cy - 13 * k), Vector2(x0, cy + 13 * k), BORDER, maxf(1.0, 1.5 * k))
		var ic := Vector2(x0 + 30 * k, cy)
		match it[0]:
			"shield": _icon_shield(ci, ic, 20 * k, CREAM)
			"load": _icon_load(ci, ic, 20 * k, CREAM)
			"shoe": _icon_shoe(ci, ic, 22 * k, CREAM)
		var fs := int(19 * k)
		var lw := font.get_string_size(it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		ci.draw_string(font, Vector2(x0 + 52 * k, cy + 7 * k), it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, CREAM)
		ci.draw_string(font, Vector2(x0 + 60 * k + lw, cy + 7 * k), str(it[2]), HORIZONTAL_ALIGNMENT_LEFT, seg - 70 * k - lw, fs, it[3])
	if float(info.budget) >= 0.0:
		var bwid := stw * 0.3
		var br := Rect2(Vector2(str_r.position.x + 16 * k, str_r.end.y - 7 * k), Vector2(bwid, 4 * k))
		ci.draw_rect(br, TRACK)
		ci.draw_rect(Rect2(br.position, Vector2(bwid * float(info.budget), br.size.y)), info.phase_color)
	return pause_r


## 진행 점: 출발 → 중간 다섯 → 깃발. best까지 지난 점은 체크, 지금 위치 다음 점은 강조.
func _progress(ci: CanvasItem, r: Rect2, k: float, best: float, now: float) -> void:
	var n := 7
	var y := r.get_center().y
	var x0 := r.position.x
	var step := r.size.x / (n - 1)
	ci.draw_line(Vector2(x0, y), Vector2(r.end.x, y), DOT_OFF, 5 * k)
	ci.draw_line(Vector2(x0, y), Vector2(x0 + r.size.x * clampf(best, 0.0, 1.0), y), GOLD, 5 * k)
	var cur := clampi(int(floor(clampf(now, 0.0, 1.0) * (n - 1) + 0.0001)), 0, n - 1)
	for i in n:
		var p := Vector2(x0 + step * i, y)
		var passed := best >= float(i) / (n - 1) - 0.0001 and i > 0
		if i == n - 1:
			ci.draw_circle(p, 9 * k, GOLD if best >= 1.0 else DOT_OFF)
			ci.draw_circle(p, 6 * k, Color.WHITE)
			ci.draw_line(p + Vector2(0, -6 * k), p + Vector2(0, -26 * k), CREAM, 2.5 * k)
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -26 * k), p + Vector2(18 * k, -21 * k), p + Vector2(0, -15 * k)]), GOLD)
		elif passed:
			ci.draw_circle(p, 12 * k, GOLD)
			ci.draw_polyline(PackedVector2Array([p + Vector2(-5, 0) * k, p + Vector2(-1, 4) * k, p + Vector2(6, -4) * k]), Color("3a2a1c"), 2.5 * k)
		elif i == cur + 1 or (i == 0 and best <= 0.0):
			ci.draw_circle(p, 12 * k, GOLD)
			ci.draw_circle(p, 8 * k, Color.WHITE)
		else:
			ci.draw_circle(p, 9 * k, DOT_OFF)


func _stamina(ci: CanvasItem, r: Rect2, k: float, label: String, value: float, right: bool) -> void:
	panel(ci, r, k)
	var cy := r.get_center().y
	_icon_hand(ci, Vector2(r.position.x + 32 * k, cy), 24 * k, CREAM, right)
	var fs := int(20 * k)
	ci.draw_string(font, Vector2(r.position.x + 58 * k, cy + 7 * k), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, CREAM)
	var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var bx := r.position.x + 74 * k + lw
	var bar := Rect2(Vector2(bx, cy - 13 * k), Vector2(r.end.x - 16 * k - bx, 26 * k))
	panel(ci, bar, k, TRACK, Color(1, 1, 1, 0.25), 8)
	var f := clampf(value / 100.0, 0.0, 1.0)
	if f > 0.0:
		var col := GOOD if value >= 50.0 else (WARN if value >= 25.0 else BAD)
		var fill := Rect2(bar.position + Vector2(2, 2) * k, Vector2((bar.size.x - 4 * k) * f, bar.size.y - 4 * k))
		panel(ci, fill, k, col, Color(0, 0, 0, 0), 6)
		ci.draw_rect(Rect2(fill.position + Vector2(3 * k, 2 * k), Vector2(maxf(0.0, fill.size.x - 6 * k), fill.size.y * 0.3)), Color(1, 1, 1, 0.22))
	var t := "%d / 100%s" % [roundi(value), "  !" if value < 25.0 else ""]
	ci.draw_string_outline(font, Vector2(bar.position.x, cy + 7 * k), t, HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, int(20 * k), int(6 * k), Color(0.1, 0.07, 0.05, 0.85))
	ci.draw_string(font, Vector2(bar.position.x, cy + 7 * k), t, HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, int(20 * k), Color.WHITE)


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
