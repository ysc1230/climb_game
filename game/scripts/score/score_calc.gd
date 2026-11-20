class_name ScoreCalc
extends RefCounted
## 100점 점수(docs/superpowers/specs/2026-11-19-3-score-design.md §3.1). 노드 없음. 완등한 시도의 기록(ScoreRecorder.to_dict)만 매긴다.
## 힘 아끼기 30 · 안정 25 · 정확한 손발 20 · 기술 15 · 마무리 10. 관문이 없으면 기술을 빼고 ×100/85.

const ENERGY := 30.0
const STABLE := 25.0
const PRECISE := 20.0
const TECHNIQUE := 15.0
const DANGER_PENALTY := 4.0
const BARN_PENALTY := 3.0
const MISS_PENALTY := 2.0
const EXTRA_GRAB_PENALTY := 1.0
const GATE_AFTER_TICKS := 15  # 패드 기술 라벨이 잡은 뒤 이만큼 늦게 바뀌어도 그 잡기로 친다
## 패드로 하는 기술 → 판정이 남기는 move 라벨.
const PAD_LABELS := {&"T_HIGH_STEP": [&"HighStep"], &"T_MATCH": [&"HandMatch"], &"T_CROSS": [&"CrossReach"], &"T_LOCK_OFF": [&"LockOff"]}


static func top_y(route: RouteDef) -> float:
	var y := -INF
	for k in route.goal_slots:
		if route.slots.has(k):
			y = maxf(y, (route.slots[k].pos as Vector2).y)
	return y if y > -INF else route.start_pelvis.y + 1.0


## {total: int, parts: {energy, stable, precise, technique(관문 없으면 −1), finish}, helped}
static func score(rec: Dictionary, route: RouteDef) -> Dictionary:
	var ev: Array = rec.get("events", [])
	var h := maxf(top_y(route) - float(rec.get("start_y", route.start_pelvis.y)), 0.5)
	var energy := ENERGY
	var ref := float(route.score_ref.get("spent_per_m", 0.0))
	if ref > 0.0:
		var r := (float(rec.get("spent", 0.0)) / h) / ref
		energy = ENERGY * clampf((2.5 - r) / 1.5, 0.0, 1.0)
	var ticks := maxi(int(rec.get("ticks", 0)), 1)
	var f := float(rec.get("stable_ticks", 0)) / ticks
	var stable := maxf(STABLE * clampf((f - 0.5) / 0.4, 0.0, 1.0) - DANGER_PENALTY * int(rec.get("danger_entries", 0)) - BARN_PENALTY * int(rec.get("barn_doors", 0)), 0.0)
	var grabs := ev.filter(func(e): return e.type == "grab").size()
	var misses := ev.filter(func(e): return e.type == "miss").size()
	var extra := maxi(grabs - int(route.score_ref.get("grabs", grabs)), 0) if route.score_ref.has("grabs") else 0
	var precise := maxf(PRECISE - MISS_PENALTY * misses - EXTRA_GRAB_PENALTY * extra, 0.0)
	var fin: Dictionary = rec.get("finish", {})
	var finish := 4.0 + (4.0 if bool(fin.get("feet_on", false)) else 0.0) + (2.0 if bool(fin.get("stable", false)) else 0.0)
	var parts := {"energy": roundi(energy), "stable": roundi(stable), "precise": roundi(precise), "finish": roundi(finish), "technique": -1}
	var total := 0
	if route.score_gates.is_empty():
		total = roundi((energy + stable + precise + finish) * 100.0 / 85.0)
	else:
		var tech := TECHNIQUE * gates_hit(ev, route.score_gates) / float(route.score_gates.size())
		parts.technique = roundi(tech)
		total = roundi(energy + stable + precise + finish + tech)
	return {"total": clampi(total, 0, 100), "parts": parts, "helped": bool(rec.get("helped", false))}


## 맞춘 관문 수(관문마다 한 번만). 버튼 기술은 기록의 슬롯, 패드 기술은 그 슬롯을 잡은 잡기와
## 바로 앞 잡기 사이(또는 잡은 뒤 GATE_AFTER_TICKS 안)에 남은 move 라벨로 본다.
static func gates_hit(ev: Array, gates: Array) -> int:
	var hit := 0
	for g in gates:
		var tech: StringName = g.technique
		var slot: String = g.slot
		var ok := false
		for i in ev.size():
			var e: Dictionary = ev[i]
			if e.type == "succeeded" and StringName(str(e.get("id", ""))) == tech and str(e.get("key", "")) == slot:
				ok = true
			elif e.type == "pad_foot_swap" and tech == &"T_FOOT_SWAP" and str(e.get("key", "")) == slot:
				ok = true
			elif e.type == "grab" and str(e.get("key", "")) == slot and PAD_LABELS.has(tech):
				var t0 := -INF
				for j in range(i - 1, -1, -1):
					if ev[j].type == "grab":
						t0 = float(ev[j].tick)
						break
				for m in ev:
					if m.type == "move" and StringName(str(m.get("label", ""))) in PAD_LABELS[tech] and float(m.tick) >= t0 and int(m.tick) <= int(e.tick) + GATE_AFTER_TICKS:
						ok = true
			if ok:
				break
		if ok:
			hit += 1
	return hit
