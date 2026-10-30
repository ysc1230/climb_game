class_name Fatigue
extends RefCounted
## docs/04 피로 분류표. 단위는 1초당 점수, 붙은 손 각각에 적용한다.

const FREE_HAND_RATE := 15.0
const STABLE_SPEED := 0.10
const WARNING_ENTER := 25.0
const WARNING_EXIT := 35.0


## 붙은 손의 변화율. 위에서부터 첫 조건을 적용한다.
static func attached_hand_rate(on_platform_stable: bool, loaded_feet: int, attached_hands: int, body_speed: float) -> float:
	if on_platform_stable:
		return 15.0
	if loaded_feet >= 2:
		return 10.0 if body_speed <= STABLE_SPEED else -2.0
	if loaded_feet == 1:
		return -3.0 if attached_hands >= 2 else -8.0
	return -15.0 if attached_hands >= 2 else -30.0


## 보조 모드의 피로 끄기는 감소만 0으로 바꾼다.
static func apply(stamina: float, rate: float, dt: float, fatigue_disabled: bool = false) -> float:
	if fatigue_disabled and rate < 0.0:
		rate = 0.0
	return clampf(stamina + rate * dt, 0.0, 100.0)
