class_name RoutePreview
extends RefCounted
## 루트 읽기(docs/superpowers/specs/2026-11-19-1-feel-design.md §1.6, 2026-11-19 사용자: "탑 홀드가 보이는 화면에서 시작하는
## 부분까지 1초에서 2초 사이로 천천히 아래로 내려주며 루트를 보여주면 좋겠어"). 카메라 높이만 정한다(표현 전용).
## 2026-11-24 사용자: "각 난이도를 시작할 때 가장 높은 탑 부분부터 천천히 화면을 내려오며 캐릭터가 있는 곳까지 내려와서
## 어떤 문제들이 있는지 알려주자. 캐릭터가 위치하는 곳에 카메라가 위치하면 1초 정도 있다가 시작하자"
## → 처음 들어갈 때(full): 탑에 HOLD_TOP, 초당 SPEED로 내려오고(PAN_MIN~PAN_MAX), 캐릭터에서 HOLD_END 멈춘 뒤 끝.
##   다시 하기: 예전처럼 짧게(탑 0.3초 + 1~2초 안, 끝 멈춤 없음).

const HOLD_TOP := 0.8
const SPEED := 0.8
const PAN_MIN := 1.2
const PAN_MAX := 4.0
const HOLD_END := 1.0
const TITLE_FADE := 0.3   # 문제 안내가 시작 직전에 사라지는 시간(초)

var t := 0.0
var top_y := 0.0
var start_y := 0.0
var hold_top := HOLD_TOP
var pan := 0.0
var hold_end := HOLD_END
var dur := 0.0


func _init(p_top_y: float, p_start_y: float, full := true) -> void:
	top_y = p_top_y
	start_y = p_start_y
	var dist := absf(p_top_y - p_start_y)
	if full:
		pan = clampf(dist / SPEED, PAN_MIN, PAN_MAX) if dist > 0.05 else 0.0
	else:
		hold_top = 0.3
		hold_end = 0.0
		pan = clampf(dist / 1.5, 0.7, 1.7)
	dur = hold_top + pan + hold_end


func advance(dt: float, paused: bool) -> void:
	if not paused:
		t = minf(t + dt, dur)


func skip() -> void:
	t = dur


func done() -> bool:
	return t >= dur


func y() -> float:
	if t < hold_top or pan <= 0.0:
		return top_y if t < hold_top + pan else start_y
	if t >= hold_top + pan:
		return start_y
	return lerpf(top_y, start_y, smoothstep(0.0, 1.0, (t - hold_top) / pan))


## 문제 안내(이름·등급·벽 각도) 보이기: 처음부터 보이고 끝나기 TITLE_FADE 전부터 사라진다. 다시 하기는 없음.
func title_alpha() -> float:
	if hold_end <= 0.0 or done():
		return 0.0
	return clampf((dur - t) / TITLE_FADE, 0.0, 1.0)
