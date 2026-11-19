class_name GripWarning
extends RefCounted
## 손 힘 경고 단계(docs/superpowers/specs/2026-11-19-1-feel-design.md §1.3, 2026-11-19 사용자: "40%, 20% 게이지일 때 깜빡이게").
## 표현 전용. 들어감과 나감 사이 5점 여유로 경계에서 깜빡거리지 않는다.

enum { NONE, CAUTION, DANGER }

const CAUTION_ENTER := 40.0
const CAUTION_EXIT := 45.0
const DANGER_ENTER := 20.0
const DANGER_EXIT := 25.0


## 지금 손 힘과 직전 단계로 이번 단계.
static func level(stamina: float, prev: int) -> int:
	if stamina < DANGER_ENTER or (prev == DANGER and stamina < DANGER_EXIT):
		return DANGER
	if stamina < CAUTION_ENTER or (prev >= CAUTION and stamina < CAUTION_EXIT):
		return CAUTION
	return NONE


## 게이지 깜빡임(초당 횟수).
static func blink_hz(lv: int) -> float:
	return [0.0, 2.0, 4.0][lv]


## 캐릭터 손 떨림 (진폭 m, 주파수 Hz).
static func tremble(lv: int) -> Vector2:
	return [Vector2.ZERO, Vector2(0.003, 8.0), Vector2(0.006, 12.0)][lv]
