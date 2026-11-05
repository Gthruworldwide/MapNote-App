# -*- coding: utf-8 -*-
"""
تقرير المحطات الكامل:
  1) فحص روابط خرائط جوجل وفك الاختصار واستخراج الإحداثيات.
  2) دمج مسؤولي المحطات من ملف منفصل بمطابقة أسماء محافظة (تلقائي / اقتراح للمراجعة).

    py station_report.py                 # كل الصفوف
    py station_report.py --active-only   # المفعّلة فقط
"""
import argparse
import json
import os
import threading
from concurrent.futures import ThreadPoolExecutor

import pandas as pd
import requests

import matcher
from station_audit import classify, read_stations, resolve

HERE = os.path.dirname(os.path.abspath(__file__))
STATIONS = r"C:\Users\nader\Downloads\المحطات - مانيكس المفعله 20-10-2026 (1).xlsx"
MANAGERS = r"C:\Users\nader\Downloads\مسؤل المحطة.xlsx"
OUTPUT = r"C:\Users\nader\Downloads\تقرير_المحطات_الكامل.xlsx"
CACHE = os.path.join(HERE, "link_cache.json")
OVERRIDES = os.path.join(HERE, "browser_overrides.json")
EGYPT = (22.0, 32.0, 24.0, 37.0)
BAD_MANAGER = {'-', '', 'nan', 'none', 'لا يوجد'}

# توحيد كتابة المحافظات للعرض والتجميع فقط (المصدر يكتب الاسم بأشكال مختلفة)
GOV_DISPLAY = {matcher.norm(k): v for k, v in {
    'القاهرة': 'القاهرة', 'الجيزة': 'الجيزة', 'الإسكندرية': 'الإسكندرية',
    'الدقهلية': 'الدقهلية', 'الشرقية': 'الشرقية', 'القليوبية': 'القليوبية',
    'البحيرة': 'البحيرة', 'المنوفية': 'المنوفية', 'المنيا': 'المنيا',
    'أسيوط': 'أسيوط', 'سوهاج': 'سوهاج', 'قنا': 'قنا', 'الأقصر': 'الأقصر',
    'أسوان': 'أسوان', 'البحر الأحمر': 'البحر الأحمر', 'مطروح': 'مطروح',
    'مرسى مطروح': 'مرسى مطروح', 'شمال سيناء': 'شمال سيناء',
    'جنوب سيناء': 'جنوب سيناء', 'السويس': 'السويس', 'الإسماعيلية': 'الإسماعيلية',
    'بورسعيد': 'بورسعيد', 'دمياط': 'دمياط', 'كفر الشيخ': 'كفر الشيخ',
    'الغربية': 'الغربية', 'بني سويف': 'بني سويف', 'الفيوم': 'الفيوم',
    'الوادي الجديد': 'الوادي الجديد', 'البحيرة ': 'البحيرة',
    'جنوب سينا': 'جنوب سيناء', 'كفرالشيخ': 'كفر الشيخ',
}.items()}


def display_gov(value):
    """يشذّب المسافات والأسطر الجديدة ويوحّد تهجئة اسم المحافظة."""
    s = ' '.join(str(value).split())
    return GOV_DISPLAY.get(matcher.norm(s), s)


def load_managers(path):
    df = pd.read_excel(path, header=0)
    df.columns = [str(c).strip() for c in df.columns]
    df = df.dropna(how='all')
    for c in ('مسؤل المحطة', 'مسؤل المحطة2', 'مسؤل المحطة3'):
        if c in df.columns:
            df[c] = df[c].apply(lambda v: None if str(v).strip().lower() in BAD_MANAGER else str(v).strip())
    df = df[df['مسؤل المحطة'].notna()]
    return df.reset_index(drop=True)


def assign(report, managers):
    """إسناد 1:1: التلقائي أولاً ثم اقتراحات المراجعة، دون تكرار أي مسؤول."""
    names = managers['الأسم'].astype(str).tolist()
    govs = managers['المحافظة'].astype(str).tolist()
    types = managers['النوع'].astype(str).tolist() if 'النوع' in managers else [''] * len(names)

    pairs = []
    for i in range(len(report)):
        for j in range(len(managers)):
            c = matcher.compare(report['اسم المحطة'][i], report['النوع'][i], report['المحافظة'][i],
                                names[j], types[j], govs[j])
            if c['verdict'] in ('تلقائي', 'يحتاج مراجعة'):
                rank = 2 if c['verdict'] == 'تلقائي' else 1
                pairs.append((rank, c['score'], i, j, c))
    pairs.sort(key=lambda p: (p[0], p[1]), reverse=True)

    used_st, used_mgr, best_sugg = set(), set(), {}
    for rank, score, i, j, c in pairs:
        if rank == 2:
            if i in used_st or j in used_mgr:
                continue
            used_st.add(i)
            used_mgr.add(j)
            report.at[i, '_mgr'] = j
            report.at[i, '_score'] = c['score']
            report.at[i, '_state'] = 'تلقائي'
        elif i not in best_sugg:
            best_sugg[i] = (j, c)

    for i, (j, c) in best_sugg.items():
        if i in used_st:
            continue
        report.at[i, '_sugg'] = j
        report.at[i, '_sugg_state'] = f"اقتراح ({c['verdict']})"
        report.at[i, '_sugg_score'] = c['score']
        used_sugg = True
    return used_mgr


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--input', default=STATIONS)
    ap.add_argument('--managers', default=MANAGERS)
    ap.add_argument('--output', default=OUTPUT)
    ap.add_argument('--workers', type=int, default=8)
    ap.add_argument('--active-only', action='store_true')
    args = ap.parse_args()

    df = read_stations(args.input)
    if args.active_only:
        df = df[df['الحالة'].astype(str).str.strip().eq('مفعل')].reset_index(drop=True)

    cache = json.load(open(CACHE, encoding='utf-8')) if os.path.exists(CACHE) else {}
    overrides = {}
    if os.path.exists(OVERRIDES):
        overrides = {k: v for k, v in json.load(open(OVERRIDES, encoding='utf-8')).items()
                     if not k.startswith('_')}

    urls = [str(u).strip() for u in df['اللوكيشن']]
    todo = [u for u in dict.fromkeys(urls) if u.startswith('http') and u not in cache]
    if todo:
        print(f'تحميل {len(todo)} رابط جديد...')
        lock = threading.Lock()
        session = requests.Session()
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            list(pool.map(lambda u: resolve(u, session, cache, lock), todo))
        json.dump(cache, open(CACHE, 'w', encoding='utf-8'), ensure_ascii=False)

    rows = []
    for _, r in df.iterrows():
        url = str(r['اللوكيشن']).strip()
        o = dict(cache.get(url) or {})
        if url in overrides:
            o['lat'] = overrides[url]['lat']
            o['lng'] = overrides[url]['lng']
            o['place'] = overrides[url].get('place', '')
            source = 'صفحة المكان (متصفح)'
        elif o.get('lat') is not None:
            source = 'الرابط'
        else:
            source = ''

        lat, lng = o.get('lat'), o.get('lng')
        status = 'صحيح' if url in overrides else (classify(o) if url.startswith('http') else 'رابط مفقود')
        notes = []
        if o.get('how'):
            notes.append('استخراج ' + o['how'])
        if o.get('place'):
            notes.append('مكان جوجل: ' + str(o['place']))
        if lat is not None:
            inside = EGYPT[0] <= lat <= EGYPT[1] and EGYPT[2] <= lng <= EGYPT[3]
            swapped = EGYPT[0] <= lng <= EGYPT[1] and EGYPT[2] <= lat <= EGYPT[3]
            if not inside and swapped:
                notes.append('الإحداثيات مقلوبة (خطأ محتمل)')
            elif not inside:
                notes.append('خارج نطاق مصر')

        rows.append({
            'م': r['م'], 'اسم المحطة': r['اسم_المحطة'], 'اسم التاجر': r['اسم_التاجر'],
            'النوع': r['النوع'], 'المنطقة': r['المنطقة'], 'المحافظة': r['المحافظة'],
            'الحالة': r['الحالة'],
            'مسؤول المحطة': None, 'مسؤول المحطة 2': None, 'مسؤول المحطة 3': None,
            'حالة المطابقة': None, 'درجة الثقة': None,
            'مسؤول مقترح (للمراجعة)': None,
            'الرابط الأصلي': url, 'الرابط النهائي': o.get('final', ''),
            'Latitude': lat, 'Longitude': lng, 'مصدر الإحداثيات': source,
            'رابط الخريطة': f'https://www.google.com/maps?q={lat},{lng}' if lat is not None else '',
            'حالة الرابط': status, 'ملاحظات': ' | '.join(notes),
        })
    report = pd.DataFrame(rows)
    report['المحافظة'] = report['المحافظة'].apply(display_gov)
    report['_mgr'] = None
    report['_score'] = None
    report['_state'] = None
    report['_sugg'] = None
    report['_sugg_state'] = None
    report['_sugg_score'] = None

    managers = load_managers(args.managers)
    if 'المحافظة' in managers.columns:
        managers['المحافظة'] = managers['المحافظة'].apply(display_gov)
    assign(report, managers)

    mcols = [c for c in ('مسؤل المحطة', 'مسؤل المحطة2', 'مسؤل المحطة3') if c in managers.columns]
    out_cols = ['مسؤول المحطة', 'مسؤول المحطة 2', 'مسؤول المحطة 3']
    used_confirmed = set()
    for i in report.index:
        if pd.isna(report.at[i, '_mgr']):
            continue
        j = int(report.at[i, '_mgr'])
        used_confirmed.add(j)
        for k, c in enumerate(mcols):
            v = managers.at[j, c]
            if v is not None and pd.notna(v):
                report.at[i, out_cols[k]] = v
        report.at[i, 'حالة المطابقة'] = 'مطابقة مؤكدة'
        report.at[i, 'درجة الثقة'] = report.at[i, '_score']

    for i in report.index:
        if pd.isna(report.at[i, '_sugg']):
            continue
        j = int(report.at[i, '_sugg'])
        if j in used_confirmed:
            continue
        v = [str(managers.at[j, c]) for c in mcols
             if managers.at[j, c] is not None and pd.notna(managers.at[j, c])]
        if not v:
            continue
        report.at[i, 'مسؤول مقترح (للمراجعة)'] = ' / '.join(v)
        report.at[i, 'حالة المطابقة'] = report.at[i, '_sugg_state']
        report.at[i, 'درجة الثقة'] = report.at[i, '_sugg_score']

    used_mgr = {int(x) for x in report['_mgr'].dropna()}
    no_manager = report['مسؤول المحطة'].isna()
    ok = report['Latitude'].notna()

    key = report['Latitude'].round(5).astype(str) + ',' + report['Longitude'].round(5).astype(str)
    dup_coord = report[ok & key.duplicated(keep=False)].sort_values(['Latitude', 'Longitude'])
    dup_link = report[report['الرابط الأصلي'].duplicated(keep=False) &
                      report['الرابط الأصلي'].str.startswith('http')].sort_values('الرابط الأصلي')
    unmatched_mgr = managers.loc[~managers.index.isin(used_mgr)]

    summary = pd.DataFrame([
        ('إجمالي المحطات', len(report)),
        ('مفعّلة / غير مفعّلة',
         f"{int(report['الحالة'].astype(str).str.strip().eq('مفعل').sum())} / "
         f"{int((~report['الحالة'].astype(str).str.strip().eq('مفعل')).sum())}"),
        ('روابط بها إحداثيات', int(ok.sum())),
        ('روابط بدون إحداثيات', int((~ok).sum())),
        ('نسبة تغطية الإحداثيات', f'{ok.mean() * 100:.1f}%'),
        ('إحداثيات خارج مصر / مقلوبة', int(report['ملاحظات'].str.contains('خارج نطاق|مقلوبة').sum())),
        ('روابط مكررة بين محطات', len(dup_link)),
        ('إحداثيات مكررة (نفس النقطة)', len(dup_coord)),
        ('مسؤول مطابقة مؤكدة', int(report['حالة المطابقة'].eq('مطابقة مؤكدة').sum())),
        ('مسؤول مقترح للمراجعة',
         int(report['حالة المطابقة'].astype(str).str.startswith('اقتراح').sum())),
        ('محطات بدون مسؤول مؤكد', int(no_manager.sum())),
        ('محطات بدون مسؤول ولا اقتراح', int((no_manager & report['مسؤول مقترح (للمراجعة)'].isna()).sum())),
        ('نسبة تغطية المسؤولين (مؤكد فقط)',
         f"{report['مسؤول المحطة'].notna().mean() * 100:.1f}%"),
        ('نسبة التغطية مع الاقتراحات',
         f"{report['حالة المطابقة'].notna().mean() * 100:.1f}%"),
        ('مسؤولون في الملف بلا محطة', len(unmatched_mgr)),
    ], columns=['البند', 'القيمة'])

    gov = (report.assign(geo=ok, mgr=report['مسؤول المحطة'].notna())
           .groupby('المحافظة', dropna=False)
           .agg(عدد_المحطات=('اسم المحطة', 'size'), إحداثيات=('geo', 'sum'), مسؤولين=('mgr', 'sum'))
           .reset_index())
    gov['نسبة_الإحداثيات'] = (gov['إحداثيات'] / gov['عدد_المحطات'] * 100).round(1)

    review = report[report['حالة المطابقة'].astype(str).str.startswith('اقتراح')]
    final_cols = ['م', 'اسم المحطة', 'اسم التاجر', 'النوع', 'المنطقة', 'المحافظة', 'الحالة',
                  'مسؤول المحطة', 'مسؤول المحطة 2', 'مسؤول المحطة 3', 'حالة المطابقة',
                  'درجة الثقة', 'مسؤول مقترح (للمراجعة)',
                  'الرابط الأصلي', 'الرابط النهائي', 'Latitude', 'Longitude',
                  'مصدر الإحداثيات', 'رابط الخريطة', 'حالة الرابط', 'ملاحظات']

    with pd.ExcelWriter(args.output, engine='openpyxl') as xw:
        report[final_cols].to_excel(xw, sheet_name='التقرير', index=False)
        summary.to_excel(xw, sheet_name='الملخص', index=False)
        gov.sort_values('عدد_المحطات', ascending=False).to_excel(xw, sheet_name='حسب المحافظة', index=False)
        if len(review):
            review[final_cols].to_excel(xw, sheet_name='مطابقة تحتاج مراجعة', index=False)
        report[no_manager & report['مسؤول مقترح (للمراجعة)'].isna()][final_cols].to_excel(
            xw, sheet_name='بدون مسؤول (ولا اقتراح)', index=False)
        if len(unmatched_mgr):
            unmatched_mgr.to_excel(xw, sheet_name='مسؤولون بلا محطة', index=False)
        if len(dup_link):
            dup_link[final_cols].to_excel(xw, sheet_name='روابط مكررة', index=False)
        if len(dup_coord):
            dup_coord[final_cols].to_excel(xw, sheet_name='إحداثيات مكررة', index=False)
        if int((~ok).sum()):
            report[~ok][final_cols].to_excel(xw, sheet_name='بدون إحداثيات', index=False)

        widths = [5, 34, 28, 13, 15, 15, 10, 15, 15, 15, 20, 9, 20, 30, 40, 11, 11, 20, 34, 28, 40]
        for name, ws in xw.sheets.items():
            for i, w in enumerate(widths, start=1):
                ws.column_dimensions[ws.cell(row=1, column=i).column_letter].width = w
            ws.freeze_panes = 'A2'
            if name == 'التقرير':
                ws.auto_filter.ref = ws.dimensions

    print('\n' + summary.to_string(index=False))
    print(f'\n✅ {args.output}')


if __name__ == '__main__':
    main()
