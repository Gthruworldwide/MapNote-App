# -*- coding: utf-8 -*-
"""
مطابقة أسماء المحطات بين ملف المحطات وملف مسؤولي المحطات.

المبدأ: لا تُقبل المطابقة إلا إذا كان كل رمز مميز في اسم المسؤول موجوداً في اسم
المحطة (تغطية كاملة)، مع توافق العلامة التجارية والمحافظة، وغياب تعارض في الأرقام.
ما دون ذلك يُدرج كـ"اقتراح" للمراجعة اليدوية ولا يُكتب كبيان مؤكد.
"""
import difflib
import re

TASHKEEL = re.compile(r'[\u064B-\u0652\u0670\u0640]')
DIGITS = str.maketrans('٠١٢٣٤٥٦٧٨٩', '0123456789')

GENERIC = {'محطه', 'محطات', 'بنزين', 'وقود', 'غاز', 'طبيعي', 'للبترول', 'البترول', 'بترول',
           'تعبئه', 'تعبه', 'خدمات', 'station', 'gas', 'fuel', 'petrol', 'petroleum',
           'service', 'حدود', 'الف', 'كيلو', 'محور', 'طريق', 'دائري'}
BRAND_WORDS = {
    'موبيل': 'mobil', 'mobil': 'mobil',
    'توتال': 'total', 'total': 'total', 'totalenergies': 'total',
    'طاقه': 'taqa', 'taqa': 'taqa',
    'وطنيه': 'watanya', 'watanya': 'watanya', 'wataniya': 'watanya',
    'نيل': 'nile', 'nile': 'nile',
    'تعاون': 'taawon', 'coop': 'taawon',
    'cpc': 'taawon', 'سيبي': 'taawon', 'بي': 'taawon', 'سي': 'taawon',
    'اولي': 'ola', 'اولى': 'ola', 'ola': 'ola',
    'انرجي': 'energy', 'energy': 'energy',
    'بترومين': 'petromin', 'بترمين': 'petromin', 'petromin': 'petromin',
    'ايني': 'eni', 'اينى': 'eni', 'eni': 'eni',
    'egc': 'egc', 'ماراثون': 'marathon',
}
# بادئات/جذور أسماء علامات تُحذف حتى لو كُتبت بتهجئة مختلفة (petromen, Wataniya ...)
BRAND_ROOTS = re.compile(r'^(petro|mobil|total|taqa|watany|nile|coop|cpc|ola|eni|egc|energy'
                         r'|marathon|بترم|وطن|طاق|موبيل|توتال|تعاون|نيل)', re.I)
NOISE = GENERIC | set(BRAND_WORDS)

GOVS = {'القاهره', 'الجيزه', 'الاسكندريه', 'الدقهليه', 'الشرقيه', 'القلوبيه', 'البحيره',
        'المنوفيه', 'المنيا', 'اسيوط', 'سوهاج', 'قنا', 'الاقصر', 'اسوان', 'البحر الاحمر',
        'مطروح', 'مرسي مطروح', 'شمال سيناء', 'جنوب سيناء', 'السويس', 'الاسماعيليه',
        'بورسعيد', 'دمياط', 'كفر الشيخ', 'الغربيه', 'بني سويف', 'الفيوم', 'الوادي الجديد'}


def norm(s):
    s = TASHKEEL.sub('', str(s)).translate(DIGITS).lower()
    for a, b in (('أ', 'ا'), ('إ', 'ا'), ('آ', 'ا'), ('ٱ', 'ا'), ('ى', 'ي'), ('ئ', 'ي'),
                 ('ؤ', 'و'), ('ة', 'ه'), ('ـ', '')):
        s = s.replace(a, b)
    return s


def _words(s):
    return re.findall(r'[a-z0-9\u0621-\u064a]+', norm(s))


def toks(s):
    out = []
    for t in _words(s):
        if len(t) > 3 and t.startswith('ال'):
            t = t[2:]
        if t.isdigit():
            out.append(t)
            continue
        if len(t) < 2 or t in NOISE or BRAND_ROOTS.match(t):
            continue
        out.append(t)
    return out


def brand(*fields):
    for f in fields:
        s = norm(f)
        if 'مصر للبترول' in s or 'مصر البترول' in s or 'misr petroleum' in s or 'misrpetroleum' in s:
            return 'misr'
        for w in _words(f):
            b = BRAND_WORDS.get(w) or BRAND_WORDS.get(w[2:] if w.startswith('ال') else w)
            if b:
                return b
    return ''


def gov_name(g):
    j = ' '.join(w for w in _words(g) if w != 'ال')
    return j if j in GOVS else ''


def compare(station, station_type, station_gov, mgr_name, mgr_type, mgr_gov):
    a, b = set(toks(station)), set(toks(mgr_name))
    shared = a & b
    cover = len(shared) / len(b) if b else 0.0          # كل رموز المسؤول موجودة في المحطة
    f1 = (2 * len(shared) / (len(a) + len(b))) if a and b else 0.0
    ratio = difflib.SequenceMatcher(None, ' '.join(sorted(a)), ' '.join(sorted(b))).ratio()

    ba, bb = brand(station, station_type), brand(mgr_name, mgr_type)
    brand_state = None if not ba or not bb else ba == bb
    ga, gb = gov_name(station_gov), gov_name(mgr_gov)
    gov_state = None if not ga or not gb else ga == gb
    num_conflict = bool({t for t in a if t.isdigit()} and
                        {t for t in b if t.isdigit()} and
                        {t for t in a if t.isdigit()} != {t for t in b if t.isdigit()})

    verdict = 'لا مطابقة'
    if num_conflict:
        verdict = 'تعارض في الأرقام'
    elif gov_state is False:
        verdict = 'اختلاف المحافظة'
    elif brand_state is False:
        verdict = 'اختلاف العلامة'
    elif shared and cover == 1.0 and (len(shared) >= 2 or len(a) == len(b) == len(shared)):
        verdict = 'تلقائي'
    elif shared and (cover >= 0.5 or f1 >= 0.5):
        verdict = 'يحتاج مراجعة'

    score = round(0.5 * cover + 0.35 * f1 + 0.15 * ratio, 3)
    return {'score': score, 'cover': round(cover, 3), 'f1': round(f1, 2),
            'ratio': round(ratio, 2), 'shared': len(shared), 'gov': gov_state,
            'brand': brand_state, 'verdict': verdict,
            'toks_a': sorted(a), 'toks_b': sorted(b)}


if __name__ == '__main__':
    import pandas as pd
    st = pd.read_excel(r"C:\Users\nader\Downloads\تقرير_المحطات_الكامل.xlsx", sheet_name='التقرير')
    mg = pd.read_excel(r"C:\Users\nader\Downloads\مسؤل المحطة.xlsx", header=0)
    mg = mg[~mg['مسؤل المحطة'].astype(str).str.strip().isin(['-', 'nan', ''])].reset_index(drop=True)
    names = mg['الأسم'].astype(str).tolist()
    govs = mg['المحافظة'].astype(str).tolist()
    mans = mg['مسؤل المحطة'].astype(str).tolist()
    types = mg['النوع'].astype(str).tolist()
    rank = {'تلقائي': 3, 'يحتاج مراجعة': 2}
    rows = []
    for i in range(len(st)):
        best, bj = None, None
        for j in range(len(mg)):
            c = compare(st['اسم المحطة'][i], st['النوع'][i], st['المحافظة'][i],
                        names[j], types[j], govs[j])
            if best is None or (rank.get(c['verdict'], 0), c['score']) > (rank.get(best['verdict'], 0), best['score']):
                best, bj = c, j
        rows.append({'م': st['م'][i], 'المحطة': str(st['اسم المحطة'][i])[:36],
                     'المرشح': names[bj][:34], 'sh': best['shared'], 'cover': best['cover'],
                     'gov': best['gov'], 'brand': best['brand'],
                     'حكم': best['verdict'], 'المسؤول': mans[bj][:13]})
    d = pd.DataFrame(rows)
    print(d['حكم'].value_counts().to_string())
    print('\n--- مطابقة تلقائية (عينة) ---')
    print(d[d['حكم'] == 'تلقائي'].sample(min(12, len(d[d['حكم'] == 'تلقائي'])), random_state=7).to_string(index=False))
    print('\n--- للمراجعة (عينة) ---')
    print(d[d['حكم'] == 'يحتاج مراجعة'].head(12).to_string(index=False))
    print('\n--- أسباب الرفض ---')
    print(d[d['حكم'].isin(['اختلاف العلامة', 'اختلاف المحافظة', 'تعارض في الأرقام'])].head(12).to_string(index=False))
