# -*- coding: utf-8 -*-
# 剥注释逐行对拍：正式版 student.gd vs 参考答案_student.gd
# 规矩（2026-10-29 22:48）：代码部分逐字一致，差异只许在注释。
import sys
sys.stdout.reconfigure(encoding="utf-8")

def strip(path):
    out = []
    for line in open(path, encoding="utf-8"):
        s = line.rstrip("\n")
        # 去行内注释（简单处理：不在字符串里的 #）
        res = []
        in_str = False
        q = ""
        for ch in s:
            if in_str:
                res.append(ch)
                if ch == q:
                    in_str = False
            else:
                if ch in "\"'":
                    in_str = True
                    q = ch
                    res.append(ch)
                elif ch == "#":
                    break
                else:
                    res.append(ch)
        code = "".join(res).rstrip()
        if code.strip():
            out.append(code)
    return out

a = strip(r"D:\dugaogaogao\阿姨别追\阿姨别追\游戏效果控制\角色交互\基础移动\student.gd")
b = strip(r"D:\dugaogaogao\阿姨别追\阿姨别追\游戏效果控制\角色交互\基础移动\参考答案_student.gd")

print("正式版代码行数: %d" % len(a))
print("参考答案代码行数: %d" % len(b))

if len(a) != len(b):
    print("!! 行数不一致")
    import difflib
    for line in difflib.unified_diff(a, b, "student.gd", "参考答案", lineterm=""):
        print(line)
else:
    diff = [i for i, (x, y) in enumerate(zip(a, b)) if x != y]
    if not diff:
        print("PASS：%d 行代码逐行一致" % len(a))
    else:
        print("!! 有 %d 行不一致：" % len(diff))
        for i in diff:
            print("第%d行:\n  正式: %r\n  答案: %r" % (i + 1, a[i], b[i]))
