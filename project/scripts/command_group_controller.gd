extends Node
## CommandGroupController
##
## ТЗ §56.3 item B ("Selection becomes a named command group") / §1.10.4
## ("Выбранные объекты должны быть объединены в единую командную
## группу") / §1.10.5 (hierarchical control "должно использовать
## существующую архитектуру CommandEchelon, FormationState и
## IndividualOrder, а не создавать отдельную параллельную систему
## управления").
##
## Pure INPUT-TO-COMMAND-STRUCTURE translator, same convention as
## PlayerInput (scripts/player_input.gd): reads one discrete Input Map
## action (project.godot [input] "selection_make_group", G key, added
## this pass) and turns the CURRENT multi-selection (SelectionState,
## §56.3 item A) into REAL SimulationWorld command structure -- a
## FormationState (station-keeping) wrapped in a leaf CommandEchelon
## (§28 hierarchy; `kind` is deliberately free-form per CommandEchelon's
## own class doc, so the display NAME lives directly in `kind` -- e.g.
## "Squadron 1" -- rather than inventing a separate "group name" field
## nothing else in the architecture has) -- NOT a UI-only list of
## selected ids living only in this script. This is what lets §1.10.5's
## "если выбрана formation: корабли сохраняют formation" actually
## happen: once grouped, SimulationWorld._resolve_formation_keeping
## (already-existing code, unchanged by this pass) starts holding these
## ships at the relative positions captured at group-creation time.
##
## SCOPE (this pass only): create a NEW group from the current
## selection. Does NOT yet handle disbanding a group, merging two
## existing groups, or renaming one after creation -- item B's checklist
## line only asks for "selection becomes a named command group" plus the
## visual list (scripts/command_group_panel.gd), not full group lifecycle
## management; open follow-up, see .tools/state.md.
##
## ELIGIBILITY (ASSUMPTION, logged in ASSUMPTIONS.md "§56.3 item B"):
## only ids that are (a) real ships (`world.ships.has(id)` -- a missile
## or enemy sensor-contact id present in the selection is silently
## excluded: §1.10.4's "командная группа" is a *command* structure and
## can only ever consist of ships the player's own side actually
## commands) and (b) on the SAME team as the first eligible id in
## selection order (a mixed-team selection happens naturally under
## §1.10.4 -- e.g. selecting an own ship AND an enemy contact together to
## designate a target for item D's order menu -- and must never fold
## hostile ships into the player's own formation). Fewer than 2 eligible
## ids is a no-op: a single selected ship is already fully controllable
## via the existing IndividualOrder/PlayerInput path and gains nothing
## from a formation wrapper.
class_name CommandGroupController

var world: SimulationWorld
var selection: SelectionState

var _next_group_index: int = 1

func _unhandled_input(event: InputEvent) -> void:
	if world == null or selection == null:
		return
	if event.is_action_pressed("selection_make_group"):
		make_group_from_selection()

## Returns the new echelon_id on success, "" if the current selection was
## not eligible (see class doc). Public (not just reachable via
## _unhandled_input) so headless tests can call it directly without
## synthesizing InputEventKey presses.
func make_group_from_selection() -> String:
	var eligible: Array = _eligible_ship_ids()
	if eligible.size() < 2:
		return ""

	var guide_id: String = eligible[0]
	var guide_ship: ShipPhysicsState = world.ships.get(guide_id)
	if guide_ship == null:
		return ""

	var group_index: int = _next_group_index
	_next_group_index += 1
	var formation_id: String = "cmdgroup_%d_formation" % group_index
	var echelon_id: String = "cmdgroup_%d" % group_index

	var formation: FormationState = world.add_formation(formation_id, guide_id)
	for i in range(1, eligible.size()):
		var member_id: String = eligible[i]
		var member_ship: ShipPhysicsState = world.ships.get(member_id)
		if member_ship == null:
			continue
		# §1.10.5 "относительные позиции сохраняются": freeze whatever
		# relative position this ship happens to be at right now as its
		# station, expressed in the GUIDE's own local/body frame per
		# FormationState.member_offsets' documented convention (the
		# formation then rotates with the guide, not fixed to world
		# axes) -- same interpretation status as §56.2's distance-
		# compression convention (see ASSUMPTIONS.md).
		var offset_world: Vector3 = member_ship.position - guide_ship.position
		var offset_local: Vector3 = guide_ship.orientation.inverse() * offset_world
		formation.set_station(member_id, offset_local)

	var echelon: CommandEchelon = world.add_command_echelon(echelon_id, "Squadron %d" % group_index)
	world.attach_formation_to_echelon(echelon_id, formation_id)

	return echelon_id

## Ships eligible to be grouped from the CURRENT selection: real ships
## only, restricted to whichever team the first eligible id belongs to
## (see class doc). Preserves selection order (SelectionState's own
## documented convention) so `eligible[0]` deterministically becomes the
## guide -- FormationState itself has no opinion on WHICH member is
## guide; "first selected = leader" is this controller's own
## deterministic pick, analogous to §33's succession_order convention.
func _eligible_ship_ids() -> Array:
	var result: Array = []
	var required_team: String = ""
	for id in selection.selected_ids:
		if not world.ships.has(id):
			continue
		var team: String = String(world.teams.get(id, ""))
		if result.is_empty():
			required_team = team
		elif team != required_team:
			continue
		result.append(id)
	return result
