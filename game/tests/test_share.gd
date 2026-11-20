extends RefCounted
## 문제 공유(작업 6 §4·§5): 공유 코드, 서버 요청 만들기·응답 해석(가짜 응답), 이름 거친 말, 받은 문제 이름 바꾸기.

var runner


func test_share_code() -> void:
	runner.check(ShareCode.is_valid("AB23CD") and not ShareCode.is_valid("AB0CD1") and not ShareCode.is_valid("ABC"), "6글자, 0/O/1/I 없음")
	runner.check(ShareCode.normalize(" ab23cd ") == "AB23CD", "공백·소문자 정리")
	runner.check(not ShareCode.ALPHABET.contains("O") and not ShareCode.ALPHABET.contains("I") and ShareCode.ALPHABET.length() == 32, "32글자")


func test_requests() -> void:
	var api := ShareApi.new("https://x.supabase.co", "sb_publishable_k")
	var r := api.sign_in()
	runner.check(r.method == HTTPClient.METHOD_POST and r.url == "https://x.supabase.co/auth/v1/signup" and r.headers.has("apikey: sb_publishable_k"), "익명 로그인 %s" % [r])
	runner.check(not Array(r.headers).any(func(x): return x.begins_with("Authorization")), "로그인 전에는 Authorization 없음")
	api.token = "T"
	r = api.publish("U_abc", "문제", "클라이머1", "V3", {"route_id": "U_abc"}, 2, "public")
	var body = JSON.parse_string(r.body)
	runner.check(r.url.ends_with("/rest/v1/rpc/publish_route") and r.headers.has("Authorization: Bearer T") and body.p_version == 2 and body.p_visibility == "public", "올리기 %s" % [r])
	r = api.browse("stars", "V3", 20)
	runner.check(r.method == HTTPClient.METHOD_GET and r.url.contains("order=stars.desc,created_at.desc") and r.url.contains("grade=eq.V3") and r.url.contains("offset=20") and r.url.contains("limit=20"), "둘러보기 %s" % r.url)
	r = api.browse("new", "", 0)
	runner.check(r.url.contains("order=created_at.desc") and not r.url.contains("grade="), "최신·등급 없음 %s" % r.url)
	r = api.by_code("ab23cd")
	runner.check(JSON.parse_string(r.body).p_code == "AB23CD", "코드는 대문자로")


func test_parse() -> void:
	var s := ShareApi.parse_session(200, '{"access_token":"A","refresh_token":"R","expires_in":3600,"user":{"id":"u1"}}')
	runner.check(s.ok and s.token == "A" and s.refresh == "R" and s.user == "u1", "로그인 응답 %s" % [s])
	var p := ShareApi.parse_rows(200, '[{"code":"AB23CD","id":"i1"}]')
	runner.check(p.ok and p.rows[0].code == "AB23CD", "행")
	var e := ShareApi.parse_rows(400, '{"message":"daily limit"}')
	runner.check(not e.ok and e.error == ShareApi.E_LIMIT, "하루 제한 문구 %s" % [e])
	e = ShareApi.parse_rows(0, "")
	runner.check(not e.ok and e.error == ShareApi.E_OFFLINE, "연결 안 됨")
	e = ShareApi.parse_rows(400, '{"message":"clear required"}')
	runner.check(e.error == ShareApi.E_CLEAR, "완등해야 별")


func test_word_filter() -> void:
	runner.check(WordFilter.ok("가는 사선") and not WordFilter.ok("시발 문제") and not WordFilter.ok("FUCK wall"), "거친 말 막기")


## 받은 문제는 route_id를 "S_" + 코드로 바꿔 이 기기의 내 문제와 섞이지 않게 한다(슬롯 키 앞부분도).
func test_shared_rename() -> void:
	var d := RouteDraft.new()
	d.route_id = "U_abcdefghij"
	d.name = "받은 문제"
	var f1 := d.place("foot_chip", -0.15, 0.1)
	var f2 := d.place("foot_chip", 0.18, 0.1)
	var h1 := d.place("jug", -0.3, 1.5)
	var h2 := d.place("jug", 0.3, 1.5)
	d.place("goal", 0.05, 2.1)
	for p in [[&"LH", h1], [&"RH", h2], [&"LF", f1], [&"RF", f2]]:
		d.set_start(p[0], p[1])
	var dict := SharedRoutes.rename(d.to_route_dict(), "AB23CD")
	var r := RouteDef.from_dict(dict)
	runner.check(r.route_id == "S_AB23CD" and r.errors.is_empty() and r.slots.has("S_AB23CD/H03/hand_1"), "이름 바꾼 문제 읽힘 %s" % [r.errors])
	runner.check(SharedRoutes.too_new({"schema": RouteDraft.SCHEMA + 1}) and not SharedRoutes.too_new({"schema": 1}), "더 새 판은 열지 않음")
