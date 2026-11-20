extends RefCounted
## 등급 이름·설명(docs/superpowers/specs/2026-11-19-3-score-design.md §3.6).

var runner


func test_names() -> void:
	for case in [["V0", "입문"], ["V1", "입문"], ["V2", "쉬움"], ["V3", "쉬움"], ["V4", "보통"], ["V5", "보통"], ["V6", "어려움"], ["V8", "어려움"], ["V9", "극한"], ["V12", "극한"]]:
		runner.check(GradeInfo.name_of(case[0]) == case[1], "%s → %s (%s)" % [case[0], case[1], GradeInfo.name_of(case[0])])
	runner.check(GradeInfo.label("V3") == "V3 · 쉬움", "카드 표시")


func test_texts() -> void:
	for g in ["V0", "V1", "V2", "V3", "V4", "V5", "V6", "V7", "V8", "V10"]:
		runner.check(GradeInfo.text(g) != "", "%s 설명 있음" % g)
	runner.check(GradeInfo.text("V3").contains("하이스텝"), "V3 문구")
	runner.check(GradeInfo.tip_id("V3") == "grade_V3", "처음 한 번 기록 키")
