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
## LAYOUT (§56.3 item F "first real shared UI-panel layout pass" --
## previously an ASSUMPTION-logged fixed guess, see ASSUMPTIONS.md
## "§56.3 item B" for that original decision and "§56.3 item F" for this
## pass's change): top-left column, stacked BELOW Hud's own panel
## (scripts/hud.gd, top-left at (12,12)) using Hud's REAL current
## measured height (Hud.get_bottom_y(), added this pass) plus a fixed
## margin -- not a second hardcoded pixel guess independent of Hud's
## actual line count. main.gd passes Hud's current get_bottom_y() into
## update() below every tick (same "composition root queries a sibling's
## real size" pattern this pass also uses nowhere else yet -- WeaponPanel/
## TacticalPlot/OrderMenu occupy their own separate screen regions
## (bottom-left / top-right / full-viewport-when-open respectively) and
## do not currently stack against anything, so they are not part of this
## column and are NOT touched this pass -- see ASSUMPTIONS.md "§56.3 item
## F" for why that is still an honest, if partial, "first pass" rather
## than a claim every panel in the scene is now layout-aware of every
## other one).
class_name CommandGroupPanel

const TOP_MARGIN_PX: float = 20.0
const FALLBACK_TOP_Y: float = 360.0  # used only if update() is ever called before _ready() has run, so _label always has a position

var _label: Label

func _ready() -> void:
	_label = Label.new()
	_label.name = "CommandGroupLabel"
	_label.position = Vector2(12, FALLBACK_TOP_Y)
	_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	_label.add_theme_font_size_override("font_size", 16)
	add_child(_label)

## Call once per simulation tick (same convention as Hud.update/
## TacticalPlot.update, see main.gd._on_tick) with the world, the shared
## SelectionState (§56.3 item A) so each group's roster can mark which of
## its members are currently selected, and `hud_bottom_y` -- Hud's own
## CURRENT get_bottom_y() this same tick, from main.gd -- so this panel's
## position tracks Hud's real height instead of a stale fixed guess (see
## class doc comment above). `hud_bottom_y` defaults to FALLBACK_TOP_Y so
## existing callers/tests that only cared about `_build_text` output
## (not position) keep working unchanged.
func update(world: SimulationWorld, selection: SelectionState, hud_bottom_y: float = FALLBACK_TOP_Y) -> void:
	_label.position = Vector2(12, hud_bottom_y + TOP_MARGIN_PX)
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
