class_name SlowMotion
extends RefCounted
## 초급 슬로우모션(2026-11-08 사용자 요청: "지지(균형)가 떨어지기 직전을 슬로우모션, 초급만").
## 판정 틱(60Hz) 자체를 덜 돌려 시간을 늦춘다. 판정 수치·예산(틱 단위)은 그대로라 결과는 같고 생각할 시간만 늘어난다.
## 떨어지기 직전 = 지지 상태가 "균형 회복 중"(REBALANCING) 또는 "지지 없음"(GRACE)에 들어간 순간.
## 이 상태에서 떨어지기까지 남은 게임 시간은 최대 0.3초(18틱)라, 들어가는 순간이 예측할 수 있는 가장 이른 때다.
## SCALE 0.1: 실제 3초 = 게임 0.3초(균형 예산 18틱 전부, 2026-11-08 사용자: "0.3초를 3초로").
## 지지를 되찾거나 떨어지면 바로 정상 속도로 돌아온다.

const SCALE := 0.1       # 슬로우모션 중 게임 속도
const DURATION := 3.0    # 실제 초. 한 번 켜지면 최대 이만큼
const RAMP := 0.06       # 실제 초. 들어갈 때·나올 때 속도를 부드럽게 바꾸는 시간
const COOLDOWN := 1.0    # 실제 초. 끝난 뒤 이만큼은 다시 켜지지 않는다(연달아 느려져 답답하지 않게)

var enabled := false
var scale := 1.0         # 지금 게임 속도(1 = 정상)
var left := 0.0          # 남은 슬로우모션(실제 초)
var cooldown := 0.0
var _acc := 0.0
var _was_danger := false


func reset() -> void:
	scale = 1.0
	left = 0.0
	cooldown = 0.0
	_acc = 0.0
	_was_danger = false


func active() -> bool:
	return left > 0.0


## 실제 시간 real_dt가 지난 뒤 이번에 돌릴 판정 틱 수(0 또는 1, 정상이면 1).
## danger: 지금 떨어지기 직전 상태인가. ended: 떨어졌거나(추락 연출) 장면이 바뀌어 슬로우모션을 끝낼 때.
func update(danger: bool, ended: bool, real_dt: float) -> int:
	cooldown = maxf(0.0, cooldown - real_dt)
	if not enabled:
		reset()
		return 1
	if left > 0.0:
		left = maxf(0.0, left - real_dt)
		if ended or not danger or left <= 0.0:
			left = 0.0
			cooldown = COOLDOWN
	elif danger and not _was_danger and not ended and cooldown <= 0.0:
		left = DURATION
	_was_danger = danger
	var want := SCALE if left > 0.0 else 1.0
	scale = move_toward(scale, want, (1.0 - SCALE) * real_dt / RAMP)
	if scale >= 1.0:
		_acc = 0.0
		return 1
	_acc += scale
	if _acc >= 1.0:
		_acc -= 1.0
		return 1
	return 0
