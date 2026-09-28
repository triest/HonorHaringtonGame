extends RefCounted
## ShipClasses
##
## 2026-09-28 (user: "сделай редактор миссий, чтобы можно было выбирать
## соотношение и типы кораблей сторон"): a small, DEMO-SCALE set of ship
## classes for the Mission Editor to mix and match, distinct from the
## separate capital-ship ShipClassData/ShipFactory system (data/ships/
## *.tres) -- that system's canon-sourced loadouts (26-46 missile tubes,
## dozens of energy mounts, per AGENTS.md §8.4) are the wrong scale for
## this squadron-vs-squadron demo (see .tools/state.md's own note on why
## item H didn't switch to it). These four classes are ENGINEERING/
## PACING placeholders (ASSUMPTION, see ASSUMPTIONS.md), tuned around the
## exact numbers scripts/demo_scenario.gd already used for its one fixed
## "heavy cruiser" loadout -- HEAVY_CRUISER below reproduces that baseline
## exactly, so the default 4x4 mission is numerically unchanged.
##
## Only what varies by class lives here: missile armament, point defense,
## energy mounts, and maneuvering (mass/thrust/turn rate). Detection,
## missile flight performance, laserhead terminal behavior, sidewall
## penetration and combat attitude stay scenario-wide constants in
## demo_scenario.gd -- per-class tuning of those isn't part of this pass.
class_name ShipClasses

## Canonical order for UI listings (lightest to heaviest).
const ORDER: Array = ["destroyer", "light_cruiser", "heavy_cruiser", "battlecruiser", "dreadnought", "superdreadnought"]

const CLASSES: Dictionary = {
	"destroyer": {
		"label": "эсминец",
		"tubes": 2, "rounds_per_tube": 30, "reload_s": 15.0,
		"pd_mounts": 2,
		"energy_broadside": 1, "energy_bow": 0,
		"mass_kg": 4.0e8, "max_thrust_n": 3.0e11, "max_angular_speed_rad_s": 0.5,
	},
	"light_cruiser": {
		"label": "лёгкий крейсер",
		"tubes": 3, "rounds_per_tube": 35, "reload_s": 18.0,
		"pd_mounts": 2,
		"energy_broadside": 1, "energy_bow": 1,
		"mass_kg": 7.0e8, "max_thrust_n": 4.0e11, "max_angular_speed_rad_s": 0.4,
	},
	"heavy_cruiser": {
		"label": "тяжёлый крейсер",
		"tubes": 4, "rounds_per_tube": 40, "reload_s": 20.0,
		"pd_mounts": 3,
		"energy_broadside": 1, "energy_bow": 1,
		# ShipPhysicsState's own defaults -- kept identical (not just
		# numerically equal) to the pre-editor baseline.
		"mass_kg": 1.0e9, "max_thrust_n": 5.0e11, "max_angular_speed_rad_s": 0.3,
	},
	"battlecruiser": {
		"label": "линейный крейсер",
		"tubes": 6, "rounds_per_tube": 45, "reload_s": 22.0,
		"pd_mounts": 4,
		"energy_broadside": 2, "energy_bow": 1,
		"mass_kg": 1.6e9, "max_thrust_n": 7.0e11, "max_angular_speed_rad_s": 0.22,
	},
	"dreadnought": {
		"label": "дредноут",
		"tubes": 8, "rounds_per_tube": 50, "reload_s": 24.0,
		"pd_mounts": 5,
		"energy_broadside": 2, "energy_bow": 2,
		"mass_kg": 2.4e9, "max_thrust_n": 9.5e11, "max_angular_speed_rad_s": 0.16,
	},
	"superdreadnought": {
		"label": "супердредноут",
		"tubes": 10, "rounds_per_tube": 55, "reload_s": 26.0,
		"pd_mounts": 6,
		"energy_broadside": 3, "energy_bow": 2,
		"mass_kg": 3.5e9, "max_thrust_n": 1.3e12, "max_angular_speed_rad_s": 0.12,
	},
}

## Invented names only (AGENTS.md's own §8.3 -- individual-ship names are
## out of scope for canon sourcing -- and no book character/ship name is
## reused here either way). Manticore = the player's Royal Manticoran Navy
## ("КЕВ", His/Her Majesty's Ship); Haven = the People's Navy raider force
## ("НФ"). Pools sized generously past the editor's own per-side cap so a
## full 8-ship side never repeats a name.
const NAME_POOLS: Dictionary = {
	"red": {"prefix": "КЕВ", "names": ["Непреклонный", "Отважный", "Стойкий", "Бдительный", "Решительный", "Доблестный", "Верный", "Грозный", "Смелый", "Гордый"]},
	"blue": {"prefix": "НФ", "names": ["Кондотьер", "Гладиус", "Центурион", "Гренадер", "Легион", "Штандарт", "Авангард", "Бастион", "Сокрушитель", "Возмездие"]},
}

const DEFAULT_PER_SIDE_COUNT: int = 4
const MIN_PER_SIDE_COUNT: int = 1
const MAX_PER_SIDE_COUNT: int = 8

static func label(class_id: String) -> String:
	return String(CLASSES.get(class_id, {}).get("label", class_id))

## Names + prefix for `count` ships of `team` ("red"/"blue"), stable order.
static func names_for(team: String, count: int) -> Array:
	var pool: Dictionary = NAME_POOLS.get(team, NAME_POOLS["red"])
	var out: Array = []
	var names: Array = pool["names"]
	for i in range(count):
		out.append("%s «%s»" % [pool["prefix"], names[i % names.size()]])
	return out

## The pre-editor fixed scenario, expressed as a setup: 4 heavy cruisers a
## side. DemoScenario.build(world) with no `setup` argument uses exactly
## this, so every existing headless caller (probes, tests) is unaffected.
static func default_setup() -> Dictionary:
	return {
		"red": [{"class_id": "heavy_cruiser", "count": DEFAULT_PER_SIDE_COUNT}],
		"blue": [{"class_id": "heavy_cruiser", "count": DEFAULT_PER_SIDE_COUNT}],
	}

## Flattens a setup side (Array[{class_id, count}]) into one class_id per
## ship, in order -- what DemoScenario actually iterates to build ships.
static func flatten_side(side_setup: Array) -> Array:
	var out: Array = []
	for entry in side_setup:
		var cid: String = String(entry.get("class_id", "heavy_cruiser"))
		if not CLASSES.has(cid):
			cid = "heavy_cruiser"
		for _i in range(int(entry.get("count", 0))):
			out.append(cid)
	return out

static func side_total(side_setup: Array) -> int:
	var n: int = 0
	for entry in side_setup:
		n += int(entry.get("count", 0))
	return n

## Sums a numeric field (e.g. "tubes") across a side's ships -- used by
## the editor's live summary line.
static func side_stat_sum(side_setup: Array, field: String) -> int:
	var n: int = 0
	for entry in side_setup:
		var cid: String = String(entry.get("class_id", "heavy_cruiser"))
		n += int(CLASSES.get(cid, {}).get(field, 0)) * int(entry.get("count", 0))
	return n
