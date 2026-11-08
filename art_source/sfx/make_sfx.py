"""경고 효과음 합성(2026-11-09). 외부 소리 파일 없이 사인파로 만든다.
python3 art_source/sfx/make_sfx.py → game/art/sfx/*.wav (22050Hz 16bit mono)
- heartbeat: 낮은 '쿵'(위험 동안 박동마다, 두 번째 박동은 같은 소리를 작게)
- danger: 위험에 들어가는 순간 내려가는 경고음 두 번
- caution: 주의(떼면 위험) 짧은 '띵'
- recover: 회복 올라가는 두 음
"""
import math, struct, wave, os

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "game", "art", "sfx")


def write(name, samples):
    os.makedirs(OUT, exist_ok=True)
    peak = max(1e-9, max(abs(x) for x in samples))
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(32767 * 0.85 * x / peak)) for x in samples))


def tone(freq_fn, dur, env_fn, harmonics=((1, 1.0),)):
    out, ph = [], 0.0
    n = int(dur * RATE)
    for i in range(n):
        t = i / RATE
        ph += 2 * math.pi * freq_fn(t) / RATE
        v = sum(a * math.sin(ph * h) for h, a in harmonics)
        out.append(v * env_fn(t))
    return out


def attack_decay(a, d):
    return lambda t: min(1.0, t / a) * math.exp(-max(0.0, t - a) / d)


heart = tone(lambda t: 62 - 20 * t, 0.22, attack_decay(0.006, 0.05), ((1, 1.0), (2, 0.35), (3, 0.1)))
write("heartbeat", heart)

def danger_fn():
    a = tone(lambda t: 880 - 500 * t, 0.16, attack_decay(0.004, 0.07), ((1, 1.0), (2, 0.3)))
    gap = [0.0] * int(0.05 * RATE)
    b = tone(lambda t: 780 - 500 * t, 0.20, attack_decay(0.004, 0.09), ((1, 1.0), (2, 0.3)))
    return a + gap + b
write("danger", danger_fn())

write("caution", tone(lambda t: 1320, 0.18, attack_decay(0.003, 0.06), ((1, 1.0), (3, 0.15))))

rec = tone(lambda t: 660, 0.12, attack_decay(0.004, 0.08)) + tone(lambda t: 990, 0.30, attack_decay(0.004, 0.12), ((1, 1.0), (2, 0.2)))
write("recover", rec)
print("ok")
