class_name SharedRoutes
extends RefCounted
## 받은 공유 문제(작업 6 §4). user://shared_routes/<코드>.json = {meta: 목록 정보, route: 문제 JSON}.
## route_id를 "S_" + 코드로 바꿔 이 기기의 내 문제(U_)와 섞이지 않게 하고, 내 기록(점수·시간)은 이 기기에만 남긴다.

const DIR := "user://shared_routes/"


static func local_id(code: String) -> String:
	return "S_" + code


## 문제 JSON의 route_id와 슬롯 키 앞부분을 "S_코드"로 바꾼 복사본.
static func rename(route: Dictionary, code: String) -> Dictionary:
	var old := str(route.get("route_id", ""))
	var text := JSON.stringify(route)
	if old != "":
		text = text.replace("\"%s\"" % old, "\"%s\"" % local_id(code)).replace("\"%s/" % old, "\"%s/" % local_id(code))
	var d: Dictionary = JSON.parse_string(text)
	d.route_id = local_id(code)
	d.mode = "custom"
	return d


## 앱이 모르는 더 새 판(§6).
static func too_new(route: Dictionary) -> bool:
	return int(route.get("schema", 1)) > RouteDraft.SCHEMA


static func save(code: String, meta: Dictionary, route: Dictionary, dir := DIR) -> bool:
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir + code + ".json", FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"meta": meta, "route": rename(route, code)}))
	f.close()
	return true


static func load_entry(code: String, dir := DIR) -> Dictionary:
	var p := dir + code + ".json"
	if not FileAccess.file_exists(p):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if d is Dictionary else {}


static func load_route(code: String, dir := DIR) -> RouteDef:
	var e := load_entry(code, dir)
	return RouteDef.from_dict(e.route) if e.get("route") is Dictionary else null
