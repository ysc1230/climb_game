extends RefCounted
## 내 고스트·시범 보기 자세 기록(docs/superpowers/specs/2026-11-19-3-score-design.md §3.5).

var runner


func _session() -> ClimbSession:
	return ClimbSession.new(RouteDef.load_json("res://data/routes/general/G_V3_03.json"))


func test_records_ten_per_second() -> void:
	var s := _session()
	var g := GhostTrack.new()
	for i in 120:
		g.record(s, 1.0 / 60.0)
	runner.check(g.frames.size() == 20 or g.frames.size() == 21, "2초 → 10Hz로 약 20개 (%d)" % g.frames.size())
	runner.check(absf(g.duration() - 2.0) < 0.11, "길이 %.2f" % g.duration())


func test_sample_interpolates() -> void:
	var s := _session()
	var g := GhostTrack.new()
	var p0 := s.body.pos
	g.record(s, 0.0)
	s.body.pos = p0 + Vector2(1.0, 0.0)
	g.record(s, 0.1)
	var m := g.sample(0.05)
	runner.check((m.pelvis as Vector2).is_equal_approx(p0 + Vector2(0.5, 0.0)), "가운데는 반 %s" % m.pelvis)
	runner.check(m.limbs.has(&"LH") and m.attached.has(&"LH"), "손발 위치·붙음")
	runner.check((g.sample(99.0).pelvis as Vector2).is_equal_approx(p0 + Vector2(1.0, 0.0)), "끝 뒤는 마지막")


func test_dict_roundtrip_rounded() -> void:
	var s := _session()
	var g := GhostTrack.new()
	for i in 30:
		s.body.pos += Vector2(0.0123456, 0.0)
		g.record(s, 0.1)
	var d := g.to_dict()
	var h := GhostTrack.from_dict(JSON.parse_string(JSON.stringify(d)))
	runner.check(h.frames.size() == g.frames.size() and absf(h.duration() - g.duration()) < 1e-3, "저장 뒤 같음")
	runner.check(((h.sample(1.0).pelvis as Vector2) - (g.sample(1.0).pelvis as Vector2)).length() < 2e-3, "소수 셋째 자리")
	runner.check(GhostTrack.from_dict({}).frames.is_empty() and GhostTrack.from_dict({"f": "x"}).frames.is_empty(), "잘못된 값은 빈 기록")


func test_time_of_height() -> void:
	var s := _session()
	var g := GhostTrack.new()
	var p0 := s.body.pos
	for i in 11:
		s.body.pos = p0 + Vector2(0.0, 0.1 * i)
		g.record(s, 0.1)
	runner.check(absf(g.time_at_height(p0.y + 0.5) - 0.5) < 0.11, "골반이 그 높이에 처음 닿는 때 %.2f" % g.time_at_height(p0.y + 0.5))
	runner.check(g.time_at_height(p0.y - 5.0) == 0.0, "이미 넘었으면 처음부터")
