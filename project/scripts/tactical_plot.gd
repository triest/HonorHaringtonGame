extends Control
## TacticalPlot
##
## ТЗ §56.2 items A/B ("Tactical plot / contacts display, including
## missiles"): a top-down, God's-eye 2D tactical display -- the user's
## explicit replacement for judging the battle by eye through a close
## 3D camera (see AGENTS.md §56.2, user decision 2026-09-23: "every UI
## decision in this section should be checked against [tactical
## strategy], not against space-combat-game conventions in general").
##
## Pure rendering readout of already-resolved SimulationWorld state
## (§42, same convention as Hud/WeaponFx): this class invents no
## detection/targeting/combat logic of its own. TacticalPlotProjector
## (this dir) does the pure world->screen geometry and is unit-tested
## headlessly (simulation/tests/test_tactical_plot_projector.gd); this
## class only reads world.sensor_contacts/world.ships and draws.
##
## SOURCE OF CONTACTS -- deliberately `world.sensor_contacts[pov_ship_id]`,
## NOT `world.ships`/`world.missiles` directly: SimulationWorld.
## _update_sensors() already writes BOTH ship AND missile contacts into
## that one dictionary (keyed by ship_id or missile_id respectively --
## confirmed by reading simulation_world.gd._update_sensors, which
## calls SensorResolution.update_contacts for every ship AND every
## missile into the same `contacts` dict). Reading it here means the
## plot honestly reflects §23 sensor detection/fog-of-war (a contact
## the ship's SENSORS subsystem has not actually detected does not
## appear, and a lost contact fades rather than vanishing/updating
## instantly) instead of omnisciently drawing world truth -- more
## correct for a "tactical plot" (the whole point of which, per §56.2's
## own reasoning, is that it shows the tactical officer's SENSOR
## picture, not reality). WeaponFx's missile markers (§56.1 item 3) are
## a different, already-shipped capability that intentionally draws
## world.missiles directly for the 3D view; this file does not change
## that. Ship vs missile contacts are told apart the exact same way
## SimulationWorld._update_missiles already does for counter-missiles:
## `contact.target is MissileState`.
class_name TacticalPlot

const MissileState = preload("res://simulation/missile_state.gd")
const ContactState = preload("res://simulation/contact_state.gd")
const TacticalPlotProjector = preload("res://scripts/tactical_plot_projector.gd")

## Plot auto-scales each update() to comfortably fit the farthest
## currently-live contact -- keeps every known contact on-plot without a
## manual zoom control, which §56.2 item C (mouse-first control, NOT yet
## implemented -- see state.md) is expected to add explicit zoom/pan
## input for later. ASSUMPTION: a floor so the plot does not zoom in to
## a meaningless scale when there are zero/very-close contacts.
const MIN_PLOT_RANGE_M: float = 50_000.0
const AUTO_SCALE_MARGIN: float = 1.15

const PLOT_SIZE_PX: float = 320.0
const PLOT_MARGIN_PX: float = 12.0
const RING_COUNT: int = 4

## How many seconds of travel a contact's velocity-vector leader line
## represents. Purely a legibility scale (ASSUMPTION), same status as
## WeaponFx's BEAM_WIDTH_M/MISSILE_MARKER_RADIUS_M placeholder
## constants -- not a canon figure.
const VELOCITY_LEADER_SECONDS: float = 60.0

const OWN_SHIP_COLOR := Color(0.55, 0.95, 1.0)
const HOSTILE_COLOR := Color(1.0, 0.3, 0.25)
const FRIENDLY_COLOR := Color(0.4, 1.0, 0.5)
const NEUTRAL_COLOR := Color(0.85, 0.85, 0.3)
const MISSILE_COLOR := Color(1.0, 0.85, 0.2)  # matches WeaponFx's 3D missile marker colour, so the same threat reads the same hue in both views
const BACKGROUND_COLOR := Color(0.02, 0.05, 0.04, 0.85)
const RIM_COLOR := Color(0.3, 0.6, 0.5, 0.6)
const RING_COLOR := Color(0.25, 0.45, 0.4, 0.35)
const RING_LABEL_COLOR := Color(0.4, 0.65, 0.6, 0.7)
## Contacts not currently DETECTED/TRACKED (i.e. ESTIMATED/UNCERTAIN/
## LOST -- dead-reckoned, not a live detection this tick) are drawn
## dimmer so stale data reads as stale, a real §23 distinction this
## plot would otherwise flatten away.
const STALE_ALPHA: float = 0.45

var pov_ship_id: String = ""
var plot_range_m: float = MIN_PLOT_RANGE_M

var _contacts: Array = []  # Array[Dictionary], rebuilt each update()
var _origin_present: bool = false
var _pov_position: Vector3 = Vector3.ZERO
var _pov_velocity: Vector3 = Vector3.ZERO

func _ready() -> void:
	custom_minimum_size = Vector2(PLOT_SIZE_PX, PLOT_SIZE_PX)
	size = Vector2(PLOT_SIZE_PX, PLOT_SIZE_PX)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_KEEP_SIZE, int(PLOT_MARGIN_PX))
	# §56.2 item C (mouse-first control) is not implemented yet -- do not
	# swallow clicks meant for other nodes until it is; flip this to
	# MOUSE_FILTER_STOP (or PASS + real hit-testing) when that item lands.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## Call once per simulation tick (same call site/order as Hud.update /
## WeaponFx.update, see main.gd._on_tick) with the world and which ship
## this plot is a point of view for.
func update(world: SimulationWorld, ship_id: String) -> void:
	pov_ship_id = ship_id
	_contacts.clear()

	var pov_ship: ShipPhysicsState = world.ships.get(ship_id)
	_origin_present = pov_ship != null
	if not _origin_present:
		queue_redraw()
		return

	_pov_position = pov_ship.position
	_pov_velocity = pov_ship.velocity

	var farthest_m: float = MIN_PLOT_RANGE_M
	var contacts: Dictionary = world.sensor_contacts.get(ship_id, {})
	for contact_id in contacts.keys():
		var contact = contacts[contact_id]
		if contact.state == ContactState.Type.UNKNOWN:
			continue  # never actually detected -- nothing to show yet (§23)
		var is_missile: bool = contact.target is MissileState
		var range_m: float = _pov_position.distance_to(contact.estimated_position)
		farthest_m = maxf(farthest_m, range_m)
		_contacts.append({
			"id": contact_id,
			"is_missile": is_missile,
			"estimated_position": contact.estimated_position,
			"estimated_velocity": contact.estimated_velocity,
			"state": contact.state,
			"hostile": (not is_missile) and world.is_hostile(ship_id, contact_id),
			"friendly": (not is_missile) and contact_id != ship_id
				and world.teams.get(contact_id, "") != ""
				and world.teams.get(contact_id, "") == world.teams.get(ship_id, ""),
		})

	plot_range_m = maxf(farthest_m * AUTO_SCALE_MARGIN, MIN_PLOT_RANGE_M)
	queue_redraw()

func _draw() -> void:
	var radius: float = minf(size.x, size.y) * 0.5 - PLOT_MARGIN_PX
	if radius <= 4.0:
		return
	var center: Vector2 = size * 0.5

	draw_circle(center, radius + PLOT_MARGIN_PX * 0.5, BACKGROUND_COLOR)
	draw_arc(center, radius, 0.0, TAU, 48, RIM_COLOR, 1.5)

	for i in range(1, RING_COUNT + 1):
		var ring_r: float = radius * float(i) / float(RING_COUNT)
		draw_arc(center, ring_r, 0.0, TAU, 48, RING_COLOR, 1.0)
		var ring_range_m: float = plot_range_m * float(i) / float(RING_COUNT)
		draw_string(ThemeDB.fallback_font, center + Vector2(4, -ring_r + 12), _format_range(ring_range_m), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, RING_LABEL_COLOR)

	if not _origin_present:
		draw_string(ThemeDB.fallback_font, center - Vector2(70, 0), "NO PLOT (own ship unknown)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, HOSTILE_COLOR)
		return

	# Own ship: small square at the plot's centre (it is, by definition,
	# its own origin), plus its own velocity leader so the player can
	# read their own vector at a glance the same way as any contact's.
	draw_rect(Rect2(center - Vector2(5, 5), Vector2(10, 10)), OWN_SHIP_COLOR, false, 2.0)
	_draw_velocity_leader(center, _pov_velocity, radius, OWN_SHIP_COLOR)
	draw_string(ThemeDB.fallback_font, center + Vector2(8, 18), pov_ship_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, OWN_SHIP_COLOR)

	for contact in _contacts:
		var projection: Dictionary = TacticalPlotProjector.project(contact["estimated_position"], _pov_position, plot_range_m, radius)
		var icon_pos: Vector2 = center + projection["plot_offset_px"]
		var color: Color = _contact_color(contact)
		if contact["state"] != ContactState.Type.DETECTED and contact["state"] != ContactState.Type.TRACKED:
			color.a = STALE_ALPHA

		if contact["is_missile"]:
			_draw_missile_icon(icon_pos, color)
		else:
			_draw_ship_icon(icon_pos, color, projection["clamped"])
			var lead_target: Vector3 = contact["estimated_position"] + contact["estimated_velocity"] * VELOCITY_LEADER_SECONDS
			var lead_projection: Dictionary = TacticalPlotProjector.project(lead_target, _pov_position, plot_range_m, radius)
			draw_line(icon_pos, center + lead_projection["plot_offset_px"], color, 1.5)

		var label: String = "%s  %s  %s" % [contact["id"], _format_range(projection["range_m"]), _format_bearing(projection["bearing_rad"])]
		draw_string(ThemeDB.fallback_font, icon_pos + Vector2(8, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color)

func _draw_ship_icon(pos: Vector2, color: Color, clamped: bool) -> void:
	var s: float = 6.0
	var points := PackedVector2Array([pos + Vector2(0, -s), pos + Vector2(s, s), pos + Vector2(-s, s)])
	draw_polygon(points, PackedColorArray([color]))
	if clamped:
		draw_arc(pos, s + 3.0, 0.0, TAU, 12, color, 1.0)  # ring: "known to be further out, pulled to the rim"

func _draw_missile_icon(pos: Vector2, color: Color) -> void:
	# Distinct shape from the ship triangle (item B: "own distinctly-
	# marked icon/track... separate from ship contacts") -- an X/cross,
	# not a triangle, so missiles read as a different class of contact
	# at a glance, not just a different colour.
	var s: float = 4.0
	draw_line(pos + Vector2(-s, -s), pos + Vector2(s, s), color, 2.0)
	draw_line(pos + Vector2(-s, s), pos + Vector2(s, -s), color, 2.0)

func _draw_velocity_leader(from_px: Vector2, velocity: Vector3, radius: float, color: Color) -> void:
	if velocity.length_squared() < 0.0001:
		return
	var lead_m := Vector2(velocity.x, velocity.z) * VELOCITY_LEADER_SECONDS
	var scale_px_per_m: float = radius / maxf(plot_range_m, 0.001)
	var lead_px: Vector2 = lead_m * scale_px_per_m
	if lead_px.length() > radius * 0.9:
		lead_px = lead_px.normalized() * radius * 0.9
	draw_line(from_px, from_px + lead_px, color, 1.5)

func _contact_color(contact: Dictionary) -> Color:
	if contact["is_missile"]:
		return MISSILE_COLOR
	if contact["hostile"]:
		return HOSTILE_COLOR
	if contact["friendly"]:
		return FRIENDLY_COLOR
	return NEUTRAL_COLOR

static func _format_range(range_m: float) -> String:
	if range_m >= 1_000_000.0:
		return "%.2f Mkm" % (range_m / 1_000_000.0)
	return "%.0f km" % (range_m / 1000.0)

static func _format_bearing(bearing_rad: float) -> String:
	return "%03d°" % [int(round(rad_to_deg(bearing_rad))) % 360]
