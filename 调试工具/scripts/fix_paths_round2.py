# -*- coding: utf-8 -*-
# 第二轮（细分到具体东西）后修正路径引用。
# 与第一轮不同：这轮改名涉及文件名变化，所以用「旧路径 -> 新路径」全量替换 + 残留/断链双查。
import sys, os, re
sys.stdout.reconfigure(encoding="utf-8")

ROOT = r"D:/dugaogaogao/阿姨别追/阿姨别追"

REPL = {
    # 界面：HUD 这个筐 → 具体东西「道具格」
    "res://界面/HUD.tscn": "res://界面/道具格/道具格.tscn",
    "res://界面/HUD.gd":   "res://界面/道具格/道具格.gd",
    # 交互物：每个东西一个文件夹
    "res://交互物/梯子.tscn":       "res://交互物/梯子/梯子.tscn",
    "res://交互物/可搬运箱子.tscn":  "res://交互物/可搬运箱子/可搬运箱子.tscn",
    "res://交互物/可使用物品.tscn":  "res://交互物/可使用物品/可使用物品.tscn",
    # 素材：类别/具体东西
    "res://素材/场景/图块_场景精灵表_16像素_2026-10-29.png": "res://素材/场景/图块/图块_场景精灵表_16像素_2026-10-29.png",
    "res://素材/场景/梯子.png": "res://素材/场景/梯子/梯子.png",
    "res://素材/道具/钥匙_占位.png":    "res://素材/道具/钥匙/钥匙_占位.png",
    "res://素材/道具/钥匙_占位_原切.png": "res://素材/道具/钥匙/钥匙_占位_原切.png",
    "res://素材/道具/纸箱_占位.png":    "res://素材/道具/纸箱/纸箱_占位.png",
    "res://素材/道具/蓝碗_占位.png":    "res://素材/道具/蓝碗/蓝碗_占位.png",
    "res://素材/道具/道具.png":       "res://素材/道具/道具图/道具.png",
    "res://素材/道具/占位预览_4倍.png":  "res://素材/道具/道具图/占位预览_4倍.png",
}

targets = []
for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if d not in ("addons", ".godot", ".git")]
    for fn in filenames:
        if fn.endswith((".tscn", ".tres", ".gd", ".godot", ".import")):
            targets.append(os.path.join(dirpath, fn))

changed = []
for path in targets:
    with open(path, encoding="utf-8") as f:
        old = f.read()
    new = old
    hits = 0
    for a, b in sorted(REPL.items(), key=lambda kv: -len(kv[0])):  # 长串先替换，避免前缀误伤
        if a in new:
            hits += new.count(a)
            new = new.replace(a, b)
    if new != old:
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write(new)
        changed.append((os.path.relpath(path, ROOT), hits))

print("=== 改了 %d 个文件 ===" % len(changed))
for p, n in sorted(changed):
    print("  %-34s 替换 %d 处" % (p, n))

print("\n=== 残留检查 ===")
bad = 0
for path in targets:
    with open(path, encoding="utf-8") as f:
        txt = f.read()
    for a in REPL:
        if a in txt:
            print("  残留 %s  <- %s" % (a, os.path.relpath(path, ROOT)))
            bad += 1
print("  残留 %d 处" % bad)

print("\n=== 断链检查 ===")
broken = 0
for path in targets:
    with open(path, encoding="utf-8") as f:
        txt = f.read()
    for m in re.finditer(r'res://([^"\s\]]+)', txt):
        rel = m.group(1)
        if rel.startswith(".godot/"):
            continue
        if not os.path.exists(os.path.join(ROOT, rel)):
            print("  断链 res://%s  <- %s" % (rel, os.path.relpath(path, ROOT)))
            broken += 1
print("  断链 %d 处" % broken)
