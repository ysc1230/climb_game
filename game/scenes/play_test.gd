extends Node2D
## 플레이 장면. 회색 박스 벽과 2D 막대 인형을 네 패드로 조작한다.
## 판정은 PoseSolver/Fatigue/InputRouter를 사용하고, 이 노드는 상태를 들고 그리기만 한다.
## 문제는 자동 로드 Game의 current_route_id에서 받는다(docs/28 §5). Game이 없거나 비면 G_V0_01과 모든 버튼.
## 완등 결과·튜토리얼 안내·일시정지 [목록]은 PlayOverlay가 그리고, 여기서는 받은 동작만 처리한다.
## 아직 단순화한 부분: GripSystem 동시 거래 대신 release 즉시 단일 판정.

## 벽(주황·모래·올리브)과 겹치지 않는 차가운 색: 왼쪽 팔다리 하늘색, 오른쪽 팔다리 보라색(2026-11-04).
const LIMB_COLORS := {&"LH": Color("5fd4ff"), &"RH": Color("c79bff"), &"LF": Color("5fd4ff"), &"RF": Color("c79bff")}
const DEADZONE_MM := 2.5  # docs/23 제안 시작값. 04의 10논리단위와 함께 비교 대상
const PLAY_W := 3.4
const PLAY_H := 3.8
const DEFAULT_ROUTE := "res://data/routes/general/G_V0_01.json"
const PlayOverlay := preload("res://scenes/play_overlay.gd")

var session: ClimbSession
var route: RouteDef
var router := InputRouter.new()  # D패드 방식(stick_mode)은 _ready에서 켠다
var paused := false
var prepare_left := 0.0
var hud = preload("res://scenes/hud.gd").new()  # 위쪽 정보 패널·일시정지 화면(2026-11-08 사용자 참고 이미지)
## 떨어지기 전 경고 3단계(주의·위험·회복)와 초급 도움(2026-11-09, docs/18). 경고는 초급·중급 모두, 도움은 초급만.
var danger := DangerFeedback.new()
var beginner := false             # 초급: 버틸 시간 10배·해결 안내·자동 도움
var level := "intermediate"       # beginner / intermediate / advanced
## 경고·알림을 보이는가. 고급은 아무 경고 없이 손 게이지와 몸의 균형만 보고 판단한다(2026-11-10 사용자). 튜토리얼은 늘 보인다.
var warnings := true
const RESCUE_PER_ATTEMPT := 3     # 위험 게이지를 눌러 쓰는 자동 도움(AutoRescue) 횟수. 다 쓰면 경고만 남는다
var rescue_left := 0
var _rescue_anim := {}            # 자동 도움으로 옮겨 가는 중 {t, dur, pose, moves, body0, angle0, pos0, pos1}
var _safe_pose := {}              # 마지막으로 안정(STABLE)했던 자세(자동 도움이 옮길 동작을 못 찾으면 여기로)
var _fall_cause := ""
var _sfx := {}                    # 이름 → AudioStreamPlayer
var _glow: GradientTexture2D      # 화면 가장자리 빛(흰색, modulate로 색을 입힌다)
var best_height := 0.0  # 이번 시도에서 오른 가장 높은 높이(진행 점)
## 위쪽 한 줄(hud.gd TOP_H)의 아래 끝(ui_k 배율 전). 상세 정보 모드면 상태 줄만큼 더 내려간다(2026-11-10 HUD 개선 기획).
const HUD_BOTTOM := 80.0
const HUD_BOTTOM_DETAIL := 132.0
var detail_mode := false          # 상세 정보 모드(지지·손 하중·무브 상시 표시). 위쪽 [i] 버튼
var _stam_prev := {}              # 손 → 직전 틱 팔 힘(회복 중 표시)
var _stam_up := {}                # 손 → 회복 중인가
var _notice := ""                 # 동작이 바뀌었을 때·부담 큼일 때 위쪽 띠 아래 잠깐 보이는 문구
var _notice_left := 0.0
var _last_move := ""
var message := ""
var message_ticks := 0
var cam_y := 1.9
var font: Font
var ui_k := 1.0
var px_per_m := 100.0
var wall_origin := Vector2.ZERO  # 월드 (0, cam_y)가 놓일 화면 위치
var log_lines: PackedStringArray = []
## false이면 벽·홀드·인형을 그리지 않고 패드·HUD만 그린다(3D 표현 계층이 월드를 그림).
var draw_world := true
## 월드(m) ↔ 화면(px) 변환. play_3d가 카메라 투영으로 덮어쓴다. 비면 2D 변환을 쓴다.
var w2s_fn := Callable()
var s2w_fn := Callable()
## 자동 로드 Game(없으면 null). 이름으로 직접 부르지 않는다(헤드리스 테스트에서 자동 로드가 없을 수 있음).
var game: Node
var overlay := PlayOverlay.new()
var tutorial: TutorialRunner
var attempt := PlayAttempt.new()  # 이번 시도 시간·추락 수, 튜토리얼 "보기" 상태
var _tutorial_wait := false # 추락 뒤 단계 다시 시작을 추락 연출(respawn)까지 미룸
var _tutorial_wait_next := false  # 그 추락이 목표를 채운 것(다음 단계)인가
var _grip_label := {}       # 패드로 잡은 순간 손 옆 품질 문구 {pos, text, color, left}(docs/33 §7-5)
var _tips_pending: Array[String] = []  # 처음 한 번 안내 대기열(docs/33 §5)
var _saw_danger := false    # 이번 위험을 겪었는가(끝나면 TIP_DANGER)
var _reach_fails := 0       # 이번 시도에서 "닿지 않음·체중 이동" 거부 수(TIP_BODY)
## 처음 한 번 안내 문구(docs/33 §5). 튜토리얼 안에서는 나오지 않는다.
const TIPS := {
	"caution": "노란 패드: 지금 떼면 떨어질 수 있어요",
	"danger": "붉은 화면과 두근거림은 떨어지기 직전 신호예요. 손발을 다시 잡으면 돼요",
	"danger_beginner": "붉은 화면과 두근거림은 떨어지기 직전 신호예요. 캐릭터 둘레 고리를 누르면 자동으로 도와줘요(3번)",
	"recover": "버텼어요! 초록빛은 다시 안전하다는 뜻이에요",
	"body": "패드 사이 가운데를 끌면 몸을 옮길 수 있어요",
	"match": "두 손은 파란 홀드에만 모을 수 있어요",
	"rescue_out": "이번 시도의 자동 도움을 다 썼어요. 떨어지면 다시 3번이 생겨요",
}
var _swallow := {}          # 오버레이 버튼을 누른 터치(떼기 입력도 버린다)

# ---------- 기술 선택 UI 상태(docs/27 §6, 05 v0.6) ----------
enum UI { NONE, PANEL, SIDE, HOLD }
const CHECK_INTERVAL := 0.2  # 패널 흐림 검사 주기(초)
const HOLD_PICK_RADIUS := 0.12  # 탭이 홀드 영역에서 이만큼 안이면 그 홀드를 누른 것(m)
const STAGE_TEXT := {&"check": "준비 중", &"move": "옮기는 중", &"yaw": "자세를 유지하는 중"}
const ENTRY_COLS := 4
## 패널에 보여 줄 버튼 기술(docs/28 §5.5). 비면 기술 버튼을 그리지도 받지도 않는다(패드만으로 진행).
var allowed_buttons: Array[StringName] = TechniqueDefs.button_ids()
var ui_mode := UI.NONE
var sel_tech := &""
var sel_side := &""
var side_judge := {}       # side -> {available, reason, text} (쪽 선택 단계)
var hold_targets: Array = []
var dim := {}              # tech_id -> true(지금 안 될 것 같음)
var preview := {}          # 홀드 탭 미리보기 {key, ok, point, quality, text}
var _hold_index := -2      # 홀드 미리보기를 누르고 있는 터치(-2 없음)
var _check_timer := 0.0
var _techs := TechniqueJudge.defs()


func _ready() -> void:
	router.stick_mode = true
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Noto Sans CJK KR", "Noto Sans KR", "Apple SD Gothic Neo", "sans-serif"])
	font = sf
	overlay.font = sf
	hud.font = sf
	game = get_node_or_null("/root/Game")
	if game != null and game.current_route_id != "":
		route = game.index.route(game.current_route_id)
	if route == null:
		route = RouteDef.load_json(DEFAULT_ROUTE)
	else:
		overlay.has_list = true
	session = ClimbSession.new(route)
	level = game.get_flow().level() if game != null else "intermediate"
	beginner = level == "beginner"
	ClimbRules.apply_level(session.rules, level)
	_build_feedback()
	_start_tutorial()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_after_reset("시작")


## 문제가 튜토리얼이면 단계 실행기를 만들고 첫 단계를 시작한다. 기술 버튼도 정한다.
func _start_tutorial() -> void:
	tutorial = null
	_tutorial_wait = false
	overlay.can_skip = false
	if overlay.has_list and route.course_slot == "tutorial" and not route.tutorial_steps.is_empty():
		tutorial = TutorialRunner.new(route)
		tutorial.set_level("beginner" if beginner else "intermediate")  # 고급도 튜토리얼은 중급 단계로
		_begin_step()
		overlay.briefing = _briefing_for(route)
		overlay.can_skip = route.route_id == Progress.BASIC_TUTORIAL and game.progress.is_first_run()
	warnings = level != "advanced" or tutorial != null
	overlay.tutorial = tutorial
	overlay.tutorial_done = false
	_refresh_buttons()


## 튜토리얼 시작 설명 카드(사용자 결정 2026-11-04): 그 과정의 이름·설명(text_ko). 탭하면 사라지고 그때부터 시작한다.
func _briefing_for(r: RouteDef) -> Dictionary:
	if game == null or r.course_id == "":
		return {}
	var c: Dictionary = game.index.course(r.course_id)
	var t: Dictionary = c.get("text_ko", {})
	if t.is_empty():
		return {}
	return {"title": str(c.get("name_ko", "")), "purpose": str(t.get("purpose", "")), "when": str(t.get("when", "")), "how": str(t.get("how", ""))}


## 튜토리얼 단계를 (다시) 놓는다. 멈춤 없이 바로 시작하고, 목표 홀드는 단계 내내 반짝인다(사용자 결정 2026-11-04).
func _begin_step() -> void:
	tutorial.begin_step(session)
	_refresh_buttons()


func _refresh_buttons() -> void:
	if overlay.has_list:
		allowed_buttons = game.allowed_buttons_for(route, tutorial)


## 튜토리얼 단계 규칙(피로 감소 끄기·시작 체력)을 기본값으로 되돌린다.
func _end_tutorial_rules() -> void:
	session.rules.fatigue_disabled = false
	for hand in [PoseSolver.LH, PoseSolver.RH]:
		session.rules.stamina[hand] = 100.0


func _layout() -> void:
	var size := get_viewport_rect().size
	ui_k = maxf(minf(size.x / 1600.0, size.y / 900.0), 0.25)
	var pad_d := 160.0 * ui_k
	router.set_pad(&"LH", Vector2(0.11, 0.30) * size, pad_d)
	router.set_pad(&"LF", Vector2(0.11, 0.72) * size, pad_d)
	router.set_pad(&"RH", Vector2(0.89, 0.30) * size, pad_d)
	router.set_pad(&"RF", Vector2(0.89, 0.72) * size, pad_d)
	# 네 패드 사이의 네모 공간: 여기서 끌면 몸통(골반 목표)을 그 방향으로 옮긴다(docs/03 v0.9)
	var r := pad_d * 0.5
	router.body_area = Rect2(Vector2(0.11 * size.x + r + 12 * ui_k, 0.30 * size.y - r), Vector2(0.78 * size.x - 2 * r - 24 * ui_k, 0.42 * size.y + 2 * r))
	var dpi := float(DisplayServer.screen_get_dpi())
	router.deadzone_px = maxf(10.0 * ui_k, DEADZONE_MM / 25.4 * dpi)
	px_per_m = maxf(minf(size.x * 0.56 / PLAY_W, size.y / PLAY_H), 10.0)
	wall_origin = Vector2(size.x * 0.5, size.y * 0.5)
	_log("화면 %dx%d dpi %.0f k %.2f 패드 %.0fpx 데드존 %.1fpx" % [size.x, size.y, dpi, ui_k, pad_d, router.deadzone_px])


func _reset(reason: String) -> void:
	session.reset()
	_after_reset(reason)


## 세션이 다시 시작된 뒤 표시 쪽 정리(입력 초기화·카메라·문구).
func _after_reset(reason: String, ticks := 120) -> void:
	_close_ui()
	router.cancel_all()
	cam_y = session.body.pos.y + 0.12 * PLAY_H
	danger.reset()
	_saw_danger = false
	_reach_fails = 0
	rescue_left = RESCUE_PER_ATTEMPT
	_rescue_anim = {}
	_safe_pose = {}
	_flash(reason, ticks)


func _flash(text: String, ticks := 120) -> void:
	message = text
	message_ticks = ticks


## 효과음과 화면 가장자리 빛 텍스처를 만든다.
func _build_feedback() -> void:
	for name in ["heartbeat", "heartbeat2", "danger", "caution", "recover"]:
		var path := "res://art/sfx/%s.wav" % ("heartbeat" if name == "heartbeat2" else name)
		if not ResourceLoader.exists(path):
			continue
		var pl := AudioStreamPlayer.new()
		pl.stream = load(path)
		pl.volume_db = {"heartbeat": -2.0, "heartbeat2": -9.0, "danger": -4.0, "caution": -8.0, "recover": -6.0}[name]
		add_child(pl)
		_sfx[name] = pl
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 0.88])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 1)])
	_glow = GradientTexture2D.new()
	_glow.gradient = g
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1.2, 0.5)  # 반지름 0.7(UV): 화면 옆 가운데 약 60%, 모서리 100%
	_glow.width = 256
	_glow.height = 256


func _play(name: String) -> void:
	if _sfx.has(name):
		_sfx[name].play()


func _vibrate(ms: int, amplitude := -1.0) -> void:
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(ms, amplitude)


## 경고 상태를 한 프레임 진행하고 사건(소리·진동)을 낸다. 판정 틱이 돌았으면 stepped.
## 튜토리얼이면 사건을 목표용으로 넘긴다(docs/33 §7-1). 처음 겪는 신호는 한 번 안내(docs/33 §5).
func _danger_tick(real_dt: float, stepped: bool) -> void:
	var ph: int = session.rules.phase
	if not warnings:  # 고급: 경고 상태를 만들지 않는다(소리·진동·화면·멈칫·안내 없음)
		danger.reset()
		if stepped and ph == ClimbRules.Phase.STABLE and not session.falling and not session.is_dragging():
			_safe_pose = session.current_pose()
		return
	danger.observe_session(session, real_dt, stepped)
	if tutorial != null:
		for ev in danger.tutorial_events():
			tutorial.note(ev)
	for ev in danger.events:
		match ev:
			&"enter":
				_play("danger")
				_vibrate(140, 1.0)
			&"beat":
				_play("heartbeat")
				_vibrate(70, 1.0)
			&"beat2":
				_play("heartbeat2")
				_vibrate(45, 0.6)
			&"caution":
				_play("caution")
				_vibrate(35, 0.5)
			&"recover":
				_play("recover")
				_vibrate(25, 0.4)
	for ev in danger.events:
		match ev:
			&"caution":
				_tip("caution")
			&"enter":
				_saw_danger = true
			&"recover", &"fall":
				if _saw_danger:
					_saw_danger = false
					_tip("danger_beginner" if beginner else "danger", "danger")
				if ev == &"recover":
					_tip("recover")
	if not _grip_label.is_empty():
		_grip_label.left = float(_grip_label.left) - real_dt
		if _grip_label.left <= 0.0:
			_grip_label = {}
	if not _tips_pending.is_empty() and not danger.danger and message_ticks <= 0 and not session.falling:
		_flash(TIPS[_tips_pending.pop_front()], 210)
	if stepped and ph == ClimbRules.Phase.STABLE and not session.falling and not session.is_dragging():
		_safe_pose = session.current_pose()


## 처음 한 번 안내를 대기열에 넣는다(기기에 한 번, 튜토리얼 밖에서만). seen_id: 저장 키(문구 키와 다를 때).
func _tip(id: String, seen_id := "") -> void:
	var key := seen_id if seen_id != "" else id
	if not warnings or tutorial != null or game == null or game.progress.seen_tips.has(key) or _tips_pending.has(id):
		return
	game.get_flow().mark_tip(key)
	_tips_pending.append(id)


## 초급 자동 도움(2026-11-09): 위험 게이지(캐릭터 둘레 고리)를 누르면 AutoRescue가 고른 최선의 동작
## (손 하나·발 하나까지, 정상 홀드 제외)으로 옮겨 간다. 못 찾으면 마지막 안정 자세로 되돌린다. 시도마다 RESCUE_PER_ATTEMPT번.
func _rescue() -> void:
	if not beginner or rescue_left <= 0 or not danger.danger or session.falling or not _rescue_anim.is_empty():
		return
	if tutorial != null and not tutorial.rescue_allowed():
		return  # 튜토리얼은 대신 움직이지 않는다(가르치는 단계만, docs/33 §3.1)
	var plan := AutoRescue.plan(session)
	var pose := {}
	var moves: Array = []
	if not plan.is_empty():
		pose = {"pelvis": [plan.pelvis.x, plan.pelvis.y], "angle": plan.angle, "slots": plan.slots}
		moves = plan.moves
	elif not _safe_pose.is_empty():
		pose = _safe_pose.duplicate(true)
	else:
		_flash("지금은 도울 수 있는 동작이 없어요")
		return
	pose["stamina"] = session.rules.stamina.duplicate()  # 팔 힘은 그대로(쉬는 꼼수 방지)
	_apply(router.cancel_all())
	if tutorial == null:
		rescue_left -= 1  # 튜토리얼 연습은 횟수를 쓰지 않는다(반복해서 익힘)
	danger.reset()
	_play("recover")
	_vibrate(25, 0.4)
	var pos0 := {}
	var pos1 := {}
	for limb in session.limbs:
		pos0[limb] = session.limbs[limb].pos
	for m in moves:
		pos1[m.limb] = route.slot_pos(m.key)
		session.limbs[m.limb].state = "Dragging"  # 표현: 벽에서 떼어 옮긴다(판정 틱은 도는 동안 멈춤)
	_rescue_anim = {"t": 0.0, "dur": 0.35 + 0.35 * moves.size(), "pose": pose, "moves": moves, "plan": not plan.is_empty(),
		"body0": session.body.pos, "angle0": session.body.angle, "pos0": pos0, "pos1": pos1}


## 자동 도움 연출 한 프레임: 골반은 전체 시간 동안, 옮기는 손발은 하나씩 차례로 목표 홀드로. 끝나면 그 자세로 확정.
func _rescue_tick(real_dt: float) -> void:
	var an := _rescue_anim
	an.t = minf(float(an.t) + real_dt, float(an.dur))
	var k: float = an.t / an.dur
	var e := k * k * (3.0 - 2.0 * k)
	var p1 := Vector2(an.pose.pelvis[0], an.pose.pelvis[1])
	session.body.pos = (an.body0 as Vector2).lerp(p1, e)
	session.body.angle = lerpf(an.angle0, float(an.pose.angle), e)
	session.body.vel = Vector2.ZERO
	var delta: Vector2 = session.body.pos - (an.body0 as Vector2)
	var n: int = an.moves.size()
	for limb in session.limbs:
		if an.pos1.has(limb):
			var i := 0
			for j in n:
				if an.moves[j].limb == limb:
					i = j
			var kk := clampf(k * n - i, 0.0, 1.0)
			var ee := kk * kk * (3.0 - 2.0 * kk)
			var lift := Vector2(0, 0.06 * sin(PI * kk))  # 살짝 들어 올리며 옮긴다
			session.limbs[limb].pos = (an.pos0[limb] as Vector2).lerp(an.pos1[limb], ee) + lift
		elif not session.limbs[limb].state in ["Attached", "Armed"]:
			session.limbs[limb].pos = (an.pos0[limb] as Vector2) + delta
	if an.t < an.dur:
		return
	session.reset_to(an.pose)
	_rescue_anim = {}
	if tutorial != null:
		tutorial.note({"type": "rescue"})
	if rescue_left <= 0:
		_tip("rescue_out")
	_safe_pose = {}
	var names: Array[String] = []
	for m in an.moves:
		names.append(DangerFeedback.LIMB_KO[m.limb])
	var what := "자세를 바로잡았어요"
	if not an.plan:
		what = "안정했던 자세로 되돌렸어요"
	elif not names.is_empty():
		var joined := "·".join(names)
		what = "%s%s 옮겼어요" % [joined, Progress.object_particle(joined)]
	_flash("자동 도움: %s · 남은 도움 %d번" % [what, rescue_left] if rescue_left > 0 else "자동 도움: %s · 자동 도움을 다 썼어요" % what, 180)


func _log(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > 6:
		log_lines.remove_at(0)


# ---------- 입력 ----------

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and _overlay_event(event.index, event.position, event.pressed):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and _overlay_event(-1, event.position, event.pressed):
		return
	if event is InputEventScreenTouch:
		if event.canceled:
			_apply(router.cancel_all())
			return
		if paused:
			if not event.pressed and prepare_left <= 0.0:
				prepare_left = 3.0
			return
		if session.falling or not _rescue_anim.is_empty():
			return
		if _ui_event(event.index, event.position, event.pressed):
			return
		if event.pressed:
			var limb := router._pad_at(event.position)
			var attached_now: bool = limb != &"" and session.limbs[limb].state == "Attached"
			_apply(router.touch_down(event.index, event.position, attached_now))
		else:
			_apply(router.touch_up(event.index))
	elif event is InputEventScreenDrag and not paused and not session.falling and _rescue_anim.is_empty():
		if session.selecting:
			_ui_drag(event.index, event.position)
			return
		_apply(router.touch_drag(event.index, event.position))
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not paused and not session.falling:
		_ui_event(-1, event.position, event.pressed)  # 데스크톱 시험: 마우스는 기술 UI만
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and session.selecting:
		_ui_drag(-1, event.position)


## 오버레이 버튼(일시정지·목록·다시·다음·도움말·건너뛰기). 결과·완료 화면이 떠 있으면 모든 입력을 받아 쓴다.
func _overlay_event(index: int, pos: Vector2, pressed: bool) -> bool:
	if not pressed:
		if _swallow.has(index):
			_swallow.erase(index)
			return true
		return overlay.blocking()
	var act := overlay.tap(pos)
	if act == "":
		return overlay.blocking()
	_swallow[index] = true
	_overlay_action(act)
	return true


func _overlay_action(act: String) -> void:
	match act:
		"pause":
			_pause(true)
		"detail":
			detail_mode = not detail_mode
		"resume":
			if paused and prepare_left <= 0.0:
				prepare_left = 3.0
		"help":
			overlay.help_open = not overlay.help_open
		"brief":
			overlay.briefing = {}
		"retry":
			_retry()
		"rescue":
			_rescue()
		"next_course":
			game.play(str(overlay.next_course.route_id))
		"next":
			game.play(str(overlay.result.next))
		"list":
			_end_tutorial_rules()
			if overlay.can_skip and overlay.tutorial_done:
				game.home({"tab": "general", "grade": "V0"})  # 첫 실행 기본 조작 직후는 일반 탭(28 §5.2)
			else:
				game.home()
		"skip":
			_end_tutorial_rules()
			game.skip_basic()
			game.home({"tab": "general", "grade": "V0"})


## 같은 문제를 처음부터(시간·추락 새로 셈, 튜토리얼은 첫 단계부터).
func _retry() -> void:
	overlay.result = {}
	paused = false
	_end_tutorial_rules()
	session.reset()
	attempt.start(session.falls)
	_start_tutorial()
	_after_reset("다시 시작")


func _apply(cmds: Array) -> void:
	var was_dragging := {}
	for c in cmds:
		if session.limbs.has(c.limb):
			was_dragging[c.limb] = session.limbs[c.limb].state == "Dragging"
	session.apply_input(cmds)
	for c in cmds:
		if c.type == "release" and was_dragging.get(c.limb, false) and session.limbs[c.limb].state == "Attached":
			_vibrate(20)
			var ct = session.limbs[c.limb].contact
			if PoseSolver.is_hand(c.limb) and ct != null:  # 잡은 위치 품질을 손 옆에 1초(docs/33 §7-5)
				_grip_label = {"pos": session.limbs[c.limb].pos, "text": _quality_label(ct.quality), "color": _quality_color(ct.quality), "left": 1.0}
	_take_messages()


func _hud_bottom() -> float:
	return HUD_BOTTOM_DETAIL if detail_mode else HUD_BOTTOM


## 일반 플레이(상세 정보 모드가 아닐 때): 부담 큼이면 그동안, 무브가 바뀌면 1.5초 위쪽 띠 아래 가운데에 작은 문구(기획 §6).
## 균형 회복 중·지지 없음은 캐릭터 주변 위험 경고가 맡는다.
func _draw_notice(size: Vector2, ph: int) -> void:
	var text := ""
	var col := Color("fbeedd")
	if ph == ClimbRules.Phase.STRAINED:
		text = "부담 큼 · 손 하중이 커요"
		col = Color("f2c14e")
	elif _notice_left > 0.0:
		text = _notice
	if text == "":
		return
	var fs := int(20 * ui_k)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 40 * ui_k
	var r := Rect2(Vector2(size.x * 0.5 - w * 0.5, (HUD_BOTTOM + 6.0) * ui_k), Vector2(w, 36 * ui_k))
	hud.panel(self, r, ui_k, Color(0.17, 0.13, 0.10, 0.78), Color(0.83, 0.70, 0.52, 0.45), 18.0)
	draw_string(font, Vector2(r.position.x, r.position.y + 25 * ui_k), text, HORIZONTAL_ALIGNMENT_CENTER, w, fs, col)


## 팔 힘 추세(회복 중 표시)와 무브 변경 문구를 한 틱 진행한다.
func _hud_tick(real_dt: float) -> void:
	for hand in [PoseSolver.LH, PoseSolver.RH]:
		var v: float = session.rules.stamina[hand]
		_stam_up[hand] = v > float(_stam_prev.get(hand, v)) + 0.0001
		_stam_prev[hand] = v
	_notice_left = maxf(0.0, _notice_left - real_dt)
	var mv: String = session.rules.moves.korean()
	if mv != _last_move:
		if _last_move != "" and session.rules.moves.label != MoveClassifier.REST:
			_notice = "무브: " + mv
			_notice_left = 1.5
		_last_move = mv


## 세션이 쌓은 안내 문구를 화면 문구로 옮기고 비운다.
func _take_messages() -> void:
	for m in session.messages:
		if m == "균형이 무너지고 있어요":
			continue  # 위험 경고(DangerFeedback)가 대신 알린다
		if m in [GripCheck.MESSAGES[GripCheck.OUT_OF_REACH], GripCheck.MESSAGES[GripCheck.NEED_WEIGHT_SHIFT]]:
			_reach_fails += 1
			if _reach_fails >= 2:
				_tip("body")
		elif m == GripCheck.MESSAGES[GripCheck.OCCUPIED]:
			_tip("match")
		_flash(m)
	session.messages.clear()


# ---------- 고정 틱 ----------

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		_pause()


func _pause(manual := false) -> void:
	if paused or overlay.blocking() or (not manual and OS.get_cmdline_user_args().has("--no-auto-pause")):
		return
	_close_ui()
	_apply(router.cancel_all())
	paused = true
	prepare_left = 0.0


func _physics_process(_delta: float) -> void:
	if message_ticks > 0:
		message_ticks -= 1
	if ui_mode == UI.PANEL:
		_check_timer -= _delta
		if _check_timer <= 0.0:
			_refresh_dim()
	if paused:
		if prepare_left > 0.0:
			prepare_left -= _delta
			if prepare_left <= 0.0:
				paused = false
		queue_redraw()
		return
	if overlay.blocking():
		queue_redraw()
		return
	if tutorial != null and overlay.help_open:
		queue_redraw()  # 튜토리얼 도움말을 펼친 동안 게임을 멈춘다(기획 §7)
		return
	if not _rescue_anim.is_empty():
		_rescue_tick(_delta)  # 자동 도움으로 옮겨 가는 중: 판정 틱·떨어지는 시계 멈춤
		queue_redraw()
		return
	if danger.hitstop_left > 0.0 and not session.selecting:
		_danger_tick(_delta, false)  # 위험에 들어가는 순간 잠깐 멈칫(신호용, 판정 틱을 쉰다)
		queue_redraw()
		return
	_apply(router.tick(_delta))  # D패드: 누르고 있는 방향으로 손발을 계속 움직인다
	var result := session.step()
	_hud_tick(_delta)
	if result.begins_with("fall:"):
		_fall_cause = danger.fall_cause(result.trim_prefix("fall:")) if warnings else "떨어졌어요"
	_danger_tick(_delta, not session.selecting)
	best_height = maxf(best_height, _height())
	_take_messages()
	var dt := attempt.tick(Tuning.DT, session.selecting)  # 고르는 중에는 0(시간·도움말 타이머 멈춤)
	attempt.on_result(result, session.falls)  # respawn: 새 시도(Ruling I)
	if tutorial != null and _tutorial_tick(result, dt):
		queue_redraw()
		return
	match result:
		"fall:NO_SUPPORT", "fall:BALANCE_LOST":
			_apply(router.cancel_all())
			_flash(_fall_cause, 300)  # 왜 떨어졌는지 한 줄(DangerFeedback.fall_cause)
			queue_redraw()
			return
		"unresolved":
			_log("힘 계산 실패: 일시정지")
			_pause()
			return
		"respawn":
			best_height = 0.0
			_after_reset(_fall_cause if _fall_cause != "" else "떨어졌어요. 처음부터", 240)
			_fall_cause = ""
			queue_redraw()
			return
		"clear":
			_log("완등 %d회" % session.clears)
			_after_reset("")
			_show_result()
			queue_redraw()
			return
	if session.falling:
		queue_redraw()
		return
	if not session.selecting:
		_camera_tick()  # 고르는 중에는 카메라도 멈춘다
	queue_redraw()


## 튜토리얼 단계 진행(28 §6.1). 추락 뒤 다시 시작은 추락 연출이 끝난 respawn에서 한다. 처리했으면 true.
func _tutorial_tick(result: String, dt: float) -> bool:
	if _tutorial_wait:
		if result != "respawn":
			return false
		_tutorial_wait = false
		_begin_step()
		if _tutorial_wait_next:
			_after_reset("잘했어요. 떨어져도 처음 자세로 돌아와요", 180)
		else:  # 왜 떨어졌는지 한 줄 뒤 그 단계 다시(docs/33 §3.3)
			_after_reset(_fall_cause if _fall_cause != "" else "이 단계를 다시 해 봐요", 180)
		_fall_cause = ""
		return true
	var act := tutorial.observe(session, result, dt)
	match act:
		"next", "restart":
			if result.begins_with("fall:"):
				_tutorial_wait = true
				_tutorial_wait_next = act == "next"
				return false
			var again := "이 단계를 다시 해 봐요"
			if act == "restart" and str(tutorial.current().get("goal_event", {}).get("type", "")) == "rescue":
				again = "패드 말고 캐릭터 둘레 고리를 눌러요"
			_begin_step()
			_after_reset("" if act == "next" else again, 180)
			return true
		"done":
			_end_tutorial_rules()
			overlay.tutorial_done = true
			overlay.next_course = game.get_flow().next_basic_tutorial(route.route_id) if game != null else {}
			if overlay.has_list:
				game.finish_tutorial()
			_after_reset("")
			return true
	if result == "clear":  # 목표가 완등이 아닌 단계에서 정상을 잡음: 세션이 처음으로 돌아갔으니 그 단계를 다시 놓는다
		_begin_step()
		_after_reset("")
		return true
	return false


## 완등 결과 오버레이(28 §5). Game이 있으면 기록·저장하고 [다음]을 정한다.
func _show_result() -> void:
	var falls := attempt.falls(session.falls)
	var r := {"seconds": attempt.seconds, "falls": falls, "no_fall": falls == 0, "time_limit": route.time_medal_seconds,
		"time": route.time_medal_seconds > 0.0 and attempt.seconds <= route.time_medal_seconds, "next": "", "saved": true}
	if overlay.has_list:
		var rec: Dictionary = game.finish_clear(attempt.seconds, falls)  # 메달은 기록한 쪽 판정을 그대로 쓴다
		for key in ["no_fall", "time", "saved"]:
			if rec.has(key):
				r[key] = rec[key]
		var flow: PlayFlow = game.get_flow()
		var nid := flow.next_route_id(route.route_id)
		if nid != "" and game.progress.route_lock_text(game.index.route(nid), game.index) == "":
			r.next = nid
	overlay.result = r
	attempt.start(session.falls)


func _camera_tick() -> void:
	var screen_frac := 0.5 - (session.body.pos.y - cam_y) * px_per_m / get_viewport_rect().size.y
	if screen_frac < 0.50 or screen_frac > 0.68:
		var goal := session.body.pos.y + 0.12 * PLAY_H
		cam_y += clampf((goal - cam_y) * 8.0 * Tuning.DT, -2.0 * Tuning.DT, 2.0 * Tuning.DT)


# ---------- 그리기 ----------

func w2s(p: Vector2) -> Vector2:
	if w2s_fn.is_valid():
		return w2s_fn.call(p)
	return _w2s_2d(p)


func s2w(s: Vector2) -> Vector2:
	if s2w_fn.is_valid():
		return s2w_fn.call(s)
	var q := (s - wall_origin) / px_per_m
	return Vector2(q.x, cam_y - q.y)


func _w2s_2d(p: Vector2) -> Vector2:
	return wall_origin + Vector2(p.x, cam_y - p.y) * px_per_m


func _draw() -> void:
	var size := get_viewport_rect().size
	if not draw_world:
		_draw_pads(size)
		_draw_hud(size)
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color("2b2622"))
	var tl := w2s(Vector2(-PLAY_W / 2, cam_y + PLAY_H / 2))
	draw_rect(Rect2(tl, Vector2(PLAY_W, PLAY_H) * px_per_m), Color("8a5a40"))
	draw_line(w2s(Vector2(-1.7, 0)), w2s(Vector2(1.7, 0)), Color("3a3028"), 4.0)
	for key in route.slots:
		var sp := route.slot_pos(key)
		var is_goal := route.goal_slots.has(key)
		var is_hand_slot: bool = route.slots[key].allowed.has(&"LH")
		var col := Color("f1d59a") if is_goal else (Color("c97a5c") if is_hand_slot else Color("7d7f5c"))
		draw_circle(w2s(sp), 0.07 * px_per_m, col)
		draw_arc(w2s(sp), 0.07 * px_per_m, 0, TAU, 20, Color("302820"), 2.0)
	for limb in session.limbs:
		if session.limbs[limb].state == "Dragging":
			var c: Dictionary = session.limbs[limb].cand
			if not c.is_empty():
				draw_arc(w2s(c.point), 0.11 * px_per_m, 0, TAU, 24, Color("fff2c8"), 3.0)
			var j := PoseSolver.joint_position(session.body.pos, session.body.angle, limb, session.body.yaw)
			draw_arc(w2s(j), PoseSolver.reach_of(limb).y * px_per_m, 0, TAU, 64, Color(1, 1, 1, 0.15), 1.5)
	_draw_body()
	_draw_pads(size)
	_draw_hud(size)


func _draw_body() -> void:
	var pel := w2s(session.body.pos)
	var neck := w2s(session.body.pos + Vector2(0, 0.62).rotated(deg_to_rad(session.body.angle)))
	var ink := Color("302820")
	draw_line(pel, neck, Color("4f6a68"), 0.22 * px_per_m)
	draw_circle(w2s(session.body.pos + Vector2(0, 0.78).rotated(deg_to_rad(session.body.angle))), 0.12 * px_per_m, Color("c7b79b"))
	for limb in session.limbs:
		var j := PoseSolver.joint_position(session.body.pos, session.body.angle, limb, session.body.yaw)
		var e: Vector2 = session.limbs[limb].pos
		var hand := PoseSolver.is_hand(limb)
		var a := Tuning.ARM_UPPER if hand else Tuning.LEG_UPPER
		var b := Tuning.ARM_LOWER if hand else Tuning.LEG_LOWER
		var side := -1.0 if limb in [&"LH", &"LF"] else 1.0
		var mid := _two_bone(j, e, a, b, side if hand else side)
		var col: Color = LIMB_COLORS[limb]
		draw_line(w2s(j), w2s(mid), col, 0.07 * px_per_m)
		draw_line(w2s(mid), w2s(e), col, 0.06 * px_per_m)
		var state: String = session.limbs[limb].state
		var tip := Color.WHITE if state == "Dragging" else (ink if state in ["Attached", "Armed"] else Color("aaaaaa"))
		draw_circle(w2s(e), 0.045 * px_per_m, tip)


## 2D 두 뼈 IK. side 방향(바깥쪽)으로 관절을 꺾는다.
func _two_bone(root: Vector2, end: Vector2, a: float, b: float, side: float) -> Vector2:
	var v := end - root
	var d := clampf(v.length(), absf(a - b) + 0.001, a + b - 0.001)
	var dir := v.normalized() if v.length() > 0.0001 else Vector2.DOWN
	var x := (a * a - b * b + d * d) / (2.0 * d)
	var h := sqrt(maxf(a * a - x * x, 0.0))
	var perp := Vector2(-dir.y, dir.x)
	if perp.x * side < 0:
		perp = -perp
	return root + dir * x + perp * h


func _draw_pads(size: Vector2) -> void:
	for limb in router.pads:
		var p: Dictionary = router.pads[limb]
		var active := router.active_limbs().has(limb)
		var col: Color = LIMB_COLORS[limb]
		# 안쪽은 더 투명하게(뒤의 벽·홀드가 보이게), 테두리는 어두운 밑선 + 색 선으로 어느 바탕에서도 보이게
		var ready: bool = session.limbs[limb].state == "Dragging" and not session.limbs[limb].cand.is_empty()
		draw_circle(p.center, p.radius, Color(col, 0.45 if ready else (0.30 if active else 0.08)))
		draw_arc(p.center, p.radius, 0, TAU, 48, Color(0.08, 0.07, 0.10, 0.6), 7.0 * ui_k)
		draw_arc(p.center, p.radius, 0, TAU, 48, Color(col, 0.95), 3.5 * ui_k)
		_draw_dpad(p, col, router.stick_knob(limb))
		var label := "%s%s" % ["왼" if limb in [&"LH", &"LF"] else "오른", "손" if PoseSolver.is_hand(limb) else "발"]
		var fs := int(26 * ui_k)
		draw_string(font, p.center + Vector2(-p.radius, 8 * ui_k + 2 * ui_k), label, HORIZONTAL_ALIGNMENT_CENTER, p.radius * 2, fs, Color(0, 0, 0, 0.7))
		draw_string(font, p.center + Vector2(-p.radius, 8 * ui_k), label, HORIZONTAL_ALIGNMENT_CENTER, p.radius * 2, fs, Color.WHITE)
		# 튜토리얼: 지금 움직일 팔다리의 패드를 금색으로 깜빡여 강조(기획 §7)
		var target: bool = _tutorial_limb() == limb
		if target:
			var pl := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 1.4)
			draw_arc(p.center, p.radius + 8 * ui_k, 0, TAU, 48, Color(1.0, 0.82, 0.3, 0.45 + 0.5 * pl), 6 * ui_k)
		# 손 패드 바로 위 팔 힘 게이지(기획 §5)
		if PoseSolver.is_hand(limb):
			hud.draw_pad_stamina(self, p.center, p.radius, ui_k, float(session.rules.stamina[limb]), bool(_stam_up.get(limb, false)), col, target, not warnings)


## D패드 표시: 네 방향 화살표와 가운데(멈춤) 원, 누르고 있으면 손잡이가 손가락 쪽으로 간다.
func _draw_dpad(p: Dictionary, col: Color, knob) -> void:
	var r: float = p.radius
	var c: Vector2 = p.center
	var ink := Color(0.08, 0.07, 0.10, 0.55)
	for i in 4:
		var d := Vector2.RIGHT.rotated(i * PI / 2.0)
		var tip := c + d * r * 0.86
		var base := c + d * r * 0.66
		var side := d.orthogonal() * r * 0.13
		draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), Color(1, 1, 1, 0.75))
		draw_polyline(PackedVector2Array([tip, base + side, base - side, tip]), ink, 2.0 * ui_k)
	draw_arc(c, r * InputRouter.STICK_DEAD, 0, TAU, 32, Color(1, 1, 1, 0.35), 2.0 * ui_k)
	if knob != null:
		var kp: Vector2 = c + (knob as Vector2)
		draw_circle(kp, r * 0.24, Color(col.lightened(0.3), 0.85))
		draw_arc(kp, r * 0.24, 0, TAU, 32, ink, 3.0 * ui_k)


## 튜토리얼 지금 단계의 목표 팔다리(없으면 &"").
func _tutorial_limb() -> StringName:
	if tutorial == null or tutorial.done:
		return &""
	return StringName(str(tutorial.current().get("goal_event", {}).get("limb", "")))


## 시작 골반에서 오른 높이(m).
func _height() -> float:
	return maxf(session.body.pos.y - route.start_pelvis.y, 0.0)


## 목표 높이(m): 정상 홀드가 시작 손 홀드보다 높은 만큼(골반도 대략 그만큼 오른다).
func _goal_height() -> float:
	var top := -INF
	for key in route.goal_slots:
		top = maxf(top, route.slot_pos(key).y)
	var start := -INF
	for limb in [&"LH", &"RH"]:
		if route.start_slots.has(limb):
			start = maxf(start, route.slot_pos(route.start_slots[limb]).y)
	if not is_finite(top) or not is_finite(start):
		return 1.0
	return maxf(top - start, 0.5)


func _draw_hud(size: Vector2) -> void:
	# 지지 상태(docs/25 피드백): 색만이 아니라 문구로도 표시
	var names := ["안정", "부담 큼", "균형 회복 중", "지지 없음"]
	var colors := [Color("cfe3c8"), Color("f1d59a"), Color("ff8a6a"), Color("ff5a4a")]
	var ph: int = session.rules.phase
	var hu: Dictionary = session.rules.last.get("u", {})
	var budget := -1.0
	if ph == ClimbRules.Phase.REBALANCING or ph == ClimbRules.Phase.GRACE:
		budget = float(session.rules.budget_left()[0])
	var move: String = session.rules.moves.korean()
	if not session.rules.flag_ready.is_empty():
		move += " · 놓으면 균형 발"
	var name := route.name_ko if route.name_ko != "" else route.route_id
	var title := ("%s-%d  %s" % [route.grade, route.order, name]) if route.mode == "general" and route.grade != "" else name
	var falls := attempt.falls(session.falls)
	if falls > 0:
		title += "  · 추락 %d" % falls
	if not paused:
		_draw_danger_glow(size)  # 위쪽 정보 패널보다 먼저(패널이 붉게 흐려지지 않게)
	var top_btns: Dictionary = hud.draw_top(self, size, ui_k, {"detail": detail_mode and warnings, "no_detail": not warnings,
		"title": title, "goal_height": _goal_height(), "height": _height(), "best_height": best_height,
		"stamina": session.rules.stamina, "phase_name": names[ph], "phase_color": colors[ph],
		"load_l": roundi(hu.get(&"LH", 0.0) * 100), "load_r": roundi(hu.get(&"RH", 0.0) * 100),
		"move": move, "budget": budget,
	})
	overlay.pause_rect = top_btns.pause
	overlay.detail_rect = top_btns.detail if warnings else Rect2()
	if not detail_mode and not paused and warnings:
		_draw_notice(size, ph)
	var y := size.y - 20 * ui_k
	for i in range(log_lines.size() - 1, -1, -1):
		if tutorial != null:
			break  # 튜토리얼 중에는 시험 기록 줄을 숨긴다
		draw_string(font, Vector2(size.x * 0.25, y), log_lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * ui_k), Color(1, 1, 1, 0.6))
		y -= 18 * ui_k
	if message_ticks > 0:
		_outlined(Vector2(0, maxf(size.y * (0.36 if session.selecting or tutorial != null else 0.30), (_hud_bottom() + 70.0) * ui_k)), message, 34, size.x, Color("fff2c8"))
	if not paused:
		_draw_danger(size)
	_draw_tech_ui(size)
	_draw_body_goal()
	if draw_world:
		_draw_grab_ready()  # 2D 시험 장면만. 3D 화면은 홀드 자체가 빛난다(play_3d)
	var goal_key := _tutorial_goal_key()
	overlay.goal_screen_y = w2s(route.slots[goal_key].pos).y if goal_key != "" else -1.0
	overlay.dim_band = danger.danger  # 위험 동안 안내 줄을 흐리게(docs/33 §3.5)
	if not _grip_label.is_empty() and not paused:
		var gp := w2s(_grip_label.pos) + Vector2(0, -46 * ui_k)
		var ga := clampf(float(_grip_label.left) * 2.0, 0.0, 1.0)
		_outlined(Vector2(gp.x - 100 * ui_k, gp.y), str(_grip_label.text), 22, 200 * ui_k, Color(_grip_label.color, ga))
	overlay.draw(self, size, ui_k, paused, session.selecting)
	if paused and not overlay.blocking():
		overlay.add_buttons(hud.draw_pause(self, size, ui_k, prepare_left, overlay.has_list))
	elif not paused and not overlay.blocking():
		_draw_rescue_button(size)
	if draw_world and goal_key != "" and not paused and not session.selecting and not overlay.blocking():
		_draw_goal_mark(goal_key)  # 2D 시험 장면만. 3D 화면은 목표 홀드 자체가 노랗게 깜빡인다(play_3d)


## 경고 화면(docs/18 "떨어지기 전 경고"). 글자를 읽지 않아도 알게: 화면 가장자리 빛, 캐릭터 둘레 남은 시간 고리,
## 머리 위 큰 글자, 패드 깜빡임. 초급은 해결 안내(다시 잡을 홀드·몸 옮길 방향)를 더 그린다.
func _draw_danger(size: Vector2) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var body: Vector2 = session.body.pos
	var head := w2s(body + Vector2(0, 1.05))
	var top := (_hud_bottom() + 70.0) * ui_k
	# ① 주의: 눌러 둔 손발을 떼면 위험
	var blink := 0.5 + 0.5 * sin(t * TAU * 3.0)
	for limb in danger.caution:
		if not router.pads.has(limb):
			continue
		var p: Dictionary = router.pads[limb]
		# 떼자마자 1초 안에 떨어질 손발은 빨강(2026-11-10 사용자), 그보다 여유가 있으면 노랑
		var fast := _fall_seconds(danger.caution[limb]) <= 1.0
		var cc := Color(1.0, 0.25, 0.18) if fast else Color(1.0, 0.8, 0.2)
		draw_circle(p.center, p.radius, Color(cc, 0.25 + 0.25 * blink))
		draw_arc(p.center, p.radius + 6 * ui_k, 0, TAU, 48, Color(cc, 0.95), 7.0 * ui_k)
		_draw_bang(p.center + Vector2(p.radius * 0.72, -p.radius * 0.72), 22.0 * ui_k, cc)
		var txt := "떼면 바로 떨어져요" if fast else DangerFeedback.caution_text(danger.caution[limb])
		_outlined(_pad_label_pos(p), txt, 26, 320 * ui_k, cc.lightened(0.25))
	if not danger.caution.is_empty() and not danger.danger:
		_draw_bang(Vector2(head.x, maxf(head.y - 20 * ui_k, top)), 26.0 * ui_k, Color(1.0, 0.8, 0.2))
	# ③ 회복
	if danger.recover_left > 0.0:
		var a := danger.recover_left / DangerFeedback.RECOVER_SHOW
		var y := maxf(head.y - 30 * ui_k - (1.0 - a) * 40 * ui_k, top)
		_outlined(Vector2(head.x - 200 * ui_k, y), "휴!", 60, 400 * ui_k, Color(0.7, 1.0, 0.75, a))
	if not danger.danger:
		return
	var warn := Color(1.0, 0.25, 0.15).lerp(Color(1.0, 0.7, 0.2), danger.frac)
	# 캐릭터 둘레 남은 시간 고리
	var ring := _ring()
	var c: Vector2 = ring[0]
	var r: float = ring[1]
	draw_arc(c, r, 0, TAU, 64, Color(0, 0, 0, 0.35), 14 * ui_k, true)
	draw_arc(c, r, -PI / 2, -PI / 2 + TAU * danger.frac, 64, warn, 10 * ui_k, true)
	# 머리 위 큰 글자(튀어나오며 커졌다 줄어듦)
	var pop := 1.0 + 0.6 * exp(-danger.danger_time * 10.0)
	var y := maxf(head.y - 40 * ui_k, top + 30 * ui_k)
	_outlined(Vector2(head.x - 300 * ui_k, y), DangerFeedback.shout(danger.kind), int(76 * pop), 600 * ui_k, Color(1, 0.95, 0.9), Color(0.55, 0.05, 0.02))
	var sub := DangerFeedback.reason_short(danger.kind)
	if beginner and danger.ticks_left >= 0:
		sub += " · %.1f초" % (danger.ticks_left * Tuning.DT)
	_outlined(Vector2(head.x - 300 * ui_k, y + 40 * ui_k), sub, 26, 600 * ui_k, Color(1, 0.9, 0.8))
	if beginner:
		_draw_rescue_hint(t)


## 주의 종류(release_risk)에 따라 떼면 떨어지기까지의 시간(초).
func _fall_seconds(k: StringName) -> float:
	var ticks := session.rules.grace_budget if k == &"GRACE" else session.rules.imbalance_budget
	return ticks * Tuning.DT


## 화면 가장자리 빛: 위험이면 심장 박동에 맞춰 뛰는 빨강, 회복이면 잠깐 초록.
func _draw_danger_glow(size: Vector2) -> void:
	if danger.danger:
		draw_texture_rect(_glow, Rect2(Vector2.ZERO, size), false, Color(1.0, 0.1, 0.05, 0.5 + 0.45 * danger.pulse()))
	elif danger.recover_left > 0.0:
		draw_texture_rect(_glow, Rect2(Vector2.ZERO, size), false, Color(0.35, 1.0, 0.5, 0.6 * danger.recover_left / DangerFeedback.RECOVER_SHOW))


## 패드 옆 안내 글자 위치: 위쪽 패드(손)는 아래에, 아래쪽 패드(발)는 위에(위쪽 정보 패널과 겹치지 않게).
func _pad_label_pos(p: Dictionary) -> Vector2:
	var below: bool = p.center.y < _view_size().y * 0.5
	return Vector2(p.center.x - 160 * ui_k, p.center.y + (p.radius + 34 * ui_k if below else -p.radius - 16 * ui_k))


## 초급 해결 안내: 방금 뗀 손발(버틸 손이 없으면 손)이 다시 잡을 홀드(그 손발 색으로 깜빡임 + "다시 잡기") + 그 패드 깜빡임,
## 몸이 기운 경우 몸을 옮길 방향 화살표.
func _draw_rescue_hint(t: float) -> void:
	var blink := 0.5 + 0.5 * sin(t * TAU * 2.5)
	var free := {}
	for l in session.limbs:
		free[l] = not session.limbs[l].state in ["Attached", "Armed"]
	var rel := danger.rescue_release(free)
	if not rel.is_empty():
		var limb: StringName = rel.limb
		var col: Color = LIMB_COLORS[limb]
		var hp := w2s(route.slot_pos(str(rel.key)))
		var hr := maxf(_screen_r(session.body.pos, 0.16), 26 * ui_k)
		draw_circle(hp, hr, Color(col, 0.20 + 0.25 * blink))
		draw_arc(hp, hr * (1.0 + 0.25 * blink), 0, TAU, 40, Color(col, 0.95), 6 * ui_k, true)
		_outlined(Vector2(hp.x - 120 * ui_k, hp.y - hr - 14 * ui_k), "다시 잡기", 26, 240 * ui_k, Color.WHITE)
		if router.pads.has(limb):
			var p: Dictionary = router.pads[limb]
			draw_arc(p.center, p.radius + 8 * ui_k, 0, TAU, 48, Color(col, 0.5 + 0.5 * blink), 9 * ui_k)
			_outlined(_pad_label_pos(p), "이 패드로 다시 잡아요", 24, 320 * ui_k, Color.WHITE)
	if danger.kind != &"GRACE":
		var body: Vector2 = session.body.pos
		var cx := session.rules.support_center_x(body, session.body.angle, session.attached(), session.body.yaw)
		var dx := clampf(cx - body.x, -0.6, 0.6)
		if absf(dx) > 0.04:
			var a := w2s(body + Vector2(0, 0.1))
			var b := w2s(body + Vector2(dx, 0.1))
			var dir := (b - a).normalized()
			var len := maxf(a.distance_to(b), 70 * ui_k)
			b = a + dir * len
			var col := Color(0.6, 1.0, 0.7, 0.7 + 0.3 * blink)
			draw_line(a, b, Color(0, 0, 0, 0.5), 16 * ui_k)
			draw_line(a, b, col, 9 * ui_k)
			var n := Vector2(-dir.y, dir.x)
			draw_colored_polygon(PackedVector2Array([b + dir * 26 * ui_k, b + n * 20 * ui_k, b - n * 20 * ui_k]), col)
			_outlined(Vector2((a.x + b.x) * 0.5 - 150 * ui_k, a.y + 44 * ui_k), "몸을 이쪽으로", 24, 300 * ui_k, Color.WHITE)


## 위험 게이지(캐릭터 둘레 고리) 중심·반지름(화면 px).
func _ring() -> Array:
	var body: Vector2 = session.body.pos
	return [w2s(body + Vector2(0, 0.35)), _screen_r(body, 0.95)]


## 초급: 위험 게이지를 누르면 자동 도움. 고리 아래에 남은 횟수, 다 쓰면 "자동 도움 끝".
func _draw_rescue_button(_size: Vector2) -> void:
	if not beginner or not danger.danger or session.falling or (tutorial != null and not tutorial.rescue_allowed()):
		return
	var ring := _ring()
	var c: Vector2 = ring[0]
	var r: float = ring[1]
	var y := c.y + r - 18 * ui_k
	if rescue_left <= 0:
		_outlined(Vector2(c.x - 200 * ui_k, y), "자동 도움 끝", 22, 400 * ui_k, Color(1, 1, 1, 0.6))
		return
	var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 2.0)
	var w := 300.0 * ui_k
	var pill := Rect2(Vector2(c.x - w * 0.5, y - 32 * ui_k), Vector2(w, 46 * ui_k))
	hud.panel(self, pill, ui_k, Color(0.96, 0.84, 0.55, 0.95), Color(1, 1, 1, 0.9), 23.0)
	draw_string(font, Vector2(pill.position.x, pill.position.y + 32 * ui_k), "눌러서 자동 도움 %d/%d" % [rescue_left, RESCUE_PER_ATTEMPT], HORIZONTAL_ALIGNMENT_CENTER, w, int(22 * ui_k), Color(0.19, 0.15, 0.11))
	draw_arc(c, r + 10 * ui_k, 0, TAU, 64, Color(1, 0.9, 0.6, 0.35 + 0.4 * blink), 4 * ui_k, true)
	overlay.add_buttons([{"rect": Rect2(c - Vector2(r, r), Vector2(r, r) * 2), "circle": [c, r + 16 * ui_k], "action": "rescue"}])


## 테두리 있는 가운데 정렬 글자. pos: 왼쪽 기준선, w: 폭.
func _outlined(pos: Vector2, text: String, fs: int, w: float, col: Color, outline := Color(0, 0, 0, 0.75)) -> void:
	var px := int(fs * ui_k)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, w, px, maxi(4, int(px * 0.16)), Color(outline, outline.a * col.a))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, w, px, col)


## 노란 원 안 "!".
func _draw_bang(c: Vector2, r: float, col: Color) -> void:
	draw_circle(c, r, col)
	draw_arc(c, r, 0, TAU, 32, Color(0.25, 0.12, 0.0, 0.8), 3 * ui_k, true)
	draw_string(font, Vector2(c.x - r, c.y + r * 0.55), "!", HORIZONTAL_ALIGNMENT_CENTER, r * 2, int(r * 1.5), Color(0.25, 0.12, 0.0))


## 끌고 있는 손발 아래에 지금 놓으면 잡히는 홀드가 있으면(세션 후보) 그 홀드를 그 팔다리 색으로 반짝이고
## "놓으면 잡혀요"를 띄운다(가동범위 부채꼴 대신, 2026-11-04 사용자 결정). 후보는 실제 잡기 판정과 같다.
## 몸통 끌기 중: 골반에서 목표 골반 쪽으로 화살표(docs/03 v0.9).
func _draw_body_goal() -> void:
	var g: Vector2 = session.rules.body_goal
	if not session.body_dragging() or not g.is_finite():
		return
	var a := w2s(session.body.pos)
	var b := w2s(g)
	if a.distance_to(b) < 4.0:
		draw_circle(a, 10 * ui_k, Color(1, 1, 1, 0.8))
		return
	var col := Color("fff2c8")
	draw_line(a, b, Color(0, 0, 0, 0.6), 9 * ui_k)
	draw_line(a, b, col, 5 * ui_k)
	var d := (b - a).normalized()
	var n := d.orthogonal()
	draw_colored_polygon(PackedVector2Array([b + d * 14 * ui_k, b - d * 6 * ui_k + n * 11 * ui_k, b - d * 6 * ui_k - n * 11 * ui_k]), col)


func _draw_grab_ready() -> void:
	if session.selecting:
		return
	var p := PlayOverlay.pulse(Time.get_ticks_msec() * 0.001 * 1.6)
	for limb in session.limbs:
		var l: Dictionary = session.limbs[limb]
		if l.state != "Dragging" or l.cand.is_empty():
			continue
		var key: String = l.cand.key
		var col: Color = LIMB_COLORS[limb]
		var c := w2s(l.cand.point)
		var rr := _screen_r(route.slots[key].pos, 0.11)
		draw_circle(c, rr * (1.6 + 0.6 * p), Color(col, 0.22 + 0.28 * p))
		draw_circle(c, rr * 1.15, Color(col, 0.35))
		draw_arc(c, rr * 1.3, 0, TAU, 36, Color(0.05, 0.05, 0.08, 0.75), 10.0 * ui_k)
		draw_arc(c, rr * 1.3, 0, TAU, 36, Color(col, 1.0), 6.0 * ui_k)
		var fs := int(24 * ui_k)
		var tp := c + Vector2(-160 * ui_k, -rr * 1.5 - 10 * ui_k)
		draw_string(font, tp + Vector2(0, 2 * ui_k), "놓으면 잡혀요", HORIZONTAL_ALIGNMENT_CENTER, 320 * ui_k, fs, Color(0, 0, 0, 0.8))
		draw_string(font, tp, "놓으면 잡혀요", HORIZONTAL_ALIGNMENT_CENTER, 320 * ui_k, fs, Color.WHITE)


## 지금 튜토리얼 단계 목표가 가리키는 홀드 키. 튜토리얼이 아니거나 목표에 홀드가 없으면 "".
func _tutorial_goal_key() -> String:
	if tutorial == null or tutorial.done:
		return ""
	return PlayAttempt.goal_slot(tutorial.current(), route)


## 튜토리얼 목표 홀드를 계속 반짝이게 표시한다(밝기·크기가 함께 출렁임, 기술 홀드 고르기와 같은 모양).
func _draw_goal_mark(key: String) -> void:
	var goal: Dictionary = tutorial.current().get("goal_event", {})
	var hand: bool = PoseSolver.is_hand(StringName(goal.limb)) if goal.has("limb") else (route.slots[key].allowed.has(&"LH") or route.slots[key].allowed.has(&"RH"))
	var p := PlayOverlay.pulse(Time.get_ticks_msec() * 0.001)
	var c := w2s(route.slots[key].pos)
	draw_circle(c, _screen_r(route.slots[key].pos, 0.11) * (1.15 + 0.35 * p), Color(1.0, 0.95, 0.78, 0.18 + 0.30 * p))
	_draw_hold_mark(key, hand, false)


# ---------- 기술 선택 UI (docs/27 §6, 05 v0.6, 18 v0.6) ----------

func _close_ui() -> void:
	if session != null and session.selecting:
		session.close_select()
	ui_mode = UI.NONE
	hold_targets = []
	preview = {}
	_hold_index = -2


func _cancel_select(with_message: bool) -> void:
	_close_ui()
	if with_message:
		_flash("기술을 취소했어요")


func _view_size() -> Vector2:
	return get_viewport_rect().size


func _btn_rect(size: Vector2) -> Rect2:
	var w := 240.0 * ui_k
	return Rect2(Vector2(size.x * 0.5 - w * 0.5, _hud_bottom() * ui_k + 10.0 * ui_k), Vector2(w, 44.0 * ui_k))


func _panel_rect(size: Vector2) -> Rect2:
	var b := _btn_rect(size)
	var rows := maxi(1, ceili(float(_panel_techs().size()) / ENTRY_COLS))
	return Rect2(Vector2(size.x * 0.5 - 400.0 * ui_k, b.end.y + 8.0 * ui_k), Vector2(800.0 * ui_k, rows * 64.0 * ui_k + 12.0 * ui_k))


func _entry_rect(size: Vector2, i: int) -> Rect2:
	var p := _panel_rect(size)
	var cw := (776.0 - 24.0) / ENTRY_COLS
	return Rect2(p.position + Vector2((12.0 + (i % ENTRY_COLS) * (cw + 8.0)) * ui_k, (10.0 + (i / ENTRY_COLS) * 64.0) * ui_k), Vector2(cw, 56.0) * ui_k)


## 쪽 버튼: 왼쪽은 LH·LF 패드 사이, 오른쪽은 RH·RF 패드 사이.
func _side_rect(side: StringName) -> Rect2:
	var a: Vector2 = router.pads[&"LH" if side == &"left" else &"RH"].center
	var b: Vector2 = router.pads[&"LF" if side == &"left" else &"RF"].center
	var sz := Vector2(150.0, 76.0) * ui_k
	return Rect2((a + b) * 0.5 - sz * 0.5, sz)


## 패널에 그릴 기술 id 목록(allowed 순서, 정의가 있는 버튼 기술만).
static func panel_techs_for(allowed: Array[StringName], defs: Dictionary) -> Array:
	var out := []
	for id in allowed:
		if defs.has(id) and defs[id].input == &"button":
			out.append(id)
	return out


## 기술 버튼을 보이고 받을지(28 §5.5). 버튼 기술이 하나도 없으면 숨긴다.
static func shows_tech_button(allowed: Array[StringName], defs: Dictionary) -> bool:
	return not panel_techs_for(allowed, defs).is_empty()


func _panel_techs() -> Array:
	return panel_techs_for(allowed_buttons, _techs)


## 가벼운 검사(0.2초마다): 두 쪽 다 안 되면 흐리게. 흐려도 누를 수는 있다.
func _refresh_dim() -> void:
	_check_timer = CHECK_INTERVAL
	var snap := ClimbSnapshot.from_session(session)
	for id in _panel_techs():
		var j := TechniqueJudge.light_judge(snap, id)
		dim[id] = not j.values().any(func(r): return r.available)


## 기술 UI 입력. 선택 중이면 항상 받아 쓴다(패드 입력 없음). 쓴 입력이면 true.
func _ui_event(index: int, pos: Vector2, pressed: bool) -> bool:
	if not shows_tech_button(allowed_buttons, _techs):
		return false  # 버튼 기술이 없으면 기술 버튼·홀드 탭 입력을 받지 않는다
	var size := _view_size()
	var btn := _btn_rect(size)
	if not session.selecting:
		if pressed and btn.has_point(pos):
			if session.cancel_technique():  # 실행 중이면 버튼은 "풀기"
				_flash("기술을 취소했어요")
			else:
				_open_select()
			return true
		return false
	if pressed and btn.has_point(pos):
		_cancel_select(ui_mode != UI.PANEL)  # 같은 버튼: 닫기(시간 재개)
		return true
	if ui_mode == UI.HOLD:
		if pressed:
			_hold_index = index
			_hold_preview(pos)
		elif index == _hold_index:
			_hold_index = -2
			_hold_commit(pos)
		return true
	if not pressed:
		return true
	if router._pad_at(pos) != &"":
		return true  # 패드는 선택 중 입력을 받지 않는다
	match ui_mode:
		UI.PANEL:
			_panel_tap(size, pos)
		UI.SIDE:
			_side_tap(pos)
	return true


func _ui_drag(index: int, pos: Vector2) -> void:
	if ui_mode == UI.HOLD and index == _hold_index:
		_hold_preview(pos)


func _open_select() -> void:
	if session.is_dragging() or not session.runner.active.is_empty() or session.falling:
		return
	if session.open_select():
		_apply(router.cancel_all())  # 입력 세대 증가, 눌러 둔 터치 정리
		ui_mode = UI.PANEL
		_refresh_dim()


func _panel_tap(size: Vector2, pos: Vector2) -> void:
	var ids := _panel_techs()
	for i in ids.size():
		if _entry_rect(size, i).has_point(pos):
			_pick_tech(ids[i])
			return
	if not _panel_rect(size).has_point(pos):
		_cancel_select(false)  # 빈 벽 탭: 닫기


func _pick_tech(id: StringName) -> void:
	sel_tech = id
	side_judge = TechniqueJudge.judge(ClimbSnapshot.from_session(session), id)
	ui_mode = UI.SIDE


func _side_tap(pos: Vector2) -> void:
	for side in [&"left", &"right"]:
		if not _side_rect(side).has_point(pos):
			continue
		if not side_judge.has(side):
			continue
		var j: Dictionary = side_judge[side]
		if not j.available:
			_flash(j.text if not j.text.is_empty() else String(j.reason))  # 불가능: 이유 한 줄
			return
		if TechniqueJudge.uses_hold(sel_tech):
			sel_side = side
			hold_targets = TechniqueJudge.hold_targets(ClimbSnapshot.from_session(session), sel_tech, side)
			preview = {}
			ui_mode = UI.HOLD
		else:
			_start_technique(side, "", Vector2.INF)
		return
	_cancel_select(true)  # 빈 벽 탭: 취소


func _start_technique(side: StringName, key: String, point: Vector2) -> void:
	var r := session.choose(sel_tech, side, key, point)
	if r != &"":
		var text := TechniqueJudge.text_for(r)
		_flash(text if not text.is_empty() else String(r))
		return
	_close_ui()


## 탭 위치에서 가장 가까운 홀드 슬롯 키(영역 선분까지 거리 HOLD_PICK_RADIUS 이내). 없으면 "".
func _slot_at(p: Vector2) -> String:
	var best := ""
	var best_d := HOLD_PICK_RADIUS
	var limb := TechniqueJudge.limb_for(sel_tech, sel_side)
	for key in route.slots:
		var seg := _area_segment(route.slots[key], PoseSolver.is_hand(limb))
		var d := _dist_to_segment(p, seg[0], seg[1])
		if d < best_d or (is_equal_approx(d, best_d) and best == ""):
			best = key
			best_d = d
	return best


## 홀드의 잡기/디딤 영역 선분 [a, b]. 손 기술은 hand_area, 발 기술은 foot_area(없으면 한 점).
func _area_segment(slot: Dictionary, hand: bool) -> Array:
	if hand and slot.has("hand_area"):
		return [slot.pos - slot.hand_area.dir * slot.hand_area.half_width, slot.pos + slot.hand_area.dir * slot.hand_area.half_width]
	if not hand and slot.has("foot_area"):
		return [slot.pos - slot.foot_area.up * slot.foot_area.half_height, slot.pos + slot.foot_area.up * slot.foot_area.half_height]
	return [slot.pos, slot.pos]


func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := 0.0 if ab.length_squared() < 0.000001 else clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _hold_preview(pos: Vector2) -> void:
	var p := s2w(pos)
	var key := _slot_at(p)
	if key.is_empty():
		preview = {}
		return
	var c := TechniqueJudge.check_hold(ClimbSnapshot.from_session(session), sel_tech, sel_side, key, p)
	preview = {"key": key, "ok": c.ok, "point": c.point if c.ok else p, "quality": c.quality, "text": c.text}


func _hold_commit(pos: Vector2) -> void:
	var p := s2w(pos)
	preview = {}
	var key := _slot_at(p)
	if key.is_empty():
		_cancel_select(true)  # 빈 벽 탭: 취소
		return
	var c := TechniqueJudge.check_hold(ClimbSnapshot.from_session(session), sel_tech, sel_side, key, p)
	if not c.ok:
		_flash(c.text if not c.text.is_empty() else String(c.reason))  # 후보가 아닌 홀드: 이유
		return
	_start_technique(sel_side, key, p)


func _quality_label(q: float) -> String:
	return "잘 잡음" if q >= 0.85 else ("보통" if q >= 0.5 else "끝을 잡음")


func _quality_color(q: float) -> Color:
	return Color("b8e0a0") if q >= 0.85 else (Color("f1d59a") if q >= 0.5 else Color("ff9a6a"))


## 색과 함께 모양으로도 구분: 좋음 = 동그라미, 보통 = 마름모, 끝 = 삼각형.
func _draw_quality_glyph(c: Vector2, q: float, r: float) -> void:
	var col := _quality_color(q)
	var ink := Color("302820")
	var pts := PackedVector2Array()
	if q >= 0.85:
		draw_circle(c, r, col)
		draw_arc(c, r, 0, TAU, 20, ink, 2.0)
		return
	if q >= 0.5:
		pts = PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
	else:
		pts = PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, r), c + Vector2(-r, r)])
	draw_colored_polygon(pts, col)
	pts.append(pts[0])
	draw_polyline(pts, ink, 2.0)


func _draw_lock(c: Vector2, k: float, col: Color) -> void:
	draw_arc(c + Vector2(0, -4 * k), 5 * k, PI, TAU, 10, col, 2.0 * k)
	draw_rect(Rect2(c + Vector2(-7, -4) * k, Vector2(14, 11) * k), col)


func _draw_button(r: Rect2, text: String, fs: int, fill: Color, text_col: Color, outline: Color = Color(1, 1, 1, 0.5)) -> void:
	draw_rect(r, fill)
	draw_rect(r, outline, false, 2.0)
	draw_string(font, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + fs * 0.35), text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, text_col)


func _screen_r(p: Vector2, meters: float) -> float:
	return w2s(p).distance_to(w2s(p + Vector2(meters, 0)))


func _draw_tech_ui(size: Vector2) -> void:
	var k := ui_k
	var btn := _btn_rect(size)
	var running: Dictionary = session.runner.active
	if not shows_tech_button(allowed_buttons, _techs):
		return  # 버튼 기술이 없으면 기술 버튼을 그리지 않는다
	var disabled := (session.is_dragging() or session.falling) and running.is_empty()
	var label := "기술"
	if not running.is_empty():
		var stage: String = STAGE_TEXT.get(running.step, "")
		label = "풀기 · %s" % _techs[running.id].name_ko  # 실행 중 같은 버튼은 풀기(27 §6 5)
		if not stage.is_empty():
			label += " · " + stage
	var open := session.selecting
	_draw_button(btn, label, int(20 * k), Color("f1d59a", 0.9) if open else Color(0.1, 0.1, 0.1, 0.6 if not disabled else 0.35),
		Color("302820") if open else Color(1, 1, 1, 0.45 if disabled else 1.0))
	if session.is_dragging() and running.is_empty():
		_draw_lock(btn.position + Vector2(btn.size.x - 20 * k, btn.size.y * 0.5), k, Color(1, 1, 1, 0.5))
	if not open:
		return
	draw_string(font, Vector2(btn.end.x + 14 * k, btn.position.y + btn.size.y * 0.5 + 8 * k), "고르는 중 · 시간 멈춤", HORIZONTAL_ALIGNMENT_LEFT, -1, int(24 * k), Color("fff2c8"))
	match ui_mode:
		UI.PANEL:
			_draw_panel(size)
		UI.SIDE:
			_draw_prompt(btn, "%s · 쪽을 골라 주세요" % _techs[sel_tech].name_ko)
			for side in [&"left", &"right"]:
				if side_judge.has(side):
					_draw_side_button(side)
		UI.HOLD:
			_draw_prompt(btn, "%s · 쓸 홀드를 눌러 주세요" % _techs[sel_tech].name_ko)
			_draw_hold_select(size)


func _draw_prompt(btn: Rect2, text: String) -> void:
	draw_string(font, Vector2(btn.position.x - 160 * ui_k, btn.end.y + 30 * ui_k), text, HORIZONTAL_ALIGNMENT_CENTER, btn.size.x + 320 * ui_k, int(24 * ui_k), Color.WHITE)


func _draw_panel(size: Vector2) -> void:
	var k := ui_k
	draw_rect(_panel_rect(size), Color(0.08, 0.07, 0.06, 0.7))
	var ids := _panel_techs()
	for i in ids.size():
		var r := _entry_rect(size, i)
		var is_dim: bool = dim.get(ids[i], false)
		_draw_button(r, _techs[ids[i]].name_ko, int(19 * k), Color(0.18, 0.2, 0.2, 0.35 if is_dim else 0.9), Color(1, 1, 1, 0.5 if is_dim else 1.0), Color(1, 1, 1, 0.25 if is_dim else 0.6))
		if is_dim:
			_draw_lock(r.position + Vector2(r.size.x - 14 * k, 14 * k), k * 0.8, Color(1, 1, 1, 0.6))  # 색 말고 아이콘으로도 표시


func _draw_side_button(side: StringName) -> void:
	var k := ui_k
	var r := _side_rect(side)
	var j: Dictionary = side_judge[side]
	var ok: bool = j.available
	_draw_button(r, "왼쪽" if side == &"left" else "오른쪽", int(26 * k), Color("4fa3d9" if side == &"left" else "e08a3c", 0.9 if ok else 0.25),
		Color(1, 1, 1, 1.0 if ok else 0.5), Color(1, 1, 1, 0.9 if ok else 0.3))
	if not ok:
		_draw_lock(r.position + Vector2(r.size.x * 0.5, r.size.y - 16 * k), k, Color(1, 1, 1, 0.75))


func _draw_dashed_circle(c: Vector2, r: float, col: Color, width: float) -> void:
	var n := 12
	for i in n:
		var a0 := TAU * i / n
		draw_arc(c, r, a0, a0 + TAU / n * 0.55, 6, col, width)


## 홀드 하나 강조: 고리(실선 = 바로, 점선 = 체중을 옮긴 뒤) + 잡기 선분 또는 디딤 면.
func _draw_hold_mark(key: String, hand: bool, needs_shift: bool) -> void:
	var k := ui_k
	var slot: Dictionary = route.slots[key]
	var col := Color("a8d8d0") if needs_shift else Color("fff2c8")
	var c := w2s(slot.pos)
	var rr := _screen_r(slot.pos, 0.11)
	var ink := Color(0.19, 0.16, 0.13, 0.85)  # 밝은 벽에서도 보이게 어두운 밑선을 깐다
	draw_arc(c, rr, 0, TAU, 28, ink, 7.0 * k)
	if needs_shift:
		_draw_dashed_circle(c, rr, col, 4.0 * k)  # 점선 = 체중을 옮긴 뒤 도달
	else:
		draw_arc(c, rr, 0, TAU, 28, col, 4.0 * k)  # 실선 = 지금 바로
	var seg := _area_segment(slot, hand)
	var a := w2s(seg[0])
	var b := w2s(seg[1])
	if hand:
		draw_line(a, b, ink, 9.0 * k)
		draw_line(a, b, Color(col, 0.95), 5.0 * k)  # 잡기 영역 선분
		for e in [a, b]:
			draw_circle(e, 4.0 * k, col)
	else:
		var n := (b - a).orthogonal().normalized() * _screen_r(slot.pos, 0.05)  # 디딤 면
		draw_colored_polygon(PackedVector2Array([a + n, b + n, b - n, a - n]), Color(col, 0.45))
		draw_polyline(PackedVector2Array([a + n, b + n, b - n, a - n, a + n]), ink, 5.0 * k)
		draw_polyline(PackedVector2Array([a + n, b + n, b - n, a - n, a + n]), col, 2.5 * k)


func _draw_hold_select(size: Vector2) -> void:
	var k := ui_k
	var hand := PoseSolver.is_hand(TechniqueJudge.limb_for(sel_tech, sel_side))
	for t in hold_targets:
		_draw_hold_mark(t.key, hand, t.needs_shift)
	draw_string(font, Vector2(0, size.y - 52 * k), "실선 = 바로 가능 · 점선 = 몸을 옮겨야 닿아요", HORIZONTAL_ALIGNMENT_CENTER, size.x, int(18 * k), Color(1, 1, 1, 0.8))
	if preview.is_empty():
		return
	var pc := w2s(preview.point)
	if preview.ok:
		_draw_quality_glyph(pc, preview.quality, 11.0 * k)
		var qp := pc + Vector2(-70 * k, -20 * k)
		draw_string_outline(font, qp, _quality_label(preview.quality), HORIZONTAL_ALIGNMENT_CENTER, 140 * k, int(20 * k), 6, Color("302820"))
		draw_string(font, qp, _quality_label(preview.quality), HORIZONTAL_ALIGNMENT_CENTER, 140 * k, int(20 * k), _quality_color(preview.quality))
	else:
		draw_line(pc + Vector2(-8, -8) * k, pc + Vector2(8, 8) * k, Color("ff8a6a"), 3.0 * k)
		draw_line(pc + Vector2(-8, 8) * k, pc + Vector2(8, -8) * k, Color("ff8a6a"), 3.0 * k)
		draw_string(font, pc + Vector2(-140 * k, -20 * k), preview.text, HORIZONTAL_ALIGNMENT_CENTER, 280 * k, int(18 * k), Color("ff8a6a"))
