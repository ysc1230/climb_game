# 일반·기술 모드, 등급 문제, 기술 과정 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 기술 버튼을 아웃사이드 엣지·드롭니 2개로 줄이고, 홈의 일반(V0~V2 등급 문제)·기술(과정 튜토리얼·문제) 탭과 저장·해금·튜토리얼·검증 봇을 만들어 1차 콘텐츠 33개를 넣는다.

**Architecture:** 판정·진행·튜토리얼·검증은 노드 없는 순수 GDScript(RefCounted)로 두고 헤드리스 테스트로 검증한다. 검증 봇은 게임과 같은 ClimbSession을 합성 패드 명령으로 몰아 결과가 게임 판정과 어긋나지 않게 한다. 화면은 홈 장면과 기존 플레이 장면을 Game 자동 로드가 잇는다.

**Tech Stack:** Godot 4.7.2, GDScript, 헤드리스 테스트 러너(`game/tests/run_tests.gd`), Android export.

**Spec:** `docs/28_modes_grades_courses_design.md` (브랜치 design/modes-grades). 기술 판정 세부는 `docs/27_technique_actions_design.md`, 튜토리얼 원본 단계는 `docs/16_stage_specs.md` T01~T03.

## Global Constraints

- 작업 브랜치 `design/modes-grades`. main에 합치지 않는다.
- 판정·진행 로직은 노드 의존 없는 RefCounted. 새 로직마다 `game/tests/test_*.gd` 테스트(AGENTS).
- 테스트 명령: `cd game && godot --headless --import >/dev/null 2>&1; godot --headless --script res://tests/run_tests.gd` → 마지막 줄 `N개 중 0개 실패`.
- 능력치 성장 없음. 해금은 버튼 노출만 바꾸고 판정 수치를 바꾸지 않는다(28 §2·§3).
- 같은 자세는 버튼이든 패드든 같은 판정(27 §3). forbid 플래그는 검증 봇 전용이며 플레이 경로에서 켜지지 않는다.
- 사용자 문구는 한국어, 28에 적힌 문구를 그대로 쓴다.
- Tuning 수치는 바꾸지 않는다(TUNING_VERSION 4 유지). 28 §4.3의 동률 여유 0.02는 새 상수.
- 커밋 메시지 끝: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. 모델 이름을 코드·문서에 쓰지 않는다.

## Review Focus

1. **예전 저장/R01 기록:** R01을 G_V0_01로 옮겨도 저장 파일이 없거나 깨져 있으면 새 진행으로 시작해야 하고 크래시가 없어야 한다 → Task 6 테스트 `test_load_corrupt_file_starts_fresh`.
2. **버튼이 하나도 없는 플레이:** 해금된 버튼 기술이 없으면 기술 버튼 자체가 보이지 않고, 홀드 탭 입력도 받지 않는다 → Task 8 `test_no_unlocked_buttons_hides_panel`(play_test 로직 함수 단위).
3. **튜토리얼 추락 반복:** 추락 후 단계 재시작이 무한 반복되지 않고, 추락이 목표인 단계는 완료된다 → Task 7 `test_fall_goal_completes_step`, `test_fall_restarts_step`.
4. **잡기 방향 떨림:** pull·sidepull 비용이 거의 같을 때 앞 방식을 쓴다 → Task 2 `test_grip_tie_prefers_first_mode`.
5. **잠긴 카드:** 필요 버튼 기술이 잠긴 문제는 시작할 수 없고 이유 문구를 준다 → Task 6 `test_route_locked_by_button_technique`.

---

### Task 1: 기술 버튼 정리

**Files:**
- Modify: `game/data/techniques.json`, `game/scripts/climbing/technique_defs.gd`, `technique_judge.gd`, `technique_runner.gd`, `game/scenes/play_test.gd`
- Modify/Delete tests: `game/tests/test_judge.gd`, `test_runner.gd`, `test_select.gd`, `test_technique_defs.gd`, `test_final_review.gd`, `test_deadpoint.gd`
- Create: `game/tests/test_technique_buttons.gd`

**Interfaces:**
- Produces: `TechniqueDefs.button_ids() -> Array[StringName]` = `[&"T_OUTSIDE_EDGE", &"T_DROP_KNEE"]`(phase 1·input button, techniques.json 순서). `TechniqueRunner.start(...)`는 버튼이 아닌 ID에 `&"NOT_BUTTON"`을 돌려준다. `play_test.gd`의 `var allowed_buttons: Array[StringName]`(기본값 `TechniqueDefs.button_ids()`), 비어 있으면 기술 버튼을 그리지도 받지도 않는다.

- [ ] **Step 1: 실패 테스트** `test_technique_buttons.gd`
  - `test_button_ids`: `TechniqueDefs.button_ids() == [&"T_OUTSIDE_EDGE", &"T_DROP_KNEE"]`
  - `test_every_entry_has_input`: techniques.json 모든 항목의 `input`이 `"button"` 또는 `"pad"`. `T_FLAG_INSIDE`·`T_FLAG_OUTSIDE` 항목 없음.
  - `test_removed_buttons_rejected`: R01 시작 세션에서 `runner.start(session, id, &"left")`가 T_HIGH_STEP, T_LOCK_OFF, T_REST, T_CROSS, T_MATCH, T_FOOT_SWAP, T_INSIDE_EDGE, T_DEADPOINT, T_SIDEPULL, T_GASTON, T_UNDERCLING, T_FLAG 모두 `&"NOT_BUTTON"`.
- [ ] **Step 2:** 테스트 실행 → 실패 확인.
- [ ] **Step 3: 구현.** techniques.json: 모든 항목에 `input`(OUTSIDE_EDGE·DROP_KNEE·HEEL_HOOK·TOE_HOOK·SMEAR = button, 나머지 pad), 인사이드·아웃사이드 플래그 항목 삭제, pad 항목의 how_ko를 패드 조작 설명으로 고침(28 §8.3 예시 문체). 판단기·실행기에서 버튼 전용 경로(쪽 판단·홀드 후보·실행 단계)를 지운다. **패드가 쓰는 것은 남긴다:** 패드 데드포인트(deadpoint_bonus/catch/far, `_start_pad_deadpoint`), 패드 풋스왑(`_try_pad_foot_swap`가 쓰는 판단), 합손 이동, 균형 발 flag_cost, yaw 기술 공통(yaw_pose_reason 등). play_test 패널에서 발/손/몸 탭을 없애고 `allowed_buttons` 목록 하나로 그린다.
- [ ] **Step 4: 기존 테스트 정리.** 지운 버튼만 검증하던 테스트는 지우고, 같은 동작의 패드 경로 테스트(패드 데드포인트, 패드 풋스왑, 균형 발, 합손)는 반드시 남거나 새로 있다. 파일별로 지운 테스트 이름과 이유를 보고서에 적는다.
- [ ] **Step 5:** 전체 테스트 0 실패, `godot --headless --script res://tools/route_check.gd -- R01` 두 줄 통과.
- [ ] **Step 6: 커밋** `refactor: 기술 버튼을 아웃사이드 엣지·드롭니로 정리`

### Task 2: 패드 잡기 방향 자동 선택(28 §4.3)

**Files:**
- Modify: `game/scripts/climbing/grip_check.gd`, `climb_session.gd`
- Create: `game/tests/test_grip_auto.gd`, 테스트 전용 루트 `game/data/routes/TX_GRIP.json`(사이드풀만 있는 홀드, pull+sidepull 홀드, 언더클링 홀드)

**Interfaces:**
- Produces: `GripCheck.contact_for_pose(slot_key: String, slots: Dictionary, limb: StringName, point: Vector2, pelvis: Vector2, angle: float, yaw: float, attached: Dictionary, meta: Dictionary, endpoints: Dictionary, forbid_auto := false) -> ContactInfo`. `const GRIP_TIE_MARGIN := 0.02`. ClimbSession은 패드 잡기에 이것을 쓰고 `technique_log`에 `{"type": "pad_grip", "limb", "key", "mode"}`를 남긴다(Task 3의 `_log_event` 형식).

- [ ] **Step 1: 실패 테스트**
  - `test_sidepull_only_hold_by_pad`(MG09): 몸이 홀드 반대쪽인 자세에서 패드로 잡으면 접점 mode == &"sidepull", 로그에 pad_grip mode sidepull.
  - `test_pull_preferred_below_hold`(MG10): pull·sidepull 둘 다 있는 홀드 바로 아래 자세 → pull.
  - `test_grip_tie_prefers_first_mode`: 두 방식 비용 차 < 0.02가 되게 만든 자세 → grip_modes[0].
  - `test_no_mode_solves_falls_back_first`: 어느 방식도 균형이 안 풀리면 grip_modes[0].
  - `test_low_quality_excludes_sidepull`: 끝(q < 0.5)을 잡으면 sidepull·gaston 후보 제외.
  - `test_forbid_auto_uses_first`: forbid_auto=true → 항상 grip_modes[0].
- [ ] **Step 2:** 실패 확인.
- [ ] **Step 3: 구현.** 방식마다 ContactInfo를 만들어 TechniqueJudge의 지지 판정(`support_reason`과 같은 SupportSolver 경로)으로 성립 여부와 균형 비용(ClimbRules의 flag_cost와 같은 비용)을 구한다. 맞는 래퍼가 없으면 ClimbRules에 얇은 함수 하나를 더한다. 언더클링 조건은 기존 단일 규칙 함수를 재사용한다. 성립 중 최소 비용, 차이 < 0.02면 앞 순서.
- [ ] **Step 4:** 테스트 0 실패.
- [ ] **Step 5: 커밋** `feat: 패드 잡기 방향 자동 선택`

### Task 3: 패드 기술 이벤트와 검증용 금지 플래그

**Files:**
- Modify: `game/scripts/climbing/climb_session.gd`, `climb_rules.gd`, `move_classifier.gd`
- Create: `game/tests/test_pad_events.gd`

**Interfaces:**
- Produces: technique_log 이벤트 어휘(Task 7이 소비). 기존 기술 이벤트 형식 `{tick, type, id, side, key, quality, reason}`에 더해:
  - `{"type": "move", "label": <MoveClassifier 라벨>}` — 확정 라벨이 HighStep·StandUp·CrossReach·HandMatch·LockOff로 바뀔 때 1회
  - `{"type": "grab", "limb", "key", "quality"}` — 패드·기술로 붙을 때마다
  - `{"type": "flag", "limb"}` — 패드 균형 발이 될 때
  - `{"type": "pad_foot_swap", "limb", "key"}`, `{"type": "pad_deadpoint", "limb", "key", "ok": bool}` — 이미 남기는 이벤트가 있으면 그 이름을 이것으로 맞춘다
  - `{"type": "pad_grip", ...}` (Task 2)
  - `{"type": "fall", "reason"}` — 추락 시작 시
- Produces: `ClimbSession.forbid: Dictionary`(키 StringName → true). 키와 효과(28 §7.4 표): `&"high_step"`(고관절−0.20m 위 발 후보 거부 + StandUp 선호 끔), `&"cross"`(반대 손 X 넘는 손 후보 거부), `&"flag"`(균형 발 상태 안 만듦), `&"match"`(반대 손이 잡은 홀드 거부), `&"foot_swap"`, `&"lock_off"`(LockOff 선호 대신 0.60), `&"grip_auto"`(Task 2 forbid_auto), `&"deadpoint"`(보너스 0).
- Produces: `ClimbSession.reset_to(pose: Dictionary)` — `{pelvis: [x,y], angle, slots: {limb: key}, stamina?: {LH, RH}}` 자세로 다시 시작(튜토리얼 단계 시작용, RouteDef.start_pose와 같은 형식).

- [ ] **Step 1: 실패 테스트** — 이벤트마다 하나(R01에서 높은 발판 딛기 → move HighStep 후 StandUp, 교차 잡기 → CrossReach, 발 허공에 놓기 → flag, 추락 → fall), forbid 키마다 하나(같은 입력이 금지 시 다른 결과), `test_reset_to_pose`.
- [ ] **Step 2:** 실패 확인. **Step 3:** 구현. **Step 4:** 테스트 0 실패.
- [ ] **Step 5: 커밋** `feat: 패드 기술 이벤트와 검증용 금지 플래그`

### Task 4: 문제 데이터 형식과 콘텐츠 목록

**Files:**
- Modify: `game/scripts/climbing/route_def.gd`
- Create: `game/scripts/content/content_index.gd`, `game/data/courses.json`, `game/data/routes/general/G_V0_01.json`(R01 이동), `game/tests/test_content_index.gd`
- Delete: `game/data/routes/R01.json` (참조하는 코드·테스트·도구는 G_V0_01로 바꿈. TX_*.json은 그대로)

**Interfaces:**
- Produces: RouteDef 필드 `mode`("general"/"course"), `grade`, `order`, `name_ko`, `required_techniques: Array[StringName]`, `course_id`, `course_slot`("tutorial"/"easy"/"normal"/"hard"), `tutorial_steps: Array`, `crux_steps: Dictionary`(기술 ID → intended_moves 인덱스), `check_swapped: bool`(기본 false), `intended_moves`는 Task 5 단계 형식 원본 배열 그대로도 보관(`steps_raw`). 검증 추가: mode/grade 형식(`^V\d+$`), course 문제는 course_id·course_slot 필수, required_techniques가 techniques.json에 있음, crux_steps 키 ⊆ required_techniques·인덱스 범위, tutorial만 tutorial_steps 필수.
- Produces: `ContentIndex.load_all(root := "res://data") -> ContentIndex`; `grades() -> Array[String]`(정렬 V0,V1,…), `general(grade) -> Array[RouteDef]`(order 순), `courses() -> Array[Dictionary]`(courses.json 순서), `course(course_id) -> Dictionary`, `route(route_id) -> RouteDef`, `errors: PackedStringArray`.
- courses.json 항목: `{course_id, order, name_ko, kind: "button"|"pad", techniques: [ID], tutorial: route_id, problems: [route_id ×3] (C_BASIC은 []), phase, text_ko?: {purpose, when, how}}`. 1차 6개(C_BASIC, C_HIGH_STEP, C_CROSS, C_FLAG, C_OUTSIDE_EDGE, C_DROP_KNEE), 2차 5개는 phase 2로 항목만(경로 빈 배열, 목록에서 숨김).
- G_V0_01: content_version 5, mode general, grade V0, order 1, name_ko "첫 번째 벽", required_techniques [], check_swapped true.

- [ ] Step 1 실패 테스트(필드 읽기, 각 검증 오류, ContentIndex 정렬·조회, phase 2 숨김) → Step 2 실패 확인 → Step 3 구현 → Step 4 0 실패 → Step 5 커밋 `feat: 문제 데이터 형식과 콘텐츠 목록`

### Task 5: 세션 검증 봇과 콘텐츠 검사

**Files:**
- Create: `game/scripts/content/session_bot.gd`, `game/scripts/content/grade_rules.gd`, `game/scripts/content/content_check.gd`, `game/tests/test_session_bot.gd`, `game/tests/test_content.gd`
- Modify: `game/tools/route_check.gd`(ContentCheck 사용, 인자 없으면 전체)

**Interfaces:**
- Consumes: Task 3 forbid·이벤트, Task 4 RouteDef·ContentIndex.
- Produces: `SessionBot.run(route: RouteDef, steps: Array, forbid := {}) -> SessionBot`; `ok() -> bool`, `failure: String`, `failed_step: int`(-1 = 성공 또는 목표 미도달), `log: PackedStringArray`, `metrics: Dictionary`{min_reach_margin, min_hand_half_width, max_hand_u, min_stamina, moves, seconds}.
  - 단계 형식(28 §7.4): `[limb, key]` 패드 이동, `[limb, "T_DROP_KNEE"]` 제자리 버튼 기술, `[limb, "T_OUTSIDE_EDGE", key]` 홀드로 옮기는 버튼 기술, `[hand, key, "deadpoint"]` 패드 데드포인트, `[foot, "flag", [x, y]]` 발을 그 벽 지점으로 끌어 놓기.
  - 패드 이동: detach → 말단을 2.5m/s로 목표 쪽 move 명령 → 세션 후보가 그 키가 되면 speed 0으로 release → 안정(골반 속도 < 0.01m/s 6틱, 최대 240틱). 180틱 안에 후보가 안 되면 실패. 데드포인트: `deadpoint_window()`가 열릴 때까지 최대 120틱 기다렸다가 목표 방향으로 끌어 speed 2.0으로 release. 버튼 기술: `open_select` → `choose(id, side, key, point)` → 실행기가 빌 때까지 틱. side는 limb에서(L→&"left", R→&"right").
  - 모든 단계 뒤 양손 정상 슬롯 + 세션 `step()`이 "clear"를 낼 때까지 최대 240틱.
- Produces: `GradeRules.LIMITS: Dictionary` 등급 → {min_half_width, min_reach_margin}(28 §7.3: V0 0.12/0.15, V1 0.10/0.10, V2 0.08/0.06, V3 0.06/0.03, V4 0.05/0.02, V5 0.04/0.0); `GradeRules.warnings(route, metrics) -> PackedStringArray`.
- Produces: `ContentCheck.check(route: RouteDef) -> Dictionary`{ok: bool, lines: PackedStringArray, metrics}. 순서: 저작 오류 없음 → 의도 경로 SessionBot 성공 → check_swapped면 RouteBot.swapped_pairs 형태의 교체 경로도 성공 → required_techniques마다 금지 재생이 crux 인덱스 i에서 i 또는 i+1 단계에 실패(버튼 기술은 금지 대신 그 단계를 패드 이동으로 바꾸거나 제자리 기술은 건너뜀, 패드 기술은 Task 3 forbid 키: T_HIGH_STEP→high_step, T_CROSS→cross, T_FLAG→flag, T_MATCH→match, T_FOOT_SWAP→foot_swap, T_LOCK_OFF→lock_off, T_SIDEPULL/T_GASTON/T_UNDERCLING→grip_auto, T_DEADPOINT→deadpoint) → GradeRules 경고는 lines에 "경고:"로 남기되 ok에 영향 없음. 튜토리얼(course_slot tutorial)은 의도 경로 검사만.

- [ ] Step 1 실패 테스트: `test_bot_clears_g_v0_01`(의도·교체 둘 다), `test_bot_reports_failed_step`(일부러 닿지 않는 홀드), `test_bot_button_technique_step`(TX_TECH 루트에서 드롭니 단계 실행 기록), `test_required_check_detects_unneeded`(필요 없는 기술을 required로 넣은 임시 RouteDef → ok false), `test_grade_warning`. `test_content.gd`: ContentIndex 모든 루트가 ContentCheck ok(이 테스트가 콘텐츠 작업의 관문).
- [ ] Step 2 실패 → Step 3 구현 → Step 4 0 실패, `route_check.gd` 실행 출력에 측정값이 보임 → Step 5 커밋 `feat: 세션 검증 봇과 콘텐츠 검사`

### Task 6: 진행·저장·해금

**Files:**
- Create: `game/scripts/meta/progress.gd`, `game/scripts/meta/save_store.gd`, `game/tests/test_progress.gd`

**Interfaces:**
- Produces: `Progress`(RefCounted) 데이터 `{schema_version: 1, seq: int, cleared: {route_id: {content_version, no_fall: bool, time: bool, best_seconds: float}}, tutorials: {route_id: true}, basic_skipped: bool, last_tab: "general"|"technique"}`. 함수:
  - `is_first_run() -> bool` (C_BASIC 튜토리얼 미완료이고 건너뜀도 아님)
  - `grade_unlocked(grade: String, index: ContentIndex) -> bool` (V0: 첫 실행 아님. V(n+1): V(n) 완등 ≥ 2)
  - `grade_lock_text(grade, index) -> String` 예 "V0에서 1개 더 완등하면 열려요"
  - `unlocked_buttons(index) -> Array[StringName]` (kind button 과정의 튜토리얼 완료 → 그 과정 techniques 중 button_ids에 있는 것)
  - `route_lock_text(route, index) -> String` ""면 열림. 일반: 등급 잠금 → 등급 문구, 필요 버튼 기술 잠김 → "<기술 이름>을(를) 배우면 열려요". 과정: 첫 실행이면 잠김, 과정 문제는 앞 단계(튜토리얼 → easy → normal → hard) 완료 필요 "앞 단계를 먼저 깨 주세요"
  - `record_clear(route, seconds: float, falls: int) -> void` (no_fall = falls == 0, time = seconds ≤ route.time_medal_seconds(>0일 때), 기존 메달 유지·최고 시간 갱신), `record_tutorial(route_id)`, `skip_basic()`
- Produces: `SaveStore.load(path := "user://save.json") -> Progress`(없거나 파싱 실패·schema 불일치면 새 Progress), `SaveStore.save(p: Progress, path := "user://save.json") -> bool`(seq+1, `path + ".tmp"`에 쓰고 DirAccess.rename으로 교체).

- [ ] Step 1 실패 테스트: `test_first_run_and_skip`(MG01·MG02), `test_grade_unlock_two_of_four`(MG03·MG04), `test_unlocked_buttons_after_tutorial`(MG06), `test_route_locked_by_button_technique`(MG05 문구), `test_course_slot_order`, `test_record_keeps_best`, `test_save_roundtrip`(MG14, 테스트 경로 `user://test_save.json`), `test_load_corrupt_file_starts_fresh`, `test_tmp_left_behind_keeps_previous`(MG15: .tmp만 있고 본 파일 정상 → 본 파일 로드)
- [ ] Step 2 → 3 → 4 → Step 5 커밋 `feat: 진행 저장과 해금 계산`

### Task 7: 튜토리얼 실행기

**Files:**
- Create: `game/scripts/meta/tutorial_runner.gd`, `game/tests/test_tutorial_runner.gd`

**Interfaces:**
- Consumes: Task 3 이벤트·`reset_to`, Task 4 `tutorial_steps`.
- Produces: `TutorialRunner.new(route: RouteDef)`; `index: int`, `done: bool`; `begin_step(session: ClimbSession) -> void`(start_pose 있으면 reset_to, rules 적용: `rules.fatigue_disabled = not fatigue_drain`, start_stamina를 양손에, `techniques`를 현재 단계 허용 버튼으로); `allowed_buttons() -> Array[StringName]`; `observe(session, step_result: String, dt: float) -> String` 반환 ""/"next"/"done"/"restart"(마지막으로 본 technique_log 이후 이벤트만 검사, 목표 일치 → next/done, step_result가 "fall:"로 시작하고 목표가 fall이 아니면 restart, 목표가 fall이면 next); `help_level() -> int`(0/1/2: 마지막 진행 후 12초 또는 그 단계 실패 3회 → 1, 그 상태에서 다시 12초 또는 실패 3회 → 2); `static func matches(goal: Dictionary, ev: Dictionary) -> bool`(goal의 type 외 키가 ev에 같은 값으로 있으면 일치).

- [ ] Step 1 실패 테스트: `test_matches`, `test_goal_advances`, `test_fall_restarts_step`, `test_fall_goal_completes_step`, `test_rules_applied`(피로 끔·시작 체력·버튼 목록), `test_help_levels`, `test_last_step_done`
- [ ] Step 2 → 3 → 4 → Step 5 커밋 `feat: 튜토리얼 실행기`

### Task 8: 홈 화면과 플레이 연결

**Files:**
- Create: `game/scripts/meta/game.gd`(자동 로드 `Game`), `game/scenes/home.tscn`, `game/scenes/home.gd`, `game/tests/test_play_flow.gd`
- Modify: `game/project.godot`(main_scene → home.tscn, autoload Game), `game/scenes/play_test.gd`, `game/scenes/play_3d.gd`(루트를 Game에서 받음)

**Interfaces:**
- Consumes: Task 4 ContentIndex, Task 6 Progress/SaveStore, Task 7 TutorialRunner, Task 1 allowed_buttons.
- Produces: `Game`: `progress`, `index`, `current_route_id`, `play(route_id)`(장면을 play_3d로), `home()`(home으로), `finish_clear(seconds, falls)`(기록·저장), `finish_tutorial()`, `allowed_buttons_for(route) -> Array[StringName]`(일반: progress.unlocked_buttons, 과정 튜토리얼: 과정 기술만(TutorialRunner 단계 규칙 우선), 과정 문제: 과정 기술 ∪ 해금). Game이 없을 때(play_3d 단독 실행, 테스트) play_test는 G_V0_01과 모든 버튼으로 동작한다.
- 홈(28 §5): 상단 탭 일반/기술(마지막 탭 기억). 일반: 등급 줄(V0…, 잠김은 자물쇠+문구, 완료 n/4) + 카드(이름, 필요 기술 이름, 메달 3개 상태 글자, 잠김 문구, 버튼 기술 잠김이면 [배우러 가기] → 기술 탭 그 과정). 기술: 과정 카드(이름, 버튼/패드 기술, 진행 "튜토리얼 ✓ · 문제 2/3", 버튼 기술 해금 여부) → 과정 화면(purpose/when/how, 튜토리얼 + 쉬움·보통·어려움, 잠김 문구). 첫 실행이면 바로 C_BASIC 튜토리얼, 튜토리얼 화면에 [건너뛰기].
- 플레이: 완등 시 결과 오버레이(시간·추락·메달, [다음] [다시] [목록]), 일시정지에 [목록]. 튜토리얼이면 상단에 단계 문장, [도움말](help_level ≥ 1에서 강조, 1단계 "움직일 팔다리", 2단계 "누를 버튼과 홀드" = 단계 help_ko[0/1]), 완료 시 "다 배웠어요" + [목록].
- 색으로만 잠금·완료를 나타내지 않는다(글자·자물쇠 표시 함께). 시각 세부는 구현자 판단.

- [ ] Step 1 실패 테스트(노드 없이 가능한 부분): `test_allowed_buttons_for_modes`, `test_no_unlocked_buttons_hides_panel`(play_test의 패널 표시 판정 함수를 정적 함수로 분리해 검증), `test_finish_clear_records_and_saves`(테스트 저장 경로)
- [ ] Step 2 → 3 구현 → Step 4 테스트 0 실패, 헤드리스로 home 장면 로드 시 오류 없음(`godot --headless --quit-after 120 res://scenes/home.tscn` 출력에 SCRIPT ERROR 없음)
- [ ] Step 5 커밋 `feat: 홈 일반·기술 탭과 플레이 연결`

### Task 9: 기본 조작 튜토리얼(C_BASIC)

**Files:** Create `game/data/routes/course/C_BASIC_T.json`

- [ ] **Step 1:** 16의 T01~T03 단계(T01-A~, T02-A~D, T03-A~E)를 tutorial_steps로 옮긴다. 각 단계의 완료 조건을 Task 3 이벤트로 표현(예: 지정 슬롯 grab, move StandUp, fall). 16의 단계 규칙(피로 끔·시작 체력 70·T03 A/B/C 피로 끔 D/E 켬, 시작 값 100)을 rules로. T01-C "터치 없이 1초 유지"·T03-A "6틱 동시 드래그"처럼 이벤트로 표현할 수 없는 조건은 Task 7에 goal type을 하나 더해 처리한다(`{"type": "hold_still", "seconds": 1.0}`, `{"type": "together", "limbs": [...], "ticks": 6}`) — 추가 시 TutorialRunner 테스트도 더한다.
- [ ] **Step 2:** 홀드 배치 작성, 의도 경로(튜토리얼 전체를 완주하는 패드 단계)를 intended_moves로. `test_content` 통과.
- [ ] **Step 3:** 커밋 `content: 기본 조작 튜토리얼`

### Task 10: 기술 과정 5개(튜토리얼 + 문제 3개씩)

**Files:** Create `game/data/routes/course/C_<ID>_T.json`, `_1`, `_2`, `_3` (HIGH_STEP, CROSS, FLAG, OUTSIDE_EDGE, DROP_KNEE), courses.json 경로 채움

- [ ] **Step 1:** 과정마다 튜토리얼 3단계(보기·해 보기·써먹기, 28 §6.1). 써먹기 단계는 그 기술 없이는 닿지 않는 홀드. 문구는 techniques.json purpose/when/how와 mistakes 문체.
- [ ] **Step 2:** 문제 3개: 쉬움(그 기술 1회, 이동 6~10), 보통(2회 이상·좌우 교대, 홀드 조금 작게), 어려움(그 기술 + 1차의 다른 기술 하나, V2~V3 수준). grade를 GradeRules 기준으로 매김, required_techniques·crux_steps 기록.
- [ ] **Step 3:** 과정 하나씩 `test_content` 통과시키고 과정 단위로 커밋 `content: <과정 이름> 과정`. 경고(등급 범위 밖)는 고치거나 등급을 바꾼다. 남긴 경고는 보고서에 이유와 함께.

### Task 11: 일반 V0~V2 12문제

**Files:** Create `game/data/routes/general/G_V0_02..04.json`, `G_V1_01..04.json`, `G_V2_01..04.json`

- [ ] **Step 1:** V0: 07의 주제(지그재그, 옆으로 한 걸음, 잠깐 버티기)로 3개, 기술 없음. V1: 하이스텝·크로스·플래그를 각각 필요로 하는 문제 + 하나 자유(4개 중 각 기술 최소 1개). V2: 아웃사이드 엣지·드롭니 각 2개. 28 §7.3 기준.
- [ ] **Step 2:** 등급 하나씩 `test_content` 통과 후 커밋 `content: V<n> 문제`.

### Task 12: 문서 반영과 APK

**Files:** Modify `docs/01,02,03,05,07,09,11,16,18,19,23,26,27`, `README.md`, `AGENTS.md`(구조 바뀐 곳), `game/export_presets.cfg`

- [ ] **Step 1:** 28 §10 표대로 각 문서에 "v0.7" 절 또는 교체 반영. 27 §3 문장 교체. 23에 "## v0.7 일반·기술 모드 구현" 진행 기록(테스트 수, 콘텐츠 수, 남은 일).
- [ ] **Step 2:** version/code 9, version/name "0.8.0-modes". 전체 테스트 0 실패, route_check 전체 통과, APK 빌드(`godot --headless --export-debug "Android" ../build/climb_game_0.8.0.apk`, JAVA_HOME=/opt/homebrew/opt/openjdk@17).
- [ ] **Step 3:** 커밋 `docs: v0.7 모드·등급 반영과 0.8.0 빌드`
