# 13. 공식 근거·참고 자료

확인일: **2026-10-29(KST)**. 공식 릴리스와 Godot 4.7 버전 문서를 우선 확인했다. 링크의 내용과 배포 정책은 바뀔 수 있으므로 실제 개발 착수/출시 때 다시 확인한다. 검색 결과의 제3자 글을 기술 근거로 채택하지 않았다.

## 기술 자료

| ID | 공식 자료 | 확인한 사실 | 설계에 적용한 범위 |
| --- | --- | --- | --- |
| S01 | [Godot 4.7.2 유지보수 릴리스](https://godotengine.org/article/maintenance-release-godot-4-7-2/) / [다운로드 아카이브](https://godotengine.org/download/archive/) | 4.7.2 stable 릴리스가 게시됨 | 개발 기준 버전 후보. 설치·빌드를 했다는 뜻은 아님 |
| S02 | [InputEventScreenTouch 4.7](https://docs.godotengine.org/en/4.7/classes/class_inputeventscreentouch.html) | 터치 index, 눌림/해제, 취소 정보 제공 | 포인터별 소유권과 cancel/release 분리 |
| S03 | [InputEventScreenDrag 4.7](https://docs.godotengine.org/en/4.7/classes/class_inputeventscreendrag.html) | relative의 콘텐츠 배율과 screen_relative의 차이 | 드래그 좌표를 명시적으로 변환, 감도 일관성 |
| S04 | [렌더러 개요 4.7](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html) | Mobile/Compatibility/Forward+의 플랫폼·기능 차이 | 모바일 3D의 Mobile 우선 시험, 호환 렌더러 별도 검증 |
| S05 | [iOS 내보내기 4.7](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_ios.html) | macOS와 Xcode, 내보내기·서명 관련 준비 | iOS 개발 환경을 별도 작업으로 계획 |
| S06 | [Skeleton3D 4.7](https://docs.godotengine.org/en/4.7/classes/class_skeleton3d.html) | 뼈 계층·포즈와 스켈레톤 좌표의 의미 | 표현 리그와 판정 좌표의 경계 관리 |
| S07 | [물리 틱과 렌더 프레임 4.7](https://docs.godotengine.org/en/4.7/tutorials/physics/interpolation/physics_interpolation_introduction.html) | 고정 물리 틱과 렌더 프레임은 다를 수 있음 | 고정 틱 게임 규칙과 보간 표현 분리 |
| S08 | [Android 내보내기 4.7](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_android.html) | JDK·Android SDK·엔진 설정 필요 | 첫 실제 기기 빌드 준비 목록 |

공식 터치 API가 있다는 사실은 모든 장치의 네 손가락 입력과 편안함을 보장하지 않는다. 렌더러가 모바일을 지원한다는 사실도 이 게임이 목표 FPS를 달성함을 의미하지 않는다. 실제 판정은 [검증 계획](10_validation.md)에 따른다.

## 자체 설계인 부분

네 패드 배치, 드래그 후 놓아 잡기, 홀드 자동 유지, 몸통 자세 비용 함수, 피로 변화율, 슬롯 동시 확정, 12개 루트, 성능 목표, 공수는 이 프로젝트의 제안이다. 공식 문서나 다른 게임이 같은 방식을 사용한다고 주장하지 않는다. 경쟁 게임의 이름을 붙여 이미 검증된 방식처럼 표현하지 않는다.

## 이미지와 아트

참고 이미지 **REF01 수신·분석 완료(2026-10-30 KST)**. 출처는 사용자가 첨부한 44439.jpg이며 JPEG 758×1536px다. 화면에 gamebakers 계정명과 Cairn을 언급한 설명이 보인다. 원 게시물 URL·게시일·원작 렌더링 기법은 제공되지 않았으며 별도 확인한 사실로 쓰지 않는다.

분석 대상은 캡처 중앙의 약 758×426px 가로 게임 장면이다. SNS 인터페이스·프로필·영상 자막은 게임 아트 비교에서 제외한다. 원본 식별 해시, 관찰 내용, 제작 팔레트와 적용 기준은 [22. 참고 이미지 분석](22_reference_art_direction.md)에 있다. 화면의 가는 선·무광 질감·넓은 명암·따뜻한 흙빛을 우리 아트 방향에 반영했다.

원본 이미지를 게임의 텍스처·캐릭터 자산으로 추출하지 않았다. 기존 와이어프레임은 정보 배치만 검토하는 자체 제작 자료이며 목표 스타일의 완성 시안이나 실행 화면이 아니다. 위 기술 자료의 확인일과 이번 첨부 이미지 분석일은 서로 다른 기록이다.

## 배포 시 다시 확인할 사항

Godot의 최신 안정 패치·내보내기 템플릿, Android의 SDK/타깃 API·서명 요구, iOS의 Xcode/SDK·서명 요구, 스토어 제출·개인정보 관련 서식은 실제 배포일의 공식 자료로 갱신한다. 이번 문서가 향후 정책을 확정하는 자료가 되지 않게 한다.
