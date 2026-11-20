class_name HoldArea
extends RefCounted
## 홀드 영역 투영과 접촉 품질 (docs/27 §8, docs/04 §10.2). 순수 정적 함수.

const HAND_INTERVAL_HALF := 0.04
const FOOT_FLAT_V := -0.2
const FOOT_MIN_QUALITY := 0.5


## 손 영역(중심 pos, 방향 dir, 반폭)의 선분에 점을 투영한다. q = 1 - t^2.
static func project_hand(slot: Dictionary, point: Vector2) -> Dictionary:
	var area: Dictionary = slot.hand_area
	var hw: float = area.half_width
	var s := clampf((point - slot.pos).dot(area.dir), -hw, hw)
	var t := absf(s) / hw
	return {"point": slot.pos + area.dir * s, "t": t, "quality": 1.0 - t * t}


## 발 디딤 면(중심 pos, up 방향, 반높이)에 점을 투영한다. v >= -0.2면 q = 1, v = -1에서 0.5.
static func project_foot(slot: Dictionary, point: Vector2) -> Dictionary:
	var area: Dictionary = slot.foot_area
	var hh: float = area.half_height
	var s := clampf((point - slot.pos).dot(area.up), -hh, hh)
	var v := s / hh
	var q := 1.0
	if v < FOOT_FLAT_V:
		q = 1.0 - (1.0 - FOOT_MIN_QUALITY) * (FOOT_FLAT_V - v) / (FOOT_FLAT_V + 1.0)
	return {"point": slot.pos + area.up * s, "v": v, "quality": q}


## 슬로퍼 몸 창(작업 4 §4.1): 몸(골반) x가 홀드 중심에서 좌우 window[0] 안이면 1, window[1] 밖이면 window[2], 사이는 선형.
## 접점 품질에 곱한다(품질은 피로·최대 하중·반각에 들어감). 창이 없으면 1.
static func window_factor(window: Array, hold_x: float, x: float) -> float:
	if window.size() < 3 or not is_finite(x):
		return 1.0
	var d := absf(x - hold_x)
	var t := clampf((d - float(window[0])) / (float(window[1]) - float(window[0])), 0.0, 1.0)
	return lerpf(1.0, float(window[2]), t)


## 손 접촉 구간(선분 좌표, 중심 기준 부호 있는 거리 s 주변 +-0.04).
static func hand_interval(slot: Dictionary, point: Vector2) -> Vector2:
	var area: Dictionary = slot.hand_area
	var hw: float = area.half_width
	var s := clampf((point - slot.pos).dot(area.dir), -hw, hw)
	return Vector2(s - HAND_INTERVAL_HALF, s + HAND_INTERVAL_HALF)
