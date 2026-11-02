# -*- coding: utf-8 -*-
"""《游戏流程.docx》排版整理：只动格式，一字不改。
标题居中加粗；阶段句加粗当小标题；正文宋体小四+首行缩进+1.5倍行距；
管线图 8 行用等宽宋体、按页宽自动选字号保证不折行；空段落移除改用段间距。"""
import sys
sys.stdout.reconfigure(encoding="utf-8")
import unicodedata
from docx import Document
from docx.shared import Pt, Emu
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn

PATH = r"D:\dugaogaogao\阿姨别追\游戏流程.docx"

doc = Document(PATH)
before = [p.text for p in doc.paragraphs if p.text.strip()]
print(f"改前非空段落数：{len(before)}")
print("=== 原文 repr 备案（改前逐字记录）===")
for t in before:
    print(repr(t))

# 页面可用宽度（决定管线图字号，防止折行破坏对齐）
sec = doc.sections[0]
pw = sec.page_width.pt if sec.page_width else 595.0
lm = sec.left_margin.pt if sec.left_margin else 72.0
rm = sec.right_margin.pt if sec.right_margin else 72.0
text_w = pw - lm - rm
print(f"版心宽度：{text_w:.0f}pt（页宽{pw:.0f} - 左{lm:.0f} - 右{rm:.0f}）")

# 1) 移除空段落（分段改用段间距表达，内容零损失）
removed = 0
for p in list(doc.paragraphs):
    if not p.text.strip():
        p._element.getparent().remove(p._element)
        removed += 1
print(f"移除空段落：{removed}")

H1 = {
    "确定游戏玩法，策划框架与细节",
    "我们有一个整体的流程了，准备看着拆任务卡",
    "在文档中心创建游戏名字，在godot创建游戏，开工",
    "然后就是这么循环下去",
}
SUB = {"先思考，游戏要什么"}

def units(text):  # 半角宽度计数：全角=2、半角=1
    return sum(2 if unicodedata.east_asian_width(c) in ("F", "W") else 1 for c in text)

# 管线图 8 行的最大宽度 → 选不折行的最大字号
diagram_lines = []  # 先找出这 8 段（紧随"总体的全部管线"标题之后）
grab = 0
for p in doc.paragraphs:
    t = p.text.strip()
    if grab > 0:
        diagram_lines.append(p.text)
        grab -= 1
        continue
    if t.startswith("总体的全部管线"):
        grab = 8
max_units = max(units(t) for t in diagram_lines)
print(f"管线图最宽行：{max_units} 个半角单位")
diagram_size = 9.0
for cand in (12.0, 10.5, 9.0):
    if max_units * cand / 2.0 <= text_w - 12:
        diagram_size = cand
        break
print(f"管线图采用字号：{diagram_size}pt（需 {max_units * diagram_size / 2:.0f}pt ≤ 余量 {text_w - 12:.0f}pt）")

def style_runs(p, ascii_font, east_font, size, bold):
    for r in p.runs:
        r.font.name = ascii_font
        r.font.size = Pt(size)
        r.font.bold = bold
        r._element.get_or_add_rPr().get_or_add_rFonts().set(qn("w:eastAsia"), east_font)

def set_indent_chars(p, chars=2):
    p._p.get_or_add_pPr().get_or_add_ind().set(qn("w:firstLineChars"), str(chars * 100))

diagram_left = 0
for p in doc.paragraphs:
    t = p.text.strip()
    pf = p.paragraph_format
    if t == "游戏流程":
        style_runs(p, "微软雅黑", "微软雅黑", 22, True)
        pf.alignment = WD_ALIGN_PARAGRAPH.CENTER
        pf.space_before, pf.space_after, pf.line_spacing = Pt(0), Pt(10), 1.3
    elif t.startswith("总体的全部管线"):
        diagram_left = 8
        style_runs(p, "微软雅黑", "微软雅黑", 14, True)
        pf.space_before, pf.space_after, pf.line_spacing = Pt(13), Pt(6), 1.3
    elif diagram_left > 0:
        diagram_left -= 1
        # 清掉个别行残留的首行缩进属性，统一靠行内空格对齐
        ind = p._p.get_or_add_pPr().find(qn("w:ind"))
        if ind is not None:
            for attr in ("w:firstLine", "w:firstLineChars", "w:hanging", "w:hangingChars"):
                ind.attrib.pop(qn(attr), None)
        style_runs(p, "宋体", "宋体", diagram_size, False)
        pf.space_before, pf.space_after, pf.line_spacing = Pt(0), Pt(6 if diagram_left == 0 else 0), 1.0
    elif t in H1:
        style_runs(p, "微软雅黑", "微软雅黑", 14, True)
        pf.space_before, pf.space_after, pf.line_spacing = Pt(13), Pt(6), 1.3
    elif t in SUB:
        style_runs(p, "微软雅黑", "微软雅黑", 12, True)
        pf.space_before, pf.space_after, pf.line_spacing = Pt(6), Pt(4), 1.5
    else:
        style_runs(p, "Times New Roman", "宋体", 12, False)
        pf.space_before, pf.space_after, pf.line_spacing = Pt(0), Pt(6), 1.5
        pf.first_line_indent = Pt(24)
        set_indent_chars(p, 2)

try:
    doc.save(PATH)
except PermissionError:
    print("保存失败：文件可能正被 Word/WPS 打开，请关掉后重跑。")
    sys.exit(1)
print("已保存，开始复核……")

doc2 = Document(PATH)
after = [p.text for p in doc2.paragraphs if p.text.strip()]
assert after == before, "文字内容有变化，中止！"
print(f"内容对拍：改前 {len(before)} 段 == 改后 {len(after)} 段，逐字一致，0 增 0 删 0 改 ✓")
print(f"剩余空段落：{sum(1 for p in doc2.paragraphs if not p.text.strip())}")

print("=== 排版结果抽查 ===")
for i, p in enumerate(doc2.paragraphs):
    if not p.runs:
        continue
    r = p.runs[0]
    rf = r._element.rPr.rFonts
    east = rf.get(qn("w:eastAsia"))
    sz = r.font.size.pt if r.font.size else None
    b = "粗" if r.font.bold else "常"
    ind = p._p.pPr.ind.get(qn("w:firstLineChars")) if p._p.pPr is not None and p._p.pPr.ind is not None else None
    print(f"{i:02d} {r.font.name}/{east} {sz}pt {b} 缩进={ind} | {p.text[:26]}")
print("完成")
