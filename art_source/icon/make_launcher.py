# 사용자 아이콘(검은 바탕 위 둥근 사각형 그림) → 앱 아이콘들. 바깥 검정은 투명으로(테두리에서 이어진 어두운 부분만).
import bpy, sys, numpy as np
src, out = sys.argv[sys.argv.index("--") + 1:][:2]
img = bpy.data.images.load(src)
w, h = img.size
px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1].copy()   # 위가 0행
lum = px[..., :3].max(-1)
dark = lum < 0.06
outside = np.zeros_like(dark)
outside[0, :] = dark[0, :]; outside[-1, :] = dark[-1, :]; outside[:, 0] = dark[:, 0]; outside[:, -1] = dark[:, -1]
while True:   # 테두리에서 이어진 어두운 곳만(그림 속 검은 선은 남는다)
    g = outside.copy()
    g[1:] |= outside[:-1]; g[:-1] |= outside[1:]; g[:, 1:] |= outside[:, :-1]; g[:, :-1] |= outside[:, 1:]
    g &= dark
    if (g == outside).all():
        break
    outside = g
alpha = (~outside).astype(np.float32)
edge = np.zeros_like(outside)   # 바깥과 닿은 1~2px은 밝기로 부드럽게
for dy in (-2, -1, 0, 1, 2):
    for dx in (-2, -1, 0, 1, 2):
        edge |= np.roll(np.roll(outside, dy, 0), dx, 1)
edge &= ~outside
alpha[edge] = np.clip(lum[edge] / 0.3, 0.0, 1.0)
px[..., 3] = alpha
ys, xs = np.nonzero(alpha > 0.5)
y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
side = max(y1 - y0, x1 - x0)
cy, cx = (y0 + y1) // 2, (x0 + x1) // 2
crop = np.zeros((side, side, 4), dtype=np.float32)
sy, sx = cy - side // 2, cx - side // 2
crop[:] = px[sy:sy + side, sx:sx + side]
print("CROP", x0, x1, y0, y1, "side", side)
# 둥근 모서리 근처 그림 색(적응형 뒤 층)
ring = crop[int(side * 0.1):int(side * 0.9), int(side * 0.05):int(side * 0.12), :3]
bg = np.median(ring.reshape(-1, 3), 0)
print("BG", (bg * 255).round())


def save(arr, path, size):
    im = bpy.data.images.new("o", arr.shape[1], arr.shape[0], alpha=True)
    im.pixels.foreach_set(arr[::-1].ravel())
    if arr.shape[0] != size:
        im.scale(size, size)
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    print("SAVED", path, size)


save(crop, out + "/icon_overhang_512.png", 512)          # 프로젝트 아이콘(둥근 사각형, 바깥 투명)
save(crop, out + "/launcher_192.png", 192)               # 안드로이드 기본 아이콘
# 적응형 앞 층: 432 중 가운데 360에 그림(보이는 곳 = 가운데 288). 둥근 모서리 투명은 보이는 곳 밖.
fg = np.zeros((432, 432, 4), dtype=np.float32)
im = bpy.data.images.new("s", side, side, alpha=True)
im.pixels.foreach_set(crop[::-1].ravel())
im.scale(360, 360)
small = np.array(im.pixels[:], dtype=np.float32).reshape(360, 360, 4)[::-1]
fg[36:396, 36:396] = small
save(fg, out + "/adaptive_fg_432.png", 432)
bgimg = np.ones((432, 432, 4), dtype=np.float32)
bgimg[..., :3] = bg
save(bgimg, out + "/adaptive_bg_432.png", 432)
