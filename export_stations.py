import pandas as pd
import json
import os

excel_path = r'C:\Users\nader\Downloads\تقرير_المحطات_الكامل.xlsx'
df = pd.read_excel(excel_path, sheet_name='التقرير')

gov_map = {
    'طنطا': 'الغربية', 'المحله الكبرى': 'الغربية', 'المحلة الكبرى': 'الغربية',
    'العامرية': 'الإسكندرية', 'حى غرب': 'الإسكندرية', 'حي شرق': 'الإسكندرية',
    'الغردقة': 'البحر الأحمر', 'اكتوير': 'الجيزة', 'مطروح': 'مرسى مطروح'
}
df['المحافظة_الموحدة'] = df['المحافظة'].astype(str).str.strip().replace(gov_map)
df.loc[df['م'] == 4, ['Latitude', 'Longitude']] = [26.7497, 33.9365]

stations = []
for idx, r in df.iterrows():
    mgr = r.get('مسؤول المحطة')
    if pd.isna(mgr) or str(mgr).strip() in ['', '-']:
        mgr = r.get('مسؤول مقترح (للمراجعة)')
    mgr_str = str(mgr).strip() if pd.notna(mgr) and str(mgr).strip() != '-' else 'غير محدد'
    
    stations.append({
        'id': f'ST_{r.get("م", idx+1)}',
        'name': str(r.get('اسم المحطة', '')).strip(),
        'vendor': str(r.get('اسم التاجر', '')).strip() if pd.notna(r.get('اسم التاجر')) else '',
        'type': str(r.get('النوع', '')).strip() if pd.notna(r.get('النوع')) else '',
        'address': str(r.get('المنطقة', '')).strip() if pd.notna(r.get('المنطقة')) else '',
        'city': str(r.get('المحافظة_الموحدة', '')).strip(),
        'area': str(r.get('المنطقة', '')).strip() if pd.notna(r.get('المنطقة')) else '',
        'latitude': float(r['Latitude']) if pd.notna(r.get('Latitude')) else 0.0,
        'longitude': float(r['Longitude']) if pd.notna(r.get('Longitude')) else 0.0,
        'managerName': mgr_str,
        'managerPhone': '',
        'status': str(r.get('الحالة', 'مفعل')).strip(),
        'isDefault': True,
        'isCustom': False
    })

out_path = r'D:\RouteNote App\assets\data\stations.json'
os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, 'w', encoding='utf-8') as f:
    json.dump(stations, f, ensure_ascii=False, indent=2)

print(f'✅ تم تصدير {len(stations)} محطة بنجاح إلى {out_path}')