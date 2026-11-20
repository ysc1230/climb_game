class_name RouteDraft
extends RefCounted
## 문제 만들기 초안(작업 6 §2·§3, docs/superpowers/specs/2026-11-19-6-editor-design.md). 노드 없음.
## 홀드 목록·시작 네 자리·탑 하나를 들고, 일반 문제와 같은 JSON(mode "custom")으로 바꾼다.
## 놓기·옮기기는 1cm, 돌리기는 5°에 맞물린다. 되돌리기는 최근 UNDO_MAX단계.

const SCHEMA := 1                 # 공유 문제 JSON 판(§6). 앱이 모르는 더 새 판이면 열지 않는다
const MAX_HOLDS := 40
const NAME_MAX := 20
const UNDO_MAX := 30
const WALL_HALF := 1.0            # 벽 폭 2.0m
const WALL_H := 4.5
const Y_MIN := 0.05
const GOAL_HALF := 0.2            # 탑 두 칸의 간격 절반(일반 문제와 같음)
const GRADES := ["V0", "V1", "V2", "V3", "V4", "V5", "V6", "V7"]
const P_NAME := "문제 이름을 적어 주세요"
const P_START := "시작 자리(두 손·두 발)를 정해 주세요"
const P_GOAL := "탑 홀드를 놓아 주세요"
const P_SPACING := "빨간 홀드가 다른 홀드와 너무 가까워요"
const P_POSE := "시작 자세를 만들 수 없어요(손발이 너무 멀어요)"
const P_ROUTE := "문제 데이터 오류"

var route_id := ""
var name := ""
var grade := "V0"
var version := 1
var holds: Array = []             # [{id, type, size, rot, x, y, matchable}]
var start := {&"LH": "", &"RH": "", &"LF": "", &"RF": ""}  # limb → 홀드 id
var _next := 1
var _undo: Array = []
var _frozen := false              # 완등·올린 판: 다음 고침에서 판을 올린다


func hold(id: String) -> Dictionary:
	for h in holds:
		if h.id == id:
			return h
	return {}


func goal_hold() -> Dictionary:
	for h in holds:
		if h.type == "goal":
			return h
	return {}


static func is_hand_type(type: String) -> bool:
	return HoldTypes.has(type) and not HoldTypes.is_foot(type)


## 종류 type을 (x, y)에 놓는다. 탑은 하나라 이미 있으면 옮긴다. 반환: 홀드 id, 못 놓으면 "".
func place(type: String, x: float, y: float, size := "M", rot := 0) -> String:
	if not HoldTypes.has(type):
		return ""
	if type == "goal" and not goal_hold().is_empty():
		var g := goal_hold()
		move(g.id, x, y)
		return g.id
	if holds.size() >= MAX_HOLDS:
		return ""
	_push()
	var prefix := "G" if type == "goal" else ("F" if HoldTypes.is_foot(type) else "H")
	var id := "G01" if type == "goal" else "%s%02d" % [prefix, _next]
	if type != "goal":
		_next += 1
	holds.append({"id": id, "type": type, "size": size, "rot": _snap_rot(rot), "x": _sx(x), "y": _sy(y), "matchable": false})
	return id


func move(id: String, x: float, y: float) -> void:
	var h := hold(id)
	if h.is_empty():
		return
	_push()
	h.x = _sx(x)
	h.y = _sy(y)


## deg만큼 더 돌린다(5°씩 맞물림, 0~355).
func rotate(id: String, deg: int) -> void:
	set_rot(id, int(hold(id).get("rot", 0)) + deg)


func set_rot(id: String, deg: int) -> void:
	var h := hold(id)
	if h.is_empty() or h.type == "goal":
		return
	_push()
	h.rot = _snap_rot(deg)


func set_size(id: String, size: String) -> void:
	var h := hold(id)
	if h.is_empty() or not HoldTypes.SIZES.has(size) or h.type == "goal":
		return
	_push()
	h.size = size


func set_matchable(id: String, on: bool) -> void:
	var h := hold(id)
	if h.is_empty() or not is_hand_type(h.type) or h.type == "goal":
		return
	_push()
	h.matchable = on


func remove(id: String) -> void:
	var i := holds.find(hold(id))
	if i < 0:
		return
	_push()
	holds.remove_at(i)
	for l in start:
		if start[l] == id:
			start[l] = ""


## 시작 자리. 손은 손홀드만(탑 제외), 발은 탑이 아닌 아무 홀드. 같은 홀드를 다른 손발이 쓰고 있었으면 그쪽을 비운다.
func set_start(limb: StringName, id: String) -> bool:
	var h := hold(id)
	if h.is_empty() or h.type == "goal":
		return false
	if PoseSolver.is_hand(limb) and not is_hand_type(h.type):
		return false
	_push()
	for l in start:
		if start[l] == id:
			start[l] = ""
	start[limb] = id
	return true


func set_name(n: String) -> void:
	name = n.strip_edges().substr(0, NAME_MAX)


func undo() -> bool:
	if _undo.is_empty():
		return false
	_load_state(_undo.pop_back())
	return true


## 완등했거나 올린 판: 다음 고침에서 판(version)을 올린다(§3 "고치면 새 판").
func freeze() -> void:
	_frozen = true


func _push() -> void:
	if _frozen:
		_frozen = false
		version += 1
	_undo.append(_state())
	if _undo.size() > UNDO_MAX:
		_undo.pop_front()


func _state() -> Dictionary:
	return {"holds": holds.duplicate(true), "start": start.duplicate(), "next": _next}


func _load_state(s: Dictionary) -> void:
	holds = s.holds
	start = s.start
	_next = s.next


static func _sx(x: float) -> float:
	return snappedf(clampf(x, -WALL_HALF, WALL_HALF), 0.01)


static func _sy(y: float) -> float:
	return snappedf(clampf(y, Y_MIN, WALL_H), 0.01)


static func _snap_rot(deg: int) -> int:
	return posmod(int(round(deg / 5.0)) * 5, 360)


# ---------- 문제 JSON ----------

func _key(h: Dictionary, side := "") -> String:
	if h.type == "goal":
		return "%s/G01/goal_%s" % [route_id, side]
	return "%s/%s/%s" % [route_id, h.id, "foot_1" if HoldTypes.is_foot(h.type) else "hand_1"]


## 일반 문제와 같은 형식(mode "custom", schema). pelvis: 시작 골반(비우면 start_pose()로 계산).
func to_route_dict(pelvis := Vector2.INF, angle := 0.0) -> Dictionary:
	var hs: Array = []
	var goal_slots: Array = []
	for h in holds:
		if h.type == "goal":
			var slots: Array = []
			for side in ["left", "right"]:
				var x: float = h.x + (-GOAL_HALF if side == "left" else GOAL_HALF)
				slots.append({"slot_id": "goal_" + side, "pos": [snappedf(x, 0.001), h.y], "allowed": ["LH", "RH"], "hold_type": "goal", "size": "M", "rot_deg": 0})
				goal_slots.append(_key(h, side))
			hs.append({"hold_id": "G01", "slots": slots})
			continue
		var foot := HoldTypes.is_foot(h.type)
		var s := {"slot_id": "foot_1" if foot else "hand_1", "pos": [h.x, h.y], "allowed": ["LF", "RF"] if foot else ["LH", "RH"],
			"hold_type": h.type, "size": h.size, "rot_deg": h.rot}
		if h.matchable:
			s["hand_area"] = {"matchable": true}
		hs.append({"hold_id": h.id, "slots": [s]})
	var st := {}
	for l in start:
		var h := hold(start[l])
		st[String(l)] = _key(h) if not h.is_empty() else ""
	if pelvis == Vector2.INF:
		var p := start_pose()
		pelvis = p.pelvis
		angle = p.angle
	var d := {
		"route_id": route_id, "mode": "custom", "schema": SCHEMA, "grade": grade, "order": 0, "name_ko": name,
		"content_version": version, "validation_status": "Draft", "note": "",
		"bounds": {"x_min": -1.5, "x_max": 1.5, "y_min": 0.0, "y_max": 4.5}, "fail_line_y": -0.5,
		"check_swapped": false, "time_medal_seconds": 120, "goal_slots": goal_slots, "platforms": [],
		"start_pose": {"angle": angle, "pelvis": [snappedf(pelvis.x, 0.001), snappedf(pelvis.y, 0.001)], "slots": st},
		"intended_moves": [], "required_techniques": [], "crux_steps": {}, "holds": hs,
	}
	# 두 시작 발이 바닥 가까이(발판 높이 ≤ 0.15m)면 바닥 받침(일반 문제의 시작 발판과 같음)
	var lf := hold(start[&"LF"])
	var rf := hold(start[&"RF"])
	if not lf.is_empty() and not rf.is_empty() and HoldTypes.is_foot(lf.type) and HoldTypes.is_foot(rf.type) and lf.y <= 0.15 and rf.y <= 0.15:
		d.platforms = [{"platform_id": "P00", "foot_slot_keys": [_key(lf), _key(rf)], "top_y": 0.1,
			"x_range": [snappedf(minf(lf.x, rf.x) - 0.35, 0.01), snappedf(maxf(lf.x, rf.x) + 0.35, 0.01)]}]
	return d


func build(pelvis := Vector2.INF, angle := 0.0) -> RouteDef:
	return RouteDef.from_dict(to_route_dict(pelvis, angle))


## 시작 네 자리에서 몸이 자리 잡는 골반 {ok, pelvis, angle}(PoseSolver.find_target, 여러 출발점).
func start_pose() -> Dictionary:
	var att := {}
	for l in start:
		var h := hold(start[l])
		if h.is_empty():
			return {"ok": false, "pelvis": Vector2(0, 0.75), "angle": 0.0}
		att[l] = Vector2(h.x, h.y)
	var cx: float = (att[&"LH"].x + att[&"RH"].x + att[&"LF"].x + att[&"RF"].x) / 4.0
	var fy: float = minf(att[&"LF"].y, att[&"RF"].y)
	var hy: float = minf(att[&"LH"].y, att[&"RH"].y)
	for dy in [0.65, 0.5, 0.8, 0.4, 0.95]:
		for dx in [0.0, -0.15, 0.15]:
			var seed := Vector2(cx + dx, minf(fy + dy, hy - 0.3))
			if not PoseSolver.is_valid(seed, 0.0, att, 0.0):
				continue
			var t := PoseSolver.find_target(seed, 0.0, att, PoseSolver.supporting_feet(seed, 0.0, att, [], 0.0))
			var p := Vector2(t.x, t.y)
			if PoseSolver.is_valid(p, t.z, att, 0.0):
				return {"ok": true, "pelvis": p, "angle": t.z}
	return {"ok": false, "pelvis": Vector2(cx, fy + 0.65), "angle": 0.0}


## 저장·올리기를 막는 것들(문구 목록). 비면 문제 없음.
func problems() -> Array:
	var out: Array = []
	if name.strip_edges() == "":
		out.append(P_NAME)
	if start.values().has(""):
		out.append(P_START)
	if goal_hold().is_empty():
		out.append(P_GOAL)
	if not out.has(P_START) and not out.has(P_GOAL):
		var pose := start_pose()
		var r := build(pose.pelvis, pose.angle)
		if not r.errors.is_empty():
			out.append(P_ROUTE)
		elif not pose.ok or SessionBot.run(r, []).failed_step == SessionBot.START_FAILED:
			out.append(P_POSE)
	if not bad_holds().is_empty():
		out.append(P_SPACING)
	return out


## 간격 규칙(docs/44)을 어기는 홀드 id.
func bad_holds() -> Array:
	var out: Array = []
	if holds.size() < 2:
		return out
	var d := to_route_dict(Vector2(0, 0.75))
	if d.goal_slots.is_empty():
		d.goal_slots = ["x", "y"]  # 탑 없이도 간격은 본다(읽기 오류는 무시)
	var r := RouteDef.from_dict(d)
	for line in HoldSpacing.violations(r):
		for part in String(line).split(" ↔ "):
			var id := part.split(" ")[0]
			if not out.has(id):
				out.append(id)
	return out


## 올리기 조건(§3): 막는 것이 없고 만든 사람이 이 판을 도움 없이 완등(best_seconds가 있음 = 도움 없는 완등).
func can_publish(progress: Progress) -> bool:
	var c: Dictionary = progress.cleared.get(route_id, {})
	return problems().is_empty() and int(c.get("content_version", -1)) == version and c.has("best_seconds")


# ---------- 저장 ----------

func to_dict() -> Dictionary:
	var st := {}
	for l in start:
		st[String(l)] = start[l]
	return {"schema": SCHEMA, "route_id": route_id, "name": name, "grade": grade, "version": version, "holds": holds.duplicate(true), "start": st, "next": _next}


static func from_dict(d: Dictionary) -> RouteDraft:
	var r := RouteDraft.new()
	r.route_id = str(d.get("route_id", ""))
	r.name = str(d.get("name", ""))
	r.grade = str(d.get("grade", "V0"))
	r.version = int(d.get("version", 1))
	r._next = int(d.get("next", 1))
	for h in d.get("holds", []):
		if h is Dictionary and HoldTypes.has(str(h.get("type", ""))):
			r.holds.append({"id": str(h.id), "type": str(h.type), "size": str(h.get("size", "M")), "rot": int(h.get("rot", 0)),
				"x": float(h.x), "y": float(h.y), "matchable": bool(h.get("matchable", false))})
	var st: Dictionary = d.get("start", {})
	for l in r.start:
		r.start[l] = str(st.get(String(l), ""))
	return r
