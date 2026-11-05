# -*- coding: utf-8 -*-
"""يبني `assets/data/stations.json` (بيانات الشحن الأولى) من تقرير المحطات.

المصدر: تقرير المحطات المدقّق (الأوراق: التقرير) + ملف المحطات الأصلي (لـ ID والعنوان).

القواعد:
  * المحطات المفعّلة فقط (الحالة = مفعل) — الافتراضي 394 محطة.
  * اسم المسؤول يُكتب فقط عند «مطابقة مؤكدة» (المطابقة 1:1 مع ملف المسؤولين).
    الاقتراحات التي تحتاج مراجعة لا تُشحن أبدًا كبيانات مؤكدة.
  * أرقام الهواتف غير متوفرة في ملف المسؤولين اليوم؛ الحقل يُكتب null ويُملأ
    لاحقًا من ملف الأرقام بدون تغيير الكود (انظر --phones).

    py tool/build_stations_seed.py
    py tool/build_stations_seed.py --phones "أرقام المسؤولين.xlsx"
"""
import argparse
import json
import os
import sys

import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

DEFAULT_STATIONS = r"C:\Users\nader\Downloads\المحطات - مانيكس المفعله 20-10-2026 (1).xlsx"
DEFAULT_REPORT = r"C:\Users\nader\Downloads\تقرير_المحطات_الكامل.xlsx"
DEFAULT_OUT = os.path.join(ROOT, "assets", "data", "stations.json")

# طابع زمني ثابت: قائمة الشاشة الرئيسية تُرتّب تنازليًا بالتاريخ، فالثابت يجعل
# ترتيب محطات الشحن حتميًا بدل أن يعتمد على وقت أول تشغيل على كل جهاز.
SEED_TIMESTAMP = "2026-10-20T00:00:00.000Z"

MANAGER_COLUMNS = ("مسؤول المحطة", "مسؤول المحطة 2", "مسؤول المحطة 3")
BAD_MANAGER = {"-", "", "nan", "none"}


def clean_number(value):
    """يحوّل رقم Excel (29.0) إلى نص صحيح، ويرجع '' عند غيابه."""
    if value is None or pd.isna(value):
        return ""
    text = str(value).strip()
    if text.endswith(".0"):
        text = text[:-2]
    return text


def clean_phone(value):
    """يطبّع رقم الهاتف كما يقرأه Excel.

    الخطر الحقيقي: من يكتب `01001234567` في خلية رقمية يفقد الصفر الأول،
    فيصل الرقم `1001234567` — وهو ليس رقمًا يُطلب. لذا نُعيد الصفر عندما
    يكون الرقم عشرة أرقام ويبدأ بـ 1 (صيغة المحمول المصرية)، ونحتفظ بـ + عند
    وجودها. القيم غير الصالحة تُرفض بدل أن تُكتب كرقم ميت في التطبيق.
    """
    text = clean_number(value)
    if not text:
        return ""
    # 1.00123e+09 نتيجة خلية عريضة جدًا في Excel.
    if "e+" in text.lower():
        try:
            text = str(int(float(text)))
        except ValueError:
            return ""
    has_plus = text.startswith("+")
    digits = "".join(ch for ch in text if ch.isdigit())
    if not digits:
        return ""
    if not has_plus and len(digits) == 10 and digits.startswith("1"):
        digits = "0" + digits
    if len(digits) < 7:
        return ""
    return f"+{digits}" if has_plus else digits


def load_report(report_path):
    """يقرأ التقرير مرة واحدة: المسؤولون المؤكدون + الإحداثيات لكل صف."""
    report = pd.read_excel(report_path, sheet_name="التقرير")
    confirmed = report["حالة المطابقة"].astype(str).str.strip().eq("مطابقة مؤكدة")
    managers, coordinates = {}, {}
    for _, row in report.iterrows():
        number = int(row["م"])
        coordinates[number] = (
            row.get("Latitude"),
            row.get("Longitude"),
            str(row.get("المحافظة") or "").strip(),
            str(row.get("المنطقة") or "").strip(),
        )
        if not confirmed.loc[row.name]:
            continue
        names = []
        for column in MANAGER_COLUMNS:
            value = row.get(column)
            if value is None or pd.isna(value):
                continue
            name = str(value).strip()
            if name.lower() in BAD_MANAGER or name in names:
                continue
            names.append(name)
        if names:
            managers[number] = names
    return managers, coordinates


def load_phones(path):
    """{اسم المسؤول: رقم الهاتف} من ملف الأرقام (عمودان: الاسم، الهاتف)."""
    if not path:
        return {}
    frame = pd.read_excel(path)
    frame.columns = [str(c).strip() for c in frame.columns]
    name_column = next((c for c in frame.columns if "مسؤول" in c or "اسم" in c), None)
    phone_column = next((c for c in frame.columns if "هاتف" in c or "رقم" in c), None)
    if name_column is None or phone_column is None:
        raise SystemExit("ملف الأرقام يجب أن يحتوي عمودَي الاسم والهاتف")
    phones = {}
    skipped = []
    for _, row in frame.iterrows():
        name = str(row[name_column]).strip()
        raw = row[phone_column]
        phone = clean_phone(raw)
        if not name or name.lower() in BAD_MANAGER:
            continue
        if not phone:
            if not pd.isna(raw) and str(raw).strip():
                skipped.append(f"{name}: {raw}")
            continue
        phones[name] = phone
    if skipped:
        print("⚠️ أرقام غير صالحة تم تجاهلها:")
        for item in skipped:
            print(f"   {item}")
    return phones


def build(stations_path, report_path, phones_path=None, active_only=True):
    frame = pd.read_excel(stations_path, header=10)
    frame.columns = [str(c).strip() for c in frame.columns]
    frame = frame[frame["م"].notna()].copy()
    frame["م"] = frame["م"].astype(int)

    managers_by_row, coordinates = load_report(report_path)
    phones = load_phones(phones_path)

    if active_only:
        active = frame["الحالة"].astype(str).str.strip().eq("مفعل")
        frame = frame[active]
    frame = frame.sort_values("م")

    stations = []
    for _, row in frame.iterrows():
        number = int(row["م"])
        external_id = clean_number(row.get("ID"))
        # ID الرسمي إن وُجد، وإلا معرّف ثابت مبني على رقم الصف (252 صفًا بلا ID).
        station_id = f"stn_{external_id}" if external_id else f"stn_row_{number}"

        notes = str(row.get("العنوان") or "").strip()
        if notes.lower() == "nan":
            notes = ""

        managers = [
            {"name": name, "phone": phones.get(name)}
            for name in managers_by_row.get(number, [])
        ]

        latitude, longitude, governorate, area = coordinates.get(
            number, (None, None, "", "")
        )
        if governorate.lower() == "nan":
            governorate = ""
        if area.lower() == "nan":
            area = ""

        stations.append(
            {
                "id": station_id,
                "name": str(row.get("اسم المحطة") or "").strip(),
                "notes": notes,
                "category": "gas_station",
                "city": governorate,
                "area": area,
                "latitude": round(float(latitude), 7) if pd.notna(latitude) else None,
                "longitude": round(float(longitude), 7) if pd.notna(longitude) else None,
                "managers": managers,
                "timestamp": SEED_TIMESTAMP,
                "isDefault": True,
                "isCustom": False,
            }
        )
    return stations


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--stations", default=DEFAULT_STATIONS)
    parser.add_argument("--report", default=DEFAULT_REPORT)
    parser.add_argument("--phones", default=None)
    parser.add_argument("--out", default=DEFAULT_OUT)
    parser.add_argument("--all", action="store_true", help="يشمل غير المفعّلة أيضًا")
    args = parser.parse_args()

    stations = build(args.stations, args.report, args.phones, active_only=not args.all)
    missing = [s for s in stations if s["latitude"] is None or s["longitude"] is None]
    if missing:
        raise SystemExit(f"{len(missing)} محطة بلا إحداثيات — أوقف البناء")

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as handle:
        json.dump(stations, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    with_manager = sum(1 for s in stations if s["managers"])
    multi = sum(1 for s in stations if len(s["managers"]) > 1)
    with_phone = sum(1 for s in stations for m in s["managers"] if m["phone"])
    print(f"✅ {args.out}")
    print(f"   محطات: {len(stations)} | بمسؤول مؤكد: {with_manager} | بأكثر من مسؤول: {multi}")
    print(f"   بأرقام هواتف: {with_phone}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
