extends RefCounted
## ShipStatus
##
## 2026-09-27 (user: "drop the HP bar, show module damage as the spec
## says" -- AGENTS.md §25.1): the ONE place that turns a ship's modules
## (ShipSubsystems) into what the player reads -- a short combat-capability
## verdict ("боеспособен" / "без хода" / "обезоружен" / ...) and per-module
## names/colours. No aggregate health number anywhere.
class_name ShipStatus

const SubsystemType = preload("res://simulation/subsystem_type.gd")
const UiTheme = preload("res://scripts/ui_theme.gd")

## Display order + short labels for the module grid.
const MODULES: Array = [
	["PROPULSION", "ДВИГ", "импеллеры"], ["MANEUVERING", "МАНЁВР", "маневровые"],
	["POWER", "ЭНЕРГ", "реактор"], ["STRUCTURAL_INTEGRITY", "КОРПУС", "корпус"],
	["SENSORS", "СЕНС", "сенсоры"], ["COMMUNICATIONS", "СВЯЗЬ", "связь"],
	["WEAPONS", "ОРУД", "орудия"], ["MISSILE_SYSTEMS", "РАКЕТ", "ракетные трубы"],
	["POINT_DEFENSE", "ПРО", "ПРО"], ["COUNTER_MISSILE_SYSTEMS", "ПРТР", "противоракеты"],
	["DEFENSIVE_SYSTEMS", "СТЕНЫ", "бортовые стены"],
]
const DISABLED_COLOR := Color(0.45, 0.45, 0.45)

static func type_of(key: String) -> int:
	return SubsystemType.Type[key]

static func long_name(type_value: int) -> String:
	var key: String = SubsystemType.Type.keys()[type_value]
	for m in MODULES:
		if m[0] == key:
			return m[2]
	return key

static func module_color(cond: float) -> Color:
	if cond <= 0.0:
		return DISABLED_COLOR
	return UiTheme.condition_color(cond)

## {"text": String, "color": Color} -- the verdict for labels/cards.
## Mirrors SimulationWorld.CRITICAL_HULL_FRACTION -- the threshold at
## which _resolve_weapons_ai/_resolve_missile_launch_ai treat a ship as
## "disengaging" and silence BOTH its energy weapons and missile tubes
## entirely (see that const's own doc comment), regardless of whether any
## individual weapon module is itself still intact. Kept as a local
## literal (not a cross-file reference) per this codebase's existing
## small-constant convention -- see UiTheme.ACCENT_COLOR's own doc.
const DISENGAGE_HULL_FRACTION: float = 0.3

static func verdict(world: SimulationWorld, sid: String) -> Dictionary:
	var ship = world.ships.get(sid)
	if ship == null or ship.is_wreck:
		return {"text": "УНИЧТОЖЕН", "color": DISABLED_COLOR}
	var subs = ship.subsystems
	if subs == null:
		return {"text": "", "color": UiTheme.ACCENT_COLOR}
	var T = SubsystemType.Type
	# 2026-09-28 (user: "посмотри, почему иногда корабли могут прекратить
	# стрелять"): checked FIRST and takes priority over every other
	# verdict below -- a ship can be sitting on 100% weapons/missiles and
	# still be completely silent this instant because the hull itself
	# crossed 30%, which is a DIFFERENT condition than any one module
	# being knocked out. Without this check the card could say
	# "боеспособен" for a ship that has, in fact, gone quiet and turned
	# to run -- confusing, looked like a bug. See CHANGELOG.md this date.
	if subs.get_condition(T.STRUCTURAL_INTEGRITY) <= DISENGAGE_HULL_FRACTION:
		return {"text": "ОТСТУПАЕТ — критические повреждения корпуса", "color": UiTheme.CONDITION_CRITICAL_COLOR}
	if subs.is_disabled(T.POWER):
		return {"text": "без энергии", "color": UiTheme.CONDITION_CRITICAL_COLOR}
	if subs.is_disabled(T.WEAPONS) and subs.is_disabled(T.MISSILE_SYSTEMS):
		return {"text": "обезоружен", "color": UiTheme.CONDITION_CRITICAL_COLOR}
	if subs.is_disabled(T.PROPULSION):
		return {"text": "без хода", "color": UiTheme.CONDITION_CRITICAL_COLOR}
	var lost: Array = []
	var worst: float = 1.0
	for m in MODULES:
		var c: float = subs.get_condition(type_of(m[0]))
		worst = minf(worst, c)
		if c <= 0.0:
			lost.append(m[2])
	if not lost.is_empty():
		return {"text": "выбито: " + ", ".join(lost), "color": UiTheme.CONDITION_WARN_COLOR}
	if worst < 0.995:
		return {"text": "повреждения", "color": UiTheme.CONDITION_WARN_COLOR if worst < 0.66 else UiTheme.CONDITION_GOOD_COLOR}
	return {"text": "боеспособен", "color": UiTheme.CONDITION_GOOD_COLOR}


## Enemy ships: only what our sensors could plausibly see from outside
## (§26 "no cheat vision"): venting/debris, lost drive, dead emissions --
## a coarse verdict, never their internal module list.
static func verdict_observed(world: SimulationWorld, sid: String) -> Dictionary:
	var ship = world.ships.get(sid)
	if ship == null or ship.is_wreck:
		return {"text": "уничтожен", "color": DISABLED_COLOR}
	var subs = ship.subsystems
	if subs == null:
		return {"text": "", "color": UiTheme.ACCENT_COLOR}
	var T = SubsystemType.Type
	# Sensor-honest, not cheat vision: a disengaging ship visibly stops
	# firing and turns away -- this is externally observable behavior,
	# not a peek at its internal module list.
	if subs.get_condition(T.STRUCTURAL_INTEGRITY) <= DISENGAGE_HULL_FRACTION:
		return {"text": "выходит из боя", "color": UiTheme.CONDITION_CRITICAL_COLOR}
	if subs.is_disabled(T.POWER):
		return {"text": "без признаков энергии", "color": UiTheme.CONDITION_CRITICAL_COLOR}
	if subs.is_disabled(T.PROPULSION):
		return {"text": "клин погас", "color": UiTheme.CONDITION_CRITICAL_COLOR}
	var lost: int = 0
	var worst: float = 1.0
	for m in MODULES:
		var c: float = subs.get_condition(type_of(m[0]))
		worst = minf(worst, c)
		if c <= 0.0:
			lost += 1
	if lost >= 3 or worst < 0.33:
		return {"text": "тяжёлые повреждения", "color": UiTheme.CONDITION_CRITICAL_COLOR}
	if worst < 0.995:
		return {"text": "есть попадания", "color": UiTheme.CONDITION_WARN_COLOR}
	return {"text": "без видимых повреждений", "color": UiTheme.CONDITION_GOOD_COLOR}
