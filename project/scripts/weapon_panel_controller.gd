extends Node
## WeaponPanelController
##
## §56.3 item E ("Weapon-type selection panel for the selected ship",
## §1.10.8). Same §42 division of labor as CommandGroupController/
## MoveOrderController/OrderMenuController: PURE state + order-routing,
## no UI Control reference held (see those classes' own doc comments for
## why -- headless testability). WeaponPanel (scripts/weapon_panel.gd)
## reads `rows`/`is_visible`/`ship_id` once per tick via sync(), calling
## back into `execute_row(kind)` when the player clicks a row -- same
## one-kind-per-row model as OrderMenuController.execute(kind).
##
## VISIBILITY RULE (ASSUMPTION, logged in ASSUMPTIONS.md "§56.3 item E"):
## shown only when the CURRENT selection is EXACTLY ONE ship, and that
## ship belongs to `player_team` -- a multi-ship group selection has no
## single "selected ship's mounted weapons" to show (§1.10.8's own text
## is written in terms of "the selected ship", singular), and a hostile
## contact's own loadout is never shown to the player (no ground-truth
## leak). Selecting a group, an empty selection, or a hostile contact all
## hide the panel entirely -- a strict yes/no gate, not a "pick one ship
## out of the group" sub-interaction (that would be a real new UI feature
## beyond this item's own text).
##
## HARD REQUIREMENT (§1.10.8: "Нельзя показывать игроку оружие, которого
## у корабля нет"): every row this class ever builds reads directly from
## `world.weapon_mounts[ship_id]`/`world.missile_tubes[ship_id]`/
## `world.pd_mounts[ship_id]` -- never a hardcoded weapon list. A ship
## with none of a given mount type simply gets no section for it (see
## _build_rows), exactly like OrderMenuController honestly omits
## DEFEND/COVER/FOLLOW/INTERCEPT rather than showing a dead button.
##
## HONEST GAPS (checked first, logged here and in ASSUMPTIONS.md "§56.3
## item E", same discipline as items C/D):
##  - MISSILES "missile type" selection: not implemented -- MissileTube
##    (simulation/missile_tube.gd) has no "type" field at all, and no
##    ship in this codebase is ever loaded with more than one tube type,
##    so there is nothing distinct to choose between yet.
##  - COUNTER-MISSILES (AUTO/MANUAL DESIGNATION/HOLD): NOT shown at all,
##    not even a disabled row -- there is no automatic counter-missile
##    LAUNCH decision anywhere in simulation/*.gd (grep-confirmed before
##    writing this class). Every counter-missile in this codebase today
##    is a MissileState manually constructed with target = an incoming
##    missile (see counter_missile_resolution.gd's own class doc and its
##    test file) -- CounterMissileResolution only ever RESOLVES an
##    already-flying counter-missile's intercept, it never decides to
##    launch one. A real AUTO/MANUAL/HOLD policy needs that launch-
##    decision mechanic to exist first; that is a new combat-AI feature,
##    not a UI/routing change (§56.3 item E's own checklist text: "map
##    onto what exists, log clearly whatever doesn't"). A menu entry with
##    nothing behind it would be worse than an honest omission (the same
##    reasoning OrderMenuController's own doc comment gives for
##    DEFEND/COVER/FOLLOW/INTERCEPT).
##  - POINT DEFENSE "priority-target" designation: not implemented --
##    TacticalAI.select_pd_target only supports automatic nearest-usable-
##    contact selection, with no override parameter to route a
##    commander's choice through. AUTO/HOLD (this pass's real addition,
##    via world.ship_pd_hold/set_ship_pd_hold/transmit_ship_pd_hold,
##    checked by SimulationWorld._resolve_point_defense) IS implemented
##    and wired end to end.
class_name WeaponPanelController

const AttackGeometry = preload("res://simulation/attack_geometry.gd")
const WeaponData = preload("res://simulation/weapon_data.gd")

var world: SimulationWorld
var selection: SelectionState
var player_team: String = ""

## §1.10.8 MISSILES "salvo size": how many of the selected ship's ready
## tubes FIRE actually launches from this call, capped to
## [1, tube_count] -- see SimulationWorld.order_missile_launch's own doc
## comment for how this reaches the simulation. Persisted per ship_id
## (not just "the current selection") so switching selection away and
## back does not silently reset the player's last choice for that ship.
var _salvo_size_by_ship: Dictionary = {}   # ship_id -> int

## §1.10.8 MISSILES "throttle/profile if available" -- IS available
## (MissileState.set_throttle(), see order_missile_launch's own doc
## comment on this pass's extension of it): two named presets rather
## than a continuous slider -- no continuous-value UI widget exists
## anywhere in this codebase yet (same "plain hand-drawn Control, no
## popup-menu/slider widget" convention as order_menu.gd), same
## per-ship persistence as salvo size.
const THROTTLE_FULL_BURN: float = 1.0
const THROTTLE_EXTENDED_RANGE: float = 0.5
var _throttle_by_ship: Dictionary = {}   # ship_id -> float

## Read once per tick by WeaponPanel.sync() -- see class doc comment.
var is_visible: bool = false
var ship_id: String = ""
var rows: Array = []  # Array[{"label": String, "kind": String}], "" kind = not clickable (header/info row)

func sync() -> void:
	if world == null or selection == null:
		_hide()
		return
	var id: String = _single_selected_own_ship()
	if id == "":
		_hide()
		return
	ship_id = id
	is_visible = true
	rows = _build_rows(id)

func _hide() -> void:
	is_visible = false
	ship_id = ""
	rows = []

## Called by WeaponPanel when the player clicks a row. Rows built with
## kind "" (headers/info, e.g. the mounted-weapon list itself or the
## current target readout) are inert -- clicking them does nothing, same
## as clicking outside every row.
func execute_row(kind: String) -> void:
	if world == null or ship_id == "" or kind == "":
		return
	match kind:
		"SALVO_CYCLE":
			_cycle_salvo()
		"THROTTLE_CYCLE":
			_cycle_throttle()
		"FIRE_MISSILES":
			_fire_missiles()
		"PD_TOGGLE":
			_toggle_pd_hold()
	# Rebuild immediately so the panel reflects the new state the same
	# tick, rather than waiting for the next scheduled sync() call.
	rows = _build_rows(ship_id)

func _single_selected_own_ship() -> String:
	if selection.selected_ids.size() != 1:
		return ""
	var id: String = selection.selected_ids[0]
	if not world.ships.has(id):
		return ""
	if String(world.teams.get(id, "")) != player_team:
		return ""
	return id

func _ready_tube_count(tubes: Array) -> int:
	var ready: int = 0
	for tube in tubes:
		if tube.is_ready():
			ready += 1
	return ready

func _cycle_salvo() -> void:
	var tubes: Array = world.missile_tubes.get(ship_id, [])
	var max_size: int = maxi(1, tubes.size())
	var current: int = int(_salvo_size_by_ship.get(ship_id, 1))
	_salvo_size_by_ship[ship_id] = (current % max_size) + 1

func _cycle_throttle() -> void:
	var current: float = float(_throttle_by_ship.get(ship_id, THROTTLE_FULL_BURN))
	_throttle_by_ship[ship_id] = THROTTLE_EXTENDED_RANGE if current >= THROTTLE_FULL_BURN else THROTTLE_FULL_BURN

## §1.10.8 MISSILES "target": reuses the SAME `SelectionState.
## designated_target_id` §56.3 item D's order menu already uses for "the
## target half" of an interaction (see that field's own doc comment) --
## no second target concept invented for this panel. Empty means "no
## designation", in which case FIRE falls back to order_missile_launch's
## own standing-target resolution (empty target_ship_id argument -- see
## that func's doc comment): "fire at whoever I'd normally be engaging",
## exactly like the order menu's own ATTACK/APPROACH entries already
## rely on shared state rather than a second target concept.
func _fire_missiles() -> void:
	var tubes: Array = world.missile_tubes.get(ship_id, [])
	if tubes.is_empty():
		return
	var salvo_size: int = clampi(int(_salvo_size_by_ship.get(ship_id, 1)), 1, maxi(1, tubes.size()))
	var throttle: float = float(_throttle_by_ship.get(ship_id, THROTTLE_FULL_BURN))
	var target_id: String = ""
	if selection != null and selection.has_designated_target():
		target_id = selection.designated_target_id
	world.order_missile_launch(ship_id, target_id, salvo_size, throttle)

func _toggle_pd_hold() -> void:
	var is_held: bool = bool(world.ship_pd_hold.get(ship_id, false))
	world.transmit_ship_pd_hold(ship_id, not is_held)

func _weapon_class_label(weapon) -> String:
	if weapon == null:
		return "unknown"
	if not String(weapon.display_name).is_empty():
		return weapon.display_name
	match weapon.weapon_class:
		WeaponData.WeaponClass.ENERGY_LASER:
			return "laser"
		WeaponData.WeaponClass.ENERGY_GRASER:
			return "graser"
		_:
			return weapon.id if not String(weapon.id).is_empty() else "energy weapon"

func _arc_label(arc_sectors: Array) -> String:
	if arc_sectors.is_empty():
		return "omnidirectional"
	var names: Array = []
	for sector in arc_sectors:
		match sector:
			AttackGeometry.Sector.BOW:
				names.append("bow")
			AttackGeometry.Sector.STERN:
				names.append("stern")
			AttackGeometry.Sector.PORT:
				names.append("port")
			AttackGeometry.Sector.STARBOARD:
				names.append("starboard")
			AttackGeometry.Sector.TOP:
				names.append("top")
			AttackGeometry.Sector.BOTTOM:
				names.append("bottom")
	var label: String = ""
	for i in range(names.size()):
		label += names[i]
		if i < names.size() - 1:
			label += "/"
	return label

## §1.10.8's sections, each honestly present only when `ship_id` actually
## has the relevant mount(s) -- see class doc comment's HARD REQUIREMENT.
## COUNTER-MISSILES is never built at all -- see class doc comment's
## HONEST GAPS.
func _build_rows(for_ship_id: String) -> Array:
	var result: Array = []

	var mounts: Array = world.weapon_mounts.get(for_ship_id, [])
	if not mounts.is_empty():
		result.append({"label": "-- ENERGY WEAPONS --", "kind": ""})
		for mount in mounts:
			var status: String = "ready" if mount.is_ready() else "cooling down"
			result.append({"label": "  %s (%s arc) -- %s" % [_weapon_class_label(mount.weapon), _arc_label(mount.arc_sectors), status], "kind": ""})

	var tubes: Array = world.missile_tubes.get(for_ship_id, [])
	if not tubes.is_empty():
		var ready: int = _ready_tube_count(tubes)
		var salvo_size: int = clampi(int(_salvo_size_by_ship.get(for_ship_id, 1)), 1, maxi(1, tubes.size()))
		_salvo_size_by_ship[for_ship_id] = salvo_size
		var throttle: float = float(_throttle_by_ship.get(for_ship_id, THROTTLE_FULL_BURN))
		var throttle_label: String = "FULL BURN" if throttle >= THROTTLE_FULL_BURN else "EXTENDED RANGE"
		var target_label: String = "auto (standing target)"
		if selection != null and selection.has_designated_target():
			target_label = selection.designated_target_id
		result.append({"label": "-- MISSILES (%d/%d tubes ready) --" % [ready, tubes.size()], "kind": ""})
		result.append({"label": "  salvo size: %d (click to cycle)" % salvo_size, "kind": "SALVO_CYCLE"})
		result.append({"label": "  profile: %s (click to cycle)" % throttle_label, "kind": "THROTTLE_CYCLE"})
		result.append({"label": "  target: %s" % target_label, "kind": ""})
		result.append({"label": "  [ FIRE MISSILES ]", "kind": "FIRE_MISSILES"})

	var pd: Array = world.pd_mounts.get(for_ship_id, [])
	if not pd.is_empty():
		var is_held: bool = bool(world.ship_pd_hold.get(for_ship_id, false))
		result.append({"label": "-- POINT DEFENSE: %s (click to toggle) --" % ("HOLD" if is_held else "AUTO"), "kind": "PD_TOGGLE"})

	return result
