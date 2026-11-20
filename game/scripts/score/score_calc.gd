class_name ScoreCalc
extends RefCounted
## 100점 점수(docs/superpowers/specs/2026-11-19-3-score-design.md §3.1). 노드 없음. 완등한 시도의 기록(ScoreRecorder.to_dict)만 매긴다.
## 힘 아끼기 30 · 안정 25 · 정확한 손발 20 · 기술 15 · 마무리 10. 관문이 없으면 기술을 빼고 ×100/85.

const ENERGY := 30.0
const STABLE := 25.0
const PRECISE := 20.0
const TECHNIQUE := 15.0
## 2026-11-20 사용자: "모든 기술을 좀 더 디테일하게, 소수점 두 자리까지". 수가 아니라 시간·거리·품질로 잰다.
const DANGER_PENALTY := 2.0          # 위험에 들어갈 때마다
const DANGER_PER_SEC := 6.0          # 위험으로 보낸 1초마다
const BARN_PENALTY := 1.5
const BARN_PER_SEC := 4.0
const STRAINED_WEIGHT := 0.5         # 버티기 힘든(STRAINED) 틱은 안정 틱의 절반
const MISS_PENALTY := 2.0
const EXTRA_GRAB_PENALTY := 1.0
const QUALITY_PART := 6.0            # 정확한 손발 20 중 잡은 자리 품질 몫(기준 품질 대비 비율)
const GATE_BASE := 0.6               # 패드 기술 관문: 0.6 + 0.4 × tq
## 패드 기술은 잡기 사건의 tech(ScoreRecorder.grab_techniques, 잡은 순간 자세)로 본다. 판정의 move 라벨은 쓰지 않는다
## (봇으로 확인: 매치 라벨이 잡은 뒤 1초 늦게 붙고, 하이스텝 라벨은 정답대로 올라도 안 붙음).


static func format(v: float) -> String:
	return "%.2f" % snappedf(v, 0.01)


static func top_y(route: RouteDef) -> float:
	var y := -INF
	for k in route.goal_slots:
		if route.slots.has(k):
			y = maxf(y, (route.slots[k].pos as Vector2).y)
	return y if y > -INF else route.start_pelvis.y + 1.0


## {total: float(0.01), parts: {energy, stable, precise, technique(관문 없으면 −1), finish}(0.01), helped}
static func score(rec: Dictionary, route: RouteDef) -> Dictionary:
	var ev: Array = rec.get("events", [])
	var h := maxf(top_y(route) - float(rec.get("start_y", route.start_pelvis.y)), 0.5)
	var energy := ENERGY
	var ref := float(route.score_ref.get("spent_per_m", 0.0))
	if ref > 0.0:
		var r := (float(rec.get("spent", 0.0)) / h) / ref
		energy = ENERGY * clampf((2.5 - r) / 1.5, 0.0, 1.0)
	var ticks := maxi(int(rec.get("ticks", 0)), 1)
	var f := (float(rec.get("stable_ticks", 0)) + STRAINED_WEIGHT * float(rec.get("strained_ticks", 0))) / ticks
	var danger := DANGER_PENALTY * int(rec.get("danger_entries", 0)) + DANGER_PER_SEC * float(rec.get("danger_ticks", 0)) * Tuning.DT
	var barn := BARN_PENALTY * int(rec.get("barn_doors", 0)) + BARN_PER_SEC * float(rec.get("barn_ticks", 0)) * Tuning.DT
	var stable := maxf(STABLE * clampf((f - 0.5) / 0.4, 0.0, 1.0) - danger - barn, 0.0)
	var grab_ev := ev.filter(func(e): return e.type == "grab")
	var misses := ev.filter(func(e): return e.type == "miss").size()
	var extra := maxi(grab_ev.size() - int(route.score_ref.get("grabs", grab_ev.size())), 0) if route.score_ref.has("grabs") else 0
	var q_part := QUALITY_PART
	var ref_q := float(route.score_ref.get("quality", 0.0))
	var qs := grab_ev.filter(func(e): return e.has("quality")).map(func(e): return float(e.quality))
	if ref_q > 0.0 and not qs.is_empty():
		var mean := 0.0
		for q in qs:
			mean += q
		q_part = QUALITY_PART * clampf(mean / qs.size() / ref_q, 0.0, 1.0)
	var precise := maxf(PRECISE - QUALITY_PART - MISS_PENALTY * misses - EXTRA_GRAB_PENALTY * extra, 0.0) + q_part
	var fin: Dictionary = rec.get("finish", {})
	var feet := int(fin.get("feet", 2 if bool(fin.get("feet_on", false)) else 0))
	var ph := str(fin.get("phase", "STABLE" if bool(fin.get("stable", false)) else "")).to_upper()
	var finish := 4.0 + 2.0 * clampi(feet, 0, 2) + (2.0 if ph == "STABLE" else (1.0 if ph == "STRAINED" else 0.0))
	var parts := {"energy": snappedf(energy, 0.01), "stable": snappedf(stable, 0.01), "precise": snappedf(precise, 0.01), "finish": snappedf(finish, 0.01), "technique": -1}
	var total := 0.0
	if route.score_gates.is_empty():
		total = (energy + stable + precise + finish) * 100.0 / 85.0
	else:
		var tech := TECHNIQUE * gate_credit(ev, route.score_gates) / float(route.score_gates.size())
		parts.technique = snappedf(tech, 0.01)
		total = energy + stable + precise + finish + tech
	return {"total": snappedf(clampf(total, 0.0, 100.0), 0.01), "parts": parts, "helped": bool(rec.get("helped", false))}


## 관문마다 얻은 몫(0~1)의 합. 버튼 기술·발 바꾸기는 1, 패드 기술은 GATE_BASE + 0.4 × tq(그 슬롯에서 가장 잘한 잡기).
static func gate_credit(ev: Array, gates: Array) -> float:
	var sum := 0.0
	for g in gates:
		var tech := str(g.technique)
		var slot: String = g.slot
		var best := 0.0
		for e in ev:
			if str(e.get("key", "")) != slot:
				continue
			if (e.type == "succeeded" and str(e.get("id", "")) == tech) or (e.type == "pad_foot_swap" and tech == "T_FOOT_SWAP"):
				best = 1.0
			elif e.type == "grab" and tech in e.get("tech", []):
				var tq: Dictionary = e.get("tq", {})
				best = maxf(best, GATE_BASE + (1.0 - GATE_BASE) * clampf(float(tq.get(tech, 1.0)), 0.0, 1.0))
		sum += best
	return sum


## 맞춘 관문 수(관문마다 한 번만). 버튼 기술은 기록의 슬롯, 패드 기술은 그 슬롯을 잡은 잡기의 tech, 발 바꾸기는 그 슬롯 사건.
static func gates_hit(ev: Array, gates: Array) -> int:
	var hit := 0
	for g in gates:
		var tech := str(g.technique)
		var slot: String = g.slot
		for e in ev:
			var on_slot := str(e.get("key", "")) == slot
			if on_slot and ((e.type == "succeeded" and str(e.get("id", "")) == tech) \
					or (e.type == "pad_foot_swap" and tech == "T_FOOT_SWAP") \
					or (e.type == "grab" and tech in e.get("tech", []))):
				hit += 1
				break
	return hit
