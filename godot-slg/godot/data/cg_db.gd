extends Node
## Autoload singleton. Loads the exported CG JSON (res://data/*.json).
## Add to Project Settings > Autoload as "CGDB".
var skills := {}        # id -> record
var jobs := {}          # id -> record
var items := {}         # id -> record
var enemies := {}       # enemy_id -> record
var skill_levels := {}  # str(skillId) -> { str(jobId): maxLevel }

func _ready() -> void:
	skills  = _index("res://data/skills.json", "id")
	jobs    = _index("res://data/jobs.json", "id")
	items   = _index("res://data/items.json", "id")
	enemies = _index("res://data/enemies.json", "enemy_id")
	var f := FileAccess.open("res://data/skill_levels.json", FileAccess.READ)
	skill_levels = JSON.parse_string(f.get_as_text())

func _index(path: String, key: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	var arr: Array = JSON.parse_string(f.get_as_text())
	var d := {}
	for r in arr:
		d[int(r[key])] = r
	return d

## CG rule reuse: per-(skill, job) level cap from skilllv.txt. 0 = can't use.
func max_skill_level(skill_id: int, job_id: int) -> int:
	var m: Dictionary = skill_levels.get(str(skill_id), {})
	return int(m.get(str(job_id), 0))

## CG rule reuse: native-family proficiency bonus (SKILL_JOBS + SKILL_RATE).
func skill_rate_for_job(skill_id: int, job_id: int) -> int:
	var s: Dictionary = skills.get(skill_id, {})
	var fam: int = s.get("native_family", -1)
	return int(s.get("rate", 100)) if (job_id / 10 * 10) == fam else 100
