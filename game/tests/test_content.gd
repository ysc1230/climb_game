extends RefCounted
## 콘텐츠 관문(docs/28 §7.4 4): ContentIndex가 읽은 모든 문제가 ContentCheck를 통과해야 한다.

var runner

## 과정 문제 파일은 아직 없다(Task 9·10에서 만든다). 그동안 목록 오류는 "없는 문제 파일"만 허용한다.
## 과정 문제를 모두 넣으면(Task 10) false로 바꿔 목록 오류 0개를 요구한다.
const ALLOW_MISSING_COURSE_FILES := true


func test_index_errors() -> void:
	var idx := ContentIndex.load_all()
	if ALLOW_MISSING_COURSE_FILES:
		var other := Array(idx.errors).filter(func(e): return not e.contains("없는 문제 파일"))
		runner.check(other.is_empty(), "없는 파일 말고 다른 목록 오류 없음: %s" % [other])
	else:
		runner.check(idx.errors.is_empty(), "목록 오류 없음: %s" % [idx.errors])


func test_every_route_passes_content_check() -> void:
	var idx := ContentIndex.load_all()
	var routes := idx.all_routes()
	runner.check(not routes.is_empty(), "문제가 하나 이상")
	for r in routes:
		var res := ContentCheck.check(r)
		runner.check(res.ok, "%s 검사 통과:\n      %s" % [r.route_id, "\n      ".join(res.lines)])
