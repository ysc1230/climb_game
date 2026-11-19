extends RefCounted
## 손 힘 경고 40%·20%(docs/superpowers/specs/2026-11-19-1-feel-design.md §1.3).

var runner


func test_levels() -> void:
	runner.check(GripWarning.level(100.0, GripWarning.NONE) == GripWarning.NONE, "100 → 없음")
	runner.check(GripWarning.level(39.9, GripWarning.NONE) == GripWarning.CAUTION, "39.9 → 주의")
	runner.check(GripWarning.level(19.9, GripWarning.CAUTION) == GripWarning.DANGER, "19.9 → 위험")
	runner.check(GripWarning.level(5.0, GripWarning.NONE) == GripWarning.DANGER, "5 → 위험")


func test_warning_hysteresis() -> void:
	runner.check(GripWarning.level(41.0, GripWarning.CAUTION) == GripWarning.CAUTION, "41 주의 유지")
	runner.check(GripWarning.level(44.9, GripWarning.CAUTION) == GripWarning.CAUTION, "44.9 주의 유지")
	runner.check(GripWarning.level(45.0, GripWarning.CAUTION) == GripWarning.NONE, "45 → 없음")
	runner.check(GripWarning.level(21.0, GripWarning.DANGER) == GripWarning.DANGER, "21 위험 유지")
	runner.check(GripWarning.level(25.0, GripWarning.DANGER) == GripWarning.CAUTION, "25 → 주의")
	runner.check(GripWarning.level(41.0, GripWarning.NONE) == GripWarning.NONE, "41은 처음엔 없음")


func test_blink_and_tremble() -> void:
	runner.check(GripWarning.blink_hz(GripWarning.NONE) == 0.0, "없음 깜빡임 0")
	runner.check(GripWarning.blink_hz(GripWarning.CAUTION) == 2.0, "주의 2Hz")
	runner.check(GripWarning.blink_hz(GripWarning.DANGER) == 4.0, "위험 4Hz")
	runner.check(GripWarning.tremble(GripWarning.NONE) == Vector2.ZERO, "없음 떨림 0")
	runner.check(GripWarning.tremble(GripWarning.CAUTION) == Vector2(0.003, 8.0), "주의 ±3mm 8Hz")
	runner.check(GripWarning.tremble(GripWarning.DANGER) == Vector2(0.006, 12.0), "위험 ±6mm 12Hz")
