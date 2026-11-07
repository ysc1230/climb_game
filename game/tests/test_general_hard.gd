extends RefCounted
## 어려운 일반 문제 G_V2_01·G_V3_01·G_V4_01(2026-11-06 사용자: "홀드가 너무 가깝고 적다"):
## 홀드 수와(G_V3_01은 2026-11-07 사용자 "홀드가 너무 많다"로 30 → 16) 의도 경로의 손 이동 평균 거리(≥ 0.58m), 기술 전 지름길이 막히는지 확인한다.
## 홀드가 적은 문제 G_V0_02·G_V2_02·G_V3_02·G_V4_02(2026-11-07 사용자: "등급마다 홀드가 너무 많다"):
## 그 등급 첫 문제보다 홀드가 30~50% 적은지 같은 방식으로 확인한다.
## 기술 금지 재생은 test_content(ContentCheck)가 맡는다.

var runner

const MIN_HAND_AVG := 0.58
## route_id → [최소 홀드 수, 최대 홀드 수](정상 포함)
const ROUTES := {
	"G_V2_01": [18, 22], "G_V3_01": [14, 18], "G_V4_01": [36, 44],
	"G_V2_02": [10, 13], "G_V3_02": [15, 21], "G_V4_02": [19, 27],
}
## V0은 기술·먼 이동이 없어 손 이동 평균은 보지 않고 홀드 수만 본다.
const V0_ROUTES := {"G_V0_02": [7, 9]}
## 기술 없이 바로 가는 순서: [route_id, 앞 단계 수, 이어 붙일 단계]. 모두 그 대안 단계에서 막혀야 한다.
const SHORTCUTS := [
	["G_V2_01", 5, [["LH", "H06"]]],  # 크로스 전 왼손이 먼 H06 바로 잡기
	["G_V3_01", 9, [["LH", "H09"]]],  # v2: 매치 전 왼손이 먼 H09 바로 잡기
	["G_V4_01", 0, [["RH", "H04"]]],
	["G_V4_01", 10, [["RH", "H09"]]],
	["G_V2_02", 0, [["LH", "H04"]]],  # 크로스 전 왼손이 먼 H04 바로 잡기
	["G_V2_02", 0, [["LH", "H03"], ["RH", "H02"], ["LH", "H04"]]],  # 손 바꿔 옮기기
	["G_V3_02", 0, [["RH", "H04"]]],
	["G_V3_02", 0, [["RH", "H03"], ["LH", "H02"], ["RH", "H04"]]],
	["G_V3_02", 10, [["RH", "H09"]]],  # 매치 전 오른손이 먼 H09 바로 잡기
	["G_V4_02", 5, [["RH", "H06"]]],  # 크로스 전 오른손이 먼 H06 바로 잡기
	["G_V4_02", 11, [["LH", "H09"]]],  # 매치 전 왼손이 먼 H09 바로 잡기
]


func _route(id: String) -> RouteDef:
	return RouteDef.load_json(ContentIndex.route_path(id))


func _hold_count(r: RouteDef) -> int:
	var ids := {}
	for key in r.slots:
		ids[str(key).split("/")[1]] = true
	return ids.size()


## 손 이동 거리: 그 손이 지금 잡은 슬롯에서 다음 슬롯까지(시작 자세부터).
func _hand_distances(r: RouteDef) -> Array:
	var at := {}
	for limb in r.start_slots:
		at[limb] = r.slot_pos(r.start_slots[limb])
	var out := []
	for m in r.intended_moves:
		var limb := StringName(m[0])
		if not PoseSolver.is_hand(limb) or m.size() != 2:
			continue
		var p := r.slot_pos(str(m[1]))
		out.append((at[limb] as Vector2).distance_to(p))
		at[limb] = p
	return out


func test_hold_counts() -> void:
	var all := ROUTES.duplicate()
	all.merge(V0_ROUTES)
	for id in all:
		var r := _route(id)
		runner.check(r.errors.is_empty(), "%s 로드: %s" % [id, r.errors])
		var n := _hold_count(r)
		var lo: int = all[id][0]
		var hi: int = all[id][1]
		runner.check(n >= lo and n <= hi, "%s 홀드 %d개(%d~%d)" % [id, n, lo, hi])


func test_hand_move_average() -> void:
	for id in ROUTES:
		var d := _hand_distances(_route(id))
		var avg := 0.0
		for v in d:
			avg += v
		avg /= maxf(1.0, d.size())
		runner.check(avg >= MIN_HAND_AVG, "%s 손 이동 평균 %.3fm ≥ %.2f" % [id, avg, MIN_HAND_AVG])


func test_shortcuts_fail() -> void:
	for s in SHORTCUTS:
		var id: String = s[0]
		var r := _route(id)
		var steps: Array = r.intended_moves.slice(0, s[1])
		for m in s[2]:
			steps.append([StringName(m[0]), "%s/%s/hand_1" % [id, m[1]]])
		var bot := SessionBot.run(r, steps)
		runner.check(bot.failed_step >= int(s[1]), "%s 지름길 %s는 막힘: #%d %s" % [id, s[2], bot.failed_step, bot.failure])
