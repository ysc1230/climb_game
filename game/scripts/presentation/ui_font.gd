class_name UiFont
extends RefCounted
## 화면 글꼴(2026-11-22 사용자: 홈이 "밤티스러워 → 깔끔하지만 세련되고 가독성 좋게").
## 기기 글꼴은 기종·사용자 설정마다 달라(삼성은 손글씨체일 수도) 넣은 글꼴을 쓴다: SUIT 가변 글꼴(OFL, art/fonts/SUIT-OFL.txt).
## 한글은 KS X 1001 2350자라 그 밖의 글자(사용자가 지은 이름 등)는 기기 글꼴로 그린다.

const FILE := preload("res://art/fonts/SUIT-Variable.ttf")
static var _cache := {}


## 굵기(100~900)별 글꼴. 같은 굵기는 한 번만 만든다.
static func get_font(weight: int) -> Font:
	if _cache.has(weight):
		return _cache[weight]
	var base: FontFile = FILE
	if base.fallbacks.is_empty():
		var sys := SystemFont.new()
		sys.font_names = PackedStringArray(["Noto Sans CJK KR", "Noto Sans KR", "Apple SD Gothic Neo", "sans-serif"])
		base.fallbacks = [sys]
	var f := FontVariation.new()
	f.base_font = base
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	_cache[weight] = f
	return f


## 글 입력칸(LineEdit)을 홈 버튼과 같은 모양으로: 반투명 남색 알약·가는 분필색 테두리·굵기 600 글자, 쓰는 중이면 노란 테두리
## (2026-11-25 사용자 "홈 화면과 유사한 UI로"). k: 화면 배율, fs: 배율 전 글자 크기, h: 칸 높이(px, 알약 둥글기).
static func style_line_edit(e: LineEdit, k: float, fs: int, h: float) -> void:
	var night := Color("0d1620")
	var chalk := Color("f6f2ea")
	var shoe := Color("ffc93c")
	for st in [["normal", Color(chalk, 0.26), 1.5], ["focus", shoe, 2.5], ["read_only", Color(chalk, 0.12), 1.5]]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(night, 0.8)
		sb.set_corner_radius_all(int(h * 0.5))
		sb.border_color = st[1]
		sb.set_border_width_all(maxi(1, roundi(float(st[2]) * k)))
		sb.content_margin_left = 20 * k
		sb.content_margin_right = 20 * k
		sb.anti_aliasing = true
		e.add_theme_stylebox_override(st[0], sb)
	e.add_theme_font_override("font", get_font(600))
	e.add_theme_font_size_override("font_size", int(fs * k))
	e.add_theme_color_override("font_color", chalk)
	e.add_theme_color_override("font_placeholder_color", Color(chalk, 0.45))
	e.add_theme_color_override("caret_color", shoe)
	e.add_theme_color_override("selection_color", Color(shoe, 0.35))
