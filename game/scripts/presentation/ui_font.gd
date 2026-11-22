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
