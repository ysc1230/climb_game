class_name HelpPicker
extends RefCounted
## 막혔을 때 도움(docs/superpowers/specs/2026-11-19-3-score-design.md §3.4). 노드 없음.
## 힌트: 가장 자주 떨어진 골반 높이(0.3m 칸) 위를 정답 순서에서 처음 잡는 손 홀드.
## 시범 보기: 정답 순서를 검사 봇으로 돌려 자세 기록(GhostTrack)을 만든다. 봇이 못 깨면 null(버튼을 보이지 않음).

const BIN := 0.3
const HAND_ABOVE := 0.5  # 손 홀드는 골반보다 이만큼 위여야 "그 높이 위"로 본다(만든 사람 판단: 손은 골반보다 위에서 잡음)
const HINT_FALLS := 3
const DEMO_FALLS := 5


## 가장 자주 떨어진 높이(그 칸 값들의 평균, 같으면 높은 칸). 기록이 없으면 −INF.
static func common_height(heights: Array) -> float:
	if heights.is_empty():
		return -INF
	var bins := {}
	for h in heights:
		var b := floori(float(h) / BIN)
		if not bins.has(b):
			bins[b] = []
		bins[b].append(float(h))
	var best = null
	for b in bins:
		if best == null or bins[b].size() > bins[best].size() or (bins[b].size() == bins[best].size() and b > best):
			best = b
	var sum := 0.0
	for h in bins[best]:
		sum += h
	return sum / bins[best].size()


static func hint_slot(route: RouteDef, heights: Array) -> String:
	var h := common_height(heights)
	if h == -INF:
		h = route.start_pelvis.y
	var last := ""
	for m in route.intended_moves:
		if m.is_empty():
			continue
		var key := str(m[m.size() - 1])
		if not str(m[0]) in ["LH", "RH"] or not route.slots.has(key):
			continue
		last = key
		if (route.slots[key].pos as Vector2).y > h + HAND_ABOVE:
			return key
	return last


static func demo_track(route: RouteDef) -> GhostTrack:
	var g := GhostTrack.new()
	var bot := SessionBot.run(route, route.intended_moves, {}, null, func(s: ClimbSession, r: String) -> void:
		if r != "clear":
			g.record(s, Tuning.DT))
	return g if bot.ok() and not g.frames.is_empty() else null


## 미리 만든 봇 기록(AI 고스트·시범 보기, tools/ai_ghost_write.gd). 문제 판·조정값이 다르거나 없으면 null.
const AI_DIR := "res://data/ai_ghosts/"


static func stored_path(route_id: String) -> String:
	return AI_DIR + route_id + ".json"


static func stored_track(route: RouteDef) -> GhostTrack:
	var path := stored_path(route.route_id)
	if not FileAccess.file_exists(path):
		return null
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary or int(d.get("content_version", -1)) != route.content_version or int(d.get("tuning_version", -1)) != Tuning.TUNING_VERSION:
		return null
	var g := GhostTrack.from_dict(d.get("ghost"))
	return g if not g.frames.is_empty() else null


static func stored_dict(route: RouteDef, g: GhostTrack) -> Dictionary:
	return {"route_id": route.route_id, "content_version": route.content_version, "tuning_version": Tuning.TUNING_VERSION, "ghost": g.to_dict()}
