class_name WordFilter
extends RefCounted
## 문제 이름·별명의 거친 말 막기(작업 6 §4, 간단한 낱말 목록). 띄어쓰기·대소문자를 무시하고 포함 여부만 본다.

const WORDS := ["시발", "씨발", "ㅅㅂ", "병신", "ㅂㅅ", "좆", "존나", "개새", "새끼", "fuck", "shit", "bitch"]


static func ok(s: String) -> bool:
	var t := s.to_lower().replace(" ", "")
	for w in WORDS:
		if t.contains(w):
			return false
	return true
