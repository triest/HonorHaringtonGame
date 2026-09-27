extends RefCounted
## UiTheme
##
## §56.3 item J (visual polish pass, see .tools/state.md / AGENTS.md §56.3):
## a small shared style helper so panels this pass and later J sub-passes
## touch (Hud first, this pass; CommandGroupPanel/OrderMenu/WeaponPanel/
## TacticalPlot's own chrome are explicitly left for later sub-passes -- see
## state.md's own "pick ONE concrete sub-piece... expect multiple passes"
## plan, item J's checklist entry in state.md) draw from one consistent
## palette/stylebox recipe instead of each hand-rolling its own colors --
## the point of docs/reference/tactical_command_ui_reference.png is a
## single coherent "HUD glass panel" visual system, not a patchwork of
## independently-styled debug overlays. Pure cosmetics/style-object
## construction -- no simulation/gameplay logic, same §42 boundary every
## other UI file in this dir already respects (this file computes nothing
## about world state, it only builds Godot StyleBox resources).
class_name UiTheme

## Cyan accent used for "this is player/own-force UI chrome" -- matches
## TacticalPlot.OWN_SHIP_COLOR (scripts/tactical_plot.gd's own-ship marker
## color) so a HUD panel's border/text reads as the same visual language as
## the plot's own-ship icon, not a coincidentally-similar but independently
## -chosen blue. Kept as a plain Color constant (not e.g. re-exporting
## TacticalPlot.OWN_SHIP_COLOR) so this file has no dependency on that class
## -- both are independently allowed to reference "the same value", per this
## codebase's existing small-helper convention (see e.g. MISSILE_COLOR's own
## doc comment in tactical_plot.gd for the same "matches X's color, kept as
## a literal, not a cross-reference" reasoning).
const ACCENT_COLOR := Color(0.55, 0.95, 1.0)
const ACCENT_COLOR_DIM := Color(0.55, 0.95, 1.0, 0.55)

## Subsystem/condition-readout color bands -- purely a legibility aid for a
## PER-SUBSYSTEM numeric percentage (AGENTS.md §25.1 explicitly allows this:
## "does not forbid displaying a numeric readout of an individual
## subsystem's condition... where that is the most readable way to show
## real, mechanically-consequential state"). This is NOT a single
## aggregate "ship health" bar/color -- each subsystem still gets its own
## independent number and color, so a ship with SENSORS destroyed but
## everything else fine still reads as exactly that, not as a single
## uniform "damaged" tint.
const CONDITION_GOOD_COLOR := Color(0.5, 0.95, 0.55)
const CONDITION_WARN_COLOR := Color(0.95, 0.85, 0.35)
const CONDITION_CRITICAL_COLOR := Color(1.0, 0.35, 0.3)
const CONDITION_WARN_THRESHOLD: float = 0.66
const CONDITION_CRITICAL_THRESHOLD: float = 0.33

const PANEL_BG_COLOR := Color(0.03, 0.07, 0.09, 0.82)
const PANEL_BORDER_WIDTH: float = 1.5
const PANEL_CORNER_RADIUS: int = 4
const PANEL_CONTENT_MARGIN: float = 8.0

## Builds a StyleBoxFlat for a panel background: dark translucent fill, a
## thin accent-colored border, slightly rounded corners -- the recurring
## "HUD glass panel" look in the reference image, factored out here so it
## is defined once rather than re-typed (and inevitably drifting slightly
## different) in every panel script that wants one.
static func panel_stylebox(border_color: Color = ACCENT_COLOR, bg_color: Color = PANEL_BG_COLOR) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.border_color = border_color
	sb.set_border_width_all(PANEL_BORDER_WIDTH)
	sb.set_corner_radius_all(PANEL_CORNER_RADIUS)
	sb.set_content_margin_all(PANEL_CONTENT_MARGIN)
	return sb

## Per-subsystem condition -> color, per the CONDITION_*_COLOR doc comment
## above (a readability aid on an already-shown, already-differentiated
## per-subsystem number -- not a new aggregate health measure).
static func condition_color(condition_fraction: float) -> Color:
	if condition_fraction < CONDITION_CRITICAL_THRESHOLD:
		return CONDITION_CRITICAL_COLOR
	if condition_fraction < CONDITION_WARN_THRESHOLD:
		return CONDITION_WARN_COLOR
	return CONDITION_GOOD_COLOR
