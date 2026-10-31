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


## 손 접촉 구간(선분 좌표, 중심 기준 부호 있는 거리 s 주변 +-0.04).
static func hand_interval(slot: Dictionary, point: Vector2) -> Vector2:
	var area: Dictionary = slot.hand_area
	var hw: float = area.half_width
	var s := clampf((point - slot.pos).dot(area.dir), -hw, hw)
	return Vector2(s - HAND_INTERVAL_HALF, s + HAND_INTERVAL_HALF)
