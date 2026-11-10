class_name CharacterAssembler
extends RefCounted
## 캐릭터 외형 고르기(docs/34 §7, 2026-11-11). data/characters.json의 파츠 목록과 저장된 선택(look)으로
## 모듈 glb 안의 메시 중 고른 것만 보이게 한다. 모든 파츠가 같은 뼈대(ClimberCommonRig, RigPose.BONES 17개)에
## 스키닝돼 있어 자세 계산(ClimberPose·RigPose)은 그대로다. 노드는 만들지 않고 보이기만 바꾼다.
## look: {body, hair, top, bottom, chalk, shoes} — 빠지거나 모르는 값은 몸의 기본값으로.

const CATALOG_PATH := "res://data/characters.json"
const SLOTS: Array[String] = ["hair", "top", "bottom", "chalk", "shoes"]

var data := {}


static func load_catalog(path := CATALOG_PATH) -> CharacterAssembler:
	var a := CharacterAssembler.new()
	if FileAccess.file_exists(path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary:
			a.data = d
	return a


func model_path() -> String:
	return str(data.get("model", ""))


func bodies() -> Array:
	return data.get("bodies", [])


func slot(id: String) -> Dictionary:
	for s in data.get("slots", []):
		if s.id == id:
			return s
	return {}


func body(id: String) -> Dictionary:
	for b in bodies():
		if b.id == id:
			return b
	return bodies()[0] if not bodies().is_empty() else {}


## 빠진 값·모르는 값을 채운 완전한 선택.
func normalize(look: Dictionary) -> Dictionary:
	var b := body(str(look.get("body", "")))
	var out := {"body": str(b.get("id", ""))}
	var defs: Dictionary = b.get("defaults", {})
	for sid in SLOTS:
		var parts: Array = slot(sid).get("parts", [])
		var want := str(look.get(sid, defs.get(sid, "")))
		var ok := parts.any(func(p): return p.id == want)
		out[sid] = want if ok else (str(defs.get(sid, "")) if parts.any(func(p): return p.id == defs.get(sid, "")) else (str(parts[0].id) if not parts.is_empty() else ""))
	return out


## 슬롯에서 지금 것 다음(step=±1) 파츠 id.
func cycle(look: Dictionary, sid: String, step: int) -> String:
	if sid == "body":
		var ids := bodies().map(func(b): return str(b.id))
		return str(ids[posmod(ids.find(str(look.body)) + step, ids.size())])
	var parts: Array = slot(sid).get("parts", [])
	if parts.is_empty():
		return ""
	var ids := parts.map(func(p): return str(p.id))
	return str(ids[posmod(ids.find(str(look.get(sid, ""))) + step, ids.size())])


func part_name(sid: String, id: String) -> String:
	if sid == "body":
		return str(body(id).get("name_ko", id))
	for p in slot(sid).get("parts", []):
		if p.id == id:
			return str(p.get("name_ko", id))
	return id


## 보일 메시 이름(P_*) 목록.
func visible_meshes(look: Dictionary) -> Array[String]:
	var n := normalize(look)
	var out: Array[String] = [str(body(n.body).get("mesh", ""))]
	for sid in SLOTS:
		for p in slot(sid).get("parts", []):
			if p.id == n[sid]:
				out.append(str(p.mesh))
	return out


## 모델 아래 P_* 메시를 고른 것만 보이게 한다. 목록에 없는 P_* 메시도 숨긴다. 반환: 보이게 한 메시 수.
func apply(model: Node, look: Dictionary) -> int:
	var show := visible_meshes(look)
	var shown := 0
	for mi in model.find_children("P_*", "MeshInstance3D", true, false):
		var on := show.has(String(mi.name))
		mi.visible = on
		if on:
			shown += 1
	return shown


## 얼굴 재질(외곽선 없음, 어둡게 칠하지 않음). 시제품은 M_eye·M_mouth·M_pupil, CH02는 M_face_*.
static func is_face_material(mname: String) -> bool:
	return mname.begins_with("M_face") or mname in ["M_eye", "M_mouth", "M_pupil"]


## 모델의 모든 메시 표면을 툰 셰이더 + 외곽선으로 바꾼다. 색은 colors[재질 이름]이 있으면 그것, 없으면 glb 기본색.
static func style(model: Node, toon_shader: Shader, outline_shader: Shader, ink: Color, colors := {}) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(i)
			var mname: String = m.resource_name if m else ""
			var c: Color = colors.get(mname, (m as BaseMaterial3D).albedo_color if m is BaseMaterial3D else Color.GRAY)
			var face := is_face_material(mname)
			var t := ShaderMaterial.new()
			t.shader = toon_shader
			t.set_shader_parameter("albedo", c)
			t.set_shader_parameter("shade", c.darkened(0.15 if face else 0.45))
			t.set_shader_parameter("wall_pattern", false)
			var o := ShaderMaterial.new()
			o.shader = outline_shader
			o.set_shader_parameter("ink", ink)
			o.set_shader_parameter("width", 0.0 if face else 0.012)
			t.next_pass = o
			mi.set_surface_override_material(i, t)
