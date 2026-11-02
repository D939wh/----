# -*- coding: utf-8 -*-
# 目录重排后修正所有 res:// 引用路径。只做字符串精确替换，改完打印一份对账。
import sys, os
sys.stdout.reconfigure(encoding="utf-8")

ROOT = r"D:/dugaogaogao/阿姨别追/阿姨别追"

# 旧路径 -> 新路径（只列真正变了的）
REPL = {
    "res://素材控制/场景素材/cj.tscn":                  "res://场景/主场景.tscn",
    "res://素材控制/场景素材/t.tres":                   "res://素材/场景/t.tres",
    "res://游戏场景/交互测试.tscn":                      "res://场景/测试/交互测试.tscn",
    "res://游戏场景/攀爬测试.tscn":                      "res://场景/测试/攀爬测试.tscn",
    "res://游戏场景/图块_场景精灵表_16像素_2026-10-29.png": "res://素材/场景/图块_场景精灵表_16像素_2026-10-29.png",
    "res://游戏角色/student.tscn":                      "res://角色/学生/student.tscn",
    "res://游戏效果控制/角色交互/基础移动/student.gd":     "res://角色/学生/student.gd",
    "res://游戏效果控制/场景交互/梯子.tscn":              "res://交互物/梯子.tscn",
    "res://游戏效果控制/场景交互/可搬运箱子.tscn":         "res://交互物/可搬运箱子.tscn",
    "res://游戏效果控制/场景交互/可使用物品.tscn":         "res://交互物/可使用物品.tscn",
    "res://游戏效果控制/界面/HUD.tscn":                  "res://界面/HUD.tscn",
    "res://游戏效果控制/界面/HUD.gd":                    "res://界面/HUD.gd",
    "res://素材控制/梯子/梯子.png":                      "res://素材/场景/梯子.png",
    "res://素材控制/道具/":                             "res://素材/道具/",
    "res://icon.svg":                                  "res://素材/角色参考/icon.svg",
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
    hits = []
    for a, b in REPL.items():
        if a in new:
            hits.append(a)
            new = new.replace(a, b)
    if new != old:
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write(new)
        changed.append((os.path.relpath(path, ROOT), len(hits)))

print("=== 改了 %d 个文件 ===" % len(changed))
for p, n in sorted(changed):
    print("  %-38s 替换 %d 处" % (p, n))

# 复查：还有没有指向旧目录的引用
print("\n=== 残留检查 ===")
bad = 0
for path in targets:
    with open(path, encoding="utf-8") as f:
        txt = f.read()
    for a in REPL:
        if a in txt:
            print("  残留 %s -> %s" % (a, os.path.relpath(path, ROOT)))
            bad += 1
print("  残留 %d 处" % bad)

# 复查：所有 res:// 引用是否指向真实存在的文件
print("\n=== 断链检查（引用了但文件不存在）===")
import re
broken = 0
for path in targets:
    with open(path, encoding="utf-8") as f:
        txt = f.read()
    for m in re.finditer(r'res://([^"\s\]]+)', txt):
        rel = m.group(1)
        if rel.startswith(".godot/"):
            continue
        full = os.path.join(ROOT, rel)
        if not os.path.exists(full):
            print("  断链 res://%s  <- %s" % (rel, os.path.relpath(path, ROOT)))
            broken += 1
print("  断链 %d 处" % broken)
