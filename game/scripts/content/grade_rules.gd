class_name GradeRules
extends RefCounted
## docs/28 §7.3 등급 기준(초기값, 플레이 후 조정). 검증 봇 측정값과 비교해 벗어나면 경고한다.
## 경고는 실패가 아니다(사람이 등급을 다시 본다, §7.4 3).

## 등급 → {min_half_width: 손홀드 반폭 하한(m, 측정값 min_hand_half_width와 비교), min_reach_margin: 가장 어려운 이동의 도달 여유 하한(m)}.
## 도달 여유 하한은 SessionBot의 "잡은 뒤 안정 자세" 측정에 맞춘 값이다(28 §7.3 표의 값에서 다시 정함, 플레이 후 조정).
const LIMITS := {
	"V0": {"min_half_width": 0.12, "min_reach_margin": 0.06},
	"V1": {"min_half_width": 0.10, "min_reach_margin": 0.04},
	"V2": {"min_half_width": 0.08, "min_reach_margin": 0.025},
	"V3": {"min_half_width": 0.06, "min_reach_margin": 0.012},
	"V4": {"min_half_width": 0.05, "min_reach_margin": 0.005},
	"V5": {"min_half_width": 0.04, "min_reach_margin": 0.0},
}
const EPS := 0.0005  # 저작 값(0.12)과 측정 값의 부동소수 오차


## 측정값(SessionBot.metrics)이 그 등급 기준을 벗어나면 "경고:" 줄들. 표에 없는 등급(시험 루트 등)은 경고 없음.
static func warnings(route: RouteDef, metrics: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	if not LIMITS.has(route.grade):
		return out
	var lim: Dictionary = LIMITS[route.grade]
	var hw := float(metrics.get("min_hand_half_width", INF))
	if hw < lim.min_half_width - EPS:
		out.append("경고: 가장 작은 손홀드 반폭 %.3fm < %s 기준 %.2fm" % [hw, route.grade, lim.min_half_width])
	var rm := float(metrics.get("min_reach_margin", INF))
	if rm < lim.min_reach_margin - EPS:
		out.append("경고: 가장 작은 도달 여유 %.3fm < %s 기준 %.2fm" % [rm, route.grade, lim.min_reach_margin])
	return out
