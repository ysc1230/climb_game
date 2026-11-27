class_name RouteDraft
extends RefCounted
## 문제 만들기 초안(작업 6 §2·§3, docs/superpowers/specs/2026-11-19-6-editor-design.md). 노드 없음.
## 홀드 목록·시작 네 자리·탑 하나를 들고, 일반 문제와 같은 JSON(mode "custom")으로 바꾼다.
## 놓기·옮기기는 1cm, 돌리기는 5°에 맞물린다. 되돌리기는 최근 UNDO_MAX단계.

const SCHEMA := 3                 # 공유 문제 JSON 판(§6). 앱이 모르는 더 새 판이면 열지 않는다. 2(0.38): 탑 칸 하나(합손), 발로만 쓰는 손홀드 종류. 3(0.46): 볼륨
const MAX_HOLDS := 300           # 2026-11-25 사용자 "100m로 제한하고 홀드는 300개"
const NAME_MAX := 20
const UNDO_MAX := 30
const WALL_HALF := 1.0            # 벽 폭 2.0m
## 벽 높이는 저장하지 않고 가장 높은 홀드에서 정한다(wall_limit). 벽 끝 위 EXTEND까지 놓을 수 있고, 놓으면 벽이 높아진다
## (2026-11-25 사용자 "벽 제한 높이보다 위에 홀드를 놓으면 높아지도록 하여 용량을 최대한 관리", "100m까지").
const WALL_H_MIN := 4.5
const WALL_H_MAX := 100.0
const EXTEND := 2.0
const Y_MIN := 0.05
const GRADES := ["V0", "V1", "V2", "V3", "V4", "V5", "V6", "V7"]
const P_NAME := "문제 이름을 적어 주세요"
const P_START := "시작 자리(두 손·두 발)를 정해 주세요"
const P_GOAL := "탑 홀드를 놓아 주세요"
const P_SPACING := "빨간 홀드가 다른 홀드와 겹쳐요"
## 간격: 2026-11-26 사용자 "홀드간 거리는 거의 겹치지만 않으면 되도록" — 보이는 타원 가장자리 사이가 이보다 좁을 때만 막는다(일반 문제는 docs/44 그대로).
const MIN_GAP := 0.01
## 벽 각도(오버행, 화면은 180 − 각): 90 천장 … 0 수직 … −120(화면 300°, 2026-11-26 사용자 "90도부터 300도까지").
const WALL_DEG_MIN := -120
const WALL_DEG_MAX := 90
const P_POSE := "시작 자세를 만들 수 없어요(손발이 너무 멀거나 가까워요) — [점검]에서 고칠 곳을 보세요"
const P_ROUTE := "문제 데이터 오류"

var route_id := ""
var name := ""
var grade := "V0"
var version := 1
var holds: Array = []             # [{id, type, size, rot, x, y, matchable, role}] role: "hand" | "foot" | "top"(하나)
var start := {&"LH": "", &"RH": "", &"LF": "", &"RF": ""}  # limb → 홀드 id
## 벽 각도 구간 [{from_y: m, deg}] from_y 오름차순, 첫 구간 0m. deg = 오버행(땅 기준: 0 수직, 90 천장, − 뒤로 누움. 플레이의 wall_sections와 같음),
## 화면에는 180 − deg(2026-11-25 사용자 "최소 단위 1m와 1도, 횟수 제한 없음", 2026-11-26 "90도부터 300도까지 … 땅 기준").
var walls: Array = [{"from_y": 0, "deg": 0}]
## 볼륨 [Volumes.make 사전](2026-11-28): 면에 놓은 홀드는 그 면에 붙고, 모서리는 잡고 딛는 칸이 된다.
var volumes: Array = []
var top_edge := ""                # 탑이 볼륨 모서리면 그 id("V05/edge_t"), 아니면 ""(탑 홀드)
var _next := 1
var _undo: Array = []
var _frozen := false              # 완등·올린 판: 다음 고침에서 판을 올린다
var _pose_key := ""               # start_pose(균형) 결과를 다시 쓰는 열쇠(시작 홀드·벽 각도)
var _spacing_key := ""            # spacing_details 결과를 다시 쓰는 열쇠(홀드 목록)
var _spacing: Array = []
var _layout_key := ""             # layout_route 결과를 다시 쓰는 열쇠
var _layout: RouteDef
var _pose := {}
## 버티는 골반을 찾을 때 옮겨 보는 거리(가까운 것부터, 좌우 0.3m·위아래 0.2m까지)
static var _POSE_OFFSETS: Array = _pose_offsets()


static func _pose_offsets() -> Array:
	var out: Array = []
	for dx in [-0.3, -0.2, -0.1, 0.0, 0.1, 0.2, 0.3]:
		for dy in [-0.2, -0.1, 0.0, 0.1, 0.2]:
			out.append(Vector2(dx, dy))
	out.sort_custom(func(a, b): return a.length() < b.length())
	return out


func hold(id: String) -> Dictionary:
	if id.contains("/"):
		return _volume_slot(id)
	for h in holds:
		if h.id == id:
			return h
	return {}


## 볼륨 모서리·면을 시작 자리·탑으로 쓸 때의 홀드 모양 사전("V05/edge_t", "V06/face"). 저장하지 않고 볼륨에서 만든다.
## role: "edge"(손발, 아래 모서리는 손만 → no_feet) | "face"(발만). 없으면 {}.
func _volume_slot(id: String) -> Dictionary:
	var v := volume(id.get_slice("/", 0))
	if v.is_empty():
		return {}
	var sid := id.get_slice("/", 1)
	for e in Volumes.edges(v):
		if e.slot_id == sid:
			return {"id": id, "type": "volume", "size": v.size, "rot": e.rot, "x": e.pos.x, "y": e.pos.y, "matchable": true, "role": "edge",
				"no_feet": sid == "edge_b"}
	var f := Volumes.face(v)
	if sid == "face" and not f.is_empty():
		return {"id": id, "type": "volume_face", "size": v.size, "rot": 0, "x": f.pos.x, "y": f.pos.y, "matchable": false, "role": "face"}
	return {}


func goal_hold() -> Dictionary:
	if top_edge != "":
		return hold(top_edge)
	for h in holds:
		if h.role == "top":
			return h
	return {}


## 볼륨의 모서리(합손)를 탑으로. 탑은 하나라 탑 홀드가 있으면 지운다. 아래 모서리·면은 안 된다.
func set_top_edge(id: String) -> bool:
	var h := hold(id)
	if h.get("role", "") != "edge" or h.get("no_feet", false):
		return false
	_push()
	holds = holds.filter(func(x): return x.role != "top")
	for l in start:
		if start[l] == id:
			start[l] = ""
	top_edge = id
	return true


## 볼륨이 없어지거나 모양이 바뀌어 사라진 모서리·면은 시작·탑에서 뺀다.
func _drop_dangling() -> void:
	for l in start:
		if String(start[l]).contains("/") and hold(start[l]).is_empty():
			start[l] = ""
	if top_edge != "" and hold(top_edge).is_empty():
		top_edge = ""


## 손 쓰임 홀드인가(손·탑). 발 쓰임도 손으로 잡히지만(2026-11-26) 길 점검(먼 손홀드)은 손 쓰임만 본다.
static func is_hand_hold(h: Dictionary) -> bool:
	return h.get("role", "hand") != "foot"


## 종류가 쓰일 수 있는 쓰임(2026-11-26 사용자 "홀드 종류가 기준이 된 후에 손 발 탑을 선택"): 어느 종류든 손·발
## ("모든 홀드들이 손홀드이자 발홀드": 쓰임은 표시이고 손발 모두 쓴다), 합손 되는 크기가 있으면 탑도. 첫째가 기본 쓰임.
static func roles_for(type: String) -> Array:
	if not HoldTypes.has(type) or type == "goal":
		return []
	var out := ["foot", "hand"] if HoldTypes.is_foot(type) else ["hand", "foot"]
	if HoldTypes.SIZES.any(func(sz): return HoldTypes.can_match(type, sz)):
		out.append("top")
	return out


## 탑은 두 손으로 잡아 끝나므로 합손 되는 크기만(사용자 고름). size가 안 되면 되는 가장 작은 크기.
static func top_size(type: String, size: String) -> String:
	if HoldTypes.can_match(type, size):
		return size
	for sz in HoldTypes.SIZES:
		if HoldTypes.can_match(type, sz):
			return sz
	return size


## 종류 type을 쓰임 role(비우면 종류대로 손·발)로 (x, y)에 놓는다. 탑은 하나라 이미 있으면 그 탑을 옮기고 종류를 바꾼다.
## "goal"은 0.37까지의 탑 이름: 큰 저그 탑. 반환: 홀드 id, 못 놓으면 "".
func place(type: String, x: float, y: float, role := "", size := "M", rot := 0) -> String:
	if type == "volume":
		return ""  # 볼륨 모서리는 볼륨이 만든다(place_volume)
	if type == "goal":
		type = "jug"
		role = "top"
		size = "L"
	if role == "":
		role = roles_for(type)[0] if HoldTypes.has(type) else "hand"
	if not roles_for(type).has(role):
		return ""
	if role == "top":
		size = top_size(type, size)
		if top_edge != "":  # 탑 홀드를 놓으면 모서리 탑은 풀린다(탑은 하나)
			_push()
			top_edge = ""
		var g := goal_hold()
		if not g.is_empty():
			_push()
			g.type = type
			g.size = size
			g.x = _sx(x)
			g.y = _sy(y)
			return g.id
	if holds.size() >= MAX_HOLDS:
		return ""
	_push()
	var id := "G01" if role == "top" else "%s%02d" % ["F" if role == "foot" else "H", _next]
	if role != "top":
		_next += 1
	holds.append({"id": id, "type": type, "size": size, "rot": _snap_rot(rot), "x": _sx(x), "y": _sy(y), "matchable": role == "top", "role": role})
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
	if h.is_empty():
		return
	_push()
	h.rot = _snap_rot(deg)


## 크기를 바꾼다. 그 크기에서 합손이 안 되면 합손을 끈다. 탑은 합손 되는 크기로만.
func set_size(id: String, size: String) -> void:
	var h := hold(id)
	if h.is_empty() or not HoldTypes.SIZES.has(size) or (h.role == "top" and not HoldTypes.can_match(h.type, size)):
		return
	_push()
	h.size = size
	h.matchable = h.matchable and HoldTypes.can_match(h.type, size)


## 합손 켜기·끄기: 탑이 아니고 그 종류·크기가 될 때만 켠다(탑은 늘 합손).
func set_matchable(id: String, on: bool) -> void:
	var h := hold(id)
	if h.is_empty() or h.role == "top" or (on and not HoldTypes.can_match(h.type, h.size)):
		return
	_push()
	h.matchable = on


## 가장 높은 홀드 높이(없으면 0).
func top_y() -> float:
	return holds.reduce(func(m, h): return maxf(m, h.y), 0.0)


## 지금 벽 높이(m): 가장 높은 홀드 위 1m를 미터로 올림, 4.5~100.
func wall_limit() -> float:
	return clampf(ceilf(top_y()) + 1.0, WALL_H_MIN, WALL_H_MAX)


## 홀드를 놓을 수 있는 가장 높은 곳.
func max_y() -> float:
	return minf(wall_limit() + EXTEND, WALL_H_MAX)


## from_y m부터 위로 벽 각도(오버행 deg, 0~90). 아래와 같은 각이 돼도 경계는 남긴다(다이얼을 끄는 중 이웃 경계가 사라지지 않게).
func set_wall(from_y: int, deg: int, push := true) -> void:
	from_y = clampi(from_y, 0, int(WALL_H_MAX) - 1)
	deg = clampi(deg, WALL_DEG_MIN, WALL_DEG_MAX)
	if push:
		_push()
	var i := 0
	while i < walls.size() and int(walls[i].from_y) < from_y:
		i += 1
	if i < walls.size() and int(walls[i].from_y) == from_y:
		walls[i].deg = deg
	else:
		walls.insert(i, {"from_y": from_y, "deg": deg})


## from_y m의 경계를 지운다(아래 구간이 이어짐). 0m는 지우지 않는다.
func remove_wall(from_y: int) -> void:
	for i in range(1, walls.size()):
		if int(walls[i].from_y) == from_y:
			_push()
			walls.remove_at(i)
			return


## 높이 y가 속한 구간의 각도(섞기 없이).
func wall_deg_at(y: float) -> int:
	var a := 0
	for w in walls:
		if float(w.from_y) <= y:
			a = int(w.deg)
	return a


func remove(id: String) -> void:
	var i := holds.find(hold(id))
	if i < 0:
		return
	_push()
	holds.remove_at(i)
	for l in start:
		if start[l] == id:
			start[l] = ""


## 시작 자리. 손발 모두 탑이 아닌 아무 홀드(2026-11-26 "모든 홀드들이 손홀드이자 발홀드"). 같은 홀드를 다른 손발이 쓰고 있었으면 그쪽을 비운다.
func set_start(limb: StringName, id: String) -> bool:
	var h := hold(id)
	if h.is_empty() or h.role == "top" or id == top_edge:
		return false
	var hand := PoseSolver.is_hand(limb)
	if (hand and h.role == "face") or (not hand and h.get("no_feet", false)):
		return false  # 볼륨 면은 발만, 아래 모서리는 손만
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
	return {"holds": holds.duplicate(true), "start": start.duplicate(), "next": _next, "walls": walls.duplicate(true), "volumes": volumes.duplicate(true), "top_edge": top_edge}


func _load_state(s: Dictionary) -> void:
	holds = s.holds
	start = s.start
	_next = s.next
	walls = s.walls
	volumes = s.get("volumes", [])
	top_edge = s.get("top_edge", "")


# ---------- 볼륨 ----------

func volume(id: String) -> Dictionary:
	for v in volumes:
		if v.id == id:
			return v
	return {}


## 볼륨을 (x, y)에 놓는다(바닥이 벽 안에 들게 가운데를 옮김). 반환: id, 못 놓으면 "".
func place_volume(shape: String, x: float, y: float, size := "M", rot := 0) -> String:
	if volumes.size() >= Volumes.MAX:
		return ""
	_push()
	var v := Volumes.make("V%02d" % _next, shape, x, y, size, rot)
	_next += 1
	_clamp_volume(v)
	volumes.append(v)
	return v.id


## 볼륨을 옮긴다. 그 면에 붙은 홀드(바닥 안의 홀드)도 같이 옮긴다(2026-11-28: 볼륨만 옮기면 홀드가 허공에 남는다).
func move_volume(id: String, x: float, y: float) -> void:
	var v := volume(id)
	if v.is_empty():
		return
	_push()
	var on := holds.filter(func(h): return Volumes.contains(v, Vector2(h.x, h.y)))
	var before := Volumes.center(v)
	v.x = x
	v.y = y
	_clamp_volume(v)
	var dv := Volumes.center(v) - before
	for h in on:
		h.x = _sx(h.x + dv.x)
		h.y = _sy(h.y + dv.y)


## 모양·크기·방향을 바꾼다(가운데 그대로, 벽 밖으로 나가면 안으로).
func set_volume(id: String, shape: String, size: String, rot: int) -> void:
	var v := volume(id)
	if v.is_empty():
		return
	_push()
	var n := Volumes.make(id, shape, v.x, v.y, size, rot)
	for k in n:
		v[k] = n[k]
	_clamp_volume(v)
	_drop_dangling()


func remove_volume(id: String) -> void:
	var v := volume(id)
	if v.is_empty():
		return
	_push()
	volumes.erase(v)
	_drop_dangling()


func _clamp_volume(v: Dictionary) -> void:
	var h := Volumes.side(v) * 0.5
	v.x = snappedf(clampf(float(v.x), -WALL_HALF + h, WALL_HALF - h), 0.01)
	v.y = snappedf(clampf(float(v.y), Y_MIN + h, maxf(Y_MIN + h, max_y() - h)), 0.01)


static func _sx(x: float) -> float:
	return snappedf(clampf(x, -WALL_HALF, WALL_HALF), 0.01)


func _sy(y: float) -> float:
	return snappedf(clampf(y, Y_MIN, max_y()), 0.01)


static func _snap_rot(deg: int) -> int:
	return posmod(int(round(deg / 5.0)) * 5, 360)


# ---------- 문제 JSON ----------

func _key(h: Dictionary) -> String:
	if h.get("role", "") in ["edge", "face"]:
		return "%s/%s" % [route_id, h.id]
	return "%s/%s/%s" % [route_id, h.id, "foot_1" if h.role == "foot" else "hand_1"]


## 일반 문제와 같은 형식(mode "custom", schema). pelvis: 시작 골반(비우면 start_pose()로 계산).
func to_route_dict(pelvis := Vector2.INF, angle := 0.0) -> Dictionary:
	var hs: Array = []
	var goal_slots: Array = []
	for h in holds:
		var foot: bool = h.role == "foot"
		# 손발 모두 쓴다(발은 RouteDef가 손 칸에 더함). 발 쓰임은 칸 이름만 foot_1
		var s := {"slot_id": "foot_1" if foot else "hand_1", "pos": [h.x, h.y], "allowed": ["LH", "RH"],
			"hold_type": h.type, "size": h.size, "rot_deg": h.rot}
		if h.role == "top":  # 탑 하나: 두 손이 같은 칸을 잡으면 완등(합손 칸)
			goal_slots.append(_key(h))
		if h.matchable:
			s["hand_area"] = {"matchable": true}
		hs.append({"hold_id": h.id, "slots": [s]})
	if top_edge != "" and not hold(top_edge).is_empty():
		goal_slots.append(_key(hold(top_edge)))
	for v in volumes:  # 볼륨 모서리: 손발이 잡고 딛는 칸(합손)
		var es: Array = []
		for e in Volumes.edges(v):
			es.append({"slot_id": e.slot_id, "pos": [snappedf(e.pos.x, 0.001), snappedf(e.pos.y, 0.001)], "allowed": ["LH", "RH"],
				"hold_type": "volume", "size": v.size, "rot_deg": e.rot, "hand_area": {"matchable": true}, "no_feet": e.slot_id == "edge_b"})
		var fc := Volumes.face(v)
		if not fc.is_empty():  # 위를 보는 면: 발 비비기(발만)
			es.append({"slot_id": "face", "pos": [snappedf(fc.pos.x, 0.001), snappedf(fc.pos.y, 0.001)], "allowed": ["LF", "RF"],
				"hold_type": "volume_face", "size": v.size, "rot_deg": 0})
		hs.append({"hold_id": v.id, "slots": es})
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
		"bounds": {"x_min": -1.5, "x_max": 1.5, "y_min": 0.0, "y_max": wall_limit()}, "fail_line_y": -0.5,
		"check_swapped": false, "time_medal_seconds": 120, "goal_slots": goal_slots, "platforms": [],
		"start_pose": {"angle": angle, "pelvis": [snappedf(pelvis.x, 0.001), snappedf(pelvis.y, 0.001)], "slots": st},
		"intended_moves": [], "required_techniques": [], "crux_steps": {}, "holds": hs,
		"wall_sections": _wall_sections(), "volumes": volumes.duplicate(true),
	}
	# 두 시작 발이 바닥 가까이(발판 높이 ≤ 0.15m)면 바닥 받침(일반 문제의 시작 발판과 같음)
	var lf := hold(start[&"LF"])
	var rf := hold(start[&"RF"])
	if not lf.is_empty() and not rf.is_empty() and lf.role == "foot" and rf.role == "foot" and lf.y <= 0.15 and rf.y <= 0.15:
		d.platforms = [{"platform_id": "P00", "foot_slot_keys": [_key(lf), _key(rf)], "top_y": 0.1,
			"x_range": [snappedf(minf(lf.x, rf.x) - 0.35, 0.01), snappedf(maxf(lf.x, rf.x) + 0.35, 0.01)]}]
	return d


## 플레이의 꺾이는 벽 구간: 아래와 같은 각의 경계는 합친다.
func _wall_sections() -> Array:
	var out: Array = []
	for w in walls:
		if out.is_empty() or out[-1].deg != float(w.deg):
			out.append({"from_y": float(w.from_y), "deg": float(w.deg)})
	return out


func build(pelvis := Vector2.INF, angle := 0.0) -> RouteDef:
	return RouteDef.from_dict(to_route_dict(pelvis, angle))


## 3D 미리보기·간격·막는 것이 같이 쓰는 문제(골반 (0, 0.75), 읽기 오류는 골반과 무관). 홀드·시작·벽이 그대로면 지난 것을 쓴다
## (홀드 300개면 한 번 읽는 데 약 5ms, 고칠 때마다 세 번 읽던 것을 한 번으로, 2026-11-26 최적화). 받은 쪽은 고치지 않는다.
func layout_route() -> RouteDef:
	var key := str([holds, start, walls, route_id, name, grade, volumes, top_edge])
	if key != _layout_key:
		_layout_key = key
		_layout = build(Vector2(0, 0.75))
	return _layout


## 시작 네 자리에서 몸이 자리 잡는 골반 {ok, pelvis, angle, balanced}(PoseSolver.find_target, 여러 출발점).
## balance: 그 골반에서 실제로 버티는지(SessionBot.start_ok)도 보고, 안 되면 골반을 가까운 곳부터 옮겨 버티는 자리를 찾는다
## (2026-11-26 사용자 "무게중심 때문에 시작 홀드 설정이 안 되는 경우가 있는데 여유롭게": 450가지 배치에서 못 버틴 85개가 모두 0.3m 안에 버티는 자리가 있었다).
## 시작 홀드·벽 각도가 같으면 지난 결과를 쓴다.
func start_pose(balance := true) -> Dictionary:
	var att := {}
	for l in start:
		var h := hold(start[l])
		if h.is_empty():
			return {"ok": false, "pelvis": Vector2(0, 0.75), "angle": 0.0, "balanced": false}
		att[l] = Vector2(h.x, h.y)
	var key := str([att, walls]) if balance else ""
	if balance and key == _pose_key:
		return _pose.duplicate()
	var pose := _geometric_pose(att)
	if balance:
		pose.balanced = false
		if pose.ok:
			for o in _POSE_OFFSETS:
				var q: Vector2 = pose.pelvis + o
				if SessionBot.start_ok(build(q, pose.angle if o == Vector2.ZERO else 0.0)):
					pose.pelvis = q
					pose.angle = pose.angle if o == Vector2.ZERO else 0.0
					pose.balanced = true
					break
		_pose_key = key
		_pose = pose.duplicate()
	return pose


func _geometric_pose(att: Dictionary) -> Dictionary:
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
		if Array(layout_route().errors).any(func(e): return not String(e).begins_with("name_ko")):  # 이름은 P_NAME이 알린다(둘 다 뜨면 헷갈림)
			out.append(P_ROUTE)
		elif not start_pose().balanced:
			out.append(P_POSE)
	if not bad_holds().is_empty():
		out.append(P_SPACING)
	var wi := wall_issue()
	if not wi.is_empty():
		out.append(wi.text)
	for vi in volume_issues():
		if not out.has(vi.text):
			out.append(vi.text)
	return out


const HOLD_EDGE := 0.06  # 홀드 중심이 볼륨 모서리에서 이보다 가까우면 반쯤 걸친다(면에도 벽에도 안 붙음)


## 볼륨 배치의 막는 것 [{text, y, volume?, hold?}](2026-11-28 트집 잡힐 배치): 볼륨끼리 겹침, 벽이 꺾이는 곳(각도 경계)에 걸침,
## 홀드가 볼륨 모서리에 반쯤 걸침.
func volume_issues() -> Array:
	var out: Array = []
	for i in volumes.size():
		var v: Dictionary = volumes[i]
		var c := Volumes.center(v)
		var h := Volumes.side(v) * 0.5
		for j in range(i + 1, volumes.size()):
			var w: Dictionary = volumes[j]
			var dd := (Volumes.center(w) - c).abs()
			var hw := h + Volumes.side(w) * 0.5
			if dd.x < hw - 0.005 and dd.y < hw - 0.005:
				out.append({"text": "볼륨 둘이 %.1fm에서 겹쳐요. 떼어 놓으세요" % c.y, "y": c.y, "volume": v.id})
		for k in range(1, walls.size()):
			var fy := float(walls[k].from_y)
			if fy > c.y - h + 0.005 and fy < c.y + h - 0.005 and int(walls[k].deg) != int(walls[k - 1].deg):
				out.append({"text": "볼륨이 벽이 꺾이는 곳(%dm)에 걸쳐요. 위나 아래로 옮기세요" % int(fy), "y": c.y, "volume": v.id})
				break
		for hd in holds:
			var d := (Vector2(hd.x, hd.y) - c).abs()
			var inside := d.x <= h + HOLD_EDGE and d.y <= h + HOLD_EDGE
			var clear_in := d.x <= h - HOLD_EDGE and d.y <= h - HOLD_EDGE
			if inside and not clear_in:
				out.append({"text": "%s가 볼륨 모서리에 걸쳐요. 볼륨 면 안쪽이나 바깥으로 옮기세요" % HoldTypes.name_ko(hd.type), "y": hd.y, "hold": hd.id})
	return out


const LOW_ROOF_DEG := 75   # 이보다 기운(화면 105° 이하) 구간은 천장: 바닥에서 LOW_ROOF_Y 넘게 떠야 매달린다
const LOW_ROOF_Y := 0.9


## 만들 수 없는 벽 모양 {text, y(그 구간 높이)}, 없으면 {}(2026-11-27 벽 모양 점검: 1m마다 각도를 이으면 생긴다).
## 구간마다 곧은 벽이라 꺾이는 점만 본다(월드 y, z = 벽면 선 ∫(cos a, sin a), 화면 WallProfile과 같음).
## 바닥 밑으로 내려감(270°보다 더 꺾인 구간이 길 때), 바닥에 붙은 천장, 이웃하지 않은 구간끼리 가로지름.
func wall_issue() -> Dictionary:
	var top := wall_limit()
	var secs := walls.filter(func(w): return float(w.from_y) < top)
	if secs.is_empty():
		return {}
	var pts: Array = [Vector2.ZERO]  # (월드 y, z), 구간 경계마다
	var froms: Array = []
	for i in secs.size():
		var s0: float = 0.0 if i == 0 else float(secs[i].from_y)
		var s1: float = float(secs[i + 1].from_y) if i + 1 < secs.size() else top
		var a := deg_to_rad(float(secs[i].deg))
		pts.append(pts[-1] + Vector2(cos(a), sin(a)) * (s1 - s0))
		froms.append(int(s0))
		var deg := int(secs[i].deg)
		if pts[-1].x < -0.01:
			return {"text": "벽이 %dm 구간(%d°)에서 바닥 밑으로 내려가요. 270°보다 더 꺾인 구간을 줄여 주세요" % [froms[i], 180 - deg], "y": float(froms[i])}
		if deg >= LOW_ROOF_DEG and minf(pts[-2].x, pts[-1].x) < LOW_ROOF_Y:
			return {"text": "%dm 구간 천장(%d°)이 바닥에서 너무 낮아요. 벽을 %.1fm 넘게 올린 뒤에 천장을 만들어 주세요" % [froms[i], 180 - deg, LOW_ROOF_Y], "y": float(froms[i])}
	for i in pts.size() - 1:
		for j in range(i + 2, pts.size() - 1):
			if _seg_cross(pts[i], pts[i + 1], pts[j], pts[j + 1]):
				return {"text": "벽의 %dm 구간과 %dm 구간이 서로 겹쳐요. 꺾인 각도를 줄여 주세요" % [froms[i], froms[j]], "y": float(froms[j])}
	return {}


static func _seg_cross(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var d1 := (b - a).cross(c - a)
	var d2 := (b - a).cross(d - a)
	var d3 := (d - c).cross(a - c)
	var d4 := (d - c).cross(b - c)
	return d1 * d2 < -1e-9 and d3 * d4 < -1e-9


## 시작 자세가 안 될 때 고칠 곳(2026-11-25 사용자 "얼마나 가까워야 하는지 모르겠어"): 시작 홀드 하나를 8방향으로 0.1m씩(0.6m까지)
## 옮겨 보며 시작 자세(start_pose)가 되는 가장 작은 이동을 찾는다. {limb, hold, move(m), text}. 이미 되거나 못 찾으면 {}.
## 점검 창을 열 때만 부른다(최대 192번 자세 계산, 약 0.2초).
func start_fix() -> Dictionary:
	if start.values().has("") or start_pose(false).ok:
		return {}
	var dirs := [[Vector2(0, -1), "아래로"], [Vector2(0, 1), "위로"], [Vector2(-1, 0), "왼쪽으로"], [Vector2(1, 0), "오른쪽으로"],
		[Vector2(-1, -1), "왼쪽 아래로"], [Vector2(1, -1), "오른쪽 아래로"], [Vector2(-1, 1), "왼쪽 위로"], [Vector2(1, 1), "오른쪽 위로"]]
	const NAMES := {&"LH": "왼손", &"RH": "오른손", &"LF": "왼발", &"RF": "오른발"}
	for step in range(1, 7):
		for limb in [&"LF", &"RF", &"LH", &"RH"]:
			var h := hold(start[limb])
			var x0: float = h.x
			var y0: float = h.y
			for dv in dirs:
				var mv: Vector2 = (dv[0] as Vector2).normalized() * step * 0.1
				h.x = _sx(x0 + mv.x)
				h.y = _sy(y0 + mv.y)
				var ok: bool = start_pose(false).ok
				h.x = x0
				h.y = y0
				if ok:
					return {"limb": limb, "hold": h.id, "move": mv, "text": "%s 홀드를 %s %.1fm 옮기면 시작 자세가 돼요" % [NAMES[limb], dv[1], step * 0.1]}
	return {}


const FAR_HAND := 1.2   # 아래 손홀드에서 이보다 먼 손홀드는 닿기 어렵다(두 팔 다 뻗어도 손 사이 약 1.75m, 기존 문제는 0.5~0.6m)
const ROOF_DEG := 70    # 이보다 기운(화면 110° 이하) 구간은 발 딛기가 어렵다


## 만들 수는 있지만 문제가 있을 수 있는 것 [{text, hold, y}](점검 창). 가벼운 계산만(고칠 때마다 센다).
func warnings() -> Array:
	var out: Array = []
	var hands := holds.filter(func(h): return is_hand_hold(h))
	hands.sort_custom(func(a, b): return a.y < b.y)  # 높이 순: 1.2m 안 아래 홀드만 본다(홀드 300개면 모든 쌍 9만, 2026-11-26 최적화)
	var base := -INF
	for l in [&"LH", &"RH"]:
		if start[l] != "":
			base = maxf(base, hold(start[l]).y)
	for i in hands.size():
		var h: Dictionary = hands[i]
		if h.y <= base + 0.01:
			continue
		var near := false
		var j := i - 1
		while j >= 0 and h.y - hands[j].y <= FAR_HAND:
			if hands[j].y < h.y - 0.01 and Vector2(hands[j].x, hands[j].y).distance_to(Vector2(h.x, h.y)) <= FAR_HAND:
				near = true
				break
			j -= 1
		if near:
			continue
		var best := INF
		for o in hands:
			if o.y < h.y - 0.01:
				best = minf(best, Vector2(o.x, o.y).distance_to(Vector2(h.x, h.y)))
		if best > FAR_HAND and best < INF:
			var tip := " 합손 홀드라 다이노로는 닿을 수 있어요." if h.get("matchable", false) else ""
			out.append({"text": "%s(%.1fm)가 아래 손으로 잡는 홀드에서 %.1fm 떨어져 닿기 어려워요(%.1fm 안이 좋아요).%s" % [HoldTypes.name_ko(h.type), h.y, best, FAR_HAND, tip], "hold": h.id, "y": h.y})
	for w in walls:
		if int(w.deg) >= ROOF_DEG and float(w.from_y) < wall_limit():
			out.append({"text": "%dm부터 %d°: 천장에 가까워 발을 딛기 어려워요(토훅·힐훅은 아직 없어요)." % [int(w.from_y), 180 - int(w.deg)], "hold": "", "y": float(w.from_y)})
	var g := goal_hold()
	if not g.is_empty():
		var above := holds.filter(func(h): return h.role != "top" and h.y > g.y + 0.3)
		if not above.is_empty():
			out.append({"text": "탑보다 높은 홀드 %d개는 쓰이지 않아요." % above.size(), "hold": above[0].id, "y": above[0].y})
	if wall_limit() > 20.0:
		out.append({"text": "벽이 20m 넘게 높아요. [봇으로 확인](5초)이 끝까지 못 볼 수 있어요.", "hold": "", "y": -1.0})
	return out


## 간격 규칙을 어기는(겹친) 홀드 쌍 [{hold, other, text}](점검 창). 홀드가 그대로면 지난 결과를 쓴다(고칠 때마다 막는 것·빨간 홀드가 두 번 부름).
func spacing_details() -> Array:
	var key := str(holds)
	if key == _spacing_key:
		return _spacing
	_spacing_key = key
	_spacing = _spacing_of()
	return _spacing


func _spacing_of() -> Array:
	var out: Array = []
	if holds.size() < 2:
		return out
	var r := layout_route()  # 탑이 없어 읽기 오류가 있어도 홀드 칸은 읽힌다
	for line in HoldSpacing.violations(r, 0.0, MIN_GAP):
		var p := String(line).split(" ")  # "H03 ↔ H05 간격 0.050m < 0.120m"
		var a := hold(p[0])
		var b := hold(p[2])
		if a.is_empty() or b.is_empty():
			continue
		out.append({"hold": p[0], "other": p[2], "text": "%s·%s가 겹쳐 있어요. 조금 떼어 놓으세요." % [HoldTypes.name_ko(a.type), HoldTypes.name_ko(b.type)]})
	return out


## 간격 규칙(docs/44)을 어기는 홀드 id.
func bad_holds() -> Array:
	var out: Array = []
	for v in spacing_details():
		for id in [v.hold, v.other]:
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
	return {"schema": SCHEMA, "route_id": route_id, "name": name, "grade": grade, "version": version, "holds": holds.duplicate(true), "start": st, "next": _next,
		"walls": walls.duplicate(true), "volumes": volumes.duplicate(true), "top_edge": top_edge}


static func from_dict(d: Dictionary) -> RouteDraft:
	var r := RouteDraft.new()
	r.route_id = str(d.get("route_id", ""))
	r.name = str(d.get("name", ""))
	r.grade = str(d.get("grade", "V0"))
	r.version = int(d.get("version", 1))
	r._next = int(d.get("next", 1))
	for h in d.get("holds", []):
		if not (h is Dictionary and HoldTypes.has(str(h.get("type", "")))):
			continue
		var t := str(h.type)
		var size := str(h.get("size", "M"))
		var role := str(h.get("role", "foot" if HoldTypes.is_foot(t) else "hand"))
		if t == "goal":  # 0.37까지의 탑
			t = "jug"
			size = "L"
			role = "top"
		if not roles_for(t).has(role):
			role = roles_for(t)[0]
		if role == "top":
			size = top_size(t, size)
		var m := role == "top" or (bool(h.get("matchable", false)) and HoldTypes.can_match(t, size))
		r.holds.append({"id": str(h.id), "type": t, "size": size, "rot": int(h.get("rot", 0)), "x": float(h.x), "y": float(h.y), "matchable": m, "role": role})
	# 벽 각도 탭 전(0.27까지)의 초안은 등급이 각도를 정했다: 그 각도 한 구간으로
	r.walls = [{"from_y": 0, "deg": int(GradeInfo.wall_deg(r.grade))}]
	if d.get("walls") is Array and not d.walls.is_empty():
		r.walls = []
		for w in d.walls:
			r.walls.append({"from_y": int(w.get("from_y", 0)), "deg": clampi(int(w.get("deg", 0)), WALL_DEG_MIN, WALL_DEG_MAX)})
		r.walls.sort_custom(func(a, b): return a.from_y < b.from_y)
		r.walls[0].from_y = 0
	for v in d.get("volumes", []):
		if v is Dictionary and r.volumes.size() < Volumes.MAX:
			r.volumes.append(Volumes.make(str(v.get("id", "V%02d" % (r.volumes.size() + 90))), str(v.get("shape", "box")), float(v.get("x", 0.0)), float(v.get("y", 1.0)), str(v.get("size", "M")), int(v.get("rot", 0))))
	r.top_edge = str(d.get("top_edge", ""))
	var st: Dictionary = d.get("start", {})
	for l in r.start:
		r.start[l] = str(st.get(String(l), ""))
	r._drop_dangling()
	return r
