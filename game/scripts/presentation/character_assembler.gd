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


## 모델 뼈 길이가 지금 판정 몸(Tuning)과 맞는가(±1cm). 다르면 관절에서 메시가 벌어지므로 쓰지 않는다
## (2026-11-11 B안으로 몸 비율을 바꾼 뒤, 옛 비율 모델 CH02·시제품은 캡슐 인형으로 대신한다).
static func compatible(sk: Skeleton3D) -> bool:
	var pairs := [["upperarm_L", "forearm_L", Tuning.ARM_UPPER], ["forearm_L", "hand_L", Tuning.ARM_LOWER],
		["thigh_L", "shin_L", Tuning.LEG_UPPER], ["shin_L", "foot_L", Tuning.LEG_LOWER]]
	for pr in pairs:
		var a := sk.find_bone(pr[0])
		var b := sk.find_bone(pr[1])
		if a < 0 or b < 0:
			return false
		if absf(sk.get_bone_global_rest(a).origin.distance_to(sk.get_bone_global_rest(b).origin) - float(pr[2])) > 0.01:
			return false
	var sh := sk.find_bone("upperarm_R")
	return sh >= 0 and sk.get_bone_global_rest(sh).origin.distance_to(Vector3(Tuning.SHOULDER_OFFSET.x, Tuning.SHOULDER_OFFSET.y, 0)) <= 0.02


## 파츠 목록의 모델(없으면 path)이 지금 몸과 맞는가. 화면에서 쓸 수 있는 모델인지 미리 볼 때.
func model_compatible() -> bool:
	var path := model_path()
	if path == "" or not ResourceLoader.exists(path):
		return false
	var m: Node3D = load(path).instantiate()
	var found := m.find_children("*", "Skeleton3D", true, false)
	var ok := found.size() > 0 and compatible(found[0])
	m.free()
	return ok
