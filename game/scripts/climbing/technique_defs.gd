class_name TechniqueDefs
extends RefCounted
## docs/27 §9.2 기술 정의 로더. 판단 로직은 코드, 설명 문구는 data/techniques.json.

const PATH := "res://data/techniques.json"
# mistakes.text_ko는 튜토리얼용 설명이다. 실행 거부 시 UI 이유 문구는 docs/27 §7.3을 따로 쓴다.


## id(StringName) -> {id, name_ko, phase, input, body_parts, sides, flow, group, purpose_tags, purpose_ko, when_ko, how_ko, mistakes,
## real_ko(실제 클라이밍에서는), seen_ko(게임이 알아보면 보이는 것), cond_ko(되는 조건), ready(기술 사전에 보이는가, docs/42 §4.3)}
## input: &"button"(기술 버튼으로 실행) 또는 &"pad"(패드 조작으로 하고 게임이 판정·기록, docs/28 §4).
static func load_all() -> Dictionary:
	var out := {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("기술 정의 JSON 파싱 실패: %s" % PATH)
		return out
	for d in data.get("techniques", []):
		var mistakes: Array = []
		for m in d.get("mistakes", []):
			mistakes.append({"reason": StringName(m.reason), "text_ko": m.text_ko})
		var tags: Array = []
		for tag in d.get("purpose_tags", []):
			tags.append(StringName(tag))
		var id := StringName(d.id)
		out[id] = {
			"id": id,
			"name_ko": d.name_ko,
			"phase": int(d.phase),
			"input": StringName(d.get("input", "pad")),
			"body_parts": StringName(d.body_parts),
			"sides": StringName(d.sides),
			"flow": StringName(d.flow),
			"group": StringName(d.group),
			"purpose_tags": tags,
			"purpose_ko": d.purpose_ko,
			"when_ko": d.when_ko,
			"how_ko": d.how_ko,
			"mistakes": mistakes,
			"real_ko": str(d.get("real_ko", "")),
			"seen_ko": str(d.get("seen_ko", "")),
			"cond_ko": str(d.get("cond_ko", "")),
			"ready": bool(d.get("ready", true)),
		}
	return out


## 1차(phase 1) 버튼 기술 ID(techniques.json 순서). 이 밖의 ID는 기술 버튼으로 실행할 수 없다(docs/28 §4.2).
static func button_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	var defs := load_all()
	for id in defs:
		if defs[id].phase == 1 and defs[id].input == &"button":
			out.append(id)
	return out


## 이 게임에 없는 기술 [{name_ko, why_ko}](기술 사전 "없는 기술", docs/42 §3.3).
static func absent() -> Array:
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return data.get("absent", []) if typeof(data) == TYPE_DICTIONARY else []
