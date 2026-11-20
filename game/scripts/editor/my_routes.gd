class_name MyRoutes
extends RefCounted
## 이 기기에 저장한 내 문제(작업 6 §3). 파일 하나에 {draft: RouteDraft.to_dict(), route: 문제 JSON, saved_at}.
## 인터넷 없이 저장·플레이된다. route_id는 "U_" + 10글자(기기에서 만든 고유값). 노드 없음.

const DIR := "user://my_routes/"
const ID_CHARS := "23456789abcdefghjkmnpqrstuvwxyz"


static func new_id() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var s := "U_"
	for i in 10:
		s += ID_CHARS[rng.randi_range(0, ID_CHARS.length() - 1)]
	return s


static func path(route_id: String, dir := DIR) -> String:
	return dir + route_id + ".json"


static func save(d: RouteDraft, dir := DIR) -> bool:
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path(d.route_id, dir), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"draft": d.to_dict(), "route": d.to_route_dict(), "saved_at": Time.get_unix_time_from_system()}))
	f.close()
	return true


static func _read(route_id: String, dir: String) -> Dictionary:
	var p := path(route_id, dir)
	if not FileAccess.file_exists(p):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if d is Dictionary else {}


static func load_draft(route_id: String, dir := DIR) -> RouteDraft:
	var d := _read(route_id, dir)
	return RouteDraft.from_dict(d.draft) if d.get("draft") is Dictionary else null


static func load_route(route_id: String, dir := DIR) -> RouteDef:
	var d := _read(route_id, dir)
	return RouteDef.from_dict(d.route) if d.get("route") is Dictionary else null


## [{route_id, name, grade, version, saved_at}], 최근 저장 순.
static func list(dir := DIR) -> Array:
	var out: Array = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".json"):
			continue
		var d := _read(f.get_basename(), dir)
		if not d.get("draft") is Dictionary:
			continue
		var dr: Dictionary = d.draft
		out.append({"route_id": str(dr.get("route_id", "")), "name": str(dr.get("name", "")), "grade": str(dr.get("grade", "V0")),
			"version": int(dr.get("version", 1)), "saved_at": float(d.get("saved_at", 0.0))})
	out.sort_custom(func(a, b): return a.saved_at > b.saved_at)
	return out


static func remove(route_id: String, dir := DIR) -> bool:
	return DirAccess.remove_absolute(path(route_id, dir)) == OK
