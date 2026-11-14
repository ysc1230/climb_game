class_name PlacementMetrics
extends RefCounted
## 배치 수치(docs/41 §5 도구 A). 홀드 = 슬롯 키의 윗 경로(route/hold). 정상 홀드는 세지 않는다.
## 높이는 바닥(y 0)에서 가장 높은 정상 슬롯까지. 손 이동 비율은 팔 길이(ARM_UPPER + ARM_LOWER) 대비.


## 반환 {height, hand_holds, foot_only, foot_places, hand_per_m, foot_places_per_m, unused(의도 경로에 안 쓰는 홀드 수),
## hand_move_avg, hand_move_max(의도 경로 손 이동 거리 m, 정상 제외), hand_move_avg_ratio, hand_move_max_ratio}.
static func measure(route: RouteDef) -> Dictionary:
	var goal_holds := {}
	var height := 0.0
	for k in route.goal_slots:
		goal_holds[String(k).get_base_dir()] = true
		height = maxf(height, route.slots[k].pos.y)
	var hand := {}
	var foot_only := {}
	for key in route.slots:
		var h := String(key).get_base_dir()
		if goal_holds.has(h):
			continue
		if route.slots[key].has("hand_area"):
			hand[h] = true
		else:
			foot_only[h] = true
	for h in hand:
		foot_only.erase(h)
	var used := {}
	var at := {}
	for limb in route.start_slots:
		used[String(route.start_slots[limb]).get_base_dir()] = true
		at[StringName(limb)] = route.slots[route.start_slots[limb]].pos
	var dists: Array[float] = []
	for m in route.intended_moves:
		if m.size() < 2 or not route.slots.has(str(m[1])):
			continue
		var limb := StringName(str(m[0]))
		var key := str(m[1])
		used[key.get_base_dir()] = true
		var pos: Vector2 = route.slots[key].pos
		if PoseSolver.is_hand(limb) and at.has(limb) and not route.goal_slots.has(key):
			dists.append(at[limb].distance_to(pos))
		at[limb] = pos
	var places := hand.size() + foot_only.size()
	var unused := 0
	for h in hand.keys() + foot_only.keys():
		if not used.has(h):
			unused += 1
	var arm := Tuning.ARM_UPPER + Tuning.ARM_LOWER
	var avg := 0.0
	var mx := 0.0
	for d in dists:
		avg += d / dists.size()
		mx = maxf(mx, d)
	var hm := maxf(height, 0.001)
	return {"height": height, "hand_holds": hand.size(), "foot_only": foot_only.size(), "foot_places": places,
		"hand_per_m": hand.size() / hm, "foot_places_per_m": places / hm, "unused": unused,
		"hand_move_avg": avg, "hand_move_max": mx, "hand_move_avg_ratio": avg / arm, "hand_move_max_ratio": mx / arm}


## 봇 기록에서 하중 받는 발이 2개 미만인 채 끝난 이동 수 [적은 발 이동, 전체 이동].
static func low_feet_moves(bot_log: Array) -> Array[int]:
	var low := 0
	var total := 0
	for line in bot_log:
		var s := String(line)
		var i := s.find("하중발=[")
		if i < 0 or s.find("성공") < 0:
			continue
		total += 1
		if s.substr(i, s.find("]", i) - i).count("&\"") < 2:
			low += 1
	return [low, total]


static func lines(route: RouteDef, bot_log: Array) -> PackedStringArray:
	var m := measure(route)
	var lf := low_feet_moves(bot_log)
	return PackedStringArray([
		"배치: 높이 %.2fm, 손홀드 %d(%.1f개/m), 발 전용 %d, 발 디딜 곳 %d(%.1f곳/m), 의도 경로에 안 쓰는 홀드 %d" % [m.height, m.hand_holds, m.hand_per_m, m.foot_only, m.foot_places, m.foot_places_per_m, m.unused],
		"배치: 손 이동 평균 %.2fm(팔 길이의 %.2f), 최대 %.2fm(%.2f), 한 발·무발로 끝난 이동 %d/%d(%.0f%%)" % [m.hand_move_avg, m.hand_move_avg_ratio, m.hand_move_max, m.hand_move_max_ratio, lf[0], lf[1], 100.0 * lf[0] / maxi(lf[1], 1)],
	])
