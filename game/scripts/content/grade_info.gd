class_name GradeInfo
extends RefCounted
## 등급 이름·설명 카드(docs/superpowers/specs/2026-11-19-3-score-design.md §3.6). 문구는 작업 5에서 실제 문제에 맞춰 고쳤다(2026-11-21).

const TEXTS := {
	"V0": "입문. 큰 홀드가 계단처럼 이어져요. 손발을 하나씩 옮기면 돼요. 필요한 기술: 없음",
	"V1": "입문. 손홀드 사이가 멀어요. 발을 먼저 올리면 손이 닿아요",
	"V2": "쉬움. 옆으로 비껴 오르거나 중간에 큰 저그가 있어요. 두 발로 서서 쉬면 손 힘이 차요",
	"V3": "쉬움. 하이스텝이나 매치를 써야 지나가는 곳이 하나 있어요",
	"V4": "보통. 하이스텝 없이는 못 가는 곳이 있거나, 작은 홀드에서 손 힘을 아껴야 해요",
	"V5": "보통. 크림프·포켓 같은 작은 홀드가 이어져요. 기술 하나가 필요하고, 쉬는 자리는 하나뿐이에요",
	"V6": "어려움. 하이스텝으로 올라선 뒤 매치하는 식으로 기술 두 개를 이어 써야 해요",
	"V7": "어려움. 기술 두 개에 옆이나 아래를 향한 홀드가 섞여요. 몸 위치를 맞춰야 덜 지쳐요",
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
