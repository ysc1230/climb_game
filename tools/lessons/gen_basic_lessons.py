import json, os
OUT = os.path.expanduser("~/Projects/climb_game/game/data/routes/course")
os.makedirs(OUT, exist_ok=True)
NO = {"fatigue_drain": False, "techniques": []}

def hand(hid, x, y, hw=0.12, **kw):
    a = {"dir": [1, 0], "half_width": hw}; a.update(kw)
    return {"hold_id": hid, "slots": [{"slot_id": "hand_1", "pos": [x, y], "allowed": ["LH", "RH"], "hand_area": a}]}
def foot(hid, x, y):
    return {"hold_id": hid, "slots": [{"slot_id": "foot_1", "pos": [x, y], "allowed": ["LF", "RF"]}]}
def goal(xl, xr, y):
    return {"hold_id": "G01", "slots": [{"slot_id": "goal_left", "pos": [xl, y], "allowed": ["LH", "RH"]}, {"slot_id": "goal_right", "pos": [xr, y], "allowed": ["LH", "RH"]}]}

def route(rid, course, name, note, holds, moves, steps, xmax=1.5, version=1):
    def k(s):
        h, sl = s.split("/") if "/" in s else (s, None)
        if sl is None:
            sl = "foot_1" if h.startswith("F") else "hand_1"
        return "%s/%s/%s" % (rid, h, sl)
    for st in steps:
        g = st["goal_event"]
        if "slot" in g: g["slot"] = k(g["slot"])
        if "start_pose" in st:
            st["start_pose"]["slots"] = {l: k(v) for l, v in st["start_pose"]["slots"].items()}
    d = {"route_id": rid, "content_version": version, "validation_status": "Draft", "mode": "course", "grade": "V0", "order": 0,
         "name_ko": name, "course_id": course, "course_slot": "tutorial", "required_techniques": [], "note": note,
         "bounds": {"x_min": -1.5, "x_max": xmax, "y_min": 0.0, "y_max": 4.0}, "fail_line_y": -0.5,
         "platforms": [{"platform_id": "P00", "top_y": 0.1, "x_range": [-0.4, 0.8], "foot_slot_keys": [k("F01"), k("F02")]}],
         "start_pose": {"pelvis": [0.1, 0.76], "angle": 0.0, "slots": {"LH": k("H01"), "RH": k("H02"), "LF": k("F01"), "RF": k("F02")}},
         "goal_slots": [k("G01/goal_left"), k("G01/goal_right")],
         "holds": holds, "intended_moves": [[l, k(s)] for l, s in moves], "tutorial_steps": steps}
    json.dump(d, open(os.path.join(OUT, rid + ".json"), "w"), ensure_ascii=False, indent=1)

def step(sid, text, goal_event, help_, rules=None, **kw):
    s = {"step_id": sid, "text_ko": text, "goal_event": goal_event, "help_ko": help_, "rules": dict(rules or NO)}
    s.update(kw); return s
def grab(l, s): return {"type": "grab", "limb": l, "slot": s}

BASE = [hand("H01", -0.1, 1.85), hand("H02", 0.3, 1.85), foot("F01", -0.05, 0.1), foot("F02", 0.25, 0.1)]
import sys
P = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "basic_params.json")))

# ---- 기본 조작
b = P["basic"]
holds = BASE + [hand("H03", -0.1, b["h1"]), hand("H04", 0.3, b["h1"]), foot("F03", -0.05, b["f1"]), foot("F04", 0.25, b["f1"]),
                hand("H05", -0.1, b["h2"]), hand("H06", 0.3, b["h2"]), foot("F05", -0.05, b["f2"]), foot("F06", 0.25, b["f2"]), goal(-0.1, 0.3, b["g"])]
moves = [("LH", "H03"), ("RH", "H04"), ("LF", "F03"), ("RF", "F04"), ("LH", "H05"), ("RH", "H06"), ("LF", "F05"), ("RF", "F06"), ("LH", "G01/goal_left"), ("RH", "G01/goal_right")]
W = "홀드가 하얗게 빛나면 손가락을 떼요"
steps = [
 step("B1", "왼손을 노란 홀드로 옮겨 잡아요.", grab("LH", "H03"), ["왼쪽 위 손 패드를 누른 채 끌어요", W]),
 step("B2", "오른손도 노란 홀드로 옮겨요.", grab("RH", "H04"), ["오른쪽 위 손 패드를 끌어요", W]),
 step("B3", "왼발을 노란 발판에 올려요.", grab("LF", "F03"), ["왼쪽 아래 발 패드를 끌어요", "발판이 하얗게 빛나면 떼요"]),
 step("B4", "오른발도 올려요. 몸이 따라 올라가요.", grab("RF", "F04"), ["오른쪽 아래 발 패드를 끌어요", "발판이 하얗게 빛나면 떼요"]),
 step("B5", "손을 하나씩 다음 노란 홀드로 옮겨요.", grab("LH", "H05"), ["손을 하나씩 옮겨요", "하얗게 빛나면 떼요"]),
 step("B6", "다른 손도 옮겨요.", grab("RH", "H06"), ["손을 하나씩 옮겨요", "하얗게 빛나면 떼요"]),
 step("B7", "발도 하나씩 올려요.", grab("LF", "F05"), ["발을 하나씩 올려요", "하얗게 빛나면 떼요"]),
 step("B8", "다른 발도 올려요. 위쪽 '현재 높이'가 늘어요.", grab("RF", "F06"), ["발을 하나씩 올려요", "하얗게 빛나면 떼요"]),
 step("B9", "두 손으로 맨 위 크림색 홀드를 잡으면 끝나요.", {"type": "clear"}, ["한 손씩 정상 홀드로", "두 손이 다 잡으면 완등"]),
]
route("C_BASIC_T", "C_BASIC", "기본 조작", "v1(2026-11-14, docs/42 수업 0): 사용자 더미 몸에 맞춘 짧은 사다리. 손 → 손 → 발 → 발 순서로 두 번 오르고 정상. 모든 단계 피로 끔.", holds, moves, steps)

# ---- 발로 오르기
f = P["feet"]
holds = BASE + [foot("F03", -0.05, f["f1"]), foot("F04", 0.25, f["f2"]), hand("H03", -0.1, f["h"]), hand("H04", 0.3, f["h"]),
                hand("H05", -0.05, f["m1"], 0.1), hand("H06", 0.25, f["m2"], 0.1), goal(-0.1, 0.3, f["g"])]
moves = [("LF", "F03"), ("RF", "F04"), ("LH", "H03"), ("RH", "H04"), ("LF", "H05"), ("RF", "H06"), ("LH", "G01/goal_left"), ("RH", "G01/goal_right")]
steps = [
 step("F1", "손은 그대로 두고 왼발부터 노란 발판에 올려요.", grab("LF", "F03"), ["왼쪽 아래 발 패드를 끌어요", "발판이 하얗게 빛나면 떼요"]),
 step("F2", "오른발도 올려요. 발을 올리면 몸이 따라 올라가요.", grab("RF", "F04"), ["오른쪽 아래 발 패드를 끌어요", "발판이 하얗게 빛나면 떼요"]),
 step("F3", "발을 올렸더니 높은 홀드에 손이 닿아요. 왼손으로 잡아요.", grab("LH", "H03"), ["왼쪽 위 손 패드를 위로 끌어요", W]),
 step("F4", "오른손도 옮겨요.", grab("RH", "H04"), ["오른쪽 위 손 패드를 위로 끌어요", W]),
 step("F5", "발은 손으로 잡는 홀드도 딛을 수 있어요. 왼발로 노란 홀드를 딛어요.", grab("LF", "H05"), ["왼발 패드를 노란 홀드까지 끌어요", "하얗게 빛나면 떼요"]),
 step("F6", "오른발도 노란 홀드를 딛어요.", grab("RF", "H06"), ["오른발 패드를 노란 홀드까지 끌어요", "하얗게 빛나면 떼요"]),
 step("F7", "두 손으로 맨 위 크림색 홀드를 잡으면 끝나요. 이렇게 발을 먼저 올리면 팔이 덜 힘들어요.", {"type": "clear"}, ["한 손씩 정상 홀드로", "두 손이 다 잡으면 완등"]),
]
route("C_FEET_T", "C_FEET", "발로 오르기", "v1(2026-11-14, docs/42 수업 1): 발을 먼저 올려야 손이 닿는 벽. 손홀드는 H03·H04 두 개만 잡고, H05·H06은 발로 딛는다. 피로 끔.", holds, moves, steps)

# ---- 몸통 옮기기
bd = P["body"]
holds = BASE + [hand("H07", bd["x"], bd["y"]), goal(0.0, 0.3, 2.0)]
steps = [
 step("BD1", "패드 사이 가운데를 누른 채 오른쪽으로 끌어 몸을 옮겨요.", {"type": "body", "dx_min": bd["dx"], "seconds": 0.5}, ["네 패드 사이 빈 곳을 눌러요", "끄는 쪽으로 몸이 따라가요"]),
 step("BD2", "가운데를 누른 채로, 다른 손가락으로 오른손을 노란 홀드까지 뻗어요.", grab("RH", "H07"), ["한 손가락은 가운데에 그대로 두어요", "다른 손가락으로 오른손 패드를 오른쪽 멀리 끌어요"]),
]
route("C_BODY_T", "C_BODY", "몸통 옮기기", "v1(2026-11-14, docs/42 수업 2): 시작 자세 + 오른쪽 먼 손홀드 H07. 몸통을 오른쪽으로 끌어야 오른손이 닿는다. 피로 끔. 정상 홀드는 검사용(시작 자세에서 닿음)이고 수업은 H07을 잡으면 끝난다.", holds, [("LH", "G01/goal_left"), ("RH", "G01/goal_right")], steps, xmax=1.8)

# ---- 팔 힘과 쉬기
a = P["arm"]
ON = {"fatigue_drain": True, "techniques": []}
holds = BASE + [hand("S01", a["sx"], a["sy"], 0.04), goal(0.05, 0.35, 2.0)]
steps = [
 step("A1", "두 발로 서서 가만히 있어 보세요. 위쪽 '왼손 팔 힘'이 차요.", {"type": "stamina", "limb": "LH", "min": 70}, ["아무것도 누르지 말고 기다려요", "두 발로 서 있으면 팔 힘이 돌아와요"], dict(ON, start_stamina=40), lock="none"),
 step("A2", "왼발을 떼고 버텨 보세요. 한 발로 버티면 팔 힘이 빠져요.", {"type": "stamina", "limb": "LH", "max": 85}, ["왼발 패드를 끌어 허공에서 떼요", "위쪽 '왼손 팔 힘'이 줄어드는 걸 보세요"], dict(ON, start_stamina=100), lock="LF"),
 step("A3", "왼발을 다시 노란 발판에 올려요.", grab("LF", "F01"), ["왼발 패드를 발판으로 끌어요", "발판이 하얗게 빛나면 떼요"], ON),
 step("A4", "왼손으로 작은 노란 홀드를 잡아요.", grab("LH", "S01"), ["왼손 패드를 작은 홀드로 끌어요", W], ON),
 step("A5", "작은 홀드를 잡은 채 왼발을 다시 떼 보세요. 작은 홀드에서는 팔 힘이 훨씬 빨리 빠져요.", {"type": "stamina", "limb": "LH", "max": 70}, ["왼발 패드를 끌어 허공에서 떼요", "아까보다 빨리 줄어드는 걸 보세요"], dict(ON, start_stamina=100), lock="LF"),
 step("A6", "왼발을 다시 딛고 가만히 쉬어요. 힘든 곳을 지나면 두 발로 서서 쉬세요.", {"type": "stamina", "limb": "LH", "min": 85}, ["왼발 패드를 발판으로 끌어요", "두 발로 서서 기다려요"], ON, lock="LF"),
 step("A7", "두 손으로 맨 위 크림색 홀드를 잡으면 끝나요.", {"type": "clear"}, ["한 손씩 정상 홀드로", "두 손이 다 잡으면 완등"], ON),
]
route("C_ARM_T", "C_ARM", "팔 힘과 쉬기", "v1(2026-11-14, docs/42 수업 3): 시작 자세 + 작은 홀드 S01(반폭 0.04). 한 발을 떼면 팔 힘이 빠지고, 작은 홀드에서는 더 빨리 빠지고, 두 발로 서면 돌아온다.", holds, [("LH", "G01/goal_left"), ("RH", "G01/goal_right")], steps)
