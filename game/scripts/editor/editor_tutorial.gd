class_name EditorTutorial
extends RefCounted
## 만들기 튜토리얼(2026-11-26 사용자 "만들기도 튜토리얼을 만들어줘", docs/52 "어떻게 문제를 만드는지 직관적이지 않다").
## 따라 하기: 단계마다 실제로 해야 넘어가고, 다 하면 지금 초안이 막는 것 없는 첫 문제가 된다.
## 놓기·옮기기·돌리기는 만들기 화면이 note()로 알리는 사건으로, 나머지는 초안 상태로 본다(이미 돼 있으면 바로 넘어감).
## target: 노란 고리로 가리킬 버튼 [action, arg]("name"은 이름 칸). 화면이 매 프레임 update()를 부른다.

const ID := "EDITOR_T"      # Progress.tutorials 키(처음 새 문제를 열 때 한 번 저절로)
const HELP_SECONDS := 15.0

const STEPS := [
	{"id": "place", "target": ["list", "hand"],
		"text": "손홀드를 하나 골라 가운데 벽의 빈 곳을 눌러 보세요. 그 자리에 놓여요.",
		"help": "오른쪽 판 위 [손홀드]를 누르고 저그 같은 종류를 고른 뒤 벽을 누르세요."},
	{"id": "move", "target": [],
		"text": "놓은 홀드를 손가락으로 끌어 옮겨 보세요.",
		"help": "노란 고리가 있는 홀드가 고른 홀드예요. 벽 어디서 끌어도 그 홀드가 따라와요."},
	{"id": "rotate", "target": ["rot", "5"],
		"text": "오른쪽 아래 원을 돌리거나 +5° 버튼을 눌러 홀드를 돌려 보세요. 잡는 방향이 바뀌어요.",
		"help": "홀드를 눌러 먼저 고르세요. 원의 손잡이를 끌면 바로 돌아가요."},
	{"id": "spots", "target": ["list", "foot"],
		"text": "시작 자리를 만들어요. 손홀드를 하나 더 놓아 두 손홀드를 60cm쯤 떼고, 그보다 1.3m쯤 아래에 발홀드 두 개를 놓으세요.",
		"help": "[발홀드]를 누르고 종류를 고른 뒤 손홀드 아래 벽을 누르세요. 손홀드 2개, 발홀드 2개가 필요해요. 왼쪽 높이 막대의 눈금이 1m예요."},
	{"id": "start", "target": ["tool", "start"],
		"text": "왼쪽 [시작홀드 설정]을 누르고 왼손 → 오른손 → 왼발 → 오른발 차례로 홀드를 누르세요.",
		"help": "하나를 정하면 다음 손발로 저절로 넘어가요. 손은 손홀드에만 정할 수 있어요."},
	{"id": "top", "target": ["list", "goal"],
		"text": "[탑]을 골라 위쪽에 놓으세요. 두 손으로 탑을 잡으면 완등이에요.",
		"help": "빈 벽을 위로 끌거나 왼쪽 높이 막대를 누르면 위쪽 벽이 보여요."},
	{"id": "name", "target": ["name", ""],
		"text": "위쪽 이름 칸을 눌러 문제 이름을 쓰세요.",
		"help": "[나가기] 오른쪽의 \"문제 이름\" 칸이에요."},
	{"id": "check", "target": ["check_open", ""],
		"text": "아래 [점검]을 눌러 막는 것을 고치세요. 막는 것이 0이 되면 끝이에요.",
		"help": "점검 창의 [보기]를 누르면 고칠 홀드로 가요. \"옮기면 시작 자세가 돼요\"라는 말대로 옮겨 보세요."},
]

var steps: Array = STEPS
var index := 0
var done := false
var _events: Array = []
var _idle := 0.0


func current() -> Dictionary:
	return steps[index] if index < steps.size() else {}


## 만들기 화면 사건: "place_hand" / "place_foot" / "place_goal" / "move" / "rotate".
func note(ev: String) -> void:
	_events.append(ev)


## 매 프레임. 반환: "" / "next"(다음 단계) / "done"(마지막 단계까지 끝).
func update(draft: RouteDraft, problems: Array, dt: float) -> String:
	if done:
		return ""
	var evs := _events
	_events = []
	if not _met(str(current().id), draft, problems, evs):
		_idle += dt
		return ""
	index += 1
	_idle = 0.0
	done = index >= steps.size()
	return "done" if done else "next"


func help_text() -> String:
	return str(current().get("help", "")) if not done and _idle >= HELP_SECONDS else ""


func target() -> Array:
	return current().get("target", []) if not done else []


func _met(id: String, d: RouteDraft, problems: Array, evs: Array) -> bool:
	match id:
		"place":
			return evs.has("place_hand")
		"move":
			return evs.has("move")
		"rotate":
			return evs.has("rotate")
		"spots":
			var hands := d.holds.filter(func(h): return h.type != "goal" and RouteDraft.is_hand_type(h.type)).size()
			var feet := d.holds.filter(func(h): return HoldTypes.is_foot(h.type)).size()
			return hands >= 2 and feet >= 2
		"start":
			return not d.start.values().has("")
		"top":
			return not d.goal_hold().is_empty()
		"name":
			return d.name.strip_edges() != ""
		"check":
			return problems.is_empty()
	return false
