class_name GradeInfo
extends RefCounted
## 등급 이름·설명 카드(docs/superpowers/specs/2026-11-19-3-score-design.md §3.6). 문구는 작업 5에서 실제 문제를 만든 뒤 맞춰 고친다.

const TEXTS := {
	"V0": "입문. 손발을 하나씩 옮길 줄 알면 돼요. 필요한 기술: 없음",
	"V1": "입문. 발을 먼저 올리면 손이 쉬워져요",
	"V2": "쉬움. 몸을 옮겨 손이 닿게 해 봐요. 쉬는 자리를 찾아요",
	"V3": "쉬움. 하이스텝을 써야 닿는 곳이 있어요",
	"V4": "보통. 기술 하나가 꼭 필요한 곳이 있어요(매치·하이스텝)",
	"V5": "보통. 작은 홀드에서 오래 버티지 말고 쉬는 자리를 이어 가요",
	"V6": "어려움. 기술 두 개를 이어 써야 해요",
	"V7": "어려움. 옆이나 아래를 향한 홀드를 몸으로 버텨요",
	"V8": "어려움. 쉴 곳이 거의 없어요. 힘 아끼기가 전부예요",
}


static func _n(grade: String) -> int:
	return grade.substr(1).to_int()


static func name_of(grade: String) -> String:
	var n := _n(grade)
	if n <= 1:
		return "입문"
	if n <= 3:
		return "쉬움"
	if n <= 5:
		return "보통"
	if n <= 8:
		return "어려움"
	return "극한"


static func label(grade: String) -> String:
	return "%s · %s" % [grade, name_of(grade)]


static func text(grade: String) -> String:
	return TEXTS.get(grade, "극한. 몸 전체를 써서 아주 작은 홀드를 이어 가요")


static func tip_id(grade: String) -> String:
	return "grade_" + grade
