import pandas as pd
import json
import os

# 1. قراءة التقرير الرئيسي
excel_path = r"C:\Users\nader\Downloads\تقرير_المحطات_الكامل.xlsx"
df = pd.read_excel(excel_path, sheet_name="التقرير")

# 2. قاموس توحيد المحافظات
gov_map = {
    "طنطا": "الغربية",
    "المحله الكبرى": "الغربية",
    "المحلة الكبرى": "الغربية",
    "العامرية": "الإسكندرية",
    "حى غرب": "الإسكندرية",
    "حي شرق": "الإسكندرية",
    "الغردقة": "البحر الأحمر",
    "اكتوير": "الجيزة",
    "مطروح": "مرسى مطروح"
}

df['المحافظة_الموحدة'] = df['المحافظة'].astype(str).str.strip().replace(gov_map)

# 3. تصحيح إحداثيات سفاجا (الصف م = 4)
safaga_mask = df['م'] == 4
df.loc[safaga_mask, 'Latitude'] = 26.7497
df.loc[safaga_mask, 'Longitude'] = 33.9365

# 4. تجميع بيانات المحطات بالتنسيق المعتمد للتطبيق
stations_data = []

for idx, row in df.iterrows():
    # اختيار اسم المسؤول التأكيدي أولاً، وإنم لم exists يتم اختيار المقترح
    manager_name = row.get("مسؤول المحطة")
    if pd.isna(manager_name) or str(manager_name).strip() in ["", "-"]:
        manager_name = row.get("مسؤول مقترح (للمراجعة)")
    
    manager_str = str(manager_name).strip() if pd.notna(manager_name) and str(manager_name).strip() != "-" else "غير محدد"

    station_item = {
        "id": "ST_" + str(row.get("م", idx+1)),
        "name": str(row.get("اسم المحطة", "")).strip(),
        "vendor": str(row.get("اسم التاجر", "")).strip() if pd.notna(row.get("اسم التاجر")) else "",
        "type": str(row.get("النوع", "")).strip() if pd.notna(row.get("النوع")) else "",
        "address": str(row.get("المنطقة", "")).strip() if pd.notna(row.get("المنطقة")) else "",
        "city": str(row.get("المحافظة_الموحدة", "")).strip(),
        "area": str(row.get("المنطقة", "")).strip() if pd.notna(row.get("المنطقة")) else "",
        "latitude": float(row["Latitude"]) if pd.notna(row.get("Latitude")) else 0.0,
        "longitude": float(row["Longitude"]) if pd.notna(row.get("Longitude")) else 0.0,
        "managerName": manager_str,
        "managerPhone": "",
        "status": str(row.get("الحالة", "مفعل")).strip(),
        "isDefault": True,
        "isCustom": False
    }
    stations_data.append(station_item)

# 5. حفظ الملف داخل مشروع MapNote
output_path = r"D:\RouteNote App\assets\data\stations.json"
os.makedirs(os.path.dirname(output_path), exist_ok=True)

with open(output_path, "w", encoding="utf-8") as f:
    json.dump(stations_data, f, ensure_ascii=False, indent=2)

print(f"✅ تم فحص البيانات وتصدير {len(stations_data)} محطة بنجاح إلى:")
print(f"📍 {output_path}")