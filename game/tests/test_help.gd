extends RefCounted
## 막혔을 때 도움(docs/superpowers/specs/2026-11-19-3-score-design.md §3.4): 힌트 홀드 고르기, 시범 보기 기록.

var runner


func _r(id := "G_V3_03") -> RouteDef:
	return RouteDef.load_json("res://tests/fixtures/%s.json" % id)  # 옛 일반 문제(2026-11-26 게임에서 지움)를 시험용으로


func test_common_height_bins() -> void:
	runner.check(HelpPicker.common_height([]) == -INF, "기록 없으면 없음")
	var h := HelpPicker.common_height([1.0, 1.1, 1.15, 2.0, 0.4])
	runner.check(h >= 0.9 and h < 1.2, "0.3m 칸에서 가장 자주 떨어진 높이 %.2f" % h)


func test_hint_slot_first_hand_above() -> void:
	var r := _r()
	var h := 1.5
	var key := HelpPicker.hint_slot(r, [h, h, h])
	runner.check(key != "" and r.slots.has(key), "힌트 홀드 %s" % key)
	var first := ""
	for m in r.intended_moves:
		var k := str(m[m.size() - 1])
		if str(m[0]) in ["LH", "RH"] and r.slots.has(k) and (r.slots[k].pos as Vector2).y > h + HelpPicker.HAND_ABOVE:
			first = k
			break
	runner.check(key == first, "정답 순서에서 그 높이 위를 처음 잡는 손 홀드 %s = %s" % [key, first])
	runner.check(HelpPicker.hint_slot(r, []) == HelpPicker.hint_slot(r, [r.start_pelvis.y]), "기록이 없으면 시작 높이로")


func test_demo_track_reaches_top() -> void:
	var r := _r()
	var g := HelpPicker.demo_track(r)
	runner.check(g != null and g.frames.size() > 50, "봇 재생이 자세 기록을 만듦")
	if g != null:
		var top := ScoreCalc.top_y(r)
		var best := -INF
		for f in g.frames:
			best = maxf(best, float(f[2]))
		runner.check(best > top - 1.4, "탑 가까이(골반은 손보다 1.1m쯤 아래) 올라감 %.2f / %.2f" % [best, top])
