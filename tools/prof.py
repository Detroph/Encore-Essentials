import csv, sys, json, collections
W = sys.argv[1]; SKILL = int(sys.argv[2])
def rows(t): return csv.DictReader(open(f"{W}/{t}.csv", newline='', encoding='utf-8'))
sl = {r['ID']: r for r in rows('SkillLine')}
print('skill:', sl.get(str(SKILL), {}).get('DisplayName_lang'), file=sys.stderr)
sla = [r for r in rows('SkillLineAbility') if r['SkillLine'] == str(SKILL)]
spells = {r['Spell'] for r in sla}
names = {r['ID']: r['Name_lang'] for r in rows('SpellName')}
reag = {}
for r in rows('SpellReagents'):
    if r['SpellID'] in spells:
        reag[r['SpellID']] = [(r[f'Reagent_{i}'], int(r[f'ReagentCount_{i}'])) for i in range(8) if r[f'Reagent_{i}'] not in ('0', '')]
create, learn = {}, collections.defaultdict(list)
for r in rows('SpellEffect'):
    if r['SpellID'] in spells and r['Effect'] == '24':
        create[r['SpellID']] = (r['EffectItemType'], r.get('EffectBasePointsF', r.get('EffectBasePoints','1')))
    if r['Effect'] == '36' and r['EffectTriggerSpell'] in spells:
        learn[r['SpellID']].append(r['EffectTriggerSpell'])
eff = {r['ID']: r['SpellID'] for r in rows('ItemEffect')}
teach = collections.defaultdict(list)
for r in rows('ItemXItemEffect'):
    s = eff.get(r['ItemEffectID']); item = r['ItemID']
    if s is None: continue
    if s in spells: teach[s].append(item)
    for t in learn.get(s, []): teach[t].append(item)
need = set()
for v in reag.values(): need |= {i for i, _ in v}
for v in create.values(): need.add(v[0])
for v in teach.values(): need |= set(v)
items = {}
for r in rows('ItemSparse'):
    if r['ID'] in need: items[r['ID']] = (r['Display_lang'], int(r['OverallQualityID']))
out = []
for r in sorted(sla, key=lambda r: (int(r['MinSkillLineRank']), names.get(r['Spell'], ''))):
    s = r['Spell']
    out.append({
        'spell': int(s), 'name': names.get(s, '?'), 'min': int(r['MinSkillLineRank']),
        'yellow': int(r['TrivialSkillLineRankLow']), 'grey': int(r['TrivialSkillLineRankHigh']),
        'acquire': int(r['AcquireMethod']),
        'creates': create.get(s) and {'id': int(create[s][0]), 'name': items.get(create[s][0], ('?', 1))[0], 'q': items.get(create[s][0], ('?', 1))[1]},
        'reagents': [{'id': int(i), 'n': c, 'name': items.get(i, ('?', 1))[0], 'q': items.get(i, ('?', 1))[1]} for i, c in reag.get(s, [])],
        'recipeItems': [{'id': int(i), 'name': items.get(i, ('?', 1))[0], 'q': items.get(i, ('?', 1))[1]} for i in sorted(set(teach.get(s, [])))],
    })
json.dump(out, sys.stdout, ensure_ascii=False, indent=1)
