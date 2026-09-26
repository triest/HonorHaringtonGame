extends Node3D
## Main
##
## Visual prototype bring-up scene: creates a SimulationWorld with two
## ships on an inertial thrust course, each with a procedural hull mesh
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
## teams/mount setup.) Still explicitly NOT done: missile tubes for the
## demo ships (energy weapons alone are enough to exercise weapon_fx's
## beam path live; missile markers stay verified only by unit test until
## a scenario actually needs missiles) and a Windows export (item 8).
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

	var alpha := ShipPhysicsState.new()
	alpha.position = Vector3(-5000.0, 0.0, 0.0)
	alpha.commanded_thrust_local = Vector3(0.0, 0.0, -1.0)
	alpha.defense = ShipDefenseState.new()
	# ТЗ §56.1 item 4: assigned here (previously null) so the HUD's
	# per-subsystem readout has real, non-null state to show -- "per-ship
	# subsystem condition" is meaningless with subsystems always null.
	# Every subsystem starts fully healthy (ShipSubsystems._init default);
	# nothing else about the demo scenario changes, the already-wired
	# consumers (WEAPONS/POINT_DEFENSE/MISSILE_SYSTEMS/SENSORS/
	# PROPULSION/MANEUVERING/COMMUNICATIONS, see ship_subsystems.gd) simply
	# now have live data to act on as combat damages these ships.
	alpha.subsystems = ShipSubsystems.new()
	world.add_ship("alpha", alpha)
	world.set_team("alpha", "red")

	var beta := ShipPhysicsState.new()
	beta.position = Vector3(5000.0, 0.0, 0.0)
	beta.orientation = Quaternion(Vector3.UP, PI)
	beta.commanded_thrust_local = Vector3(0.0, 0.0, -1.0)
	beta.defense = ShipDefenseState.new()
	beta.subsystems = ShipSubsystems.new()  # see alpha.subsystems assignment above for rationale
	world.add_ship("beta", beta)
	world.set_team("beta", "blue")

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
		# broadside_arc(), not bow_chaser_arc(): alpha/beta start abeam of
		# each other (both on the X axis, facing along +/-Z), so the enemy
		# is on each ship's STARBOARD per AttackGeometry.classify() from
		# tick 1, never in its BOW arc -- neither ship turns to face the
		# other (that would need real steering AI, out of scope for this
		# hardcoded slice). A bow chaser here would never find arc and
		# never fire; broadside is what actually matches this geometry.
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
	command_group_panel.update(world, selection)
	move_order_controller.prune_completed()
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
