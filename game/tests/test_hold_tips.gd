extends RefCounted
## 처음 보는 홀드 종류 이름표(작업 4 §4.4): 종류마다 한 번, 그 종류의 가장 낮은 홀드 옆.

var runner


func test_one_tag_per_unseen_type() -> void:
	# 2026-11-22 오버행 앱에서 문제를 다시 배치: 손·발 홀드 종류가 여럿인 실금(크림프·저그·작은/큰 발판)으로
	var r := RouteDef.load_json("res://tests/fixtures/G_V8_01.json")
	var tags := HoldTips.pick(r, [])
	var types: Array = tags.map(func(t): return t.type)
	runner.check(types.has("crimp") and types.has("jug") and types.has("foot_chip") and types.has("foot_big") and not types.has("goal"), "종류마다 하나, 탑 제외 %s" % [types])
	var uniq := {}
	for t in types:
		uniq[t] = true
	runner.check(uniq.size() == types.size(), "같은 종류는 한 번만")
	for t in tags:
		var y: float = r.slots[t.key].pos.y
		for key in r.slots:
			if str(r.slots[key].hold_type) == t.type:
				runner.check(r.slots[key].pos.y >= y - 0.0001, "%s는 가장 낮은 홀드에 %s" % [t.type, t.key])
		runner.check(t.text == HoldTypes.name_ko(t.type) and t.tip == "hold_" + t.type, "이름표 글·저장 키 %s" % [t])


func test_seen_types_skipped() -> void:
	var r := RouteDef.load_json("res://tests/fixtures/G_V3_03.json")
	var tags := HoldTips.pick(r, ["hold_crimp", "hold_pinch"])
	runner.check(not tags.any(func(t): return t.type == "crimp" or t.type == "pinch"), "본 종류는 다시 안 뜸 %s" % [tags])
	runner.check(HoldTips.pick(RouteDef.load_json("res://data/routes/TX_TECH.json"), []).is_empty(), "옛 형식(종류 없음)은 이름표 없음")
