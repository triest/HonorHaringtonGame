extends Node3D
## Main
##
## Visual prototype bring-up scene: creates a SimulationWorld with a
## small squadron per side (§56.3 item H) on an inertial thrust course,
## each with a procedural hull mesh
## (scripts/hull_mesh_builder.gd) and a live wedge visualization driven by
## ship_defense_state.gd -- the first actually-visible prototype of the
## simulation, not just headless unit tests (ТЗ §56 Milestone 1-3 bring-up).
##
## ТЗ §56.1 item 6 ("Hardcoded 1v1/2v2 scenario vs TacticalAI"): both demo
## ships now have a team assigned (world.set_team, mutually hostile) and
## their weapon mounts are registered directly on `world` via
## world.add_weapon_mount() -- NOT in a separate main.gd-only dict like
## before. That is what makes SimulationWorld._resolve_weapons_ai actually
## select a target and fire each tick: it only ever looks at
## `world.weapon_mounts`/`world.teams`, and target SELECTION for both
## sides already goes through TacticalAI.select_weapon_target (see
## SimulationWorld._resolve_weapon_target) with no separate "AI class" to
## instantiate here -- at the time item 6 landed there was no
## player-controlled side yet, so this hardcoded scenario was then
## effectively TacticalAI vs TacticalAI, exactly as the checklist title
## says. (Items 5 and 7, added in later passes, now give alpha player
## control and a win/lose screen -- see PlayerInput/WinLoseScreen below;
## this paragraph is kept as-is for the historical "why" of the
## teams/mount setup.) §56.3 item H (this pass) upgraded the scenario
## itself from the original 1v1 (alpha vs beta) to a 3-vs-3 squadron and
## gave red/alpha missile tubes (previously energy-only) -- see the
## `ship_specs` table in _ready() below for the authoritative per-ship
## layout/loadout; this paragraph is kept as-is for the historical "why"
## of the team/mount wiring, not the current ship count.
## See CHANGELOG.md for the authoritative "done vs not done" list.
##
## WeaponFx (scripts/weapon_fx.gd, ТЗ §56.1 item 3) is wired into the
## per-tick loop below and now has something to actually draw: with teams
## assigned and mounts registered on `world`, SimulationWorld.
## last_tick_weapon_shots is populated live once both ships are in range
## and a mount comes off cooldown.

var world: SimulationWorld
var hulls: Dictionary = {}  # String ship_id -> HullState (local, illustrative only -- NOT passed to world.hulls; see world.add_ship's optional hull param, unused here)
var weapon_fx: WeaponFx
var hud: Hud
var tactical_plot: TacticalPlot
## §56.3 item A: single shared selection, injected into TacticalPlot (and
## future §56.3 UI -- squadron list, order menu) below -- see
## selection_state.gd's own doc comment for why this lives here rather
## than inside any one view.
var selection: SelectionState
## §56.3 item B: translates the group hotkey (G) into real
## FormationState/CommandEchelon structure from `selection` -- see that
## script's own doc comment. Owns no rendering; command_group_panel
## below is the readout of what it writes.
var command_group_controller: CommandGroupController
## §56.3 item B: left-side "squadron list" readout of
## world.command_echelons/world.formations, see that script's own doc
## comment for the interim layout choice.
var command_group_panel: CommandGroupPanel
## §56.3 item C: RMB-on-plot move order routing -- see that script's own
## doc comment. Same shared world/selection as command_group_controller
## above, plus `player_team` (below) so it never lets the player order an
## enemy AI ship around.
var move_order_controller: MoveOrderController
## §56.3 item D: same shared world/selection/player_team convention as
## move_order_controller above; also reuses move_order_controller itself
## for its APPROACH entry (see order_menu_controller.gd's own doc
## comment). `order_menu` is the visible popup this controller drives.
var order_menu_controller: OrderMenuController
var order_menu: OrderMenu
## §56.3 item E: same shared world/selection/player_team convention as
## move_order_controller/order_menu_controller above -- see that
## script's own doc comment for the panel's visibility rule and honest
## gaps. `weapon_panel` is the persistent (non-modal) side panel this
## controller drives.
var weapon_panel_controller: WeaponPanelController
var weapon_panel: WeaponPanel
## §56.3 item F: quick-center hotkey (project.godot [input]
## "camera_focus_selection") -- see that script's own doc comment. Same
## shared world/selection as the other §56.3 controllers above, plus a
## reference to the scene's own OrbitCamera (see _frame_camera_on_ships,
## unchanged by this item other than the camera it already framed now
## also being reachable from here).
var camera_focus_controller: CameraFocusController
var player_input: PlayerInput
var win_lose_screen: WinLoseScreen

## ТЗ §56.1 item 4 (Minimal HUD): which ship the single HUD panel is a
## point of view for. Alpha, arbitrarily -- no player-controlled side
## existed yet when item 4 was built; item 5 (PlayerInput,
## scripts/player_input.gd) has since made "alpha" the actual
## player-controlled ship (see that script's own doc comment for the
## decision), so this constant and PlayerInput's default
## `selected_ship_id` are intentionally the same ship -- the HUD shows
## exactly the ship the player commands, not an arbitrary/independent
## choice anymore.
const HUD_POV_SHIP_ID: String = "alpha"

func _ready() -> void:
	world = SimulationWorld.new()
	add_child(world)

	# §56.3 item H: hardcoded demo scenario upgraded from the original
	# 1v1 (alpha vs beta) to a small squadron vs small squadron -- three
	# ships per side, each side spread along Z around its guide's original
	# X position. Z spread is only +/-1500 m, far under the 10,000 m X
	# separation between the two sides, so AttackGeometry.classify()'s
	# dominant-axis pick (see the arc comment on world.add_weapon_mount
	# below) still always resolves to the X axis -- i.e. STARBOARD/PORT --
	# for every cross-ship pairing, not just guide-vs-guide as before.
	# "alpha"/"beta" (the two original guides) keep their original ids and
	# positions unchanged: HUD_POV_SHIP_ID, PlayerInput's hardcoded
	# player-controlled ship, and several unit tests' doc comments all
	# still refer to exactly these two ids. alpha_2/alpha_3/beta_2/beta_3
	# are new, reachable only through the §56.3 mouse-driven selection/
	# group-order systems (SelectionState/CommandGroupController/
	# MoveOrderController/OrderMenuController/WeaponPanelController all key
	# off `player_team` = world.teams.get("alpha"), not off PlayerInput's
	# own `_controllable_ship_ids` allowlist, so none of that needed any
	# changes for this) -- which is exactly the point of this item: give
	# items A-D's multi-select/group-order behavior 2+ own-team ships to
	# actually exercise live, not just in synthetic headless test worlds.
	#
	# Missile tubes (this item's other half, `missile_tubes` below): every
	# red/alpha ship gets 2 missile tubes (MissileTube's own engineering-
	# placeholder defaults -- 10 rounds/tube, 5 s reload, 60,000 km range,
	# see that script's doc comment -- easily in range at this scenario's
	# ~10 km separation), so missile salvos (item E's weapon panel) have
	# something to actually fire, live, for the first time -- previously
	# both demo ships were energy-only (§56.1-era). Blue/beta stays
	# energy-only: item H only requires "at least one side", and this
	# also keeps blue a pure energy-weapon contrast case rather than
	# doubling scope onto both sides in a single pass.
	var ship_specs: Array = [
		{"id": "alpha", "team": "red", "x": -5000.0, "z": 0.0, "missile_tubes": 2},
		{"id": "alpha_2", "team": "red", "x": -5000.0, "z": 1500.0, "missile_tubes": 2},
		{"id": "alpha_3", "team": "red", "x": -5000.0, "z": -1500.0, "missile_tubes": 2},
		{"id": "beta", "team": "blue", "x": 5000.0, "z": 0.0, "missile_tubes": 0},
		{"id": "beta_2", "team": "blue", "x": 5000.0, "z": 1500.0, "missile_tubes": 0},
		{"id": "beta_3", "team": "blue", "x": 5000.0, "z": -1500.0, "missile_tubes": 0},
	]
	for spec in ship_specs:
		var phys := ShipPhysicsState.new()
		phys.position = Vector3(spec["x"], 0.0, spec["z"])
		if spec["team"] == "blue":
			# Blue faces the opposite way, same as the original single-ship
			# "beta" setup (PI around Y) -- see AttackGeometry's doc comment:
			# -Z is bow, so a PI rotation makes blue's bow point back along
			# +Z, i.e. towards red, mirroring red's own -Z-facing bow.
			phys.orientation = Quaternion(Vector3.UP, PI)
		phys.commanded_thrust_local = Vector3(0.0, 0.0, -1.0)
		phys.defense = ShipDefenseState.new()
		# ТЗ §56.1 item 4: assigned here (previously null) so the HUD's
		# per-subsystem readout has real, non-null state to show -- "per-ship
		# subsystem condition" is meaningless with subsystems always null.
		# Every subsystem starts fully healthy (ShipSubsystems._init default);
		# nothing else about the demo scenario changes, the already-wired
		# consumers (WEAPONS/POINT_DEFENSE/MISSILE_SYSTEMS/SENSORS/
		# PROPULSION/MANEUVERING/COMMUNICATIONS, see ship_subsystems.gd) simply
		# now have live data to act on as combat damages these ships.
		phys.subsystems = ShipSubsystems.new()
		world.add_ship(spec["id"], phys)
		world.set_team(spec["id"], spec["team"])
		for _i in range(int(spec["missile_tubes"])):
			world.add_missile_tube(spec["id"], MissileTube.new())

	for ship_id in world.ships.keys():
		var view := ShipView.new()
		view.bind(world.ships[ship_id])  # builds its own procedural hull + wedge planes
		add_child(view)

		hulls[ship_id] = HullState.new()
		var laser := WeaponData.new()
		laser.id = "demo_laser"
		laser.max_range_m = 500_000.0
		laser.damage_per_hit = 100.0
		laser.recharge_time_s = 4.0
		# broadside_arc(), not bow_chaser_arc(): every red ship sits at
		# roughly the same X as guide "alpha" and every blue ship at
		# roughly the same X as guide "beta" (both facing along +/-Z, only
		# +/-1500 m Z spread per ship -- see the §56.3 item H comment
		# above -- well under the 10,000 m X separation between sides), so
		# the enemy is on every ship's STARBOARD per AttackGeometry.
		# classify() from tick 1, never in its BOW arc -- neither ship
		# turns to face the other (that would need real steering AI, out
		# of scope for this hardcoded slice). A bow chaser here would
		# never find arc and never fire; broadside is what actually
		# matches this geometry.
		world.add_weapon_mount(ship_id, WeaponMount.new(laser, WeaponMount.broadside_arc()))

	weapon_fx = WeaponFx.new()
	add_child(weapon_fx)

	hud = Hud.new()
	add_child(hud)

	# ТЗ §56.2 items A/B (tactical plot): same POV ship as Hud below --
	# see tactical_plot.gd's own doc comment for why it reads
	# world.sensor_contacts (not world.ships/world.missiles directly).
	selection = SelectionState.new()

	tactical_plot = TacticalPlot.new()
	tactical_plot.selection = selection
	add_child(tactical_plot)

	# §56.3 item B: same shared `selection`/`world` as tactical_plot
	# above -- no second selection or command-structure mechanism.
	command_group_controller = CommandGroupController.new()
	command_group_controller.world = world
	command_group_controller.selection = selection
	add_child(command_group_controller)

	command_group_panel = CommandGroupPanel.new()
	add_child(command_group_panel)

	# §56.3 item C: same shared world/selection as command_group_controller
	# above. player_team is world.teams.get(HUD_POV_SHIP_ID) rather than a
	# separately hardcoded "red" literal, so this stays correct if the
	# player-controlled ship/team ever changes without anyone remembering
	# to update a second copy of the same fact.
	move_order_controller = MoveOrderController.new()
	move_order_controller.world = world
	move_order_controller.selection = selection
	move_order_controller.player_team = String(world.teams.get(HUD_POV_SHIP_ID, ""))
	add_child(move_order_controller)
	tactical_plot.move_order_controller = move_order_controller

	# §56.3 item D: the order-menu popup itself must be added to the tree
	# AFTER tactical_plot (see order_menu.gd's own doc comment on why
	# sibling order controls input priority -- this makes the menu
	# properly modal over the plot once opened) so it draws/intercepts
	# input on top of it, never the other way around.
	order_menu = OrderMenu.new()
	add_child(order_menu)

	order_menu_controller = OrderMenuController.new()
	order_menu_controller.world = world
	order_menu_controller.selection = selection
	order_menu_controller.player_team = String(world.teams.get(HUD_POV_SHIP_ID, ""))
	order_menu_controller.move_order_controller = move_order_controller
	add_child(order_menu_controller)
	tactical_plot.order_menu_controller = order_menu_controller
	order_menu.controller = order_menu_controller

	# §56.3 item E: weapon-type selection panel for the currently
	# (singly-)selected own ship -- same shared world/selection/
	# player_team as move_order_controller/order_menu_controller above.
	# Non-modal (see weapon_panel.gd's own doc comment), so tree order
	# relative to tactical_plot/order_menu does not matter for input
	# priority the way it did for order_menu -- added after them purely
	# to keep related §56.3 controllers/panels grouped together.
	weapon_panel_controller = WeaponPanelController.new()
	weapon_panel_controller.world = world
	weapon_panel_controller.selection = selection
	weapon_panel_controller.player_team = String(world.teams.get(HUD_POV_SHIP_ID, ""))
	add_child(weapon_panel_controller)

	weapon_panel = WeaponPanel.new()
	weapon_panel.controller = weapon_panel_controller
	add_child(weapon_panel)

	# §56.3 item F: quick-center hotkey -- same shared world/selection as
	# every other §56.3 controller above. `camera` is looked up here
	# (get_node_or_null("Camera3D"), same node _frame_camera_on_ships
	# already targets below) rather than passed in from outside, since
	# main.gd is the one place that already owns both the scene's single
	# OrbitCamera and the single shared `selection`.
	camera_focus_controller = CameraFocusController.new()
	camera_focus_controller.world = world
	camera_focus_controller.selection = selection
	camera_focus_controller.camera = get_node_or_null("Camera3D") as OrbitCamera
	add_child(camera_focus_controller)

	# ТЗ §56.1 item 5 (Order input wiring): translates hotkeys (project.
	# godot [input], see PlayerInput's own doc comment) into calls on
	# `world`'s existing transmit_*/order APIs. Given `world` directly
	# (not looked up) since main.gd already owns the one SimulationWorld
	# instance for this scene.
	player_input = PlayerInput.new()
	player_input.world = world
	add_child(player_input)

	# ТЗ §56.1 item 7 (Win/lose screen): same per-tick pure-readout
	# convention as WeaponFx/Hud above (§42, ready before the tick-signal
	# connect below so it exists before the first _on_tick call).
	win_lose_screen = WinLoseScreen.new()
	add_child(win_lose_screen)

	world.clock.simulation_tick.connect(_on_tick)
	_frame_camera_on_ships()

	# 2026-09-23 live bug report (§56.1 items 4/5, see .tools/state.md/
	# CHANGELOG.md for that date): user ran the exported Windows .exe and
	# got a rendered 3D scene with ships firing on each other, but NO HUD
	# text and NO keys/mouse doing anything at all. Investigation that
	# pass found Hud/PlayerInput's own scripting logic correct -- reproduced
	# both in pure --headless (simulation/tests/test_hud.gd,
	# simulation/tests/test_player_input.gd) and in an actual Xvfb-rendered
	# run (real OpenGL display: HudLabel came up visible with real text,
	# and an injected keypress DID reach PlayerInput and change ship
	# state) -- so nothing in this file or Hud/PlayerInput was actually
	# broken. The leading remaining hypothesis for what a live user would
	# see as "nothing responds" is the OS-level game window simply not
	# having input focus when it first opens (a known category of
	# Godot/Windows export quirk -- e.g. a SmartScreen prompt or the
	# console wizard window stealing focus at launch); that can only be
	# observed live, never from this headless-only environment, so this
	# call is a defensive best-effort fix, not a confirmed root-cause fix.
	# Harmless everywhere else (a no-op if the window already has focus,
	# and both calls are silently safe under --headless/dummy display --
	# see simulation/tests -- so this does not risk breaking the existing
	# headless smoke checks).
	get_window().grab_focus()
	DisplayServer.window_move_to_foreground()

## NOTE on ordering: SimulationWorld itself connects to `world.clock.
## simulation_tick` in ITS OWN _ready() (simulation_world.gd), which runs
## synchronously during `add_child(world)` above -- BEFORE this method's
## own connect() call a few lines later in this file's _ready(). Godot
## calls a signal's listeners in connection order, so world.tick_
## simulation() (which rebuilds last_tick_weapon_shots for this tick, AND
## advances world.weapon_mounts' condition sync) has already run by the
## time this handler fires, and weapon_fx.update() below is reading this
## tick's fresh data, not last tick's.
##
## Cooldown advance for `world.weapon_mounts` (WeaponMount.tick(dt)) is
## deliberately still done HERE, not inside SimulationWorld.
## tick_simulation() -- see weapon_mount.gd: "Call once per fixed
## simulation tick to advance cooldown" is the mount's own contract, and
## SimulationWorld never calls it itself (missile tubes are the odd one
## out: _resolve_missile_launch_ai already advances those). Skipping this
## loop would leave every mount's cooldown stuck at whatever
## trigger_cooldown() last set it to, so a mount would fire once and then
## never again.
func _on_tick(dt: float, _tick: int, _sim_time: float) -> void:
	for ship_id in world.weapon_mounts.keys():
		for mount in world.weapon_mounts[ship_id]:
			mount.tick(dt)
	weapon_fx.update(world)
	hud.update(world, HUD_POV_SHIP_ID)
	tactical_plot.update(world, HUD_POV_SHIP_ID)
	# §56.3 item F: Hud's own current measured height feeds
	# CommandGroupPanel's position -- see that script's own doc comment
	# for why this replaces a previously-independent fixed guess.
	command_group_panel.update(world, selection, hud.get_bottom_y())
	move_order_controller.prune_completed()
	order_menu.sync()
	weapon_panel_controller.sync()
	weapon_panel.sync()
	win_lose_screen.update(world)

## Points the scene's OrbitCamera at the midpoint between the two demo
## ships from a distance proportional to their separation, computed from
## actual ship positions rather than a hand-tuned fixed transform in the
## .tscn (which, on inspection, was aimed along -Z without ever pointing
## at the ships -- a Milestone 1 oversight since headless test runs
## cannot verify framing visually; fixed now that this is meant to
## actually be looked at).
##
## ТЗ §56.1 item 1: the camera used to be fixed after this initial framing
## shot; OrbitCamera (scripts/orbit_camera.gd) now lets the player orbit/
## zoom from here. This function only sets the STARTING pivot/framing --
## all player-driven movement lives in OrbitCamera itself, so main.gd
## still never touches per-frame camera transforms.
func _frame_camera_on_ships() -> void:
	var camera: Camera3D = get_node_or_null("Camera3D")
	if camera == null:
		return

	var positions: Array = []
	for ship_id in world.ships.keys():
		positions.append(world.ships[ship_id].position)
	if positions.is_empty():
		return

	var midpoint: Vector3 = Vector3.ZERO
	for p in positions:
		midpoint += p
	midpoint /= positions.size()

	var spread: float = 1.0
	for p in positions:
		spread = maxf(spread, midpoint.distance_to(p))

	if camera.has_method("frame_on"):
		camera.frame_on(midpoint, spread)
		return

	# Fallback for a plain Camera3D with no OrbitCamera script attached
	# (e.g. a dev/test scene that reuses this function) -- reproduces the
	# pre-OrbitCamera fixed-framing behavior exactly.
	camera.fov = 60.0
	var half_fov_rad: float = deg_to_rad(camera.fov * 0.5)
	var required_distance: float = (spread / tan(half_fov_rad)) * 1.6
	var view_dir := Vector3(0.15, 0.45, 1.0).normalized()
	camera.global_position = midpoint + view_dir * required_distance
	camera.look_at(midpoint, Vector3.UP)
	camera.far = required_distance * 3.0 + 10000.0
