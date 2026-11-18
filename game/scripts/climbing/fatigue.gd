class_name Fatigue
extends RefCounted
## docs/04 피로 분류표. 단위는 1초당 점수, 붙은 손 각각에 적용한다.

const FREE_HAND_RATE := 15.0
const STABLE_SPEED := 0.10
const WARNING_ENTER := 25.0
const WARNING_EXIT := 35.0
## 작은 홀드 배율(docs/41 §7, 2026-11-14): 손홀드 반폭이 SIZE_REF보다 작을수록 음수 변화율이 커진다.
const SIZE_REF := 0.08
const SIZE_MULT_MAX := 2.5


## 반폭 0.08 이상 ×1, 0.06 ×1.33, 0.05 ×1.6, 0.04 ×2, 0.032 이하 ×2.5. 0(모름)은 ×1.
static func size_multiplier(half_width: float) -> float:
	if half_width <= 0.0:
		return 1.0
	return clampf(SIZE_REF / half_width, 1.0, SIZE_MULT_MAX)


## docs/04 §7 붙은 손의 변화율(초당). 위에서부터 첫 조건을 적용한다.
## rebalancing: 회복 없음 -30, 배율 없음. rest_ok: SupportedStable·정지가 6틱 유지됨.
## foot_support: 실린 발 몫의 합 0~2(docs/48 R1, ClimbRules.foot_weight). 2 → −2, 1 → −3(손 둘)/−8(손 하나),
## 0 → −15/−30, 사이는 선형. 쉬어 회복(+10)은 몫 합 ≥ REST_FOOT_SUPPORT일 때만.
## 음수 변화율에는 max(1, 0.5+u) 배율(하중 큰 손이 더 빨리 지침)과 접점 품질 배율 1+0.5(1−q).
static func attached_hand_rate(rebalancing: bool, on_platform: bool, rest_ok: bool, foot_support: float, attached_hands: int, hand_u: float, hands_low_load: bool, quality: float = 1.0) -> float:
	if rebalancing:
		return -30.0
	if on_platform and rest_ok:
		return 15.0
	if foot_support >= Tuning.REST_FOOT_SUPPORT - 0.0001 and rest_ok and hands_low_load:
		return 10.0
	var one := -3.0 if attached_hands >= 2 else -8.0
	var none := -15.0 if attached_hands >= 2 else -30.0
	var fs := clampf(foot_support, 0.0, 2.0)
	var base := lerpf(none, one, fs) if fs < 1.0 else lerpf(one, -2.0, fs - 1.0)
	return base * maxf(1.0, 0.5 + hand_u) * (1.0 + 0.5 * (1.0 - quality))


## 보조 모드의 피로 끄기는 감소만 0으로 바꾼다.
static func apply(stamina: float, rate: float, dt: float, fatigue_disabled: bool = false) -> float:
	if fatigue_disabled and rate < 0.0:
		rate = 0.0
	return clampf(stamina + rate * dt, 0.0, 100.0)
