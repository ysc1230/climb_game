class_name GradeInfo
extends RefCounted
## 등급 이름·설명 카드(docs/superpowers/specs/2026-11-19-3-score-design.md §3.6). 문구는 작업 5에서 실제 문제에 맞춰 고쳤다(2026-11-21).

## 오버행 실험 앱(2026-11-22): 벽 각도(WALL_DEG)와 홀드 수 상한에 맞춰 문제를 다시 배치하고 문구도 고쳤다.
const TEXTS := {
	"V0": "입문. 수직 벽이에요. 큰 홀드가 계단처럼 이어져요. 손발을 하나씩 옮기면 돼요",
	"V1": "입문. 벽이 10° 기울어요. 발을 먼저 올리면 손이 닿아요",
	"V2": "쉬움. 벽이 15° 기울어요. 옆으로 비껴 오르거나 중간 큰 저그에서 쉬어 가요",
	"V3": "쉬움. 벽이 20° 기울고 발판이 둘뿐이에요. 하이스텝이나 매치를 한 번 써야 해요",
	"V4": "보통. 벽이 25° 기울어요. 하이스텝이 필요하거나 작은 홀드에서 손 힘을 아껴야 해요",
	"V5": "보통. 벽이 30° 기울어요. 기술 하나가 필요하고 쉴 곳이 없어요",
	"V6": "어려움. 벽이 35° 기울어요. 하이스텝으로 올라선 뒤 매치하는 식으로 기술 두 개를 이어 써야 해요",
	"V7": "어려움. 벽이 40° 기울어요. 기술 두 개에 아래로 잡는 홀드나 먼 사선이 섞여 손 힘이 빨리 빠져요",
	"V8": "어려움. 벽이 45° 기울어요. 쉴 곳이 거의 없어요. 힘 아끼기가 전부예요",
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


## 벽 각도(오버행 실험 앱, 2026-11-22 사용자: "기울기에 따라 난이도가 달라져야 해. 알아서 판단해서 난이도별 기울기를 적용해").
## V0은 수직, V1 10°, 그 뒤 등급마다 5°씩 더 머리 위로 넘어온다(V7 40°, V8 이상 45°). 수업·튜토리얼은 수직(RouteDef).
const WALL_DEG := {"V0": 0.0, "V1": 10.0, "V2": 15.0, "V3": 20.0, "V4": 25.0, "V5": 30.0, "V6": 35.0, "V7": 40.0}


static func wall_deg(grade: String) -> float:
	return float(WALL_DEG.get(grade, 45.0 if _n(grade) >= 8 else 0.0))


## 홀드 수 상한(2026-11-22 사용자: "손발 홀드가 너무 많으면 안 돼"). 손홀드(정상 제외)·발 전용 홀드.
## 쉬운 등급(V0~V2)은 손 6·발 5, V3부터 손 5·발 4: 높은 등급은 동작이 멀고 손홀드를 발로도 딛는다.
static func max_hands(grade: String) -> int:
	return 6 if _n(grade) <= 2 else 5


static func max_feet(grade: String) -> int:
	return 5 if _n(grade) <= 2 else 4


static func tip_id(grade: String) -> String:
	return "grade_" + grade
