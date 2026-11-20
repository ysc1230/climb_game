class_name ShareCode
extends RefCounted
## 공유 코드(작업 6 §4): 헷갈리는 0/O/1/I를 뺀 32글자로 6자리. 서버(_new_code)가 만들고 앱은 형식만 본다.

const ALPHABET := "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
const LENGTH := 6


static func normalize(s: String) -> String:
	return s.strip_edges().replace(" ", "").replace("-", "").to_upper()


static func is_valid(s: String) -> bool:
	if s.length() != LENGTH:
		return false
	for c in s:
		if not ALPHABET.contains(c):
			return false
	return true
