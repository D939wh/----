# -*- coding: utf-8 -*-
# W1D4 占位素材：钥匙（黄）+ 可搬运纸箱。纯像素，颜色取自项目 24 色板。
# 输出到 素材控制\道具\
import sys
sys.stdout.reconfigure(encoding="utf-8")
from PIL import Image, ImageDraw

OUT = r"D:\dugaogaogao\阿姨别追\阿姨别追\素材控制\道具"

# 24 色板里挑的黄/棕系
M = (242, 199, 119)   # 中黄
N = (255, 231, 176)   # 浅黄（高光）
O = (216, 167, 90)    # 深黄（暗部）
P = (110, 90, 70)     # 深棕
Q = (138, 115, 96)    # 中棕
A = (18, 22, 42)      # 近黑

def hexrgb(c):  # PIL 需要 (r,g,b)
    return c

# ---------------- 钥匙 28x16 ----------------
kg = Image.new("RGBA", (28, 16), (0, 0, 0, 0))
d = ImageDraw.Draw(kg)
# 环形钥匙头（左侧）：外圈深黄，内圈镂空
d.ellipse([0, 2, 13, 14], fill=O)
d.ellipse([2, 4, 11, 12], fill=(0, 0, 0, 0))
# 左边加一道竖杆连接
d.rectangle([4, 7, 6, 9], fill=O)
# 杆子（向右延伸）
d.rectangle([7, 6, 20, 10], fill=M)
# 顶部齿
for x in (10, 13, 16):
    d.rectangle([x, 2, x + 1, 6], fill=M)
d.rectangle([10, 2, 17, 3], fill=M)
# 钥匙柄尾端
d.rectangle([20, 5, 26, 11], fill=O)
d.rectangle([21, 6, 25, 10], fill=(0, 0, 0, 0))
# 高光
d.rectangle([8, 7, 18, 7], fill=N)
kg.save(OUT + r"\钥匙_占位.png")
print("钥匙_占位.png  28x16")

# ---------------- 纸箱 16x16 ----------------
bg = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
d = ImageDraw.Draw(bg)
# 箱体
d.rectangle([0, 4, 15, 15], fill=Q)
d.rectangle([0, 4, 15, 5], fill=O)      # 顶沿高光
# 外框
d.rectangle([0, 4, 15, 15], outline=P)
# 封箱胶带（竖）
d.rectangle([7, 4, 8, 15], fill=N)
# 侧面木板纹
d.line([0, 10, 15, 10], fill=P)
# 高光点
d.point((3, 6), fill=M)
d.point((12, 8), fill=M)
bg.save(OUT + r"\纸箱_占位.png")
print("纸箱_占位.png  16x16")

# 附一张 4 倍预览给人看
sheet = Image.new("RGBA", (28 * 4 + 16 * 4 + 32, 16 * 4), (18, 22, 42, 255))
sheet.paste(kg.resize((28 * 4, 16 * 4), Image.NEAREST), (16, 0))
sheet.paste(bg.resize((16 * 4, 16 * 4), Image.NEAREST), (28 * 4 + 32, 0))
sheet.save(OUT + r"\占位预览_4倍.png")
print("占位预览_4倍.png")
