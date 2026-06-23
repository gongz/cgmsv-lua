class_name UnitData extends Resource
## A combat unit (player or enemy), built from CG stat fields.
@export var id: int
@export var unit_name: String
@export var job_id: int = 0
@export var max_hp: int = 100
@export var atk: int = 0       # 对象_攻击力
@export var def: int = 0       # 对象_防御力
@export var matk: int = 0      # 对象_魔法攻击力
@export var mdef: int = 0      # 对象_魔法防御力
@export var hit: int = 0       # 对象_命中
@export var agi: int = 0       # 对象_敏捷  (avoid + turn order)
@export var counter: int = 0   # 对象_反击
@export var crit_pct: int = 5  # 暴击 %
@export_range(0,100) var earth := 0  # 地
@export_range(0,100) var water := 0  # 水
@export_range(0,100) var fire := 0   # 火
@export_range(0,100) var wind := 0   # 风
@export var move_range := 4           # SLG: grid movement (NEW, not from CG)
@export var skills: Array[int] = []
