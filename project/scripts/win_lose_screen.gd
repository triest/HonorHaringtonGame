extends CanvasLayer
## WinLoseScreen
##
## ТЗ §56.1 item 7: "A simple win/lose end state using already-implemented
## destruction/mission-kill state (§63) -- a text message is enough, no
## polish." Invents no new destruction mechanic: this purely READS the
## existing §63 wreck state (`ShipPhysicsState.is_wreck`, set by
## `SimulationWorld._resolve_ship_destruction`) and `SimulationWorld.
## teams` (§56.1 item 6's hostility model, `world.set_team`) -- same
## "rendering only displays already-resolved simulation state" rule
## WeaponFx/Hud already follow (§42).
##
## §25.1-compliant like Hud: plain text, no decorative bars/icons.
## One-shot: once shown, stays shown and stops re-evaluating (there is
## no "restart" flow in this slice -- out of scope per §56.1's own list --
## so there is nothing to un-show it for).
##
## Win condition, kept generic over `world.teams`' actual team ids
## (not hardcoded to "red"/"blue" even though the current demo scenario
## only ever has those two, see main.gd): a team is "alive" if it has at
## least one ship that is NOT a wreck. Once exactly one team remains
## alive, that team has won. If every team's ships are simultaneously
## wrecked (mutual destruction, e.g. both sides' last ship dies the same
## tick), that's a draw -- shown rather than silently picking a side.
## A ship with no team assigned (teams.get default "") is not counted
## toward any team's alive/dead tally, matching how SimulationWorld's own
## hostility checks (`_are_hostile`) already treat an unassigned team as
## "no side".
class_name WinLoseScreen

var _label: Label
var _shown: bool = false

func _ready() -> void:
	_label = Label.new()
	_label.name = "WinLoseLabel"
	# FULL_RECT (not CENTER): a Label outside any Container keeps zero
	# rect_size unless something drives it, so CENTER anchors would pin a
	# zero-size box exactly at screen center and alignment would have
	# nothing to center text within. FULL_RECT sizes the label to the
	# whole viewport instead, and horizontal/vertical_alignment (set
	# below) then center the text inside that -- simplest robust way to
	# get an actually-centered message with no layout code.
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.6))
	_label.add_theme_font_size_override("font_size", 40)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.visible = false
	add_child(_label)

## Call once per simulation tick (same call site/order as WeaponFx.update/
## Hud.update, see main.gd._on_tick) with the world. No-op once a result
## has already been shown.
func update(world: SimulationWorld) -> void:
	if _shown:
		return

	var alive_teams: Dictionary = {}  # team id -> true, present only if team has a non-wreck ship
	var all_teams: Dictionary = {}
	for ship_id in world.ships.keys():
		var team: String = world.teams.get(ship_id, "")
		if team == "":
			continue
		all_teams[team] = true
		var ship = world.ships[ship_id]
		if not ship.is_wreck:
			alive_teams[team] = true

	# Nothing to conclude yet: fewer than 2 teams ever had ships, or more
	# than one team is still standing.
	if all_teams.size() < 2 or alive_teams.size() > 1:
		return

	var text: String
	if alive_teams.size() == 1:
		var winner: String = alive_teams.keys()[0]
		text = "%s WINS" % winner.to_upper()
	else:
		# alive_teams.size() == 0: every side's ships are wrecked at once.
		text = "DRAW -- ALL SHIPS DESTROYED"

	_label.text = text
	_label.visible = true
	_shown = true
