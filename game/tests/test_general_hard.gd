extends RefCounted
## 어려운 일반 문제 G_V2_01(2026-11-06 사용자: "홀드가 너무 가깝고 적다"):
## 홀드 수(정상 포함 20 ± 2)와 의도 경로의 손 이동 평균 거리(≥ 0.58m), 기술 전 지름길이 막히는지 확인한다.
## 기술 금지 재생은 test_content(ContentCheck)가 맡는다.

var runner

const MIN_HAND_AVG := 0.58
## route_id → [목표 홀드 수, 허용 차]
const ROUTES := {"G_V2_01": [20, 2]}
## 기술 없이 바로 가는 순서: [route_id, 앞 단계 수, 이어 붙일 단계]. 모두 그 대안 단계에서 막혀야 한다.
const SHORTCUTS := [
	["G_V2_01", 5, [["LH", "H06"]]],  # 크로스 전 왼손이 먼 H06 바로 잡기
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
	for id in ROUTES:
		var r := _route(id)
		runner.check(r.errors.is_empty(), "%s 로드: %s" % [id, r.errors])
		var n := _hold_count(r)
		var want: int = ROUTES[id][0]
		runner.check(absi(n - want) <= ROUTES[id][1], "%s 홀드 %d개(목표 %d±%d)" % [id, n, want, ROUTES[id][1]])


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
