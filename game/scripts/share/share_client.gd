class_name ShareClient
extends Node
## 공유 서버와 실제로 주고받는다(작업 6 §5). ShareApi가 만든 요청을 HTTPRequest로 보내고 응답을 해석한다.
## 익명 로그인 세션은 user://share_session.json에 둔다. 로그인이 끊기면 한 번 다시 로그인하고 다시 보낸다.
## 모든 함수는 await로 부르고 {ok, rows | error}를 돌려준다. 서버가 없거나 잠들어 있어도 게임은 멈추지 않는다.

const SESSION := "user://share_session.json"
const TIMEOUT := 12.0

var api := ShareApi.new(ShareConfig.URL, ShareConfig.KEY)
var _session := {}


func enabled() -> bool:
	return ShareConfig.enabled()


func _send(req: Dictionary) -> Dictionary:
	var h := HTTPRequest.new()
	h.timeout = TIMEOUT
	add_child(h)
	var err := h.request(req.url, req.headers, req.method, req.body)
	if err != OK:
		h.queue_free()
		return {"code": 0, "body": ""}
	var res: Array = await h.request_completed
	h.queue_free()
	var code: int = res[1] if int(res[0]) == HTTPRequest.RESULT_SUCCESS else 0
	return {"code": code, "body": (res[3] as PackedByteArray).get_string_from_utf8()}


func _load_session() -> void:
	if _session.is_empty() and FileAccess.file_exists(SESSION):
		var d = JSON.parse_string(FileAccess.get_file_as_string(SESSION))
		_session = d if d is Dictionary else {}


func _save_session() -> void:
	var f := FileAccess.open(SESSION, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_session))
		f.close()


## 로그인(없으면 익명 가입, 끝나 가면 새로 고침). 반환: 오류 문구 또는 "".
func login() -> String:
	if not enabled():
		return "공유 서버가 아직 준비되지 않았어요"
	_load_session()
	if not _session.is_empty() and float(_session.get("expires_at", 0)) > Time.get_unix_time_from_system() + 60:
		api.token = str(_session.token)
		return ""
	var s := {}
	if str(_session.get("refresh", "")) != "":
		var r := await _send(api.refresh(str(_session.refresh)))
		s = ShareApi.parse_session(r.code, r.body)
	if not s.get("ok", false):
		var r2 := await _send(api.sign_in())
		s = ShareApi.parse_session(r2.code, r2.body)
	if not s.ok:
		return s.error
	_session = s
	_save_session()
	api.token = s.token
	return ""


## 로그인한 뒤 요청 하나(build: Callable → 요청 사전). 로그인이 끊겼으면 한 번 다시.
func rows(build: Callable) -> Dictionary:
	var e := await login()
	if e != "":
		return {"ok": false, "error": e}
	var r := await _send(build.call())
	var p := ShareApi.parse_rows(r.code, r.body)
	if not p.ok and p.error == ShareApi.E_LOGIN:
		_session = {}
		e = await login()
		if e != "":
			return {"ok": false, "error": e}
		r = await _send(build.call())
		p = ShareApi.parse_rows(r.code, r.body)
	return p
