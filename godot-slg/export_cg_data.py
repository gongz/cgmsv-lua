#!/usr/bin/env python3
"""Convert CrossGate (GBK) data tables -> UTF-8 JSON for a Godot grid-SLG.
Run from repo root:  python3 godot-slg/export_cg_data.py
Outputs godot-slg/data/*.json (drop into your Godot project's res://data/).
"""
import json, os
SRC='data'; OUT='godot-slg/data'
def dec(b): return b.decode('gbk','replace')
def rows(fn):
    out=[]
    for ln in open(os.path.join(SRC,fn),'rb').read().replace(b'\r\n',b'\n').split(b'\n'):
        if not ln or ln[:1]==b'#': continue
        out.append([dec(x) for x in ln.split(b'\t')])
    return out
def I(x):
    try: return int(x)
    except: return None

# ---- skills (skill.txt, 1-based cols) ----
skills=[]
for t in rows('skill.txt'):
    if len(t)<19 or not t[0]: continue
    sid=I(t[1])
    if sid is None: continue
    skills.append({"id":sid,"name":t[0],"category":I(t[3]),"default_max_lv":I(t[4]),
        "exp_table":I(t[5]),"fp_cost":I(t[6]),"need_equip_mask":I(t[8]),
        "native_family":I(t[17]),"rate":I(t[18])})

# ---- jobs (jobs.txt: name c1, id c3, category caps c12-34) ----
jobs=[]
for t in rows('jobs.txt'):
    if len(t)<16 or not t[2]: continue
    jid=I(t[2])
    if jid is None: continue
    caps=[I(t[i]) if i<len(t) and t[i].strip() else 0 for i in range(11,34)]
    jobs.append({"id":jid,"name":t[0],"family":jid//10*10,"category_caps":caps})

# ---- items (itemset.txt) ----
items=[]
for t in rows('itemset.txt'):
    if len(t)<24: continue
    iid=I(t[11])
    if iid is None or not t[1]: continue
    stats=[I(t[i]) if i<len(t) and t[i].strip() else 0 for i in range(31,49)]
    items.append({"id":iid,"name":t[1],"type":I(t[14]),"level":I(t[23]),
        "is_equip":(I(t[18])==2),"stats":stats})

# ---- enemies (enemy.txt eid c3/baseId c4  +  enemybase.txt name c1/baseId c2/race c5) ----
base={}
for t in rows('enemybase.txt'):
    if len(t)<5 or not t[1]: continue
    bid=t[1]
    base[bid]={"name":t[0],"race":I(t[4]),"raw":t}
enemies=[]
for t in rows('enemy.txt'):
    if len(t)<4: continue
    eid=I(t[2]); bid=t[3]
    b=base.get(bid)
    if eid is None or not b: continue
    enemies.append({"enemy_id":eid,"base_id":I(bid),"name":b["name"],"race":b["race"]})

# ---- skilllv (skillId c2, jobId c3, maxLevel c4) -> {skillId:{jobId:lv}} ----
skill_levels={}
for t in rows('skilllv.txt'):
    if len(t)<4: continue
    sid,jid,lv=I(t[1]),I(t[2]),I(t[3])
    if None in (sid,jid,lv): continue
    skill_levels.setdefault(str(sid),{})[str(jid)]=lv

os.makedirs(OUT,exist_ok=True)
def dump(name,obj):
    json.dump(obj,open(os.path.join(OUT,name),'w'),ensure_ascii=False,indent=1)
    print(f"  {name}: {len(obj)} records")
print("exported:")
dump('skills.json',skills); dump('jobs.json',jobs); dump('items.json',items)
dump('enemies.json',enemies); dump('skill_levels.json',skill_levels)
