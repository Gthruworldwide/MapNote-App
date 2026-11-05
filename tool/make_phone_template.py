# -*- coding: utf-8 -*-
"""ينشئ قالب Excel لأرقام هواتف مسؤولي المحطات.

ملف «مسؤل المحطة.xlsx» لا يحتوي أي عمود أرقام، لذلك تُشحن أسماء المسؤولين فقط.
هذا القالب يجمع كل اسم مسؤول مرة واحدة (مع عدد المحطات التي يتابعها) ويترك
عمود الرقم فارغًا لتملأه، ثم:

    py tool/make_phone_template.py
    py tool/build_stations_seed.py --phones "أرقام المسؤولين.xlsx"

`build_stations_seed.py` يقرأ عمودين فقط: الأول يحتوي «اسم» والثاني يحتوي
«هاتف» أو «رقم». أي أعمدة إضافية (مثل عدد المحطات) تُتجاهل.
"""
import os
import sys
from collections import Counter

import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

REPORT = r"C:\Users\nader\Downloads\تقرير_المحطات_الكامل.xlsx"
OUT = r"C:\Users\nader\Downloads\أرقام المسؤولين.xlsx"

MANAGER_COLUMNS = ("مسؤول المحطة", "مسؤول المحطة 2", "مسؤول المحطة 3")
BAD_MANAGER = {"-", "", "nan", "none"}


def collect(report_path):
    """{اسم المسؤول: عدد المحطات المفعّلة التي يتابعها}."""
    report = pd.read_excel(report_path, sheet_name="التقرير")
    active = report["الحالة"].astype(str).str.strip().eq("مفعل")
    confirmed = report["حالة المطابقة"].astype(str).str.strip().eq("مطابقة مؤكدة")
    counts = Counter()
    for _, row in report[active & confirmed].iterrows():
        seen = set()
        for column in MANAGER_COLUMNS:
            value = row.get(column)
            if value is None or pd.isna(value):
                continue
            name = str(value).strip()
            if name.lower() in BAD_MANAGER or name in seen:
                continue
            seen.add(name)
            counts[name] += 1
    return counts


def main():
    report = sys.argv[1] if len(sys.argv) > 1 else REPORT
    out = sys.argv[2] if len(sys.argv) > 2 else OUT

    counts = collect(report)
    frame = pd.DataFrame(
        {
            "اسم المسؤول": list(counts.keys()),
            "رقم الهاتف": ["" for _ in counts],
            "عدد المحطات": [counts[name] for name in counts],
        }
    )
    frame = frame.sort_values("عدد المحطات", ascending=False).reset_index(drop=True)

    with pd.ExcelWriter(out, engine="openpyxl") as writer:
        frame.to_excel(writer, sheet_name="أرقام المسؤولين", index=False)
        sheet = writer.sheets["أرقام المسؤولين"]
        sheet.column_dimensions["A"].width = 26
        sheet.column_dimensions["B"].width = 20
        sheet.column_dimensions["C"].width = 14
        # نص لا رقم: أرقام الهواتف تبدأ بصفر ويجب ألا يحذفه Excel.
        for row in range(2, len(frame) + 2):
            sheet.cell(row=row, column=2).number_format = "@"

    print(f"✅ {out}")
    print(f"   مسؤولون: {len(frame)} | أعمدة: اسم المسؤول، رقم الهاتف، عدد المحطات")
    print("   املأ عمود «رقم الهاتف» ثم: py tool/build_stations_seed.py --phones \"أرقام المسؤولين.xlsx\"")
    return 0


if __name__ == "__main__":
    sys.exit(main())
