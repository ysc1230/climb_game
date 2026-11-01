class_name ContentIndex
extends RefCounted
## docs/28 §8 콘텐츠 목록. 일반 문제(routes/general)·과정 문제(routes/course)·과정 목록(courses.json)을 읽어 조회한다.
## 읽기 실패·없는 파일·문제 데이터 오류는 errors에 남기고 멈추지 않는다.

var errors: PackedStringArray = []
var _routes := {}  # route_id -> RouteDef
var _general := {}  # grade -> Array[RouteDef] (order 순)
var _courses: Array = []  # courses.json 순서 그대로(phase 2 포함)


## 문제 ID 규칙(docs/28 §8.1)으로 파일 경로를 정한다. G_ → general/, C_ → course/, 그 밖(TX_ 시험 루트) → routes/.
static func route_path(route_id: String, root := "res://data") -> String:
	if route_id.begins_with("G_"):
		return "%s/routes/general/%s.json" % [root, route_id]
	if route_id.begins_with("C_"):
		return "%s/routes/course/%s.json" % [root, route_id]
	return "%s/routes/%s.json" % [root, route_id]


static func load_all(root := "res://data") -> ContentIndex:
	var idx := ContentIndex.new()
	idx._load_dir(root + "/routes/general")
	idx._load_dir(root + "/routes/course")
	idx._load_courses(root)
	for g in idx._general:
		idx._general[g].sort_custom(func(a: RouteDef, b: RouteDef): return a.order < b.order or (a.order == b.order and a.route_id < b.route_id))
	return idx


func _load_dir(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	var files := Array(DirAccess.get_files_at(dir)).filter(func(f): return f.ends_with(".json"))
	files.sort()
	for f in files:
		var r := RouteDef.load_json(dir + "/" + f)
		var file_id: String = f.get_basename()
		for e in r.errors:
			errors.append("%s: %s" % [file_id, e])
		if r.route_id == "":
			continue
		if r.route_id != file_id:
			errors.append("%s: 파일 이름과 route_id(%s)가 다름" % [file_id, r.route_id])
		if _routes.has(r.route_id):
			errors.append("%s: 중복 route_id" % r.route_id)
			continue
		_routes[r.route_id] = r
		if r.mode == "general":
			if not _general.has(r.grade):
				_general[r.grade] = [] as Array[RouteDef]
			_general[r.grade].append(r)


func _load_courses(root: String) -> void:
	var path := root + "/courses.json"
	var data = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if typeof(data) != TYPE_DICTIONARY:
		errors.append("과정 목록 읽기 실패: %s" % path)
		return
	for c in data.get("courses", []):
		var course := {
			"course_id": str(c.get("course_id", "")),
			"order": int(c.get("order", 0)),
			"name_ko": str(c.get("name_ko", "")),
			"kind": str(c.get("kind", "")),
			"techniques": c.get("techniques", []).map(func(t): return StringName(t)),
			"tutorial": str(c.get("tutorial", "")),
			"problems": c.get("problems", []).map(func(p): return str(p)),
			"phase": int(c.get("phase", 1)),
		}
		if c.has("text_ko"):
			course.text_ko = c.text_ko
		_courses.append(course)
		var refs: Array = course.problems.duplicate()
		if course.tutorial != "":
			refs.push_front(course.tutorial)
		for id in refs:
			var r: RouteDef = _routes.get(id)
			if r == null:
				errors.append("%s: 없는 문제 파일 %s" % [course.course_id, id])
			elif r.mode != "course" or r.course_id != course.course_id:
				errors.append("%s: %s는 이 과정 문제가 아님(mode %s, course_id %s)" % [course.course_id, id, r.mode, r.course_id])


## 일반 문제가 있는 등급, 숫자 순(V0, V1, …, V10).
func grades() -> Array[String]:
	var out: Array[String] = []
	for g in _general:
		out.append(g)
	out.sort_custom(func(a: String, b: String): return a.substr(1).to_int() < b.substr(1).to_int())
	return out


## 그 등급 일반 문제, order 순.
func general(grade: String) -> Array[RouteDef]:
	var out: Array[RouteDef] = []
	out.assign(_general.get(grade, []))
	return out


## 목록에 보이는 과정(phase 1), courses.json 순서.
func courses() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in _courses:
		if c.phase == 1:
			out.append(c)
	return out


## 과정 하나(phase 2 포함). 없으면 빈 사전.
func course(id: String) -> Dictionary:
	for c in _courses:
		if c.course_id == id:
			return c
	return {}


func route(route_id: String) -> RouteDef:
	return _routes.get(route_id)


## 읽은 모든 문제(일반·과정), route_id 순. 콘텐츠 검사(ContentCheck)용.
func all_routes() -> Array[RouteDef]:
	var ids := _routes.keys()
	ids.sort()
	var out: Array[RouteDef] = []
	for id in ids:
		out.append(_routes[id])
	return out
