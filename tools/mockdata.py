import json, csv, sys
ALCH, W, OUT = sys.argv[1:4]
alch = {x['spell']: x for x in json.load(open(ALCH))}
req = {}
for r in csv.DictReader(open(f'{W}/ItemSparse.csv', newline='', encoding='utf-8')):
    req[r['ID']] = int(r['RequiredSkillRank'] or 0)
def glyph(name):
    n = name.lower()
    if 'vial' in n: return 'vial'
    if n.startswith('recipe') or n.startswith('blueprint'): return 'recipe'
    if any(k in n for k in ('ore', 'bar', 'crystal', 'pyrite')): return 'ore'
    if any(k in n for k in ('eye', 'finger', 'fang', 'sac', 'oil', 'heart', 'dust', 'essence', 'blood of')): return 'misc'
    return 'herb'
def out_glyph(name):
    n = name.lower()
    if any(k in n for k in ('laboratory', 'fermenter', 'mana well')): return 'camp'
    if 'bar' in n: return 'ore'
    return 'potion'
order = [1245250, 1230564, 1251741, 7183, 2329, 2331, 1244645, 1263005, 1250783, 4942, 1317279, 1250785, 1263078, 17574, 17635, 1293559]
R = {}
for s in order:
    x = alch[s]
    c = x['creates']
    R[s] = {
        'name': x['name'], 'status': x['status'], 'acq': x['acquire'], 'y': x['yellow'], 'g': x['grey'],
        'creates': {'id': c['id'], 'name': c['name'], 'q': c['q'], 'new': x.get('createsNew', False), 'gl': out_glyph(c['name'])},
        'recipe': [{'id': r['id'], 'name': r['name'], 'q': r['q'], 'req': req.get(str(r['id']), 0)} for r in x['recipeItems']],
        'reagents': [{'id': r['id'], 'name': r['name'], 'q': r['q'], 'n': r['n'], 'new': r.get('new', False), 'gl': glyph(r['name'])} for r in x['reagents']],
        # trainers / vendors / drops are not collected yet; auto-learned comes from client data
        'src': [{'type': 'auto'}] if x['acquire'] == 1 else [],
    }
json.dump(R, open(OUT, 'w'), ensure_ascii=False, separators=(',', ':'))
print(len(json.dumps(R)) // 1024, 'KB')
