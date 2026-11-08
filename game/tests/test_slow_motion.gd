extends RefCounted
## 초급 슬로우모션(SlowMotion)과 난이도 저장(Progress.level). 2026-11-08 사용자 요청.

var runner
const DT := 1.0 / 60.0
const SAVE := "user://test_level_save.json"


## frames 프레임 동안 돌리고 돌린 판정 틱 수.
func _run(s: SlowMotion, danger: bool, frames: int, ended := false) -> int:
	var n := 0
	for i in frames:
		n += s.update(danger, ended, DT)
	return n


func test_off_by_default_runs_every_tick() -> void:
	var s := SlowMotion.new()
	runner.check(_run(s, true, 120) == 120 and s.scale == 1.0, "중급(꺼짐): 위험해도 매 프레임 판정")


func test_danger_slows_to_tenth_for_three_seconds() -> void:
	var s := SlowMotion.new()
	s.enabled = true
	runner.check(_run(s, false, 30) == 30, "안정: 정상 속도")
	var n := _run(s, true, 182)  # 실제 3초(+켜지는 프레임)
	runner.check(n >= 18 and n <= 24, "위험 3초 동안 판정 약 0.3초(18틱) 분량: %d" % n)
	runner.check(not s.active(), "3초 뒤 끝남")
	var after := _run(s, true, 60)
	runner.check(after >= 54, "끝난 뒤 계속 위험해도 다시 느려지지 않음: %d" % after)


func test_recover_ends_early() -> void:
	var s := SlowMotion.new()
	s.enabled = true
	_run(s, true, 30)
	runner.check(s.active() and s.scale < 0.5, "위험 0.5초: 느려진 상태")
	_run(s, false, 12)
	runner.check(not s.active() and s.scale >= 0.999, "균형을 되찾으면 바로 정상 속도: %.2f" % s.scale)
	runner.check(_run(s, false, 60) == 60, "되찾은 뒤 매 프레임 판정")


func test_fall_ends_slow_motion() -> void:
	var s := SlowMotion.new()
	s.enabled = true
	_run(s, true, 20)
	_run(s, true, 12, true)
	runner.check(not s.active() and s.scale >= 0.999, "떨어지면(추락 연출) 정상 속도")


func test_cooldown_then_retrigger() -> void:
	var s := SlowMotion.new()
	s.enabled = true
	_run(s, true, 20)
	_run(s, false, 10)
	_run(s, true, 10)
	runner.check(not s.active(), "끝나고 1초 안에 다시 위험: 느려지지 않음")
	_run(s, false, 60)
	_run(s, true, 2)
	runner.check(s.active(), "1초 뒤 새로 위험: 다시 느려짐")


func test_level_saved_and_drives_slow_motion() -> void:
	var p := Progress.new()
	runner.check(p.level == "", "처음엔 난이도 안 고름")
	var flow := PlayFlow.new(ContentIndex.new(), p, SAVE)
	flow.set_level("beginner")
	runner.check(flow.slow_motion_enabled(), "초급: 슬로우모션 켬")
	var loaded := SaveStore.load(SAVE)
	runner.check(loaded.level == "beginner", "난이도 저장·불러오기")
	flow.set_level("intermediate")
	runner.check(not flow.slow_motion_enabled(), "중급: 슬로우모션 끔")
	flow.set_level("expert")
	runner.check(p.level == "intermediate", "모르는 값 무시")
	runner.check(Progress.from_dict({"level": "zzz"}).level == "", "저장 파일의 모르는 값은 안 고름으로")
	for f in [SAVE, SAVE + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
