"""기술 수업(docs/47): 기술마다 벽 하나. 먼저 기술 없이 해 보고(안 됨) → 기술을 써서(됨) 차이를 느끼게 한다.
실행: python3 tools/lessons/gen_tech_lessons.py [params.json]  → game/data/routes/course/C_*_T.json
위치 값은 tech_params.json(봇·테스트로 맞춘 값)."""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "game", "data", "routes", "course")
P = json.load(open(sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "tech_params.json")))
NO = {"fatigue_drain": False, "techniques": []}


def hand(hid, x, y, hw=0.08, **kw):
    a = {"dir": [1, 0], "half_width": hw}
    a.update(kw)
    return {"hold_id": hid, "slots": [{"slot_id": "hand_1", "pos": [x, y], "allowed": ["LH", "RH"], "hand_area": a}]}


def foot(hid, x, y, hw=0.05):
    return {"hold_id": hid, "slots": [{"slot_id": "foot_1", "pos": [x, y], "allowed": ["LF", "RF"], "foot_area": {"half_width": hw}}]}


def goal(xl, xr, y):
    return {"hold_id": "G01", "slots": [{"slot_id": "goal_left", "pos": [xl, y], "allowed": ["LH", "RH"]},
                                        {"slot_id": "goal_right", "pos": [xr, y], "allowed": ["LH", "RH"]}]}


def build(spec):
    rid = spec["id"]

    def k(s):
        h, sl = s.split("/") if "/" in s else (s, None)
        if sl is None:
            sl = "foot_1" if h.startswith("F") else "hand_1"
        return "%s/%s/%s" % (rid, h, sl)

    holds = []
    for h in spec["hands"]:
        holds.append(hand(h[0], h[1], h[2], h[3] if len(h) > 3 else 0.08, **({"matchable": True} if len(h) > 4 and h[4] else {})))
    for f in spec["feet"]:
        holds.append(foot(*f))
    g = spec["goal"]
    holds.append(goal(g[0], g[1], g[2]))
    start = spec["start"]
    pose = {"pelvis": start["pelvis"], "angle": 0.0, "slots": {l: k(v) for l, v in start["slots"].items()}}
    steps = []
    # 마무리 손발 옮기기(2026-11-18 사용자: "하이스텝을 해도 안 닿여" — 정상 전에 필요한 동작을 단계로 안내)
    seq = list(spec["steps"])
    fin = [step("%s_F%d" % (spec["steps"][0]["step_id"][:2], i + 1), f[2], grab(f[0], f[1]), [f[3], W if f[0].endswith("H") else "하얗게 빛나면 떼요"])
           for i, f in enumerate(P.get(spec["key"], {}).get("finish", []))]
    seq = seq[:-1] + fin + seq[-1:]
    for st in seq:
        st = json.loads(json.dumps(st))
        ge = st["goal_event"]
        if "slot" in ge:
            ge["slot"] = k(ge["slot"])
        if st.pop("reset", False):
            st["start_pose"] = json.loads(json.dumps(pose))
        if "pose" in st:
            sp = st.pop("pose")
            st["start_pose"] = {"pelvis": sp["pelvis"], "angle": 0.0, "slots": {l: k(v) for l, v in sp["slots"].items()}}
        st.setdefault("rules", dict(NO))
        steps.append(st)
    d = {"route_id": rid, "content_version": 1, "validation_status": "Draft", "mode": "course", "grade": "V0", "order": 0,
         "name_ko": spec["name"], "course_id": spec["course"], "course_slot": "tutorial", "required_techniques": [], "check_swapped": False,
         "note": spec["note"], "bounds": {"x_min": -1.5, "x_max": 1.8, "y_min": 0.0, "y_max": 4.0}, "fail_line_y": -0.5,
         "platforms": [{"platform_id": "P00", "top_y": 0.1, "x_range": [-0.5, 0.8], "foot_slot_keys": [k("F01"), k("F02")]}],
         "start_pose": pose, "goal_slots": [k("G01/goal_left"), k("G01/goal_right")],
         "holds": holds, "intended_moves": [[m[0], k(m[1])] if len(m) == 2 else [m[0], m[1], m[2]] for m in spec["moves"]], "tutorial_steps": steps}
    json.dump(d, open(os.path.join(OUT, rid + ".json"), "w"), ensure_ascii=False, indent=1)


def step(sid, text, goal_event, help_, **kw):
    s = {"step_id": sid, "text_ko": text, "goal_event": goal_event, "help_ko": help_}
    s.update(kw)
    return s


def grab(l, s):
    return {"type": "grab", "limb": l, "slot": s}


def miss(l):
    return {"type": "miss", "limb": l}


W = "하얗게 빛나면 손가락을 떼요"
CLEAR = lambda sid, text: step(sid, text, {"type": "clear"}, ["한 손씩 정상 홀드로", "두 손이 다 잡으면 끝나요"])
LESSONS = {}

# ---- 하이스텝
p = P["high"]
LESSONS["high"] = {
    "id": "C_HIGH_T", "course": "C_HIGH", "name": "하이스텝",
    "note": "기술 수업(docs/47): 발판이 낮으면 맨 위 홀드에 손이 안 닿는다 → 허리 높이 발판에 발을 올리고 일어서면 닿는다.",
    "hands": p["hands"], "feet": p["feet"], "goal": p["goal"], "start": p["start"], "moves": p["moves"],
    "steps": [
        step("HS1", "먼저 오른손을 맨 위 노란 홀드로 뻗어 보세요. 가운데를 위로 끌어 몸을 올려도 좋아요.", miss("RH"), ["오른손 패드를 위로 끝까지 끌어요", "닿지 않으면 그대로 떼요"], pose=p["pose1"]),
        step("HS2", "발이 낮아서 안 닿아요. 오른발을 허리 높이의 노란 발판에 높게 올려요. 잠깐 기다리면 몸이 그 발 위로 올라가요.", grab("RF", p["high_foot"]), ["오른발 패드를 위로 많이 끌어요", "발판이 하얗게 빛나면 떼요"], pose=p["pose1"]),
        step("HS3", "몸이 올라갔어요. 이제 오른손을 맨 위 노란 홀드로 뻗어요. 아까는 안 닿았죠?", grab("RH", p["top"]), ["몸이 다 올라갈 때까지 잠깐 기다렸다 뻗어요", "오른손 패드를 위로 끌어요. " + W]),
        CLEAR("HS4", "발을 높이 올려 일어서는 이 동작이 하이스텝이에요. 두 손으로 정상을 잡아요."),
    ]}

# ---- 다이노
p = P["dyno"]
LESSONS["dyno"] = {
    "id": "C_DYNO_T", "course": "C_DYNO", "name": "다이노",
    "note": "기술 수업(docs/47): 맨 위 홀드는 일어서도 안 닿고 중간 발판도 없다 → 뛰어서 잡는다(가운데 두 번 누르고 끌기, 날아가며 손 패드).",
    "hands": p["hands"], "feet": p["feet"], "goal": p["goal"], "start": p["start"], "moves": p["moves"],
    "steps": [
        step("DY1", "먼저 오른손을 맨 위 노란 홀드로 뻗어 보세요.", miss("RH"), ["오른손 패드를 위로 끝까지 끌어요", "닿지 않으면 그대로 떼요"]),
        step("DY2", "너무 멀어요. 뛰어서 잡아요. 화면 가운데를 손가락으로 톡톡 두 번 누르고, 두 번째는 떼지 말고 아래로 쭉 끌어내려요. 정상에 고리가 생기면 손가락을 떼요. 날아가는 동안 잡을 손의 패드를 눌러요.",
             {"type": "dyno_catch"}, ["톡톡 두 번, 두 번째는 누른 채 아래로 쭉. 처음 누른 자리로 돌아와 떼면 취소돼요", "날아가는 중 잡을 손(왼손이든 오른손이든)의 패드를 눌러요. 화면이 느려지니 서두르지 않아도 돼요"], reset=True),
        CLEAR("DY3", "멀리 있는 홀드로 뛰어서 잡는 것이 다이노예요. 두 손으로 정상을 잡아요."),
    ]}


# ---- 매치
p = P.get("match", {})
if p:
    LESSONS["match"] = {
        "id": "C_MATCH_T", "course": "C_MATCH", "name": "매치",
        "note": "기술 수업(docs/47): 초록 홀드에 두 손을 모으려 하면 먼저 있던 손이 밀려난다 → 파란 홀드에서는 두 손이 함께 잡힌다. 모은 뒤 오른손이 다음 홀드로.",
        "hands": p["hands"], "feet": p["feet"], "goal": p["goal"], "start": p["start"], "moves": p["moves"],
        "steps": [
            step("MT1", "왼손을 오른손이 잡은 초록 홀드에 같이 놓아 보세요.", {"type": "slot_swap", "limb": "LH"}, ["왼손 패드를 오른손이 있는 초록 홀드로 끌어요", "하얗게 빛나면 떼요"]),
            step("MT2", "초록 홀드는 한 손만 잡을 수 있어 오른손이 밀려났어요. 이번엔 오른손이 잡은 파란 홀드에 왼손을 모아요.", grab("LH", p["blue"]), ["왼손 패드를 파란 홀드로 끌어요", "파란 홀드는 두 손을 함께 잡을 수 있어요"], pose=p["start2"]),
            step("MT3", "두 손을 모았어요. 이제 오른손을 오른쪽 위 노란 홀드로 옮겨요.", grab("RH", p["far"]), ["오른손 패드를 오른쪽 위로 끌어요", W]),
            CLEAR("MT4", "한 홀드에 두 손을 모으는 것이 매치예요. 두 손으로 정상을 잡아요."),
        ]}

# ---- 풋스왑
p = P.get("fswap", {})
if p:
    LESSONS["fswap"] = {
        "id": "C_FSWAP_T", "course": "C_FSWAP", "name": "풋스왑",
        "note": "기술 수업(docs/47): 왼발이 멀리 있으면 오른발이 오른쪽 먼 발판에 안 닿는다 → 왼발을 오른발 자리에 넣으면 오른발이 비켜나 멀리 간다.",
        "hands": p["hands"], "feet": p["feet"], "goal": p["goal"], "start": p["start"], "moves": p["moves"],
        "steps": [
            step("FS1", "먼저 오른발을 오른쪽 멀리 노란 발판으로 뻗어 보세요. 몸을 옮겨도 좋아요.", miss("RF"), ["오른발 패드를 오른쪽 끝까지 끌어요. 가운데를 끌어 몸을 옮겨도 안 닿아요", "닿지 않으면 그대로 떼요"]),
            step("FS2", "왼발이 멀어서 안 닿아요. 왼발을 오른발이 딛은 발판에 놓아요. 오른발이 자리를 비켜 줘요.", {"type": "pad_foot_swap", "limb": "LF"}, ["왼발 패드를 오른발이 있는 발판으로 끌어요", "발판이 하얗게 빛나면 떼요"], reset=True),
            step("FS3", "이제 오른발을 오른쪽 멀리 발판으로 뻗어요. 가운데를 오른쪽으로 끌어 몸을 옮기면 닿아요.", grab("RF", p["far"]), ["가운데를 누른 채 오른쪽으로 끌고, 다른 손가락으로 오른발 패드를 오른쪽으로 끌어요", "발판이 하얗게 빛나면 떼요"]),
            CLEAR("FS4", "한 발판에서 발을 바꾸는 것이 풋스왑이에요. 두 손으로 정상을 잡아요."),
        ]}

# ---- 합발
p = P.get("fmatch", {})
if p:
    LESSONS["fmatch"] = {
        "id": "C_FMATCH_T", "course": "C_FMATCH", "name": "합발",
        "note": "기술 수업(docs/47): 풋스왑과 같은 자리지만 파란 홀드라 두 발이 함께 선다. 두 발을 모은 뒤 오른발을 멀리 옮긴다.",
        "hands": p["hands"], "feet": p["feet"], "goal": p["goal"], "start": p["start"], "moves": p["moves"],
        "steps": [
            step("FM1", "먼저 오른발을 오른쪽 멀리 노란 발판으로 뻗어 보세요. 몸을 옮겨도 좋아요.", miss("RF"), ["오른발 패드를 오른쪽 끝까지 끌어요. 가운데를 끌어 몸을 옮겨도 안 닿아요", "닿지 않으면 그대로 떼요"]),
            step("FM2", "왼발을 오른발이 딛은 파란 홀드에 같이 올려요. 파란 홀드에는 두 발이 함께 설 수 있어요.", grab("LF", p["blue"]), ["왼발 패드를 파란 홀드로 끌어요", "하얗게 빛나면 떼요"], reset=True),
            step("FM3", "두 발이 모였어요. 이제 오른발을 오른쪽 멀리 발판으로 뻗어요. 가운데를 오른쪽으로 끌어 몸을 옮기면 닿아요.", grab("RF", p["far"]), ["가운데를 누른 채 오른쪽으로 끌고, 다른 손가락으로 오른발 패드를 오른쪽으로 끌어요", "발판이 하얗게 빛나면 떼요"]),
            CLEAR("FM4", "한 홀드에 두 발을 모으는 것이 합발이에요. 두 손으로 정상을 잡아요."),
        ]}

# ---- 크로스
p = P.get("cross", {})
if p:
    LESSONS["cross"] = {
        "id": "C_CROSS_T", "course": "C_CROSS", "name": "크로스",
        "note": "기술 수업(docs/47): 왼손이 잡은 작은 홀드에는 두 손을 모을 수 없다 → 오른손을 왼손 너머로 엇갈려 왼쪽 홀드를 잡고, 왼손은 더 왼쪽으로.",
        "hands": p["hands"], "feet": p["feet"], "goal": p["goal"], "start": p["start"], "moves": p["moves"],
        "steps": [
            step("CR1", "왼쪽으로 가야 해요. 오른손을 왼손 너머로 엇갈려 왼쪽 노란 홀드를 잡아요.", grab("RH", p["cross"]), ["오른손 패드를 왼쪽으로 멀리 끌어요. 팔이 엇갈려도 돼요", W]),
            step("CR2", "왼손이 자유로워졌어요. 왼손을 더 왼쪽 노란 홀드로 옮겨요.", grab("LH", p["next"]), ["왼손 패드를 왼쪽으로 끌어요", W]),
            CLEAR("CR3", "팔을 엇갈려 옆으로 가는 것이 크로스예요. 두 손으로 정상을 잡아요."),
        ]}

for name, spec in LESSONS.items():
    spec["key"] = name
    if name in P:
        build(spec)
        print("lesson", spec["id"])
