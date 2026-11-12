import bpy, numpy as np, sys
def blur(a, r):
    for ax in (0, 1):
        c = np.cumsum(np.pad(a, [(r + 1, r) if i == ax else (0, 0) for i in range(2)], mode="edge"), axis=ax)
        a = (np.take(c, range(2 * r + 1, c.shape[ax]), axis=ax) - np.take(c, range(0, c.shape[ax] - 2 * r - 1), axis=ax)) / (2 * r + 1)
    return a
for name in ["front", "left", "back", "right"]:
    img = bpy.data.images.load("/tmp/ref/m/%s.png" % name)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    rgb = px[:, :, :3]
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    lum = rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    mx, mn = rgb.max(2), rgb.min(2)
    sat = (mx - mn) / np.maximum(mx, 1e-4)
    # 가는 선(잉크·솔기): 주변보다 확실히 어두운 얇은 부분
    hp = blur(blur(lum, 3), 3) - lum
    ink = (lum < 0.16) | ((hp > 0.12) & (lum < 0.33))
    # 청바지: 파란 기
    jeans = (b - r > 0.10) & (b > g) & (lum < 0.80)
    jl = lum[jeans & ~ink]
    base = np.median(rgb[jeans & ~ink & (lum > np.percentile(jl, 50))], axis=0)
    line_col = base * 0.45
    m = jeans
    rgb[m] = base
    rgb[m & ink] = line_col
    # 셔츠: 채도 낮은 밝은 회색~흰색(배경 순백 제외), 바지 위
    rows = np.where(jeans.any(1))[0]
    jeans_top = rows.max()   # Blender 이미지는 아래가 0 → 위쪽 = 큰 값
    yy = np.arange(h)[:, None] * np.ones((1, w))
    body = blur((lum < 0.985).astype(np.float32), 12) > 0.02
    shirt = (sat < 0.20) & (lum > 0.55) & (lum < 0.975) & (yy > jeans_top - 60) & body
    sb = np.median(rgb[(sat < 0.08) & (lum > 0.93) & (lum < 0.985) & (yy > jeans_top) & body], axis=0)
    rgb[shirt & ~(lum < 0.33)] = sb
    img.pixels = px.ravel()
    img.filepath_raw = "/tmp/ref/m/%s_clean.png" % name; img.file_format = "PNG"; img.save()
    print("CLEAN", name, "jeans", base.round(3), "shirt", sb.round(3), "jeans px", int(m.sum()), "shirt px", int((shirt & ~ink).sum()))
