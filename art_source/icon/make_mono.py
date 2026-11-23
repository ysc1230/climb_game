# 단색(테마) 아이콘: 앞 층 그림을 검은 외곽선으로 나눈 조각 중 평균 색이 피부인 것(손·팔)만 흰 실루엣으로.
import bpy, sys, numpy as np
from collections import deque
fg_path, out, LINE = sys.argv[sys.argv.index("--") + 1:][:3]
LINE = float(LINE)
im = bpy.data.images.load(fg_path); w, h = im.size
p = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1].copy()
lum = p[..., :3].max(-1)
line = (lum < LINE) | (p[..., 3] < 0.5)
lab = -np.ones((h, w), dtype=np.int32)
comps = []
for y in range(h):
    for x in range(w):
        if line[y, x] or lab[y, x] >= 0:
            continue
        i = len(comps)
        q = deque([(y, x)]); lab[y, x] = i; pts = []
        while q:
            cy, cx = q.popleft(); pts.append((cy, cx))
            for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                if 0 <= ny < h and 0 <= nx < w and not line[ny, nx] and lab[ny, nx] < 0:
                    lab[ny, nx] = i; q.append((ny, nx))
        comps.append(pts)
hand = np.zeros((h, w), dtype=bool)
kept = 0
for i, pts in enumerate(comps):
    if len(pts) < 40:
        continue
    ys, xs = zip(*pts)
    c = p[ys, xs, :3]
    r, g, b = c[:, 0], c[:, 1], c[:, 2]
    skinish = ((r > g) & (g > b) & (r - b > 0.14) & (c.max(1) > 0.5)) | ((c.min(1) > 0.8) & (r >= b))   # 피부 또는 손에 묻은 초크
    if skinish.mean() > 0.75 and (r - b).mean() > 0.12:
        hand[ys, xs] = True
        kept += 1
# 손에 붙어 나온 초크 묻은 바위(흰·회색)를 빼고, 손 안에 갇힌 구멍(손에 묻은 초크)은 메운 뒤 가장 큰 덩어리만 남긴다


def flood(seed_mask, allow):
    m = seed_mask & allow
    while True:
        n = m.copy()
        n[1:] |= m[:-1]; n[:-1] |= m[1:]; n[:, 1:] |= m[:, :-1]; n[:, :-1] |= m[:, 1:]
        n &= allow
        if (n == m).all():
            return m
        m = n


# 손가락 끝 오른쪽 아래로 붙은 바위 끝을 잘라 낸다(이 그림에서 잰 선: 손가락 끝 오른쪽 → 손등 오른쪽 옆)
cut_y = [0, 100, 162, 172, 182, 200, 300, 432]
cut_x = [335, 335, 322, 300, 268, 262, 256, 200]
xcut = np.interp(np.arange(h), cut_y, cut_x)
hand &= np.arange(w)[None, :] <= xcut[:, None]
border = np.zeros_like(hand)
border[0, :] = border[-1, :] = border[:, 0] = border[:, -1] = True
outside = flood(border, ~hand)
hand = ~outside
lab2 = -np.ones((h, w), dtype=np.int32)
best, best_n = None, 0
for y in range(h):
    for x in range(w):
        if hand[y, x] and lab2[y, x] < 0:
            q = deque([(y, x)]); lab2[y, x] = 1; pts = []
            while q:
                cy, cx = q.popleft(); pts.append((cy, cx))
                for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                    if 0 <= ny < h and 0 <= nx < w and hand[ny, nx] and lab2[ny, nx] < 0:
                        lab2[ny, nx] = 1; q.append((ny, nx))
            if len(pts) > best_n:
                best, best_n = pts, len(pts)
hand = np.zeros_like(hand)
ys, xs = zip(*best)
hand[ys, xs] = True
o = np.zeros((h, w, 4), dtype=np.float32)
o[..., :3] = 1.0
o[..., 3] = hand.astype(np.float32)
res = bpy.data.images.new("m", w, h, alpha=True); res.pixels.foreach_set(o[::-1].ravel())
res.filepath_raw = out; res.file_format = "PNG"; res.save()
print("MONO", out, "pieces", kept, "of", len(comps), "coverage %.3f" % hand.mean())
