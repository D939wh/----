# -*- coding: utf-8 -*-
# 把 素材控制\道具\道具.png 里散落的占位图按连通块切开，输出包围盒清单；
# 顺便把「黄钥匙」「蓝碗」切成独立小图（缩回真实像素尺寸，最近邻，不糊）。
import sys
sys.stdout.reconfigure(encoding="utf-8")

from PIL import Image
from collections import deque

SRC = r"D:\dugaogaogao\阿姨别追\阿姨别追\素材控制\道具\道具.png"
OUT_DIR = r"D:\dugaogaogao\阿姨别追\阿姨别追\素材控制\道具"

img = Image.open(SRC).convert("RGBA")
W, H = img.size
px = img.load()

def is_fg(x, y):
    r, g, b, a = px[x, y]
    if a < 128:
        return False
    # 白色也算背景（图里底色可能是白）
    return not (r > 245 and g > 245 and b > 245)

# 连通块标记（4 邻接）
seen = [[False] * W for _ in range(H)]
boxes = []
for y in range(H):
    for x in range(W):
        if seen[y][x] or not is_fg(x, y):
            continue
        q = deque([(x, y)])
        seen[y][x] = True
        minx = maxx = x
        miny = maxy = y
        n = 0
        while q:
            cx, cy = q.popleft()
            n += 1
            if cx < minx: minx = cx
            if cx > maxx: maxx = cx
            if cy < miny: miny = cy
            if cy > maxy: maxy = cy
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = cx + dx, cy + dy
                if 0 <= nx < W and 0 <= ny < H and not seen[ny][nx] and is_fg(nx, ny):
                    seen[ny][nx] = True
                    q.append((nx, ny))
        if n > 30:  # 忽略噪点
            boxes.append((minx, miny, maxx, maxy, n))

boxes.sort(key=lambda b: b[0])
print("找到 %d 个块：" % len(boxes))
for i, (minx, miny, maxx, maxy, n) in enumerate(boxes):
    w = maxx - minx + 1
    h = maxy - miny + 1
    print("  块%d  x=%d..%d y=%d..%d  尺寸 %dx%d  像素数 %d" % (i, minx, maxx, miny, maxy, w, h, n))

# 猜测：按 x 排序，第 1 个=梯子，第 2 个=钥匙，第 3 个=碗，第 4 个=花，第 5 个=学生
# 切图并缩放到目标尺寸
if len(boxes) >= 3:
    targets = [
        (2, 16, 16, "蓝碗_占位"),   # 第 3 块：蓝碗 → 当可搬运物体占位（16x16）
    ]
    # 钥匙单独处理（第 2 块）
    b = boxes[1]
    minx, miny, maxx, maxy = b[0], b[1], b[2], b[3]
    crop = img.crop((minx, miny, maxx + 1, maxy + 1))
    print("钥匙原尺寸 %dx%d" % crop.size)
    # 缩放到 24x16 之类？先看长宽比
    crop.save(OUT_DIR + r"\钥匙_占位_原切.png")

    for idx, tw, th, name in targets:
        bx, by, bx2, by2, _ = boxes[idx]
        c = img.crop((bx, by, bx2 + 1, by2 + 1))
        print("%s 原尺寸 %dx%d" % (name, c.size[0], c.size[1]))
        c = c.resize((tw, th), Image.NEAREST)
        c.save(OUT_DIR + "\\" + name + ".png")
        print("  已缩放保存 %dx%d" % (tw, th))

# 也把整个图的信息写给后面参考
print("完成")
