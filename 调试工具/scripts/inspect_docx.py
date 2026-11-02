import sys
sys.stdout.reconfigure(encoding="utf-8")
from docx import Document
from docx.shared import Pt

doc = Document(r"D:\dugaogaogao\阿姨别追\游戏流程.docx")

for i, p in enumerate(doc.paragraphs):
    style = p.style.name if p.style else "None"
    text = p.text.strip()
    runs_info = []
    for r in p.runs:
        fname = r.font.name
        try:
            east = r.font._element.rPr.rFonts.get('{http://schemas.openxmlformats.org/wordprocessingml/2006/main}eastAsia') if r.font._element.rPr is not None and r.font._element.rPr.rFonts is not None else None
        except Exception:
            east = None
        sz = r.font.size.pt if r.font.size else None
        b = r.font.bold
        runs_info.append(f"[{fname}|{east}|{sz}|{'B' if b else '-'}]")
    print(f"{i:03d} <{style}> {' '.join(runs_info)}")
    print(f"    TEXT: {text[:80]}")

print("\n=== TABLES ===")
print(len(doc.tables))
