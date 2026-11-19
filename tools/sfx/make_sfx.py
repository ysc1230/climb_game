# 효과음 합성(docs/superpowers/specs/2026-11-19-1-feel-design.md §1.3·1.4·1.1). 표준 라이브러리만, 씨앗 고정이라 다시 돌려도 같다.
# 실행: python3 tools/sfx/make_sfx.py  → game/art/sfx/*.wav (44.1kHz 16bit mono)
import math, random, struct, wave, os

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "game", "art", "sfx")


def write(name, samples):
    peak = max(1e-9, max(abs(x) for x in samples))
    k = 0.85 / peak
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, x * k)) * 32767)) for x in samples))


def env(i, n, attack=0.004, decay=0.03):
    t = i / SR
    a = min(1.0, t / attack) if attack > 0 else 1.0
    return a * math.exp(-t / decay)


def thud(freq, dur, decay, noise, seed):
    r = random.Random(seed); n = int(SR * dur); out = []
    lp = 0.0
    for i in range(n):
        t = i / SR
        f = freq * (1.0 + 0.6 * math.exp(-t / 0.01))  # 처음에 살짝 높았다 내려감
        tone = math.sin(2 * math.pi * f * t)
        lp += (r.uniform(-1, 1) - lp) * 0.25
        out.append((tone * (1 - noise) + lp * noise) * env(i, n, 0.002, decay))
    return out


def grip_low():
    out = []
    for f, d in [(660, 0.09), (0, 0.03), (520, 0.11)]:
        n = int(SR * d)
        out += [math.sin(2 * math.pi * f * i / SR) * env(i, n, 0.004, 0.05) if f else 0.0 for i in range(n)]
    return out


def whoosh():
    r = random.Random(7); n = int(SR * 0.12); out = []; lp = 0.0
    for i in range(n):
        a = i / n
        c = 0.05 + 0.25 * a
        lp += (r.uniform(-1, 1) - lp) * c
        out.append(lp * math.sin(math.pi * a) * 0.6)
    return out


def fanfare():
    notes = [(523.25, 0.14), (659.25, 0.14), (783.99, 0.14), (1046.5, 0.5)]
    out = []
    for f, d in notes:
        n = int(SR * d)
        out += [sum(math.sin(2 * math.pi * f * h * i / SR) / h for h in (1, 2, 3)) * env(i, n, 0.006, d * 0.9) for i in range(n)]
    n = int(SR * 1.1)  # 마지막 화음(도·미·솔·도)
    chord = [523.25, 659.25, 783.99, 1046.5]
    out += [sum(math.sin(2 * math.pi * f * i / SR) for f in chord) * 0.4 * env(i, n, 0.01, 0.55) for i in range(n)]
    return out


if __name__ == "__main__":
    write("grip_low", grip_low())
    write("grab_big", thud(140, 0.07, 0.025, 0.35, 1))
    write("grab_mid", thud(220, 0.05, 0.018, 0.45, 2))
    write("grab_small", thud(420, 0.03, 0.010, 0.55, 3))
    write("step_foot", thud(180, 0.06, 0.020, 0.15, 4))
    write("miss", whoosh())
    write("fanfare", fanfare())
    write("land_soft", thud(85, 0.18, 0.05, 0.5, 5))   # 매트 착지 쿵(낮음·중간)
    write("land_hard", thud(65, 0.3, 0.09, 0.55, 6))   # 높은 곳 착지 쿵
    print("ok")
