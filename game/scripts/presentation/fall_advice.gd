class_name FallAdvice
extends RefCounted
## 떨어진 뒤 조언의 둘째 줄 "다음에 할 일"(docs/superpowers/specs/2026-11-19-1-feel-design.md §1.2).
## plan은 AutoRescue.plan() 형식({moves: [{limb, key}], pelvis} 또는 {}). 계획이 없거나 거의 그대로면 원인별 기본 문장.

const LIMB_KO := {&"LH": "왼손", &"RH": "오른손", &"LF": "왼발", &"RF": "오른발"}
const DIRS := ["오른쪽", "오른쪽 위", "위", "왼쪽 위", "왼쪽", "왼쪽 아래", "아래", "오른쪽 아래"]
const BODY_MIN := 0.05   # 몸통 옮김으로 볼 최소 거리(m)
const HIGHER := 0.03     # 더 높은 발판으로 볼 높이 차(m)


static func text(plan: Dictionary, cause_kind: StringName, limb_pos: Dictionary, body_pos: Vector2, slot_pos: Dictionary) -> String:
	var moves: Array = plan.get("moves", [])
	var foot := {}
	var hand := {}
	for m in moves:
		if not slot_pos.has(m.key) or not limb_pos.has(m.limb):
			continue
		if PoseSolver.is_hand(m.limb):
			hand = m
		else:
			foot = m
	if not foot.is_empty():
		var name: String = LIMB_KO[foot.limb]
		var from: Vector2 = limb_pos[foot.limb]
		var to: Vector2 = slot_pos[foot.key]
		if to.y > from.y + HIGHER:
			return "%s%s 더 높은 발판에 먼저 올려 보세요" % [name, Progress.object_particle(name)]
		return "%s%s %s 발판으로 먼저 옮겨 보세요" % [name, Progress.object_particle(name), direction(to - from)]
	if not hand.is_empty():
		var name: String = LIMB_KO[hand.limb]
		return "%s%s %s 홀드로 옮겨 보세요" % [name, Progress.object_particle(name), direction((slot_pos[hand.key] as Vector2) - (limb_pos[hand.limb] as Vector2))]
	if plan.has("pelvis") and (plan.pelvis as Vector2).distance_to(body_pos) >= BODY_MIN:
		var d := direction((plan.pelvis as Vector2) - body_pos)
		return "몸을 %s%s 옮겨 보세요" % [d, _ro(d)]
	match cause_kind:
		&"FATIGUE":
			return "두 발이 몸 아래 있는 자리에서 쉬었다 가세요"
		&"NO_SUPPORT":
			return "손을 떼기 전에 발을 먼저 딛어 두세요"
		&"BARN_DOOR":
			return "반대쪽 발을 벽에 대서 몸이 돌지 않게 해 보세요"
	return "천천히 한 손발씩 옮겨 보세요"


## 8방향 말(벽 좌표: y 위가 +).
static func direction(d: Vector2) -> String:
	var a := fposmod(rad_to_deg(atan2(d.y, d.x)) + 22.5, 360.0)
	return DIRS[int(a / 45.0) % 8]


## 으로/로: 받침 없거나 ㄹ 받침이면 "로".
static func _ro(word: String) -> String:
	var c := word.unicode_at(word.length() - 1)
	if c < 0xAC00 or c > 0xD7A3:
		return "로"
	var jong := (c - 0xAC00) % 28
	return "로" if jong == 0 or jong == 8 else "으로"
