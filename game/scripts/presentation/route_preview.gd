class_name RoutePreview
extends RefCounted
## 루트 읽기(docs/superpowers/specs/2026-11-19-1-feel-design.md §1.6, 2026-11-19 사용자: "탑 홀드가 보이는 화면에서 시작하는
## 부분까지 1초에서 2초 사이로 천천히 아래로 내려주며 루트를 보여주면 좋겠어"). 카메라 높이만 정한다(표현 전용).

const HOLD_TOP := 0.3   # 처음 탑에 머무는 시간(초, 전체 길이에 포함)

var t := 0.0
var top_y := 0.0
var start_y := 0.0
var dur := 1.0


func _init(p_top_y: float, p_start_y: float) -> void:
	top_y = p_top_y
	start_y = p_start_y
	dur = duration(absf(p_top_y - p_start_y))


## 전체 길이 = clamp(거리 / 1.5m × 1초, 1초, 2초).
static func duration(distance_m: float) -> float:
	return clampf(distance_m / 1.5, 1.0, 2.0)


static func cam_y(time: float, p_top: float, p_start: float, p_dur: float) -> float:
	if time < HOLD_TOP:
		return p_top
	if time >= p_dur:
		return p_start
	return lerpf(p_top, p_start, smoothstep(0.0, 1.0, (time - HOLD_TOP) / (p_dur - HOLD_TOP)))


func advance(dt: float, paused: bool) -> void:
	if not paused:
		t = minf(t + dt, dur)


func skip() -> void:
	t = dur


func done() -> bool:
	return t >= dur


func y() -> float:
	return cam_y(t, top_y, start_y, dur)
