class_name ShareApi
extends RefCounted
## Supabase 공유 서버 요청 만들기·응답 해석(작업 6 §5). 네트워크는 하지 않는다(ShareClient가 보냄) — 그래서 가짜 응답으로 시험한다.
## 인증은 익명 로그인(/auth/v1/signup), 쓰기는 모두 RPC 함수(server/supabase/migrations). 앱에는 공개 키만 넣는다.

const E_OFFLINE := "서버에 연결하지 못했어요. 잠시 뒤 다시 해 주세요"
const E_LIMIT := "하루에 20번까지 올릴 수 있어요"
const E_CLEAR := "완등한 문제에만 별을 줄 수 있어요"
const E_LOGIN := "로그인이 끊겼어요. 다시 해 주세요"
const E_SERVER := "서버 오류가 났어요"
const PAGE := 20
const LIST_COLS := "id,code,name,grade,author_name,stars,clears,version,updated_at"

var url := ""
var key := ""
var token := ""


func _init(p_url := "", p_key := "") -> void:
	url = p_url.trim_suffix("/")
	key = p_key


func _headers(auth := true) -> PackedStringArray:
	var h := PackedStringArray(["apikey: " + key, "Content-Type: application/json"])
	if auth and token != "":  # 공개 키(sb_publishable_…)는 JWT가 아니라 Authorization에 넣지 않는다
		h.append("Authorization: Bearer " + token)
	return h


func _req(method: int, path: String, body: Variant = null, auth := true) -> Dictionary:
	return {"method": method, "url": url + path, "headers": _headers(auth), "body": JSON.stringify(body) if body != null else ""}


func _rpc(fn: String, args: Dictionary) -> Dictionary:
	return _req(HTTPClient.METHOD_POST, "/rest/v1/rpc/" + fn, args)


func sign_in() -> Dictionary:
	return _req(HTTPClient.METHOD_POST, "/auth/v1/signup", {}, false)


func refresh(refresh_token: String) -> Dictionary:
	return _req(HTTPClient.METHOD_POST, "/auth/v1/token?grant_type=refresh_token", {"refresh_token": refresh_token}, false)


func publish(local_id: String, name: String, author_name: String, grade: String, data: Dictionary, version: int, visibility: String) -> Dictionary:
	return _rpc("publish_route", {"p_local_id": local_id, "p_name": name, "p_author_name": author_name, "p_grade": grade,
		"p_data": data, "p_version": version, "p_visibility": visibility})


func by_code(code: String) -> Dictionary:
	return _rpc("get_route_by_code", {"p_code": ShareCode.normalize(code)})


## 공개 목록 한 쪽. sort: "stars" 별 많은 순 / "new" 최신. grade: "" 전체.
func browse(sort: String, grade: String, offset: int) -> Dictionary:
	var q := "/rest/v1/routes?select=%s&order=%s&limit=%d&offset=%d" % [LIST_COLS, "stars.desc,created_at.desc" if sort == "stars" else "created_at.desc", PAGE, offset]
	if grade != "":
		q += "&grade=eq." + grade
	return _req(HTTPClient.METHOD_GET, q)


func record_clear(route_uuid: String, version: int) -> Dictionary:
	return _rpc("record_clear", {"p_route": route_uuid, "p_version": version})


func set_star(route_uuid: String, on: bool) -> Dictionary:
	return _rpc("set_star", {"p_route": route_uuid, "p_on": on})


func report(route_uuid: String, reason: String) -> Dictionary:
	return _rpc("report_route", {"p_route": route_uuid, "p_reason": reason})


func my_stars() -> Dictionary:
	return _req(HTTPClient.METHOD_GET, "/rest/v1/stars?select=route_id")


## 로그인 응답 → {ok, token, refresh, user, expires_at} 또는 {ok: false, error}.
static func parse_session(code: int, body: String) -> Dictionary:
	if code == 0:
		return {"ok": false, "error": E_OFFLINE}
	var d = JSON.parse_string(body) if body != "" else null
	if code >= 300 or not d is Dictionary or not d.has("access_token"):
		return {"ok": false, "error": E_SERVER}
	return {"ok": true, "token": str(d.access_token), "refresh": str(d.get("refresh_token", "")),
		"user": str(d.get("user", {}).get("id", "")), "expires_at": Time.get_unix_time_from_system() + float(d.get("expires_in", 3600))}


## 표·RPC 응답 → {ok, rows: Array} 또는 {ok: false, error}(사람이 읽는 문구). 하나만 돌려주는 RPC도 배열로 맞춘다.
static func parse_rows(code: int, body: String) -> Dictionary:
	if code == 0:
		return {"ok": false, "error": E_OFFLINE}
	var d = JSON.parse_string(body) if body != "" else null
	if code >= 300:
		var msg := str(d.get("message", "")) if d is Dictionary else ""
		var e := E_SERVER
		if msg.contains("daily limit"):
			e = E_LIMIT
		elif msg.contains("clear required"):
			e = E_CLEAR
		elif code == 401 or msg.contains("JWT") or msg.contains("login required"):
			e = E_LOGIN
		return {"ok": false, "error": e, "status": code}
	if d == null:
		return {"ok": true, "rows": []}
	return {"ok": true, "rows": d if d is Array else [d]}
