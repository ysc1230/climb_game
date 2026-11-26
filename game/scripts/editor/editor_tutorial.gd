class_name EditorTutorial
extends RefCounted
## 만들기 튜토리얼(2026-11-26 사용자 "만들기도 튜토리얼을 만들어줘", docs/52 "어떻게 문제를 만드는지 직관적이지 않다").
## 사용자 "한 스텝씩 어디를 클릭하며 진행해야 문제가 만들어지는지 … 중간에 원하는 홀드들을 추가하도록 한 뒤 … 최종적으로 본인 문제를":
## 한 단계에 누를 곳 하나(버튼·벽의 노란 원·홀드)를 가리킨다. 시작 자리 네 개는 정해 둔 원(SPOTS)에 놓아 시작 자세가 늘 되게 하고,
## 그 뒤 자유롭게 놓기 → 카드 [다음] → 탑·이름·점검·저장으로 끝난다. 0.38: 홀드 종류를 먼저, 그다음 쓰임(손으로·발로·탑으로).
## goal: ["ev", 사건] 만들기 화면이 note()로 알린 "action:arg"(버튼) / ["spot", i] 원 i에 그 종류 홀드 / ["start", 손발, i] 원 i 홀드를 시작으로 /
## ["top"] / ["name"] 이름 있고 쓰는 중 아님 / ["check"] 막는 것 없음. 상태 목표는 이미 돼 있으면 바로 넘어간다.
## target: 노란 고리로 가리킬 곳. 버튼 [action, arg], ["mark", i](원, −1은 탑 원), ["hold", i](원 i의 홀드), ["name", ""](이름 칸).

const ID := "EDITOR_T"      # Progress.tutorials 키(처음 새 문제를 열 때 한 번 저절로)
const HELP_SECONDS := 15.0
const MARK_R := 0.25         # 원을 누른 것으로 보는 거리(m). 안이면 원 가운데에 놓는다
## 시작 자리 원: 왼손·오른손(60cm 간격), 그 1.3m 아래 왼발·오른발. 이 배치는 시작 자세가 되고 간격도 지킨다(테스트).
const SPOTS: Array[Vector2] = [Vector2(-0.3, 1.7), Vector2(0.3, 1.7), Vector2(-0.3, 0.4), Vector2(0.3, 0.4)]
const SPOT_KIND := ["hand", "hand", "foot", "foot"]
const LIMBS: Array[StringName] = [&"LH", &"RH", &"LF", &"RF"]

const STEPS := [
	{"id": "type_jug", "goal": ["ev", "type:jug"], "target": ["type", "jug"],
		"text": "오른쪽 [저그]를 누르세요. 크고 잡기 쉬운 홀드예요.", "help": "오른쪽 판 [홀드 종류]의 첫 번째 버튼이에요. 노란 고리가 깜빡이는 곳을 누르면 돼요."},
	{"id": "role_hand", "goal": ["ev", "role:hand"], "target": ["role", "hand"],
		"text": "[손으로]를 누르세요. 손으로 잡는 홀드가 돼요.", "help": "[어떻게 쓸까요] 아래 첫 번째 버튼이에요. 종류를 먼저 고르고, 손·발·탑 중 어디에 쓸지 골라요."},
	{"id": "spot0", "goal": ["spot", 0], "target": ["mark", 0],
		"text": "벽의 노란 원 1을 누르세요. 왼손으로 시작할 홀드가 놓여요.", "help": "원 안 아무 데나 누르면 원 가운데에 놓여요."},
	{"id": "spot1", "goal": ["spot", 1], "target": ["mark", 1],
		"text": "노란 원 2를 누르세요. 오른손으로 시작할 홀드예요.", "help": "원 1 오른쪽, 같은 높이예요."},
	{"id": "type_foot", "goal": ["ev", "type:crimp"], "target": ["type", "crimp"],
		"text": "이제 발 차례예요. [크림프]를 누르세요. 모든 홀드는 손으로도 발로도 써요.", "help": "[홀드 종류]의 두 번째 버튼이에요."},
	{"id": "role_foot", "goal": ["ev", "role:foot"], "target": ["role", "foot"],
		"text": "[발로]를 누르세요. 발로 딛는 홀드(보라색)가 돼요.", "help": "[어떻게 쓸까요] 아래 두 번째 버튼이에요."},
	{"id": "spot2", "goal": ["spot", 2], "target": ["mark", 2],
		"text": "노란 원 3을 누르세요. 왼발로 시작할 발판이에요.", "help": "원 1·2보다 1.3m 아래예요. 안 보이면 빈 벽을 위로 끌어요."},
	{"id": "spot3", "goal": ["spot", 3], "target": ["mark", 3],
		"text": "노란 원 4를 누르세요. 오른발로 시작할 발판이에요.", "help": "원 3 오른쪽, 같은 높이예요."},
	{"id": "tool_start", "goal": ["ev", "tool:start"], "target": ["tool", "start"],
		"text": "왼쪽 [시작홀드 설정]을 누르세요. 어느 손발이 어디서 시작할지 정해요.", "help": "왼쪽 도구 판의 네 번째 버튼이에요."},
	{"id": "start_lh", "goal": ["start", &"LH", 0], "target": ["hold", 0],
		"text": "[왼손]이 골라져 있어요. 노란 고리가 있는 홀드 1을 누르세요.", "help": "벽에서 깜빡이는 고리 안의 홀드를 누르세요."},
	{"id": "start_rh", "goal": ["start", &"RH", 1], "target": ["hold", 1],
		"text": "다음은 오른손이에요. 홀드 2를 누르세요.", "help": "하나를 정하면 다음 손발로 저절로 넘어가요."},
	{"id": "start_lf", "goal": ["start", &"LF", 2], "target": ["hold", 2],
		"text": "왼발이에요. 발판 3을 누르세요.", "help": "벽에서 깜빡이는 고리 안의 발판을 누르세요."},
	{"id": "start_rf", "goal": ["start", &"RF", 3], "target": ["hold", 3],
		"text": "오른발이에요. 발판 4를 누르세요.", "help": "벽에서 깜빡이는 고리 안의 발판을 누르세요."},
	{"id": "tool_edit", "goal": ["ev", "tool:edit"], "target": ["tool", "edit"],
		"text": "시작 자리가 다 됐어요. 왼쪽 [홀드 놓기]를 누르세요.", "help": "왼쪽 도구 판의 첫 번째 버튼이에요."},
	{"id": "free", "goal": ["ev", "tut_next:"], "target": ["tut_next", ""],
		"text": "이제 원하는 홀드를 놓아 길을 만드세요. 종류와 쓰임을 고르고 벽을 누르면 놓여요. 다 놓았으면 [다음]을 누르세요.",
		"help": "놓은 홀드는 끌어서 옮기고 오른쪽 아래 원으로 돌려요. 위쪽 벽은 빈 곳을 아래로 끌거나 왼쪽 높이 막대를 누르면 보여요."},
	{"id": "type_top", "goal": ["ev", "type:jug"], "target": ["type", "jug"],
		"text": "이제 끝 홀드(탑)예요. 탑으로 쓸 종류를 골라요. [저그]를 누르세요.", "help": "탑은 어느 종류든 되지만, 두 손으로 같이 잡을 수 있는 크기여야 해요."},
	{"id": "role_top", "goal": ["ev", "role:top"], "target": ["role", "top"],
		"text": "[탑으로]를 누르세요. 탑은 문제에 하나뿐이에요.", "help": "[어떻게 쓸까요] 아래 세 번째 버튼이에요."},
	{"id": "top", "goal": ["top"], "target": ["mark", -1],
		"text": "노란 원을 누르면 탑이 놓여요(가장 높은 홀드 위). 다른 곳을 눌러도 돼요. 두 손으로 탑을 잡으면 완등이에요.",
		"help": "원이 안 보이면 빈 벽을 아래로 끌어 위쪽을 보세요."},
	{"id": "name", "goal": ["name"], "target": ["name", ""],
		"text": "위쪽 [문제 이름] 칸을 누르고 이름을 쓰세요. 다 쓰면 키보드를 닫으세요.", "help": "[나가기] 오른쪽 칸이에요."},
	{"id": "check", "goal": ["check"], "target": ["check_open", ""],
		"text": "아래 [점검]을 누르세요. 고칠 것이 0개가 되면 넘어가요.",
		"help": "점검 창의 [보기]를 누르면 고칠 곳으로 가요. 빨간 홀드는 다른 홀드와 겹친 거예요."},
	{"id": "save", "goal": ["ev", "save:"], "target": ["save", ""],
		"text": "다 만들었어요! 위쪽 [저장]을 누르면 내 문제로 저장돼요.", "help": "오른쪽 위 맨 끝 버튼이에요."},
]

var steps: Array = STEPS
var index := 0
var done := false
var typing := false          # 이름 칸에 쓰는 중(만들기 화면이 매 프레임 알려 줌)
var _events: Array = []
var _idle := 0.0


## 시작한다: 이미 시작 자리가 다 정해진 문제면 [편집]부터, 이미 된 단계는 넘긴다.
func begin(d: RouteDraft) -> void:
	if not d.start.values().has(""):
		index = steps.map(func(s): return s.id).find("tool_edit")
	_skip(d, [])


func current() -> Dictionary:
	return steps[index] if index < steps.size() else {}


## 만들기 화면 사건: 버튼은 "action:arg"(예 "list:hand", "tut_next:", "save:").
func note(ev: String) -> void:
	_events.append(ev)


## 매 프레임. 반환: "" / "next"(다음 단계) / "done"(마지막 단계까지 끝).
func update(d: RouteDraft, problems: Array, dt: float) -> String:
	if done:
		return ""
	var evs := _events
	_events = []
	if not _met(current().goal, d, problems, evs):
		_idle += dt
		return ""
	index += 1
	_idle = 0.0
	_skip(d, problems)
	return "done" if done else "next"


func help_text() -> String:
	return str(current().help) if not done and _idle >= HELP_SECONDS else ""


func target() -> Array:
	return current().target if not done else []


## 지금 단계의 노란 원(벽 좌표). 없으면 null.
func mark(d: RouteDraft) -> Variant:
	var t := target()
	if t.size() == 2 and t[0] == "mark":
		return top_mark(d) if int(t[1]) < 0 else SPOTS[int(t[1])]
	return null


## 원 안만 놓을 수 있는가(시작 자리). 탑 원은 다른 곳도 된다.
func mark_strict() -> bool:
	return str(current().get("goal", [""])[0]) == "spot"


## 원 단계에서 놓아야 하는 종류("hand"/"foot"), 아니면 "".
func place_kind() -> String:
	return SPOT_KIND[int(current().goal[1])] if mark_strict() else ""


## 시작홀드 단계: {limb, hold}(원 홀드 id). 아니면 {}.
func start_want(d: RouteDraft) -> Dictionary:
	var g: Array = current().get("goal", [])
	if g.is_empty() or g[0] != "start":
		return {}
	return {"limb": g[1], "hold": spot_hold(d, int(g[2]))}


## 원 i 가운데(5cm 안)에 있는 그 쓰임(손·발) 홀드 id. 없으면 "".
func spot_hold(d: RouteDraft, i: int) -> String:
	for h in d.holds:
		if h.role != "top" and Vector2(h.x, h.y).distance_to(SPOTS[i]) < 0.05 and (SPOT_KIND[i] == "foot") == (h.role == "foot"):
			return h.id
	return ""


## 탑 원: 가장 높은 홀드 0.6m 위(같은 x). 홀드가 없으면 가운데 2.5m.
static func top_mark(d: RouteDraft) -> Vector2:
	var best := Vector2(0, 1.9)
	for h in d.holds:
		if h.role != "top" and h.y > best.y:
			best = Vector2(h.x, h.y)
	return Vector2(best.x, minf(best.y + 0.6, d.max_y()))


func _skip(d: RouteDraft, problems: Array) -> void:
	while index < steps.size() and current().goal[0] != "ev" and _met(current().goal, d, problems, []):
		index += 1
	done = index >= steps.size()


func _met(g: Array, d: RouteDraft, problems: Array, evs: Array) -> bool:
	match str(g[0]):
		"ev":
			return evs.has(g[1])
		"spot":
			return spot_hold(d, int(g[1])) != ""
		"start":
			return d.start[g[1]] != "" and d.start[g[1]] == spot_hold(d, int(g[2]))
		"top":
			return not d.goal_hold().is_empty()
		"name":
			return d.name.strip_edges() != "" and not typing
		"check":
			return problems.is_empty()
	return false
