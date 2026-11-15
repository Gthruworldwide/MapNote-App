import json
from collections import Counter

d = json.load(open('assets/data/stations.json', encoding='utf-8'))
mgr_counts = Counter(s['managerName'] for s in d)
print('Manager name distribution:')
for name, count in mgr_counts.most_common(10):
    print('  ', name, ':', count)
print('"غير محدد":', mgr_counts['غيرpecified'])
print('Total stations:', len(d))

status_counts = Counter(s['status'] for s in d)
print('Status distribution:')
for s, c in status_counts.most_common():
    print('  ', s, ':', c)