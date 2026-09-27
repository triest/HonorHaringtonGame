extends CanvasLayer
## Hud
##
## ТЗ §56.1 item 4: minimal, §25.1-compliant HUD (§25.1 -- "no health
## bars/damage percentages shown as decorative bars/icons") -- a plain
## TEXT readout of one ship's live simulation state, nothing more:
## per-subsystem condition, current weapon target designation, and the
## sensor contact list. Like WeaponFx (scripts/weapon_fx.gd), this is a
## pure rendering readout of ALREADY-COMPUTED SimulationWorld state
## (§42) -- it invents no new game-design mechanic and computes nothing
## itself beyond text formatting, including target selection: see
## SimulationWorld.get_weapon_target_designation(), which this reuses
## rather than re-deriving a second copy of "which target".
##
## Single-ship point of view for this first slice (ТЗ §56.1 item 4's own
## instruction: "pick ONE ship... unless showing both is trivial" --
## showing both isn't trivial with a single Label's worth of screen
## space without real layout work, so kept single per that fallback);
## main.gd wires this to "alpha". A future pass can add a second panel
## or a POV switch once order input (item 5) gives the player an actual
## controlled ship to default the POV to.
##
## §56.3 item J (visual polish pass, see .tools/state.md): this panel was
## bare unstyled text directly on the 3D viewport -- the user's explicit
## complaint after live-testing items A-E ("debug text/dots on a black
## screen"). This pass gives it a real styled background (UiTheme,
## scripts/ui_theme.gd -- a small shared stylebox/color helper, new this
## pass, meant to be reused by CommandGroupPanel/OrderMenu/WeaponPanel in
## LATER J sub-passes, not applied to them yet -- see ASSUMPTIONS.md
## "§56.3 item J" for the honest scope of what this one pass covers) and
## an accent text color matching TacticalPlot's own-ship marker color, so
## this panel reads as the same visual system as the tactical plot rather
## than an unrelated debug overlay. The TEXT CONTENT/layout logic below
## (_build_text) is completely unchanged -- this is a pure presentation
## change, still §25.1-compliant (per-subsystem numeric %, no aggregate
## health bar).
class_name Hud

const SubsystemType = preload("res://simulation/subsystem_type.gd")
const ContactState = preload("res://simulation/contact_state.gd")
const UiTheme = preload("res://scripts/ui_theme.gd")

## Gap (px) between the label's own text bounds and the drawn panel edge
## around it -- purely a legibility/aesthetic choice (ASSUMPTION, same
## status as e.g. TacticalPlot.PLOT_MARGIN_PX), not derived from anything.
const PANEL_PADDING_PX: float = 10.0

var _label: Label
var _background: Panel
var pov_ship_id: String = ""

func _ready() -> void:
	# Background added FIRST so it draws behind the label (CanvasLayer
	# children render in the order they were added, same convention as
	# every other layered draw in this codebase, e.g. TacticalPlot draws
	# rim/rings before contacts before selection rings).
	_background = Panel.new()
	_background.name = "HudBackground"
	_background.add_theme_stylebox_override("panel", UiTheme.panel_stylebox())
	# Purely decorative chrome behind a text readout -- must never steal
	# mouse events from whatever's underneath (the 3D viewport, and other
	# input-consuming UI like TacticalPlot).
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)

	_label = Label.new()
	_label.name = "HudLabel"
	_label.position = Vector2(12, 12)
	_label.add_theme_color_override("font_color", UiTheme.ACCENT_COLOR)
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.02, 0.02, 0.9))
	_label.add_theme_constant_override("outline_size", 2)
	_label.add_theme_font_size_override("font_size", 16)
	add_child(_label)
	_layout_background()

## Call once per simulation tick (same call site/order as WeaponFx.update,
## see main.gd._on_tick) with the world and which ship this HUD instance
## is a point of view for.
func update(world: SimulationWorld, ship_id: String) -> void:
	pov_ship_id = ship_id
	_label.text = _build_text(world, ship_id)
	_layout_background()

## §56.3 item J: resizes/repositions `_background` to hug `_label`'s
## CURRENT real measured bounds (Label.get_minimum_size(), the same
## "real measurement, not a guess" primitive get_bottom_y() below already
## relied on pre-item-J) plus PANEL_PADDING_PX on every side. Called after
## every text change so the panel never lags behind a line-count change
## (fewer/more subsystems, fewer/more contacts).
func _layout_background() -> void:
	if _background == null or _label == null:
		return
	var content_size: Vector2 = _label.get_minimum_size()
	var pad := Vector2(PANEL_PADDING_PX, PANEL_PADDING_PX)
	_background.position = _label.position - pad
	_background.size = content_size + pad * 2.0

## §56.3 item F ("first real shared UI-panel layout pass", §1.10.1's own
## note in .tools/state.md): this panel's CURRENT actual rendered bottom
## edge in screen pixels, so a sibling panel that stacks below it
## (CommandGroupPanel, see command_group_panel.gd) can position itself
## from Hud's REAL current height instead of a second hardcoded guess at
## "how tall is Hud usually" -- Hud's own line count varies with contact
## count/subsystem list, so a fixed guess drifts stale exactly the way
## CommandGroupPanel's PANEL_POSITION constant already admitted it might
## (see that file's own doc comment, pre-item-F).
##
## §56.3 item J update: now returns the styled BACKGROUND panel's real
## bottom edge (label bottom + PANEL_PADDING_PX), not the bare label's --
## the background is the panel's actual visible extent now that one
## exists, so a sibling stacking "below Hud" should stack below the drawn
## panel, not below where the label would end if the panel weren't there
## (which would visually clip into/overlap Hud's own border). Falls back
## to the pre-item-J label-only measurement if _background somehow isn't
## set (defensive -- _ready() always creates it, same guard style as
## every other optional-collaborator null-check in this codebase).
func get_bottom_y() -> float:
	if _background != null:
		return _background.position.y + _background.size.y
	return _label.position.y + _label.get_minimum_size().y

func _build_text(world: SimulationWorld, ship_id: String) -> String:
	var ship = world.ships.get(ship_id)
	if ship == null:
		return "HUD: no ship '%s'" % ship_id

	var lines: Array = []
	lines.append("=== %s ===" % ship_id.to_upper())

	lines.append("-- SUBSYSTEMS --")
	if ship.subsystems == null:
		lines.append("N/A (no ShipSubsystems assigned)")
	else:
		for type_value in SubsystemType.Type.values():
			var type_name: String = SubsystemType.Type.keys()[type_value]
			var condition: float = ship.subsystems.get_condition(type_value)
			lines.append("%s %d%%" % [type_name, roundi(condition * 100.0)])

	lines.append("-- TARGET --")
	var target_id: String = world.get_weapon_target_designation(ship_id)
	lines.append(target_id if target_id != "" else "NONE")

	lines.append("-- CONTACTS --")
	var contacts: Dictionary = world.sensor_contacts.get(ship_id, {})
	if contacts.is_empty():
		lines.append("(none)")
	else:
		for contact_id in contacts.keys():
			var contact = contacts[contact_id]
			var state_name: String = ContactState.Type.keys()[contact.state]
			lines.append("%s: %s" % [contact_id, state_name])

	var text: String = ""
	for i in range(lines.size()):
		text += lines[i]
		if i < lines.size() - 1:
			text += "\n"
	return text
