extends RefCounted
## 떨어진 뒤 "다음에 할 일" 문장(docs/superpowers/specs/2026-11-19-1-feel-design.md §1.2).

var runner

const LIMBS := {&"LH": Vector2(-0.3, 1.8), &"RH": Vector2(0.3, 1.8), &"LF": Vector2(-0.2, 0.6), &"RF": Vector2(0.2, 0.6)}
const SLOTS := {"F_hi": Vector2(0.25, 0.95), "F_lo": Vector2(0.6, 0.55), "H_ur": Vector2(-0.05, 2.15), "H_l": Vector2(-0.75, 1.82)}


func test_advice_foot_up() -> void:
	var plan := {"moves": [{"limb": &"RF", "key": "F_hi"}], "pelvis": Vector2(0, 1.2)}
	runner.check(FallAdvice.text(plan, &"FATIGUE", LIMBS, Vector2(0, 1.2), SLOTS) == "오른발을 더 높은 발판에 먼저 올려 보세요", FallAdvice.text(plan, &"FATIGUE", LIMBS, Vector2(0, 1.2), SLOTS))
	var side := {"moves": [{"limb": &"RF", "key": "F_lo"}], "pelvis": Vector2(0, 1.2)}
	runner.check(FallAdvice.text(side, &"FATIGUE", LIMBS, Vector2(0, 1.2), SLOTS) == "오른발을 오른쪽 발판으로 먼저 옮겨 보세요", FallAdvice.text(side, &"FATIGUE", LIMBS, Vector2(0, 1.2), SLOTS))


func test_advice_hand_dir() -> void:
	var plan := {"moves": [{"limb": &"LH", "key": "H_ur"}], "pelvis": Vector2(0, 1.2)}
	runner.check(FallAdvice.text(plan, &"BALANCE", LIMBS, Vector2(0, 1.2), SLOTS) == "왼손을 오른쪽 위 홀드로 옮겨 보세요", FallAdvice.text(plan, &"BALANCE", LIMBS, Vector2(0, 1.2), SLOTS))
	var left := {"moves": [{"limb": &"LH", "key": "H_l"}], "pelvis": Vector2(0, 1.2)}
	runner.check(FallAdvice.text(left, &"BALANCE", LIMBS, Vector2(0, 1.2), SLOTS) == "왼손을 왼쪽 홀드로 옮겨 보세요", FallAdvice.text(left, &"BALANCE", LIMBS, Vector2(0, 1.2), SLOTS))
	var both := {"moves": [{"limb": &"LH", "key": "H_ur"}, {"limb": &"RF", "key": "F_hi"}], "pelvis": Vector2(0, 1.2)}
	runner.check(FallAdvice.text(both, &"BALANCE", LIMBS, Vector2(0, 1.2), SLOTS).begins_with("오른발을"), "발과 손이 같이 있으면 발 먼저")


func test_advice_body_only() -> void:
	var plan := {"moves": [], "pelvis": Vector2(-0.2, 1.2)}
	runner.check(FallAdvice.text(plan, &"BALANCE", LIMBS, Vector2(0, 1.2), SLOTS) == "몸을 왼쪽으로 옮겨 보세요", FallAdvice.text(plan, &"BALANCE", LIMBS, Vector2(0, 1.2), SLOTS))
	var up := {"moves": [], "pelvis": Vector2(0, 1.4)}
	runner.check(FallAdvice.text(up, &"BALANCE", LIMBS, Vector2(0, 1.2), SLOTS) == "몸을 위로 옮겨 보세요", FallAdvice.text(up, &"BALANCE", LIMBS, Vector2(0, 1.2), SLOTS))


func test_advice_fallbacks() -> void:
	runner.check(FallAdvice.text({}, &"FATIGUE", LIMBS, Vector2.ZERO, SLOTS) == "두 발이 몸 아래 있는 자리에서 쉬었다 가세요", "손 힘")
	runner.check(FallAdvice.text({}, &"NO_SUPPORT", LIMBS, Vector2.ZERO, SLOTS) == "손을 떼기 전에 발을 먼저 딛어 두세요", "지지 없음")
	runner.check(FallAdvice.text({}, &"BARN_DOOR", LIMBS, Vector2.ZERO, SLOTS) == "반대쪽 발을 벽에 대서 몸이 돌지 않게 해 보세요", "문 열림")
	runner.check(FallAdvice.text({}, &"BALANCE", LIMBS, Vector2.ZERO, SLOTS) == "천천히 한 손발씩 옮겨 보세요", "그 밖")
	var still := {"moves": [], "pelvis": Vector2(0.01, 1.2)}
	runner.check(FallAdvice.text(still, &"FATIGUE", LIMBS, Vector2(0, 1.2), SLOTS) == "두 발이 몸 아래 있는 자리에서 쉬었다 가세요", "계획이 거의 그대로면 기본 문장")
