# 기술 버튼(v0.6) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 실내 볼더링 기술 1차 16개를 버튼(기술 → 쪽 → 홀드 탭)으로 실행하고, 지금 자세에서 가능한 쪽만 여는 판단기, 잡은 위치 품질, 골반 yaw, barn door, 데드포인트, 기술 선택 중 시간 정지를 구현한다.

**Architecture:** 판정은 `game/scripts/climbing/` 아래의 노드 없는 RefCounted 클래스로 둔다. 지금 `scenes/play_test.gd`에 섞여 있는 등반 상태를 `ClimbSession`으로 옮겨, 패드 입력과 기술 실행이 같은 세션 API를 통하게 한다. 판단기(`TechniqueJudge`)는 세션 스냅숏만 읽는 순수 함수, 실행기(`TechniqueRunner`)는 매 틱 세션에 손발·몸통 목표를 넘기는 상태 기계다. 화면(`play_test.gd`, `play_3d.gd`)은 세션을 읽고 입력만 전달한다.

**Tech Stack:** Godot 4.7.2 stable, GDScript, 자체 헤드리스 테스트 러너(`game/tests/run_tests.gd`).

**Spec:** `docs/27_technique_actions_design.md`(기준), 수치는 `docs/04_pose_and_physics.md` §10, 데이터는 `docs/09_data_and_save.md`·`docs/19_content_authoring.md` v0.6, 시간·상태는 `docs/15_runtime_contract.md` v0.6, 화면은 `docs/05_screens_and_ux.md`·`docs/18_screen_spec.md` v0.6.

## Global Constraints

- 엔진 Godot 4.7.2, 언어 GDScript. 외부 플러그인·라이브러리 추가 없음.
- 판정 로직(`scripts/climbing/`)은 노드·싱글턴·`Input`에 의존하지 않는다. 헤드리스로 테스트한다.
- 테스트 실행: `cd game && godot --headless --script res://tests/run_tests.gd` → 마지막 줄 `N개 중 0개 실패`. 파일 하나만: `... run_tests.gd -- test_xxx.gd`.
- 경로 검증: `cd game && godot --headless --script res://tools/route_check.gd -- R01` → 두 줄 모두 `통과`.
- 수치는 04 §10의 값을 그대로 쓴다: 손 q = 1 − t², 최대 하중 × (0.5 + 0.5q), 반각 × (0.6 + 0.4q), 손 피로 음수 × (1 + 0.5(1 − q)), 손 q < 0.5면 록오프·데드포인트·사이드풀·개스턴 불가, 발 v ≥ −0.2면 q = 1이고 v = −1에서 0.5, 손 폭 0.08m, barn door 폭 문턱 0.15m·용량(손 0.05q, 인사이드/발끝 0.04, 아웃사이드/드롭니 0.10), yaw ±40°·90°/s·360°/s², 아웃사이드 엣지 ±30°, 드롭니 ±35°, 어깨 깊이 ∓0.18 sin ψ, 고관절 ∓0.14 sin ψ, 데드포인트 v_up ≥ 0.25m/s 또는 종료 후 0.25초, 보너스 min(0.15, 0.25·v_up + 0.05·드래그 속도), 손 속도 ×2, 판정 0.15초, 받기 q ≥ 0.5·하중 1.3배, 버틴 손 피로 −10.
- 기본값(09 v0.6): hand_area 반폭 0.08m·dir (1,0), foot_area 반높이 0.04m·up (0,1), grip_modes [{pull, axis (0,1), 65°}], pivot_allowed true.
- 기술 버튼은 홀드를 대신 고르지 않고 여러 동작을 이어서 실행하지 않는다. 버튼이 하드 제약·힘 균형을 완화하지 않는다.
- 기술 선택 중(TechniqueSelect) 게임 시간·피로·카운터·몸통은 멈춘다. 드래그 중인 손발이 있으면 열 수 없다. 실행·취소 시 준비 카운트 없음.
- 능력치 성장 없음.
- 사용자 문구는 한국어, 27 §7.3과 18 v0.6 표의 문구를 그대로 쓴다.
- 판정 수치를 바꾸면 `Tuning.TUNING_VERSION`을 올린다. 이 계획에서 4로 올린다.
- 커밋 메시지 끝에 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. 패드로 넓은 홀드를 놓을 때 투영점이 이미 다른 손이 쓰는 구간과 겹침 → 겹치지 않는 가장 가까운 빈 구간으로 옮기거나, 없으면 거부(OCCUPIED). 두 손이 같은 자리를 차지하면 안 된다. (Task 2 테스트 `test_pad_grab_shifts_off_occupied_interval`)
2. 무지지 유예·균형 회복 중에 기술 패널을 열었다 닫음 → 카운터가 그대로 이어진다(초기화도, 추가 소모도 없음). (Task 10 테스트 `test_select_freezes_grace_counter`)
3. 드롭니 실행 중 다른 손 패드로 계속 오름 → yaw가 유지되고 하드 제약을 계속 지킨다. 드롭니 발 패드를 누르면 기술 취소·yaw 복귀. (Task 8 테스트 `test_drop_knee_survives_other_pad_moves`)
4. 몸이 멈춘 상태에서 손 패드를 빠르게 드래그해 먼 홀드에 놓음 → 데드포인트가 아니라 정적 잡기, 닿지 않으면 손 Free, 추락 없음. (Task 9 테스트 `test_fast_drag_while_static_is_not_deadpoint`)
5. 패드를 누르고만 있던(Armed) 상태에서 기술 패널을 엶 → 그 손발은 Attached로 정리되고, 나중에 손가락을 떼도 잡기·분리가 일어나지 않는다. (Task 10 테스트 `test_select_clears_armed_without_release`)

---

## 파일 구조

| 파일 | 책임 |
| --- | --- |
| `scripts/climbing/route_def.gd` (수정) | 슬롯별 hand_area/foot_area/grip_modes/pivot_allowed/hook 읽기·기본값·검증 |
| `scripts/climbing/hold_area.gd` (신규) | 잡기 영역 투영, 품질 계산 |
| `scripts/climbing/contact_info.gd` (신규) | 접점 메타: 슬롯 키·잡은 점·품질·방식·발 모서리 |
| `scripts/climbing/grip_check.gd` (수정) | 영역 기반 후보·잡은 점·점유 구간·거부 사유 |
| `scripts/climbing/support_solver.gd` (수정) | 접점별 축·반각·최대 하중, barn door |
| `scripts/climbing/climb_rules.gd` (수정) | 접점 메타 반영, 품질 피로, barn door 상태, profile override, yaw 목표 |
| `scripts/climbing/body_state.gd`, `pose_solver.gd` (수정) | yaw 상태와 관절 깊이·간격 |
| `scripts/climbing/climb_session.gd` (신규) | play_test의 등반 상태·틱·잡기·추락·완등을 옮긴 세션 |
| `scripts/climbing/technique_defs.gd`, `data/techniques.json` (신규) | 기술 정의 데이터 |
| `scripts/climbing/climb_snapshot.gd` (신규) | 판단기 입력 스냅숏 |
| `scripts/climbing/technique_judge.gd` (신규) | 7단계 판단·이유·홀드 후보 |
| `scripts/climbing/technique_runner.gd` (신규) | 기술 실행 상태 기계 |
| `scripts/presentation/rig_pose.gd`, `scenes/play_3d.gd` (수정) | yaw 표현, 홀드 강조·좌표 변환 |
| `scenes/play_test.gd` (수정) | 세션 사용, 기술 UI(패널·쪽 버튼·홀드 탭·품질 표시) |
| `data/routes/TX_TECH.json` (신규) | 판단기 검수용 테스트 루트 |
| `tests/test_hold_area.gd`, `test_grip_areas.gd`, `test_session.gd`, `test_yaw.gd`, `test_barn_door.gd`, `test_technique_defs.gd`, `test_judge.gd`, `test_runner.gd`, `test_deadpoint.gd`, `test_select.gd` (신규) | 각 작업 테스트 |

---

### Task 1: 홀드 영역 데이터와 품질

**Files:**
- Create: `game/scripts/climbing/hold_area.gd`, `game/data/routes/TX_TECH.json`, `game/tests/test_hold_area.gd`
- Modify: `game/scripts/climbing/route_def.gd`

**Interfaces:**
- Produces:
  - `RouteDef.slots[key]`에 추가 키: `hand_area: {dir: Vector2, half_width: float}` 또는 없음(발 전용), `foot_area: {up: Vector2, half_height: float}` 또는 없음(손 전용), `grip_modes: Array[{mode: StringName, axis: Vector2, half_angle: float}]`, `pivot_allowed: bool`, `hook: bool`. 손 허용 슬롯에만 hand_area, 발 허용 슬롯에만 foot_area 기본값을 채운다. `pos`는 영역 중심이다.
  - `HoldArea.project_hand(slot: Dictionary, point: Vector2) -> Dictionary` → `{point: Vector2, t: float, quality: float}`(선분에 클램프한 투영점, t = |오프셋|/반폭 ∈ [0,1], q = 1 − t²)
  - `HoldArea.project_foot(slot: Dictionary, point: Vector2) -> Dictionary` → `{point, v, quality}`(디딤 면 위로 클램프, v ∈ [−1,1], v ≥ −0.2면 1, 아래로 선형 감소해 v = −1에서 0.5)
  - `HoldArea.hand_interval(slot: Dictionary, point: Vector2) -> Vector2`(선분 좌표 [s−0.04, s+0.04], s는 중심 기준 부호 있는 거리)

- [ ] **Step 1: 실패하는 테스트 작성** `tests/test_hold_area.gd`
  - `test_defaults_filled`: R01의 `R01/H01/hand_1`은 hand_area.half_width == 0.08, grip_modes[0].mode == &"pull", axis == Vector2(0,1), half_angle == 65; `R01/F01/foot_1`은 foot_area.half_height == 0.04, pivot_allowed == true, hand_area 없음.
  - `test_hand_quality_center_and_edge`: 중심 투영 q == 1.0; 반폭 끝 t == 1 → q == 0.0; t = 0.5 → q == 0.75; 선분 밖 점은 끝으로 클램프.
  - `test_foot_quality_top_mid_same_bottom_worse`: v = +1 → 1.0, v = 0 → 1.0, v = −0.2 → 1.0, v = −1 → 0.5, v = −0.6 → 0.75.
  - `test_tx_tech_loads`: `TX_TECH.json` 로드 오류 0개, sidepull·gaston·undercling 모드 슬롯 각 1개 이상, pivot_allowed=false 발판 1개 이상, hand_area 반폭 0.16 이상 홀드 1개와 0.04 홀드 1개.
  - `test_invalid_area_rejected`: half_width ≤ 0 또는 grip_modes 빈 배열이면 `errors` 비어 있지 않음.
- [ ] **Step 2: 실패 확인** `godot --headless --script res://tests/run_tests.gd -- test_hold_area.gd` → `test_hold_area.gd (불러오기 실패)` 또는 FAIL
- [ ] **Step 3: 구현** `route_def.gd`의 `_read`에서 슬롯 JSON의 `hand_area`, `foot_area`, `grip_modes`, `pivot_allowed`, `hook`을 읽고 기본값을 채운다(JSON 키: `"hand_area": {"dir": [x,y], "half_width": w}`, `"foot_area": {"up": [x,y], "half_height": h}`, `"grip_modes": [{"mode": "sidepull", "axis": [x,y], "half_angle": 65}]`). `_validate`에 영역·방식 검사를 추가한다. `hold_area.gd`에 위 세 정적 함수를 둔다. `TX_TECH.json`은 R01 형식(start_pose·goal_slots·intended_moves 포함, intended_moves는 빈 배열 허용)으로 Global Constraints의 조건을 갖춘 홀드 10~14개를 배치한다.
- [ ] **Step 4: 통과 확인** 같은 명령 → `5개 중 0개 실패`. 전체 테스트와 route_check R01도 통과.
- [ ] **Step 5: 커밋** `feat: hold areas, grip modes and quality projection (v0.6 data)`

### Task 2: 영역 기반 잡기와 점유 구간

**Files:**
- Create: `game/scripts/climbing/contact_info.gd`, `game/tests/test_grip_areas.gd`
- Modify: `game/scripts/climbing/grip_check.gd`, `game/scripts/climbing/route_bot.gd`, `game/tests/test_moves.gd`(시그니처 변경 반영)

**Interfaces:**
- Consumes: Task 1의 `HoldArea`.
- Produces:
  - `class_name ContactInfo`: `var key: String`, `var point: Vector2`, `var quality: float`, `var mode: StringName`(pull/sidepull/gaston/undercling, 발은 &"foot"), `var edge: StringName`(&"inside"/&"outside"/&"toe"/&"drop_knee", 손은 &""), `static func make(key, point, quality, mode, edge) -> ContactInfo`.
  - occupied 형식 변경: `occupied: Dictionary` 슬롯 키 → `Array` of `{limb: StringName, interval: Vector2}`(손), 발은 interval = Vector2.ZERO.
  - `GripCheck.candidate(slots, limb, endpoint, pelvis, angle_deg, attached, occupied, previous := "") -> Dictionary` → `{key: String, point: Vector2, quality: float}` 또는 `{}`. 실제 말단을 영역에 투영한 점이 후보 반경 안이어야 한다. 손 투영 구간이 점유 구간과 겹치면 같은 선분 위 가장 가까운 빈 구간으로 옮기고(옮긴 점도 반경 안), 없으면 제외.
  - `GripCheck.reject_reason(...)`은 같은 인자에 occupied 새 형식. 영역에 빈 구간이 없으면 OCCUPIED.
  - `GripCheck.contact_for(slot_key, slots, limb, point) -> ContactInfo`: 손은 grip_modes[0].mode, 발은 &"foot"·edge &"inside".
- [ ] **Step 1: 실패하는 테스트** `tests/test_grip_areas.gd`
  - `test_candidate_returns_projected_point`: 손이 R01 H03 중심에서 오른쪽 0.05m, 위 0.03m → point == 중심 + (0.05, 0), quality ≈ 1 − (0.05/0.08)² ± 0.001.
  - `test_pad_grab_shifts_off_occupied_interval`(Review Focus 1): TX_TECH의 반폭 0.16 홀드에 RH가 구간 [−0.04, 0.04] 점유, LH 말단이 중심 → 결과 point가 중심에서 |0.08| 이상 떨어지고 구간이 겹치지 않음.
  - `test_narrow_hold_rejects_second_hand`: 반폭 0.04 홀드를 RH가 점유 → LH 후보 `{}`, reject_reason == OCCUPIED.
  - `test_foot_single_occupant`: 발 슬롯은 다른 발이 있으면 후보 아님.
- [ ] **Step 2: 실패 확인** `-- test_grip_areas.gd` → FAIL
- [ ] **Step 3: 구현** 위 시그니처대로 `grip_check.gd`를 바꾸고, 기존 호출부(`route_bot.gd`, `play_test.gd`의 `_occupied_map`·`_candidate`·`_try_grab`·`limbs[limb].cand`, `play_3d.gd`의 `_update_candidate`(후보 링 위치 = `cand.point`), `test_moves.gd`)를 새 형식으로 고친다. 이 단계에서 attached 위치는 슬롯 중심이 아니라 잡은 점이다.
- [ ] **Step 4: 통과 확인** 전체 테스트 0개 실패, route_check R01 통과.
- [ ] **Step 5: 커밋** `feat: area-based grabbing with occupied intervals and contact info`

### Task 3: 접점 품질·방식을 지지 계산에 반영

**Files:**
- Modify: `game/scripts/climbing/support_solver.gd`, `game/scripts/climbing/climb_rules.gd`, `game/scripts/climbing/fatigue.gd`, `game/scripts/climbing/pose_solver.gd`(하중 자격), `game/scripts/climbing/tuning.gd`(TUNING_VERSION 4)
- Test: `game/tests/test_support.gd`, `game/tests/test_rules.gd`(추가)

**Interfaces:**
- Consumes: `ContactInfo`, `RouteDef.slots[key].grip_modes`.
- Produces:
  - `SupportSolver.contact_with(limb: StringName, pos: Vector2, axis: Vector2, half_angle: float, max_load: float) -> Dictionary`(기존 `contact()`는 이 함수를 기본값으로 호출).
  - `ClimbRules.contact_meta: Dictionary` limb → ContactInfo. `ClimbRules.tick(...)`과 `evaluate(...)`가 이 메타로 접점을 만든다: 방식의 axis·half_angle, 최대 하중 × (0.5 + 0.5q), 반각 × (0.6 + 0.4q). 메타가 없는 limb은 기본(pull/발 q=1).
  - `PoseSolver.hand_load_eligible(pelvis, angle_deg, limb, slot, mode := &"pull") -> bool`: pull만 "어깨보다 0.10m 넘게 낮으면 자격 없음", 그 외 방식은 항상 true(언더클링은 ClimbRules가 하중 받는 발 ≥ 1 조건을 추가로 본다).
  - `PoseSolver.eligible_hands(pelvis, angle_deg, attached, meta := {}) -> int`: meta(limb → ContactInfo)의 mode를 hand_load_eligible에 넘긴다. 무지지 판정(ClimbRules·세션)은 meta를 넘겨 호출한다.
  - `Fatigue.attached_hand_rate(..., quality := 1.0)`: 음수 결과에 × (1 + 0.5(1 − q)) 추가.
  - `Tuning.TUNING_VERSION = 4`.
- [ ] **Step 1: 실패하는 테스트**
  - `test_support.gd::test_quality_scales_capacity`: 한 손 바로 아래 매달림에서 q = 1이면 FEASIBLE, 같은 자세 q = 0(최대 하중 0.55BW)이면 INFEASIBLE.
  - `test_support.gd::test_sidepull_axis_horizontal`: 손 하나는 axis (−1,0) 사이드풀, 발 둘 → 손 힘의 X 성분이 음수.
  - `test_rules.gd::test_low_quality_tires_faster`: 같은 자세에서 q = 0.25 손의 피로 감소가 q = 1 손의 × (1 + 0.5·0.75) ± 1%.
  - `test_rules.gd::test_undercling_below_shoulder_eligible_with_loaded_foot`: 어깨 아래 0.3m 언더클링 손 + 하중 발 1 → 지지 계산에 포함, 하중 발 0이면 제외.
- [ ] **Step 2: 실패 확인** `-- test_support.gd`, `-- test_rules.gd` → FAIL
- [ ] **Step 3: 구현** 위 시그니처대로. `route_bot.gd`와 세션 호출부는 잡을 때 만든 ContactInfo를 `rules.contact_meta`에 넣고 뗄 때 지운다.
- [ ] **Step 4: 통과 확인** 전체 테스트, route_check R01 통과(경로가 막히면 원인을 docs/23에 기록하고 R01 의도 경로를 고친다. 수치는 바꾸지 않는다).
- [ ] **Step 5: 커밋** `feat: grip quality and grip modes in support model (tuning 4)`

### Task 4: ClimbSession 분리(동작 변화 없음)

**Files:**
- Create: `game/scripts/climbing/climb_session.gd`, `game/tests/test_session.gd`
- Modify: `game/scenes/play_test.gd`, `game/scenes/play_3d.gd`(읽는 대상 변경)

**Interfaces:**
- Consumes: InputRouter 명령 형식(`{type, limb, delta}`), ClimbRules, GripCheck, ContactInfo.
- Produces `class_name ClimbSession`:
  - 필드: `route: RouteDef`, `body: BodyState`, `rules: ClimbRules`, `limbs: Dictionary`(limb → `{state: String("Attached"/"Armed"/"Dragging"/"Free"/"Flag"), key: String, pos: Vector2, req: Vector2, cand: Dictionary, flag: Vector2}`), `falling: bool`, `fall_reason: String`, `goal_ticks: int`, `clears: int`, `falls: int`, `messages: Array[String]`(이번 틱 안내 문구, 호출 측이 비움).
  - `func _init(p_route: RouteDef) -> void`, `func reset() -> void`
  - `func apply_input(cmds: Array) -> void`(arm/disarm/detach/move/release/cancel, play_test `_apply`와 같은 의미)
  - `func step() -> String`: 고정 틱 1회. 반환 "" / "fall:<NO_SUPPORT|BALANCE_LOST|DEADPOINT_MISS>" / "clear" / "unresolved".
  - `func attached() -> Dictionary`, `func occupied() -> Dictionary`, `func is_dragging() -> bool`
  - `func grab(limb: StringName, key: String, point: Vector2, contact: ContactInfo) -> bool`(검증 후 붙임, 기술 실행기도 사용)
- [ ] **Step 1: 실패하는 테스트** `tests/test_session.gd`
  - `test_reset_start_pose_stable`: R01 세션 reset 후 120틱 → 반환 모두 "", rules.phase == STABLE.
  - `test_drag_release_grabs_candidate`: LH detach → move 명령으로 H03 근처까지(여러 틱) → release → limbs.LH.state == "Attached", key == "R01/H03/hand_1".
  - `test_release_without_candidate_frees`: 허공에 release → "Free".
  - `test_all_hands_off_falls`: 두 손을 떼고 허공 release → 9틱 안에 "fall:NO_SUPPORT".
  - `test_goal_clears`: 의도 경로를 세션 API로 재생하면 "clear"(RouteBot 순서·대기 방식과 같게).
- [ ] **Step 2: 실패 확인** `-- test_session.gd` → FAIL
- [ ] **Step 3: 구현** `play_test.gd`의 `_reset`·`_attached`·`_occupied_map`·`_apply`·`_clamp_to_reach`·`_candidate`·`_try_grab`·`_physics_process`의 판정 부분·`_move_endpoints`·`_on_platform`·`_goal_tick`·`_start_fall`·`_fall_tick`을 세션으로 옮긴다. play_test는 router·일시정지·카메라·HUD·그리기만 남기고 `session`을 소유한다. `play_3d.gd`는 `logic.session.body`/`logic.session.limbs`/`logic.session.rules`를 읽는다.
- [ ] **Step 4: 통과 확인** 전체 테스트, route_check R01, `godot --resolution 1600x900 --write-movie /tmp/x/f.png --fixed-fps 30 --quit-after 175 res://tools/motion_demo.tscn -- --no-auto-pause`가 오류 없이 끝나고 프레임 60·165가 이전과 같은 장면(HUD 무브 이름·부채꼴 표시).
- [ ] **Step 5: 커밋** `refactor: extract ClimbSession from play_test`

### Task 5: 골반 yaw

**Files:**
- Modify: `game/scripts/climbing/body_state.gd`, `game/scripts/climbing/pose_solver.gd`, `game/scripts/climbing/climb_rules.gd`, `game/scripts/presentation/rig_pose.gd`, `game/scenes/play_3d.gd`
- Test: `game/tests/test_yaw.gd`

**Interfaces:**
- Produces:
  - `BodyState.yaw: float`(도), `BodyState.yaw_vel: float`
  - `PoseSolver.joint_offset(limb, yaw_deg := 0.0) -> Vector2`: X 오프셋 × cos ψ
  - `PoseSolver.joint_depth_offset(limb, yaw_deg) -> float`: 어깨 −side_sign·0.18·sin ψ, 고관절 −side_sign·0.14·sin ψ(ψ>0이면 오른쪽 관절이 벽에 가까움)
  - yaw 인자 추가(기본 0.0, 마지막 인자): `joint_position`, `limb_distance`, `can_reach`, `body_depth`, `is_valid`, `clamp_endpoint`, `find_target`, `move_body`. `body_depth`·`can_reach`는 관절별 깊이 오프셋으로 요구 골반 깊이를 계산한다. 방향각(`limb_angle`)은 yaw와 무관(04 §10.1).
  - `ClimbRules.yaw_target: float`(NAN이면 0으로 복귀). 매 틱 yaw를 목표로 90°/s·360°/s² 안에서 움직이고, 다음 yaw로 `is_valid`가 실패하면 그 틱 yaw 변화를 0으로 한다. ±40° 클램프.
  - `RigPose.solve(joints, roll_deg, yaw_deg := 0.0)`: 몸통 뼈 기준에 Y축 yaw 회전 적용.
- [ ] **Step 1: 실패하는 테스트** `tests/test_yaw.gd`
  - `test_right_hip_in_extends_right_reach`(TA08): 같은 골반에서 ψ = +30°일 때 RH의 최대 벽면 도달 거리(`planar_range` 최대값을 관절 깊이로 계산)가 ψ = 0보다 크고, LH는 작다.
  - `test_yaw_clamped_and_rate_limited`: yaw_target = 80 → 60틱 후 yaw == 40, 1틱 변화 ≤ 1.5°.
  - `test_yaw_stops_at_constraint`: 접점이 yaw 30°에서 무효가 되는 배치 → yaw가 무효 직전 값에서 멈추고 is_valid 유지.
  - `test_yaw_zero_matches_previous_behaviour`: 기존 `test_pose.gd` 전부가 yaw 인자 없이 통과(기본값 0).
  - `test_rig_yaw_frames_orthonormal`: RigPose.solve(..., 30) 모든 뼈 행렬식 1 ± 0.01.
- [ ] **Step 2: 실패 확인** `-- test_yaw.gd` → FAIL
- [ ] **Step 3: 구현** 위 시그니처대로. `_search_context`·`_candidate_cost`는 ctx에 yaw를 넣어 관절 위치·깊이를 계산한다(yaw는 탐색 변수가 아님). play_3d는 골반·가슴 뼈에 yaw를 적용한다.
- [ ] **Step 4: 통과 확인** 전체 테스트, route_check R01(yaw 0이라 결과 동일).
- [ ] **Step 5: 커밋** `feat: pelvis yaw state affecting joint depth and spacing`

### Task 6: barn door 근사

**Files:**
- Modify: `game/scripts/climbing/support_solver.gd`, `game/scripts/climbing/climb_rules.gd`
- Test: `game/tests/test_barn_door.gd`

**Interfaces:**
- Produces:
  - `SupportSolver.barn_door(contacts: Array, loads: Dictionary, com: Vector2, meta: Dictionary) -> Dictionary` → `{applies: bool, tau: float, capacity: float, exceeded: bool}`. 하중 ≥ 0.05BW 접점의 X 폭 < 0.15m일 때만 applies. 용량: 손 0.05·q, 발 edge inside/toe 0.04, outside/drop_knee 0.10.
  - `ClimbRules.imbalance_cause: StringName`(&""/&"FORCE"/&"BARN_DOOR"). 힘 해가 있어도 barn door exceeded면 phase = REBALANCING, cause = BARN_DOOR. `tick` 반환은 기존 "BALANCE_LOST" 유지, 원인은 `imbalance_cause`로 본다.
- [ ] **Step 1: 실패하는 테스트**
  - `test_vertical_line_contacts_barn_door`(TA07 앞부분): 왼손(−0.40,1.75)+왼발(−0.38,0.35)만 하중, 골반 x = +0.20 → applies, exceeded, rules.phase == REBALANCING, cause == BARN_DOOR.
  - `test_flag_reduces_tau`: 같은 자세에서 자유 오른발 endpoint를 왼쪽(−0.6, 0.5)에 둠 → tau 감소, exceeded == false.
  - `test_outside_edge_raises_capacity`: 왼발 edge = &"outside" → capacity 0.10 + 손.
  - `test_wide_contacts_no_barn_door`: R01 시작 자세 → applies == false.
- [ ] **Step 2: 실패 확인** `-- test_barn_door.gd` → FAIL
- [ ] **Step 3: 구현** 위 시그니처대로.
- [ ] **Step 4: 통과 확인** 전체 테스트, route_check R01(전 구간 Stable 유지 기대. 바뀌면 docs/23에 기록).
- [ ] **Step 5: 커밋** `feat: barn door stability approximation`

### Task 7: 기술 정의 데이터

**Files:**
- Create: `game/data/techniques.json`, `game/scripts/climbing/technique_defs.gd`, `game/tests/test_technique_defs.gd`

**Interfaces:**
- Produces:
  - `TechniqueDefs.load_all() -> Dictionary` id(StringName) → `{id, name_ko, phase: int, body_parts: StringName, sides: StringName(&"left_right"/&"none"), flow: StringName(&"hold_tap"/&"execute"/&"drag_or_hold_tap"), group: StringName(&"foot"/&"hand"/&"body", 패널 탭), purpose_tags: Array, purpose_ko, when_ko, how_ko, mistakes: Array[{reason, text_ko}]}`
  - ID는 27 §5 그대로: T_INSIDE_EDGE, T_OUTSIDE_EDGE, T_DROP_KNEE, T_HIGH_STEP, T_DEADPOINT, T_FLAG, T_FLAG_INSIDE, T_FLAG_OUTSIDE, T_LOCK_OFF, T_REST, T_CROSS, T_MATCH, T_FOOT_SWAP, T_SIDEPULL, T_GASTON, T_UNDERCLING, T_HEEL_HOOK, T_TOE_HOOK, T_SMEAR.
- [ ] **Step 1: 실패하는 테스트** `test_all_19_present`(phase 1이 16개, 2가 3개), `test_required_fields_non_empty`, `test_flow_matches_spec`(T_DROP_KNEE·T_FLAG*·T_LOCK_OFF = execute, T_REST sides none, T_DEADPOINT = drag_or_hold_tap, 나머지 1차 = hold_tap), `test_mistake_reasons_known`(mistakes.reason이 27 §7.3 ID 중 하나).
- [ ] **Step 2: 실패 확인**
- [ ] **Step 3: 구현** 문구는 26의 내용 설명과 27 §5의 "쓰는 이유"를 바탕으로 한국어 한두 문장씩 쓴다(목적·상황·방법). 2차 기술은 phase 2로 두고 판단기·실행기는 이번 계획에서 항상 MOVE_NOT_SUPPORTED로 막는다.
- [ ] **Step 4: 통과 확인**
- [ ] **Step 5: 커밋** `feat: technique definitions data (19 techniques)`

### Task 8: 판단기와 1차 기술 실행

이 작업은 크다. 판단기와 실행기를 기술 묶음별로 세 커밋에 나눠 진행한다(8a 공통+위치형, 8b yaw형, 8c 플래그). 각 커밋 전에 그 묶음 테스트가 통과해야 한다.

**Files:**
- Create: `game/scripts/climbing/climb_snapshot.gd`, `game/scripts/climbing/technique_judge.gd`, `game/scripts/climbing/technique_runner.gd`, `game/tests/test_judge.gd`, `game/tests/test_runner.gd`
- Modify: `game/scripts/climbing/climb_session.gd`, `game/scripts/climbing/climb_rules.gd`(profile override)

**Interfaces:**
- Consumes: ClimbSession, TechniqueDefs, GripCheck, HoldArea, SupportSolver, ClimbRules.yaw_target.
- Produces:
  - `ClimbSnapshot.from_session(s: ClimbSession) -> ClimbSnapshot`: body(pos, angle, yaw, vel), attached, contact_meta, keys(limb → 슬롯 키), limb states, endpoints, rules 결과(phase, last, loaded_feet, feet_eligible, stamina, imbalance_cause), route, executing: bool, dragging: bool. 복사본이며 세션을 바꾸지 않는다.
  - `TechniqueJudge.judge(snap: ClimbSnapshot, tech_id: StringName) -> Dictionary` → `{&"left": Judgement, &"right": Judgement}` 또는 sides none이면 `{&"none": Judgement}`. `Judgement = {available: bool, reason: StringName, reasons: Array[StringName], text: String}`. 7단계 순서와 이유 ID·문구는 27 §7.1·§7.3.
  - `TechniqueJudge.hold_targets(snap, tech_id, side) -> Array` of `{key: String, needs_shift: bool, area_center: Vector2}`(27 §7.2).
  - `TechniqueJudge.check_hold(snap, tech_id, side, key, point) -> Dictionary` → `{ok: bool, reason: StringName, text: String, point: Vector2, quality: float}`(탭 지점 투영과 기술별 품질 조건).
  - `ClimbRules.profile_override: Dictionary`(limb → 선호 거리, 무브 프로필 위에 덮어씀, 비면 영향 없음).
  - `TechniqueRunner`: `active: Dictionary`(비면 실행 없음: `{id, side, limb, key, point, step: StringName, ticks: int}`), `func start(session, tech_id, side, key := "", point := Vector2.INF) -> StringName`(&"" 성공, 아니면 이유), `func tick(session) -> Dictionary`(이번 틱 이벤트 `{type: &"started"/&"succeeded"/&"cancelled"/&"failed", id, side, reason}` 또는 `{}`), `func cancel(session, reason := &"cancelled") -> void`. 세션의 `step()`이 rules.tick 전에 runner.tick을 부른다.
  - `ClimbSession.technique_log: Array`: 확정된 틱의 runner 이벤트를 `{tick, type, id, side, key, quality, reason}`로 쌓는다(09 v0.6 기술 이벤트, 능력치에 쓰지 않음). 최근 200개만 유지.
  - 기술이 손발을 옮길 때 세션 limb state는 "Dragging"(req = 목표점)과 같은 경로를 쓰고, 도착하면 `session.grab(...)`으로 붙인다. 손발 패드에 down이 오면 `session.apply_input`이 그 limb을 쓰는 실행을 `cancel`한다(Review Focus 3).
- **기술별 판단·실행:** 27 §10 표와 §11을 그대로 구현한다. 손발을 떼야 하는 기술의 "떼기 판단"은 그 limb을 뺀 attached와 contact_meta로 `rules.evaluate`를 한 번 푼 결과가 FEASIBLE이고 barn door exceeded가 아닐 때 통과. 체중 이동 후 도달(needs_shift) 홀드는 실행 첫 단계에서 intents로 최대 90틱 Shift, 그 안에 도달 못 하면 `failed`·NEED_WEIGHT_SHIFT.
- [ ] **Step 1(8a): 실패하는 테스트** `test_judge.gd`
  - `test_wrong_phase_when_falling`: falling 세션 → 모든 쪽 WRONG_PHASE.
  - `test_support_needed_when_last_hand`(TA02): LH 하나 + 두 발, T_CROSS left → SUPPORT_NEEDED, 문구 "이 손발을 떼면 버틸 수 없어요".
  - `test_high_step_targets_only_high_holds`(TA03): R01 시작, T_HIGH_STEP left 후보는 Y ≥ 고관절 Y − 0.20인 발판만.
  - `test_match_needs_room`(TA10): 좁은 홀드는 NO_HOLD 또는 check_hold OCCUPIED, 넓은 홀드는 가능.
  - `test_lock_off_blocked_by_edge_grip`(TA05): LH q = 0.19(t = 0.9) → T_LOCK_OFF left GRIP_TOO_POOR.
  - `test_same_snapshot_same_result`(TA11): 패드로 만든 자세와 세션 필드를 직접 설정한 같은 자세의 judge 결과가 같음.
  - `test_judge_cost`: TX_TECH 시작 자세에서 1차 16개 judge 총 시간 출력, 기술 1개 평균 ≤ 30ms(맥).
  `test_runner.gd`
  - `test_high_step_places_foot_then_rises`: R01 시작, T_HIGH_STEP left → F03 탭 → 실행 완료 시 LF가 F03에 Attached(edge inside), 골반 Y 상승 ≥ 0.10.
  - `test_cross_reaches_over`: T_CROSS로 LH가 RH 오른쪽 홀드에 붙음, L/R ID 유지.
  - `test_no_auto_hold`(TA12): `start(..., key = "")`로 hold_tap 기술 시작 → NO_HOLD, 아무것도 움직이지 않음.
  - `test_pad_touch_cancels`(TA09): 실행 중 그 limb arm 명령 → `cancelled` 이벤트, active 비움.
  - `test_rest_and_lock_off_profiles`: T_REST 중 profile_override 팔 0.70, T_LOCK_OFF 중 그 손 0.42와 피로 ×1.5.
  - `test_sidepull_gaston_undercling_conditions`: TX_TECH에서 각 방식의 기하 조건(27 §10)이 맞는 쪽만 가능, 실행 후 contact_meta.mode가 그 방식.
  - `test_foot_swap`: RF가 LF 발판으로, 같은 틱에 LF 해제, 균형 유지.
- [ ] **Step 2(8a): 실패 확인** `-- test_judge.gd`, `-- test_runner.gd` → FAIL
- [ ] **Step 3(8a): 구현** 스냅숏·판단기 공통 7단계(쪽 판단 시에는 홀드 후보를 계산하지 않음, 27 §11), 실행 첫 틱의 수치 재검사, 위치형 기술(인사이드 엣지, 하이스텝+일어서기, 크로스, 매치, 풋스왑, 사이드풀·개스턴·언더클링, 휴식, 록오프) 판단·실행.
- [ ] **Step 4(8a): 통과 확인 후 커밋** `feat: technique judge and runner for positional techniques`
- [ ] **Step 5(8b): 실패하는 테스트** `test_runner.gd`
  - `test_drop_knee_left_only`(TA01): 두 손·두 발, 왼발 발판 pivot true·오른발 false → judge left available, right PIVOT_NOT_ALLOWED.
  - `test_drop_knee_turns_hip`: 실행 후 yaw → −35 ± 1(왼쪽 엉덩이를 벽으로 = ψ<0), contact_meta.LF.edge == &"drop_knee", 같은 쪽(LH) 도달 증가.
  - `test_outside_edge_sets_yaw`: 오른발 아웃사이드 엣지 → yaw → +30, edge &"outside".
  - `test_drop_knee_survives_other_pad_moves`(Review Focus 3): 드롭니 중 RH 패드로 다른 홀드 잡기 → yaw 유지·is_valid 유지. 이후 LF arm → cancelled, yaw_target NAN, 0으로 복귀.
- [ ] **Step 6(8b): 실패 확인** `-- test_runner.gd` → 위 4개 FAIL
- [ ] **Step 7(8b): 구현** 드롭니·아웃사이드 엣지 판단(27 §10)과 실행(yaw_target 설정, contact_meta.edge 기록, 취소 시 yaw_target = NAN)
- [ ] **Step 8(8b): 통과 확인 후 커밋** 전체 테스트 0개 실패 → `feat: drop knee and outside edge with hip yaw`
- [ ] **Step 9(8c): 실패하는 테스트** `test_runner.gd`
  - `test_flag_needed_and_fixes_barn_door`(TA07 뒷부분): Task 6의 barn door 자세에서 T_FLAG_INSIDE right 가능 → 실행 후 RF state "Flag", barn door exceeded false.
  - `test_flag_unavailable_when_no_gain`: R01 시작 자세에서 플래그 3종 모두 불가, 이유 "지금은 균형에 도움이 안 돼요"(SUPPORT_OVERLOAD 대신 쓰는 기술별 LIMB_STATE 문구로 정의).
  - `test_flag_variants_positions`: 같은 쪽/인사이드/아웃사이드가 각각 지지발 X 기준 바깥/앞(깊이 작음)/뒤(깊이 큼)에 위치.
- [ ] **Step 10(8c): 실패 확인** `-- test_runner.gd` → 위 3개 FAIL
- [ ] **Step 11(8c): 구현** 플래그 판단(균형 비용 0.02 이상 개선 또는 barn door 해소)과 위치 탐색(관절 범위 안 격자 0.05m에서 균형 비용 최소), 실행 후 limb state "Flag"
- [ ] **Step 12(8c): 통과 확인 후 커밋** 전체 테스트 0개 실패 → `feat: flag techniques (same-side, inside, outside)`

### Task 9: 데드포인트

**Files:**
- Modify: `game/scripts/climbing/climb_session.gd`, `game/scripts/climbing/technique_runner.gd`, `game/scripts/climbing/technique_judge.gd`, `game/scripts/input/input_router.gd`(드래그 속도)
- Test: `game/tests/test_deadpoint.gd`

**Interfaces:**
- Produces:
  - InputRouter `release` 명령에 `speed: float`(최근 0.1초의 손가락 이동을 월드 m/s로 환산) 추가.
  - `ClimbSession.deadpoint_window() -> bool`, `ClimbSession.deadpoint_bonus(drag_speed: float) -> float`(04 §10.5 식).
  - 세션의 release 처리: 손이고 window가 열려 있고 정적 후보가 없고 보너스 범위 안에 홀드가 있으면 데드포인트 실행(손 속도 ×2, 0.15초). 받기 실패면 step() 반환 "fall:DEADPOINT_MISS".
- [ ] **Step 1: 실패하는 테스트** `test_deadpoint.gd`
  - `test_deadpoint_catches_while_rising`(TA04): 하이스텝 일어서는 중(v_up ≥ 0.25) 정적 범위 + 0.10m 홀드로 speed 2.0 release → 붙음, 버틴 손 피로 −10.
  - `test_fast_drag_while_static_is_not_deadpoint`(Review Focus 4): 정지 상태 같은 release → 손 Free, 반환 "", 추락 없음.
  - `test_deadpoint_miss_falls`: 일어서는 중 보너스 범위 밖 0.05m 홀드 → "fall:DEADPOINT_MISS", falls 1 증가.
  - `test_deadpoint_needs_quality`: 홀드 끝(t = 0.9)으로 받으면 실패·추락.
  - `test_deadpoint_button_side_disabled_when_static`: 정지 상태 judge(T_DEADPOINT) 양쪽 불가.
- [ ] **Step 2: 실패 확인**
- [ ] **Step 3: 구현**
- [ ] **Step 4: 통과 확인** 전체 테스트, route_check R01.
- [ ] **Step 5: 커밋** `feat: one-hand deadpoint with fall on miss`

### Task 10: 기술 선택 시간 정지와 기술 UI

**Files:**
- Modify: `game/scripts/climbing/climb_session.gd`, `game/scenes/play_test.gd`, `game/scenes/play_3d.gd`, `game/tools/motion_demo.gd`
- Test: `game/tests/test_select.gd`

**Interfaces:**
- Produces:
  - `ClimbSession.selecting: bool`, `func open_select() -> bool`(드래그 중이면 false. 열면 Armed → Attached, router 세대 증가는 호출 측), `func close_select() -> void`. selecting이면 `step()`은 아무것도 바꾸지 않고 "" 반환.
  - `ClimbSession.choose(tech_id, side, key := "", point := Vector2.INF) -> StringName`: judge·check_hold 후 runner.start, 성공 시 selecting 해제(같은 틱부터 시간 재개).
  - play_test UI: 중앙 상단 "기술" 버튼(드래그 중 비활성), 패널(발/손/몸 탭, 0.2초마다 가벼운 검사로 흐림), 쪽 버튼(LH·LF 사이 / RH·RF 사이, 불가는 흐림+잠금, 누르면 이유), 홀드 강조(후보 실선, needs_shift 점선, 잡기 영역 선분/면), 탭 지점 품질 미리보기(좋음/보통/끝), HUD "고르는 중 · 시간 멈춤"과 실행 중 기술 이름·단계. 문구 키는 18 v0.6.
  - play_3d: `world_to_screen(p: Vector2) -> Vector2`(z = CONTACT_DEPTH 평면 투영), `screen_to_wall(s: Vector2) -> Vector2`(카메라 광선과 z = CONTACT_DEPTH 평면 교점). play_test는 이 Callable로 홀드 탭을 월드 좌표로 바꾼다.
- [ ] **Step 1: 실패하는 테스트** `test_select.gd`
  - `test_select_freezes_time`(TA13): open_select 후 600틱 step → body.pos·stamina·elapsed·카운터 불변.
  - `test_select_freezes_grace_counter`(Review Focus 2): 무지지 4틱에서 open → 600틱 → close → 5틱 더 → 9번째에 "fall:NO_SUPPORT".
  - `test_cannot_open_while_dragging`(TA14): LH Dragging이면 open_select() == false.
  - `test_select_clears_armed_without_release`(Review Focus 5): InputRouter로 LH 패드 touch_down → `session.apply_input`(arm) → LH "Armed". `session.open_select()`와 `router.cancel_all()` → LH "Attached". 이어서 같은 터치 인덱스로 `router.touch_drag`·`router.touch_up`이 빈 배열을 반환하고, LH 상태·접점이 그대로.
  - `test_choose_resumes_immediately`: choose 성공 틱부터 step이 시간을 진행.
- [ ] **Step 2: 실패 확인**
- [ ] **Step 3: 구현** 세션 부분 → play_test·play_3d UI. 앱 중단 시 selecting이면 close_select 후 기존 Paused 흐름.
- [ ] **Step 4: 통과 확인** 전체 테스트. 시각 확인: `motion_demo.gd`에 "기술 버튼 → 하이스텝 → 왼쪽 → F03 탭" 주입 단계를 추가해 렌더, 패널·쪽 버튼·홀드 강조·실행 HUD가 프레임에 보임.
- [ ] **Step 5: 커밋** `feat: technique selection with time stop and UI`

### Task 11: 재검증·문서·배포

**Files:**
- Modify: `docs/23_dev_readiness_review.md`(v0.6 구현 기록), `docs/04_pose_and_physics.md`(구현 편차가 생겼다면), `game/export_presets.cfg`(version 0.7.0-tech, code 7)

- [ ] **Step 1:** 전체 테스트와 route_check R01·TX_TECH(intended_moves가 있으면) 통과 확인, 결과 수치(틱 비용, 판단기 비용, R01 시간·사용률)를 23에 기록. 미구현(2차 기술, 기술 튜토리얼)도 기록.
- [ ] **Step 2:** `cd game && godot --headless --export-debug "Android" ../build/climb_game_tech.apk` 오류 없음.
- [ ] **Step 3:** 커밋 `docs: record v0.6 technique implementation` 후 push.
- [ ] **Step 4:** `gh release create v0.7.0-tech build/climb_game_tech.apk --target main --prerelease --title "Climb Test 0.7.0-tech" --notes "기술 버튼 1차"`, 링크와 크기 확인.
