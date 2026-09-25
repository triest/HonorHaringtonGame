extends CanvasLayer
## CommandGroupPanel
##
## ТЗ §56.3 item B ("named command group... visual list, e.g. left-side
## panel like the reference image's squadron list", docs/reference/
## tactical_command_ui_reference.png): pure TEXT readout of already-
## existing SimulationWorld command structure (§42 convention, same as
## Hud/WeaponFx/TacticalPlot -- this class computes nothing itself, it
## only formats `world.command_echelons`/`world.formations`, which
## CommandGroupController (scripts/command_group_controller.gd) is what
## actually WRITES when the player presses the group hotkey, G).
##
## LAYOUT (ASSUMPTION, logged in ASSUMPTIONS.md "§56.3 item B"): fixed
## top-left position offset well below Hud's own panel (scripts/hud.gd,
## also top-left at (12,12)), NOT the reference image's literal
## side-by-side "squadron list beside/above the tactical plot" geometry
## -- Hud's per-ship subsystem/contacts readout has a variable line
## count, so a real non-overlapping multi-panel layout needs a shared
## layout pass across Hud/TacticalPlot/this file, which belongs with
## item F's command-camera/view-split work, not item B alone. This is an
## interim placement that makes the group list visible and readable, not
## a claim it matches the reference image's exact geometry yet.
class_name CommandGroupPanel

const PANEL_POSITION := Vector2(12, 360)

var _label: Label

func _ready() -> void:
	_label = Label.new()
	_label.name = "CommandGroupLabel"
	_label.position = PANEL_POSITION
	_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	_label.add_theme_font_size_override("font_size", 16)
	add_child(_label)

## Call once per simulation tick (same convention as Hud.update/
## TacticalPlot.update, see main.gd._on_tick) with the world and the
## shared SelectionState (§56.3 item A) so each group's roster can mark
## which of its members are currently selected.
func update(world: SimulationWorld, selection: SelectionState) -> void:
	_label.text = _build_text(world, selection)

func _build_text(world: SimulationWorld, selection: SelectionState) -> String:
	var lines: Array = []
	lines.append("-- COMMAND GROUPS (G to group selection) --")

	var echelon_ids: Array = world.command_echelons.keys()
	var any_leaf: bool = false
	for echelon_id in echelon_ids:
		var echelon: CommandEchelon = world.command_echelons[echelon_id]
		# §56.3 item B only surfaces leaf squadrons (a group the player
		# actually created) this pass; internal Fleet/Task Force nodes
		# with no commanded formation of their own are §28-hierarchy
		# scope beyond item B and have nothing ship-level to list here.
		if not echelon.is_leaf():
			continue
		any_leaf = true

		var formation: FormationState = world.formations.get(echelon.commanded_formation_id)
		lines.append("[%s]" % echelon.kind)
		if formation == null:
			lines.append("  (formation missing)")
			continue

		var member_ids: Array = [formation.guide_ship_id]
		member_ids.append_array(formation.member_ids())
		for member_id in member_ids:
			var marker: String = "> " if (selection != null and selection.is_selected(member_id)) else "  "
			var role: String = " (guide)" if member_id == formation.guide_ship_id else ""
			lines.append("%s%s%s" % [marker, member_id, role])

	if not any_leaf:
		lines.append("(none -- select 2+ own ships, press G)")

	var text: String = ""
	for i in range(lines.size()):
		text += lines[i]
		if i < lines.size() - 1:
			text += "\n"
	return text
