import csv, json, sys
def rows(p): return csv.DictReader(open(p, newline='', encoding='utf-8'))
F, E, J = sys.argv[1], sys.argv[2], sys.argv[3]
era_sla = {r['Spell'] for r in rows(f'{E}/SkillLineAbility.csv') if r['SkillLine'] == '171'}
era_reag = {}
for r in rows(f'{E}/SpellReagents.csv'):
    era_reag[r['SpellID']] = sorted((r[f'Reagent_{i}'], r[f'ReagentCount_{i}']) for i in range(8) if r[f'Reagent_{i}'] not in ('0',''))
era_items = {r['ID'] for r in rows(f'{E}/ItemSparse.csv')}
d = json.load(open(J))
new = changed = same = 0
for x in d:
    s = str(x['spell'])
    if s not in era_sla: x['status'] = 'new'; new += 1
    else:
        cur = sorted((str(r['id']), str(r['n'])) for r in x['reagents'])
        x['status'] = 'changed' if cur != era_reag.get(s, []) else 'same'
        changed += x['status'] == 'changed'; same += x['status'] == 'same'
    x['createsNew'] = bool(x['creates']) and str(x['creates']['id']) not in era_items
    for r in x['reagents']: r['new'] = str(r['id']) not in era_items
json.dump(d, open(J, 'w'), ensure_ascii=False, indent=1)
print(f'alchemy abilities: {len(d)}  new in Forever: {new}  reagents changed: {changed}  unchanged: {same}', file=sys.stderr)
for x in d:
    if x['status'] != 'same' and x['creates']:
        print(x['status'], '|', x['name'], '|', ', '.join(f"{r['n']}x {r['name']}{'*' if r['new'] else ''}" for r in x['reagents']))
