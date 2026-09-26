# Honorverse dev state (updated every pass)
Phase: §56.3 full tactical command UI (REPLACES §56.2 as top priority; §56.2's finished pieces are the foundation, not discarded)
Context: user rejected §56.2's result as too minimal/single-ship and supplied a detailed
UI spec (AGENTS.md §56.3, verbatim from project's CHATGPT.md) plus a reference image at
docs/reference/tactical_command_ui_reference.png (VIEW THIS IMAGE FIRST -- it is the visual
target: fleet-view squadron list + tactical-plot minimap on top, closer 3D view with
weapon/order panels on bottom). Read AGENTS.md §56.3 and CLOUD.md §1.10 in full before
starting a NEW lettered item you haven't touched yet -- they are long and detailed, do not
skim; you don't need to re-read them just to resume mid-item (see §0 of this file's own
skill instructions).
What already exists from §56.2/§56.3 items A-D (do NOT rebuild, extend it):
  - Tactical plot base with IFF-colored contact icons + velocity vectors (scripts, see
    prior CHANGELOG entries for exact file names)
  - Missile tracks shown distinctly from ship contacts
  - Mouse click-to-select AND multi-select (Ctrl/Shift/drag-box) on the plot --
    scripts/selection_state.gd (SelectionState), scripts/tactical_plot_selection.gd,
    scripts/tactical_plot.gd's _gui_input handling; main.gd owns the one shared
    SelectionState instance ("selection") -- reuse it, do not create a second one.
  - A canon-scale distance-compression convention (logged in ASSUMPTIONS.md)
  - Subsystem-condition text HUD (from §56.1) as a secondary panel
  - Named command groups: scripts/command_group_controller.gd (CommandGroupController --
    hotkey G / "selection_make_group" input action turns the current 2+-ship own-team
    selection into a real FormationState + leaf CommandEchelon, kind="Squadron N";
    reuses existing SimulationWorld.add_formation/add_command_echelon/
    attach_formation_to_echelon, member stations frozen at current relative position in
    the guide's local frame) + scripts/command_group_panel.gd (CommandGroupPanel --
    read-only left-side text list of world.command_echelons/world.formations, marks
    currently-selected members with ">"). Both wired into main.gd (same world/selection
    instances) and ticked from main.gd._on_tick. Headless-tested only (synthetic 2-4-ship
    worlds in unit tests) -- NOT yet confirmed with a real player (scenario is still 1v1,
    so live grouping of 2+ own ships isn't exercisable yet; item H upgrades that).
    Explicitly NOT done as part of B: disbanding/merging/renaming a group after creation
    -- open follow-up, see ASSUMPTIONS.md "§56.3 item B".
  - RMB move order (item C, this pass): scripts/move_order_controller.gd
    (MoveOrderController) -- RMB-release on the tactical plot (scripts/tactical_plot.gd's
    _on_right_release, via scripts/tactical_plot_projector.gd's new unproject()) issues a
    move order for the current selection. Lone own-team ship not in a formation ->
    IndividualOrder.change_course (already moving) or .change_speed (near-stationary) via
    world.transmit_individual_order_now (comm-delayed, same family as PlayerInput).
    Formation member/guide -> world.issue_formation_order_now(formation_id,
    FormationOrder.approach(...)) -- NOT world.issue_echelon_order (that one only queues,
    no "_now" variant exists yet -- see ASSUMPTIONS.md "§56.3 item C" before "fixing" this
    to go through the echelon). Visualization (course line/arrow/endpoint) is UI-side
    bookkeeping in MoveOrderController.active_move_orders, drawn by
    TacticalPlot._draw_move_orders, pruned by MoveOrderController.prune_completed()
    (called from main.gd._on_tick) on arrival or if the anchor ship is gone. Headless-
    tested only (29 checks, simulation/tests/test_move_order_controller.gd) -- NOT yet
    confirmed with a real player (no live mouse in this environment, and scenario is
    still 1v1 so the FORMATION branch specifically has never been exercised outside a
    synthetic test world either, same caveat as item B).
  - Contextual order menu (item D, this pass): scripts/order_menu_controller.gd
    (OrderMenuController) + scripts/order_menu.gd (OrderMenu, a plain
    hand-drawn Control -- no PopupMenu widget used anywhere in this
    codebase). Interaction: a PLAIN LMB click on a hostile ship contact
    while the current selection already has >=1 own-team ship opens the
    menu WITHOUT replacing the selection (SelectionState.designated_target_id
    is a new, separate single-id field for this -- not a second
    multi-select). OrderMenuController holds NO reference to the OrderMenu
    Control (pure `is_open`/`menu_screen_pos`/`menu_entries` state,
    read once per tick by OrderMenu.sync() from main.gd._on_tick) --
    same §42 division of labor as MoveOrderController/TacticalPlot, kept
    this way specifically so it stays headless-testable. Implemented:
    ATTACK/FOCUS FIRE (transmit_ship_target + weapons_free(true) --
    honestly identical given today's primitives), HOLD FIRE/WEAPONS FREE
    (transmit_ship_weapons_free), APPROACH (reuses
    MoveOrderController.issue_move_order at the target's position, zero
    new order-construction code), WITHDRAW (FormationOrder/IndividualOrder
    .withdraw_orders via the immediate QUEUED api -- NOT transmit_*, see
    ASSUMPTIONS.md "§56.3 item D" for why a 2-order composite can't
    safely go through the comm-delayed "_now" family), MAINTAIN FORMATION
    (issue_formation_order_now HOLD_FORMATION, only offered when a
    selected ship is actually in a formation). NOT implemented, honestly
    omitted from the menu entirely (no backing mechanic exists anywhere
    in simulation/*.gd, confirmed by grep): DEFEND, COVER, FOLLOW,
    INTERCEPT. Headless-tested only (42 checks,
    simulation/tests/test_order_menu_controller.gd) -- NOT yet confirmed
    with a real player (same no-live-mouse caveat as items B/C).
  - Weapon-selection panel (item E, this pass): scripts/weapon_panel_controller.gd
    (WeaponPanelController) + scripts/weapon_panel.gd (WeaponPanel, non-modal --
    unlike OrderMenu it does not cover the full viewport, see that file's own doc
    comment). Visible only when EXACTLY ONE own ship is selected. ENERGY WEAPONS:
    read-only list from world.weapon_mounts. MISSILES (only if tubes exist): salvo
    size (click-to-cycle, capped to tube count) + throttle profile (FULL BURN/
    EXTENDED RANGE, click-to-cycle) are BOTH real -- new optional max_launches/
    throttle_fraction params on world.order_missile_launch/_launch_missile_from_tube
    (both default to old behavior, every existing caller/replay entry unaffected),
    throttle wires the pre-existing but previously-unused MissileState.set_throttle().
    target line reuses SelectionState.designated_target_id as-is (no second target
    concept). POINT DEFENSE (only if PD mounts exist): AUTO/HOLD is a REAL new
    mechanic -- world.ship_pd_hold + set_ship_pd_hold/transmit_ship_pd_hold (same
    comm-delayed convention as transmit_ship_weapons_free), checked by
    _resolve_point_defense (a held ship's PD mounts do not engage at all). Honest
    gaps, NOT shown: missile "type" selection (MissileTube has no type field, no
    ship anywhere has >1 tube type), COUNTER-MISSILES entirely (no automatic
    counter-missile LAUNCH decision exists anywhere in simulation/*.gd -- every
    counter-missile in this codebase is a manually-constructed test double, see
    ASSUMPTIONS.md "§56.3 item E"), PD priority-target designation (TacticalAI.
    select_pd_target has no override parameter). Headless-tested only (36 checks,
    simulation/tests/test_weapon_panel_controller.gd) -- NOT yet confirmed with a
    real player (same no-live-mouse caveat as items B/C/D), AND the MISSILES/POINT
    DEFENSE sections specifically cannot even appear in the live demo scenario yet
    (scripts/main.gd's alpha/beta ships are still energy-only -- item H is what adds
    missile tubes -- so only ENERGY WEAPONS + the panel's visibility gate are
    live-observable today; MISSILES/PD are synthetic-test-only until H lands).
Checklist (§56.3, new scope, roughly in an order that builds incrementally toward the
15-step MVP acceptance test in AGENTS.md §56.3 / §1.10.14):
  [x] A. Multi-select: Ctrl+LMB add to selection, Shift+LMB extend, LMB drag-box select
      multiple contacts. (See CHANGELOG.md 2026-09-23 entry for full detail.)
  [x] B. Selection becomes a named command group (visual list, left-side squadron-list
      panel) -- reuses CommandEchelon/FormationState via CommandGroupController/
      CommandGroupPanel (see "What already exists" above and CHANGELOG.md 2026-09-25
      entry for full detail). Headless-verified only, not live-confirmed.
  [x] C. RMB-on-space move order for the current selection (single ship or group), with a
      visual course line/vector/endpoint per §1.10.6 -- see "What already exists" above
      and CHANGELOG.md 2026-09-26 entry for full detail. Headless-verified only
      (29 checks), not live-confirmed -- see ASSUMPTIONS.md "§56.3 item C" for two
      non-obvious bugs this pass's own test caught and fixed (issue_echelon_order only
      queues; CHANGE_SPEED's is_complete() ignores heading) before anyone gets a chance
      to "simplify" the code back into them.
  [x] D. Contextual order menu after selecting own + designating enemy -- implemented:
      ATTACK, FOCUS FIRE, HOLD FIRE, WEAPONS FREE, APPROACH, WITHDRAW, MAINTAIN FORMATION.
      Honestly NOT implemented/NOT shown in the menu: DEFEND, COVER, FOLLOW, INTERCEPT
      (no backing mechanic anywhere in simulation/*.gd -- see ASSUMPTIONS.md "§56.3 item
      D"). See "What already exists" above and CHANGELOG.md 2026-09-26 entry (second
      2026-09-26 entry, this pass) for full detail. Headless-verified only (42 checks),
      not live-confirmed.
  [x] E. Weapon-type selection panel for the selected ship -- implemented: ENERGY
      WEAPONS (read-only mounted list), MISSILES (salvo size + throttle/profile +
      target readout + FIRE, only shown when tubes exist), POINT DEFENSE (real
      AUTO/HOLD toggle, only shown when PD mounts exist). Honestly NOT
      implemented/NOT shown: missile "type" selection (no type field exists on
      MissileTube), COUNTER-MISSILES entirely (no automatic launch-decision
      mechanic anywhere in simulation/*.gd), PD priority-target designation (no
      override parameter on TacticalAI.select_pd_target) -- see ASSUMPTIONS.md
      "§56.3 item E". See "What already exists" above and CHANGELOG.md 2026-09-26
      entry (item E) for full detail. Headless-verified only (36 checks), not
      live-confirmed -- MISSILES/POINT DEFENSE specifically cannot even appear live
      until item H gives a demo ship missile tubes.
  [x] F. Command camera per §1.10.1: free camera over the battle, can go near-vertical
      top-down, orbit, zoom, quick-center on selected ship/group/contact -- DONE.
      OrbitCamera already covered orbit/near-vertical top-down/zoom (§56.1 item 1);
      this pass added quick-center: new hotkey Home (project.godot [input] action
      "camera_focus_selection") -> scripts/camera_focus.gd (CameraFocus.compute:
      selection -> {pivot, spread} via world.ships/world.missiles TRUE positions,
      own selection beats designated_target_id when both exist) -> scripts/
      camera_focus_controller.gd (CameraFocusController, plain Node +
      _unhandled_input, same pattern as PlayerInput) -> OrbitCamera.focus_on() (new
      method: re-centers pivot + refits distance to the new spread, KEEPS current
      yaw/pitch unlike frame_on(), rebases _base_distance so subsequent zoom is
      relative to the new framing, far only grows never shrinks). Also did the
      first real shared UI-panel layout pass this item's own note named: Hud.
      get_bottom_y() (new, real measured label height) is fed by main.gd._on_tick
      into CommandGroupPanel.update(..., hud_bottom_y) every tick, replacing that
      panel's old hardcoded Vector2(12, 360) guess -- see ASSUMPTIONS.md "§56.3
      item F" for why this is honestly scoped as a FIRST pass (only Hud/
      CommandGroupPanel actually shared a screen region and risked overlapping;
      WeaponPanel/TacticalPlot/OrderMenu each occupy a separate region already and
      were not touched). Headless-tested only (test_camera_focus.gd 17 checks,
      test_camera_focus_controller.gd 5 checks, test_orbit_camera.gd +2,
      test_hud.gd +2, new test_command_group_panel.gd 2 checks) -- NOT live-
      confirmed (OrbitCamera cannot be instantiated outside a live scene tree in
      this headless environment, re-confirmed this pass with a throwaway probe
      script, not just assumed from test_orbit_camera.gd's own older comment; so
      whether Home actually feels good live needs a real player). See
      CHANGELOG.md 2026-09-26 entry (item F) for full detail.
  [x] G. Zoom-level behavior (§1.10.3) -- DONE this pass. Plot (2D minimap) needed no
      change: TacticalPlot.plot_range_m already auto-scales to the farthest live contact
      with no upper bound, so distant contacts were never actually lost there. The 3D
      view (OrbitCamera) had a REAL BUG (not just a gap): `far` was sized off a fixed 3x
      multiplier of required_distance while the scroll-wheel/keyboard zoom-out clamp can
      reach 20x (MAX_DISTANCE_SCALE) -- on a wide enough initial battle framing, scrolling
      all the way out pushed the camera PAST its own far clip plane and blanked the
      ENTIRE 3D view (not "some contacts lost" -- nothing renders once the camera itself
      is beyond far). Fixed with a new pure `_required_far_for_base_distance()` sharing
      the same MAX_DISTANCE_SCALE constant + 1.2x margin, used by both frame_on() and
      focus_on() (far only ever grows, per item F's existing rule). Headless-tested only
      (2 new test_orbit_camera.gd cases spanning base_distance 500m-5,000,000m; full
      regression on test_camera_focus/_controller/hud/command_group_panel all green;
      scene smoke run exit 0, same 16x baseline errors). NOT live-confirmed (same
      OrbitCamera-can't-instantiate-outside-a-scene-tree limitation as item F). Full
      detail: ASSUMPTIONS.md "§56.3 item G", CHANGELOG.md 2026-09-26 "item G" entry.
      Open follow-up logged (not a blocker): far/_base_distance stay fixed at the last
      frame_on()/focus_on() call, so a very long battle where ships drift apart WITHOUT
      the player ever pressing Home again could in principle still outrun the original
      far plane over time -- a separate, slower-moving edge case from the zoom-clamp bug
      just fixed; would need main.gd to feed OrbitCamera live contact distances every
      tick (same pattern TacticalPlot's own auto-scale already uses) to close fully.
  [x] H. Hardcoded demo scenario upgraded from 1v1 to a 3-vs-3 squadron -- DONE this
      pass. scripts/main.gd's `_ready()` now builds ships from a `ship_specs` array
      (id/team/x/z/missile_tubes) instead of two one-off local vars: "alpha"/"beta"
      (the original guides) keep their exact original ids/positions/orientations
      unchanged (HUD_POV_SHIP_ID, PlayerInput's hardcoded player ship, and several
      unit tests' doc comments all still refer to exactly these two ids); new
      alpha_2/alpha_3 (red) and beta_2/beta_3 (blue) are spread +/-1500 m along Z
      around their guide's original X position -- kept well under the 10,000 m X
      separation between sides specifically so AttackGeometry.classify()'s
      dominant-axis pick still resolves every cross-ship pairing to STARBOARD/PORT,
      never BOW/STERN (verified by re-reading attack_geometry.gd's dominant-axis
      logic before picking the 1500 m figure, not just assumed). All 6 ships still
      go through the existing per-ship loop for ShipView/hull/energy weapon mount
      (`world.add_weapon_mount`, unchanged demo_laser/broadside_arc) -- that loop
      already iterated `world.ships.keys()` generically, so it needed no changes
      beyond having more ships to iterate. Every red ship (alpha/alpha_2/alpha_3)
      additionally gets 2 `MissileTube.new()` via `world.add_missile_tube` (engineering-
      placeholder defaults: 10 rounds/tube, 5s reload, 60,000 km range -- trivially in
      range at this scenario's ~10 km separation, and `_resolve_missile_launch_ai`
      requires no extra wiring beyond a non-empty `missile_tubes[ship_id]` entry, same
      target-selection/weapons-free gating as energy mounts). Blue stays energy-only
      (item H only requires "at least one side"; considered ShipFactory + the existing
      medusa_class.tres/sultan_class.tres ShipClassData records per this file's own
      §0 prior guidance, but those are capital-ship-scale loadouts (26-46 missile
      tubes, dozens of energy mounts each) not a fit for a "small squadron" demo --
      kept the existing hand-authored-ship pattern and just added tubes/ship-count to
      it instead of switching the whole demo scenario to the data-driven path, which
      was not part of this item's own scope). This makes items A-D's multi-select/
      group-order behavior actually exercisable live for the first time (2+ own-team
      ships now exist in the live scenario, not just synthetic test worlds) and gives
      item E's MISSILES weapon-panel section something real to show/fire live -- see
      the "What already exists" notes on items B/C/D/E above for the exact "item H
      upgrades that"/"until H lands" caveats this closes; those items' own
      live-player confirmation is still open (no live mouse in this headless
      environment), same honest gap, just no longer blocked ON item H specifically.
      Verified this pass: `godot --headless --import` clean; headless scene smoke
      (`main.tscn --quit-after 120`) exit 0, exactly 48 `mesh_get_surface_count`/
      "Parameter m is null" dummy-renderer baseline errors (16 per ship-pair before
      x3 for the 2-ship-per-side -> 6-ship scenario growth, confirmed by exact count,
      not eyeballed), zero new error types. Fast-visible-result mode still in effect
      (§0/Tests below) -- no full simulation-suite regression run this pass, only the
      headless import/smoke check.
  [ ] I. Individual override: within a selected group, pick one ship and give it its own
      order while the rest keep the group order (§1.10.12 worked example).
  [ ] J. VISUAL POLISH PASS -- explicit user decision, 2026-09-26, ONLY start this AFTER
      F-I are functionally done: user live-tested items A-E and confirmed they are
      currently bare debug text/dots on a black screen (a tiny corner radar, plain text
      lists) -- nowhere near docs/reference/tactical_command_ui_reference.png's look.
      User was shown this gap directly and explicitly chose "finish F-I (functionality)
      first, visual polish after" over doing polish now. Do NOT get pulled into
      panel/theme/icon work while F-I are still open, even if it would be quick --
      that is exactly the wrong order per this decision. When this item's turn comes:
      replace debug-text/dot placeholders with real Control-based panels reasonably
      close to the reference image (left squadron/group list, proper tactical-plot
      panel with contact icons + range rings instead of a tiny debug radar, bottom
      weapon/order control bar, event/order log panel) -- real Godot Theme/styled-
      Control work, budget real time for it, do not rush.
  [ ] Run AGENTS.md §56.3/§1.10.14's 15-step MVP acceptance test yourself (headless
      script simulating the input sequence where possible) as a sanity check, but this
      does NOT substitute for the user's own live pass/fail -- see below.
Next concrete step: item I -- individual override within a selected group: pick one
ship inside an already-formed group/formation and give IT its own order while the
rest of the group keeps executing the group order (§1.10.12's worked example in
CLOUD.md/AGENTS.md -- read that worked example fresh before starting, it specifies
the expected UX: selecting a single ship that is already a formation member, then
issuing it a move/attack order, should NOT pull it out of the formation or override
the whole group, only that one ship's own execution). Read this file's own checklist
entries for items B/C (CommandGroupController/FormationState, MoveOrderController) and
D (OrderMenuController) above first -- item I is very likely a targeted change to
whichever of those three currently always resolves "selection = 1 ship that happens to
be a formation member" to a FORMATION-level order instead of an individual one (check
move_order_controller.gd/order_menu_controller.gd's own branching on formation
membership before writing new code -- this may already partially exist by accident of
how those items were built, or may need an explicit single-ship-within-formation branch
added to one or both). Now that item H gives a live 3-vs-3 scenario with real
formations reachable via item B's G hotkey, this is also the first item that can
realistically be exercised beyond synthetic 2-4-ship headless test worlds once a real
player forms a group and tries overriding one member -- but headless unit tests
(synthetic formation + single-member override) remain the actual verification for this
pass, live confirmation is still the user's own job per this file's standing rule below.
Tests: still fast-visible-result mode -- skip full simulation suite, headless import/smoke
check only, until §56.3 fully closes (this is a big scope, likely spans many passes --
that's fine, keep chipping at the checklist in order, one or two items per pass is a
reasonable pace, don't rush sloppy code to close items faster).
IMPORTANT -- same lesson as §56.1/§56.2: do NOT self-report any part of this "closed" on
headless verification alone. Report per-pass progress against the lettered checklist
above, and only use the words "§56.3 ЗАКРЫТ"/"MVP acceptance test passed" after the user
has explicitly confirmed it live, walking through (or at least trying) the 15 steps.
Blockers: none currently. This is a large scope -- if it starts feeling too big for one
pass's time budget, that's expected; just make honest incremental progress on the
checklist rather than declaring victory early (that's exactly what went wrong twice now).
Last pass finished: 2026-09-26 20:09 UTC (scheduled dev pass, fired from the normal 3h
cron; cron prompt still says "§56.1" -- stale/generic scheduled-task prompt, intentionally
ignored per this skill's own instructions in favor of this file): closed §56.3 item H
(demo scenario upgraded from 1v1 to a 3-vs-3 squadron, red side given missile tubes) --
see the checklist entry above for the full writeup (ship-spec-array refactor of
scripts/main.gd's _ready(), Z-offset geometry chosen to keep AttackGeometry.classify()'s
STARBOARD/PORT resolution intact for every cross-ship pairing). Headless import clean;
scene smoke run (main.tscn --quit-after 120) exit 0, exactly 48 baseline dummy-renderer
errors (16 x 3, scaling with the 2->6 ship count, zero new error types). No full
simulation-suite regression this pass (fast-visible-result mode still in effect, per
Tests line above -- this was a scenario-data/setup change with no new production class,
so the existing per-class unit tests were not touched and did not need re-running).
Windows .exe re-exported (.pck 451584B -> 452032B, confirming new code is in the
build). ASSUMPTIONS.md/CHANGELOG.md updated; pushed this pass.
I/J not started.
