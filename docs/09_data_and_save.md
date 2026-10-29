# 09. 데이터·저장 계약

소스와 직렬화 스키마를 작성하기 전의 필드 명세다. 코드·JSON 예제는 포함하지 않는다. 필드명은 구현 협업을 위한 제안이며 변경 시 소비 모듈과 문서를 함께 갱신한다.

## 데이터 원칙

- 콘텐츠 정의, 실행 중 상태, 영구 저장을 분리한다.
- 위치는 월드 m, 시간은 초, 각도는 도, 피로는 0~100으로 문서화한다. 엔진 API가 다른 단위를 요구하면 경계에서 변환한다.
- 모든 ID는 영구 식별자다. 표시 이름을 바꾸어도 ID를 바꾸지 않는다.
- 루트에는 content_version, 게임에는 build_version, 조정값에는 tuning_version을 둔다.
- 저장에는 schema_version을 따로 둔다. 게임 빌드 번호를 저장 포맷 버전처럼 쓰지 않는다.

## 루트 정의 RouteDefinition

| 필드 | 타입/제약 | 용도 |
| --- | --- | --- |
| route_id | 고유 문자열, T01~T03/R01~R09 | 진행·기록 참조 |
| content_version | 양의 정수 | 배치 변경 식별 |
| title_key / description_key | 번역 키 | UI 텍스트 |
| theme_id | 존재하는 테마 ID | 에셋 참조 |
| bounds / fail_line_y | 평면 영역/높이 | 카메라·실패 경계 |
| start_pose | 골반·회전·초기 슬롯 4개 | 검증된 시작 상태 |
| holds | HoldInstance 목록 | 잡을 지점 |
| platforms | 바닥 지지 영역 목록 | 서기·휴식 |
| checkpoints | CheckpointDefinition 목록 | 안전 복귀 |
| goal_slots | 손 슬롯 ID 정확히 2개 | 양손 성공 조건 |
| time_medal_seconds | 양수 또는 없음 | 시간 도전 |
| prerequisite_route_id | 루트 ID 또는 없음 | 선행 완등 |
| intended_moves | limb/slot 순서 목록 | 제작·QA 경로 기록 |
| validation_status | Draft 등 지정 값 | 미검증 콘텐츠 구분 |

## 홀드·슬롯 정의

| 구조 | 필드 | 계약 |
| --- | --- | --- |
| HoldDefinition | hold_type_id, visual_asset_id | 재사용 외형과 유형 |
| HoldDefinition | slots | 슬롯 종류·상대 위치·허용 팔다리 |
| HoldInstance | hold_id, hold_type_id, position, rotation | 루트 안의 배치 |
| SlotDefinition | slot_id, allowed_limbs | LH/RH/LF/RF 중 허용 목록 |
| SlotDefinition | local_anchor, support_direction, support_angle | 접점과 발 지지 판단 |
| SlotDefinition | capacity | MVP는 슬롯당 1. 정상은 슬롯 2개 |
| SlotState | occupant_limb_id 또는 비어 있음 | 실행 중 점유, 콘텐츠에 저장하지 않음 |

전체 슬롯 키는 route_id + hold_id + slot_id 조합으로 유일해야 한다. 정상 좌우 슬롯 이름은 위치를 의미하며 특정 손만 강제하지 않는다. goal_slots 두 개를 두 손이 서로 다르게 점유하면 된다. 두 손이 한 슬롯을 공유해서 성공하지 못한다.

발판에 붙은 상태와 발이 실제 하중을 받치는 상태를 구분한다. 후자는 PoseSolver가 매 틱 갱신하는 런타임 값이며 원본 콘텐츠의 상수 값이 아니다.

## 입력·말단 상태

| 구조 | 핵심 필드 | 수명/제약 |
| --- | --- | --- |
| PointerBinding | input_generation, touch_id, limb_id, origin | 터치 생존 기간만 유지 |
| LimbIntent | selected, requested_target, release_requested | 틱 경계에서 소비 |
| LimbState | limb_id, attachment_state, slot_key, actual_endpoint | 게임 상태의 단일 권한 |
| HandState | stamina, warning_active | 손에만 존재, 0~100 |
| BodyState | pelvis_position, body_angle, velocity | 유한 값·속도·회전 제한 |
| SupportState | supported_hand_ids, loaded_foot_ids, platform_id | 자세 결과에서 계산 |
| RunState | route_id, mode_key, elapsed, falls, checkpoint_id | 현재 시도의 진행 |

입력 ID와 슬롯 점유는 영구 저장하지 않는다. 로드 시 터치는 모두 없는 상태에서 시작한다. 최신 상태를 UI가 변경할 수 없게 읽기 전용 스냅숏을 전달한다.

## 모듈 이벤트 계약

| 이벤트 | 생산자 → 소비자 | 포함 정보 |
| --- | --- | --- |
| LimbDetached | Grip → HUD/Audio/Session | 팔다리, 이전 슬롯, 원인, tick |
| GripAccepted | Grip/Pose 거래 확정 → UI/Audio | 팔다리, 슬롯, 최종 접점, tick |
| GripRejected | Grip/Pose → UI/진단 | 팔다리, 후보, 사유, tick |
| SupportChanged | Pose → Rules/UI | 유효 손/발, 플랫폼 여부 |
| FatigueWarning | Rules → UI/Audio/Haptics | 손, 현재 값, 진입/종료 |
| RunFailed | Rules → Session/기록 | 실패 원인, 높이, 시간, 추락 수 |
| CheckpointReached | Rules → Save | route/content 버전, 체크포인트 ID |
| RunCleared | Rules → Save/결과 | 결과·메달·모드·버전 |
| SystemInterrupted | 앱 계층 → Session/Input | 취소/백그라운드/화면 변경 사유 |

이벤트는 확정된 판정에서 한 번만 발생시킨다. 저장이 실패했다고 RunCleared를 다시 발생시켜 보상을 중복 지급하지 않는다. 이벤트 ID는 run_id + tick + 순번 조합으로 진단에서 구별한다. MVP는 네트워크 이벤트 버스가 필요하지 않다.

## 저장 구조

| 영역 | 포함 내용 |
| --- | --- |
| 메타데이터 | schema_version, 저장 일련번호, 앱/콘텐츠 버전 |
| 설정 | 패드 배치·감도, 음량·진동, UI·그래픽, 보조 옵션 |
| 진행 | 튜토리얼 완료, 루트 완등, 해금 외형 |
| 기록 | route_id/content_version/mode_key별 메달·최고 시간 |
| 재개 정보 | 최근 루트·체크포인트·같은 시도의 시간/추락 수 |

플레이 중의 임의 스켈레톤과 물리 엔진 내부 상태를 저장하지 않는다. 이어하기는 같은 콘텐츠 버전의 검증된 체크포인트로 복귀하며, 없으면 루트 시작 자세로 간다. 앱 종료 전 공중 위치를 정확히 복원한다고 약속하지 않는다. 설정과 완료 기록은 재개 실패와 별개로 보존한다.

보조 기록의 mode_key에는 피로 소모 끄기·후보 반경 확대 등 판정에 영향을 주는 플래그를 포함한다. 순수 표시 옵션과 감도·패드 위치는 기록을 나누지 않는다. 중간에 보조를 켜면 해당 시도의 보조 플래그는 누적되어 유지된다. 콘텐츠/조정 버전이 바뀐 기록은 보존하되 새 버전 최고기록과 혼합 비교하지 않는다.

## 저장 시점과 원자성

설정 확정, 체크포인트 도달, 완등 결과 확정, 루트 이탈, 앱 중단 시 저장한다. 플레이 중 안정 상태에서는 최대 2초 간격으로 재개용 시도 메타데이터만 갱신할 수 있다. 매 프레임 디스크에 쓰지 않는다. OS 강제 종료 전 마지막 저장 이후의 수 초가 손실될 수 있으며 모든 종료 상황의 저장을 보장하지 않는다.

한 저장 요청에는 진행·메달·해금·재개 정보를 함께 묶는다. 임시 파일 쓰기 → 읽어 검증 → 기존 유효 파일을 백업 → 교체 순서로 처리한다. 동일 저장 위치에는 한 쓰기만 수행하고 대기 중인 최신 요청은 합칠 수 있다. 구체적인 원자적 교체 보장은 실제 플랫폼 파일 API로 확인한다.

검증은 버전, 필수 필드, 범위, 참조, 선택적인 체크섬으로 수행한다. 체크섬은 손상 탐지용이며 암호화나 부정행위 방지 기술이 아니다. 실패 시 기존 유효 저장을 덮어쓰지 않고 “기록 저장에 실패했어요”를 표시하고 재시도를 제공한다.

## 복구·마이그레이션

| 상황 | 처리 |
| --- | --- |
| 주 저장 손상 | 유효 백업 사용, 복구 안내 |
| 주 저장·백업 모두 손상 | 손상본 보존, 새 진행 시작 선택 제공 |
| 이전 스키마 | 단계별 변환 후 검증, 원본 백업 보존 |
| 미래 스키마 | 낮은 버전 앱이 덮어쓰지 않음, 업데이트 필요 표시 |
| 삭제/변경된 루트 | 기존 기록 보관, 재개만 루트 선택으로 이동 |
| 체크포인트 버전 불일치 | 새 콘텐츠의 시작 자세로 이동, 공중 좌표 적용 금지 |
| 저장 공간 부족 | 현재 세션은 유지, 저장 실패 안내, 기존 파일 보존 |
| 사용자 진행 초기화 | 설정 유지/전체 초기화 범위를 UI에서 명확히 확인 |

## 진단·개인정보 범위

개발 빌드는 최근 입력 명령, 틱, 잡기 거부 사유, 접점 오차, 프레임 시간, 빌드/콘텐츠 버전을 제한된 로컬 순환 로그로 남긴다. 화면 녹화·기기 고유 ID·연락처·계정 데이터는 필요하지 않다. 테스트 로그 공유는 사용자가 직접 내보내는 방식으로 시작한다. 외부 수집은 MVP에 없다.

진단 로그는 저장 데이터와 분리하고 용량 상한을 둔다. 앱 배포 시 개발 로그 수준을 낮춘다. 릴리스 버그 보고에는 개인정보가 없는 재현 단계·루트·버전·기기 모델·OS·입력 순서만 요청한다.
