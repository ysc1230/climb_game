class_name SaveStore
extends RefCounted
## docs/28 §9 저장. 임시 파일에 쓴 뒤 이름을 바꿔 교체한다.

const DEFAULT_PATH := "user://save.json"


static func load(path := DEFAULT_PATH) -> Progress:
	if FileAccess.file_exists(path):
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(data) == TYPE_DICTIONARY and int(data.get("schema_version", -1)) == Progress.SCHEMA_VERSION:
			return Progress.from_dict(data)
	return Progress.new()


static func save(p: Progress, path := DEFAULT_PATH) -> bool:
	p.seq += 1
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		p.seq -= 1
		return false
	f.store_string(JSON.stringify(p.to_dict()))
	f.close()
	if DirAccess.rename_absolute(tmp, path) != OK:
		DirAccess.remove_absolute(tmp)
		p.seq -= 1
		return false
	return true
