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
class_name Hud

const SubsystemType = preload("res://simulation/subsystem_type.gd")
const ContactState = preload("res://simulation/contact_state.gd")

var _label: Label
var pov_ship_id: String = ""

func _ready() -> void:
	_label = Label.new()
	_label.name = "HudLabel"
	_label.position = Vector2(12, 12)
	_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
	_label.add_theme_font_size_override("font_size", 16)
	add_child(_label)

## Call once per simulation tick (same call site/order as WeaponFx.update,
## see main.gd._on_tick) with the world and which ship this HUD instance
## is a point of view for.
func update(world: SimulationWorld, ship_id: String) -> void:
	pov_ship_id = ship_id
	_label.text = _build_text(world, ship_id)

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
