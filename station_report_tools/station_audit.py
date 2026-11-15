# -*- coding: utf-8 -*-
"""
فحص روابط اللوكيشن (خرائط جوجل) لمحطات الوقود + استخراج الإحداثيات.

الاستخدام:
    py station_audit.py
    py station_audit.py --input "ملف.xlsx" --output "تقرير.xlsx" --workers 6 --include-inactive
"""
import argparse
import json
import os
import re
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

import pandas as pd
import requests

DEFAULT_INPUT = r"C:\Users\nader\Downloads\المحطات - مانيكس المفعله 20-10-2026 (1).xlsx"
DEFAULT_OUTPUT = r"C:\Users\nader\Downloads\تقرير_فحص_المحطات.xlsx"
CACHE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "link_cache.json")

COLS = ['م', 'اسم_التاجر', 'النوع', 'اسم_المحطة', 'ID', 'العنوان', 'اللوكيشن',
        'المنطقة', 'المحافظة', 'سولار', 'بنزين_80', 'بنزين_92', 'بنزين_95',
        'غاز_طبيعي', 'الحالة']

HEADERS = {
    'User-Agent': ('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                   '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'),
    'Accept-Language': 'ar,en;q=0.9',
}

# أنماط استخراج الإحداثيات من الرابط النهائي بعد فك الاختصار
COORD_PATTERNS = [
    ('@', re.compile(r'@(-?\d{1,2}\.\d+),(-?\d{1,3}\.\d+)')),
    ('!3d!4d', re.compile(r'!3d(-?\d{1,2}\.\d+)!4d(-?\d{1,3}\.\d+)')),
    ('query', re.compile(r'[?&](?:q|query|ll|sll|center|destination|daddr|saddr)='
                         r'(-?\d{1,2}\.\d+)\s*,\s*(-?\d{1,3}\.\d+)')),
    ('place', re.compile(r'/place/(-?\d{1,2}\.\d+),(-?\d{1,3}\.\d+)')),
]


def read_stations(path):
    """يقرأ الملف مع تحديد صف العناوين تلقائياً (بدل skiprows الثابت)."""
    probe = pd.read_excel(path, sheet_name=0, header=None, nrows=25)
    header_row = 0
    for i in range(len(probe)):
        row_vals = [str(v).strip() for v in probe.iloc[i].tolist() if pd.notna(v)]
        if row_vals and 'اسم التاجر' in row_vals:
            header_row = i
            break
    df = pd.read_excel(path, sheet_name=0, header=None, skiprows=header_row + 1)
    df = df.iloc[:, :len(COLS)]
    df.columns = COLS[:df.shape[1]]
    df = df.dropna(how='all')
    return df.reset_index(drop=True)


def valid(lat, lng):
    return lat is not None and lng is not None and -90 <= lat <= 90 and -180 <= lng <= 180


def extract_coords(url):
    for label, rx in COORD_PATTERNS:
        m = rx.search(url)
        if m:
            lat, lng = float(m.group(1)), float(m.group(2))
            if valid(lat, lng):
                return lat, lng, label
    return None, None, None


def resolve(url, session, cache, lock, attempts=3):
    """يفك الرابط المختصر ويستخرج الإحداثيات، مع كاش وتكرار عند الفشل."""
    with lock:
        if url in cache:
            return cache[url]

    outcome = None
    last_err = None
    for attempt in range(attempts):
        try:
            r = session.get(url, headers=HEADERS, allow_redirects=True, timeout=15)
            final = r.url
            lat, lng, how = extract_coords(final)
            outcome = {'final': final, 'http': r.status_code, 'lat': lat, 'lng': lng,
                       'how': how, 'final_host': re.sub(r'^https?://([^/]+).*', r'\1', final)}
            break
        except Exception as e:  # noqa: BLE001
            last_err = f'{type(e).__name__}'
            time.sleep(1.0 * (attempt + 1))

    if outcome is None:
        outcome = {'final': '', 'http': 0, 'lat': None, 'lng': None, 'how': None,
                   'final_host': '', 'error': last_err}

    with lock:
        cache[url] = outcome
    return outcome


def classify(o):
    if o.get('error'):
        return f'رابط تالف / غير متاح ({o["error"]})'
    if o.get('http', 0) in (404, 410):
        return f'رابط غير موجود (HTTP {o["http"]})'
    if o.get('http') and o['http'] >= 400:
        return f'خطأ HTTP {o["http"]}'
    host = o.get('final_host') or ''
    if 'consent.google' in host or '/consent' in (o.get('final') or ''):
        return 'رابط يعمل لكنه يحوّل لصفحة موافقة (لا إحداثيات)'
    if o.get('lat') is not None:
        return 'صحيح'
    return 'رابط يعمل بدون إحداثيات صريحة'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--input', default=DEFAULT_INPUT)
    ap.add_argument('--output', default=DEFAULT_OUTPUT)
    ap.add_argument('--workers', type=int, default=6)
    ap.add_argument('--include-inactive', action='store_true',
                    help='يفحص أيضاً المحطات غير المفعّلة')
    ap.add_argument('--no-cache', action='store_true')
    args = ap.parse_args()

    df = read_stations(args.input)
    total = len(df)
    if not args.include_inactive:
        active = df['الحالة'].astype(str).str.strip().eq('مفعل')
        print(f'إجمالي الصفوف: {total} | المفعّلة: {int(active.sum())} | '
              f'غير المفعّلة: {total - int(active.sum())} (لن تُفحص، استخدم --include-inactive)')
        df = df[active].reset_index(drop=True)

    cache = {}
    if not args.no_cache and os.path.exists(CACHE_PATH):
        try:
            with open(CACHE_PATH, encoding='utf-8') as fh:
                cache = json.load(fh)
            print(f'كاش محفوظ: {len(cache)} رابط')
        except Exception:  # noqa: BLE001
            cache = {}

    lock = threading.Lock()
    session = requests.Session()
    urls = [str(u).strip() for u in df['اللوكيشن'].tolist()]
    unique = list(dict.fromkeys(u for u in urls if u.startswith('http')))
    print(f'فحص {len(unique)} رابط فريد (من {len(urls)} صف)...\n')

    results = {}
    done = 0
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {pool.submit(resolve, u, session, cache, lock): u for u in unique}
        for fut in as_completed(futures):
            u = futures[fut]
            results[u] = fut.result()
            done += 1
            lat, lng = results[u].get('lat'), results[u].get('lng')
            print(f'[{done}/{len(unique)}] {classify(results[u])}'
                  + (f' -> {lat},{lng}' if lat is not None else ''), flush=True)

    # حفظ الكاش
    try:
        with open(CACHE_PATH, 'w', encoding='utf-8') as fh:
            json.dump(cache, fh, ensure_ascii=False)
    except Exception:  # noqa: BLE001
        pass

    rows = []
    for _, r in df.iterrows():
        url = str(r['اللوكيشن']).strip()
        o = results.get(url) or {'error': 'رابط مفقود', 'final': '', 'lat': None, 'lng': None}
        lat, lng = o.get('lat'), o.get('lng')
        status = classify(o) if url.startswith('http') else 'رابط مفقود'
        rows.append({
            'م': r['م'],
            'اسم المحطة': r['اسم_المحطة'],
            'اسم التاجر': r['اسم_التاجر'],
            'النوع': r['النوع'],
            'المنطقة': r['المنطقة'],
            'المحافظة': r['المحافظة'],
            'الحالة': r['الحالة'],
            'الرابط الأصلي': url,
            'الرابط النهائي': o.get('final', ''),
            'Latitude': lat,
            'Longitude': lng,
            'حالة الرابط': status,
            'ملاحظة': o.get('how') or '',
            'رابط الخريطة': (f'https://www.google.com/maps?q={lat},{lng}'
                             if lat is not None else ''),
        })

    report = pd.DataFrame(rows)
    ok = report['حالة الرابط'].eq('صحيح')
    no_coords = report['حالة الرابط'].str.startswith('رابط يعمل')
    bad = ~ok & ~no_coords

    # كشف التكرار في الإحداثيات والروابط
    coord_key = report['Latitude'].round(5).astype(str) + ',' + report['Longitude'].round(5).astype(str)
    dup_coord = report[ok & coord_key.duplicated(keep=False)].sort_values('Latitude')
    dup_link = report[report['الرابط الأصلي'].duplicated(keep=False) &
                      report['الرابط الأصلي'].str.startswith('http')].sort_values('الرابط الأصلي')

    summary = pd.DataFrame([
        ('إجمالي الصفوف المفحوصة', len(report)),
        ('روابط صحيحة مع إحداثيات', int(ok.sum())),
        ('روابط تعمل بدون إحداثيات', int(no_coords.sum())),
        ('روابط تالفة / أخطاء', int(bad.sum())),
        ('نسبة الإحداثيات الصحيحة', f'{ok.mean() * 100:.1f}%'),
        ('روابط مكررة', len(dup_link)),
        ('إحداثيات مكررة (نفس النقطة)', len(dup_coord)),
    ], columns=['البند', 'القيمة'])

    gov = (report.assign(حالة=report['حالة الرابط'].eq('صحيح'))
           .groupby('المحافظة', dropna=False)
           .agg(عدد_المحطات=('اسم المحطة', 'size'), صحيح=('حالة', 'sum'))
           .reset_index())
    gov['نسبة'] = (gov['صحيح'] / gov['عدد_المحطات'] * 100).round(1)
    gov = gov.sort_values('عدد_المحطات', ascending=False)

    with pd.ExcelWriter(args.output, engine='openpyxl') as xw:
        report.to_excel(xw, sheet_name='التقرير', index=False)
        summary.to_excel(xw, sheet_name='الملخص', index=False)
        gov.to_excel(xw, sheet_name='حسب المحافظة', index=False)
        if len(dup_link):
            dup_link.to_excel(xw, sheet_name='روابط مكررة', index=False)
        if len(dup_coord):
            dup_coord.to_excel(xw, sheet_name='إحداثيات مكررة', index=False)
        # عرض الأعمدة
        for name, ws in xw.sheets.items():
            widths = {'التقرير': [5, 34, 30, 14, 16, 16, 10, 30, 40, 11, 11, 34, 10, 34],
                      'الملخص': [34, 40], 'حسب المحافظة': [18, 12, 8, 9],
                      'روابط مكررة': [5, 30, 16, 16, 30, 30, 12, 11, 11, 30, 8, 30],
                      'إحداثيات مكررة': [5, 30, 16, 16, 30, 30, 12, 11, 11, 30, 8, 30]}
            for i, w in enumerate(widths.get(name, []), start=1):
                ws.column_dimensions[ws.cell(row=1, column=i).column_letter].width = w
            ws.freeze_panes = 'A2'

    print('\n' + summary.to_string(index=False))
    print(f'\n✅ التقرير: {args.output}')


if __name__ == '__main__':
    main()
