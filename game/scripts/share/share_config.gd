class_name ShareConfig
extends RefCounted
## 공유 서버 주소와 공개 키(publishable key, 앱에 넣어도 되는 키). 비밀 키는 앱·저장소에 넣지 않는다(AGENTS.md).
## 비어 있으면 공유 기능은 "공유 서버 준비 중"으로 보이고, 만들기·내 문제 플레이는 그대로 된다.

const URL := ""
const KEY := ""


static func enabled() -> bool:
	return URL != "" and KEY != ""
