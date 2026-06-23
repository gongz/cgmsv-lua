# CrossGate → Godot grid-tactics SLG

Reuse CrossGate's **content + decoded rules** to build a grid tactics game (Fire
Emblem / Tactics-style) in Godot 4. The CG C engine is **not** reused — only its
data tables and the combat rules reverse-engineered from `cgmsv.exe`.

## What's here
- `export_cg_data.py` — converts the GBK `data/*.txt` tables → UTF-8 JSON.
  Run from the repo root: `python3 godot-slg/export_cg_data.py`
  → writes `godot-slg/data/{skills,jobs,items,enemies,skill_levels}.json`
  (167 skills, 324 jobs, 8757 items, 4433 enemies).
- `godot/data/cg_db.gd` — Godot autoload that loads the JSON and exposes CG rules
  (`max_skill_level(skill,job)` from skilllv; `skill_rate_for_job` proficiency bonus).
- `godot/data/unit_data.gd` — `UnitData` resource mirroring CG combat stats.
- `godot/combat/formula.gd` — CG-grounded damage / hit / crit / element / turn-order.

Copy `godot-slg/data/*.json` into your Godot project's `res://data/`, add
`cg_db.gd` as an autoload named `CGDB`, and you can immediately query content.

## Three reuse tiers
| tier | what | effort |
|------|------|--------|
| 🟢 content & rules | skills, items, jobs, enemies, exp curves, recipes, per-(skill,job) levels, proficiency, weapon gating | done — it's data |
| 🟡 combat formulas | damage/hit/crit/element. Structure recovered from CG (`攻击力/防御力`, `Battle.CalcAttributeDmgRate`); exact constants tunable or RE'd later | medium |
| 🔴 SLG layer | grid, movement, terrain, range, facing — **CG has none of this**; new Godot work | new design |

## Combat model (from CG)
CG stores derived stats per unit: `攻击力` ATK, `防御力` DEF, `魔法攻击力/防御力`
MATK/MDEF, `命中` hit, `敏捷` agility (avoid + turn order), `反击` counter, crit,
plus 4 elements 地水火风. `formula.gd` implements:
`damage = max(1, ATK*2 - DEF) * power% * elementRate * variance`, crit ×1.5,
elemental rate from attacker-vs-defender element. Constants live in one place so
you can drop in exact CG coefficients if you reverse-engineer them later.

## Architecture (Godot 4)
- **Data**: JSON → `CGDB` autoload → `UnitData`/`SkillData` resources.
- **Map**: `TileMapLayer` grid; `AStarGrid2D` for movement/pathing.
- **Turn system**: state machine (SelectUnit → Move → Action → ResolveResolve),
  initiative order by `敏捷` via `Combat.sort_by_speed`.
- **Combat**: `Combat` static funcs; UI reads results.
- **AI**: start scripted (nearest-target), later port `enemyai.txt`.

## Roadmap
1. **Vertical slice** — one map, 3 player units vs 3 enemies, move + attack on a
   grid using `formula.gd`. Proves the loop.
2. **Skills** — load `skills.json`, range/AoE templates, FP cost, `max_skill_level` gate.
3. **Progression** — jobs/exp curves, skill learning, equipment from `items.json`.
4. **Content pass** — enemy roster, recipes, maps; tune combat constants.
5. **(optional)** RE exact CG damage constants and swap into `formula.gd`.

## Practicality
The content + decoded systems (the bulk of an RPG) port directly. The combat
*engine* is rebuilt regardless, and the grid/tactics layer is new — but Godot is
well suited (tilemaps, built-in A*, resources). Biggest unknown was the damage
formula; its structure is now known, with a working tunable implementation.
