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
What already exists from §56.2/§56.3 items A-C (do NOT rebuild, extend it):
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
  [ ] D. Contextual order menu after selecting own + designating enemy: at minimum ATTACK,
      FOCUS FIRE, HOLD FIRE, WEAPONS FREE, DEFEND, COVER, FOLLOW, INTERCEPT, APPROACH,
      WITHDRAW, MAINTAIN FORMATION (full list in AGENTS.md §1.10.7, ~line 2413) --
      routes into existing ShipCombatDirective/FormationOrder/IndividualOrder, no
      UI-only order model (§1.10.7's own explicit text: "Не создавать отдельную UI-only
      модель приказов").
  [ ] E. Weapon-type selection panel for the selected ship: missiles (type + salvo size +
      target + FIRE), counter-missiles (auto/manual/hold), energy weapons, PD
      (auto/hold/priority-target) -- must only show weapons the selected ship's class
      actually has mounted (no showing weapons it doesn't carry). AGENTS.md §1.10.8,
      ~line 2434.
  [ ] F. Command camera per §1.10.1: free camera over the battle, can go near-vertical
      top-down, orbit, zoom, quick-center on selected ship/group/contact -- extend the
      existing OrbitCamera rather than replacing it if it already covers most of this.
      NOTE: this is also the point to do a real shared UI-panel layout pass (Hud +
      TacticalPlot + CommandGroupPanel currently use ad-hoc fixed positions that will
      start colliding as more panels are added -- see ASSUMPTIONS.md "§56.3 item B").
  [ ] G. Zoom-level behavior (§1.10.3): at minimum ensure zooming out doesn't lose distant
      contacts (they must stay visible on the plot even far out) and zooming in reveals
      per-ship detail -- doesn't need all 4 named levels to be literally distinct modes,
      but the plot must not become unreadable at either extreme.
  [ ] H. Hardcoded demo scenario upgraded from 1v1 to at least a couple of ships per side
      (small squadron vs small squadron) so multi-select/group-order behavior in A-D is
      actually exercisable live, and so missile salvos (E) have something meaningful to
      fire at -- give at least one side missile tubes (currently energy-only per §56.1
      CHANGELOG entries), this was explicitly asked about by the user separately.
  [ ] I. Individual override: within a selected group, pick one ship and give it its own
      order while the rest keep the group order (§1.10.12 worked example).
  [ ] Run AGENTS.md §56.3/§1.10.14's 15-step MVP acceptance test yourself (headless
      script simulating the input sequence where possible) as a sanity check, but this
      does NOT substitute for the user's own live pass/fail -- see below.
Next concrete step: item D -- contextual order menu after selecting own ship(s) + a
hostile contact. Read AGENTS.md §1.10.7 in full first (sed -n '2413,2432p' AGENTS.md --
only skimmed against item C's own needs so far, not read fresh for D's exact
requirements). Needs: (1) a way to designate the "target" half of "own + target" -- likely
a second click state on the tactical plot (e.g. selecting an own ship/group, THEN
ctrl/some-modifier-clicking (or just clicking with the existing selection already own-only)
a hostile contact opens the menu) -- read tactical_plot.gd's existing hit-test/selection
code first (TacticalPlotSelection.hit_test already tells you exactly what was clicked,
including hostiles) rather than inventing a second hit-testing path; SelectionState
currently has no notion of "designated enemy target" separate from "selected", so this
probably needs a small new concept (a single designated_target_id, not a second
multi-select) -- log the exact interaction chosen as an ASSUMPTION like items A/B/C did.
(2) an actual menu UI (a small new Control, e.g. scripts/order_menu.gd, shown near the
cursor or in a fixed panel -- no popup-menu widget used anywhere else in this codebase
yet, plain Control + draw_string buttons or a Godot PopupMenu node both defensible,
pick one and log it) listing the §1.10.7 order set, filtered to what's actually meaningful
given the current selection (e.g. WITHDRAW/MAINTAIN FORMATION don't need a target,
ATTACK/FOCUS FIRE do -- use judgement, log the exact filtering rule chosen). (3) routing:
each menu entry must call into ShipCombatDirective (transmit_ship_target/
transmit_ship_weapons_free already exist and are reusable for TARGET/WEAPONS FREE/HOLD
FIRE -- see player_input.gd's own usage) or FormationOrder/IndividualOrder (APPROACH/
WITHDRAW/MAINTAIN FORMATION/FOLLOW/INTERCEPT/COVER/DEFEND need real construction --
some of these kinds may not exist yet on ShipCombatDirective/FormationOrder, e.g. DEFEND/
COVER/FOLLOW/INTERCEPT sound like they need a "follow/escort another ship" concept that
doesn't currently exist anywhere in simulation/*.gd -- check first with grep before
assuming, and if a kind genuinely doesn't exist yet, that's fine: implement the ones that
map cleanly onto existing primitives this pass, log the rest as an honest gap in
ASSUMPTIONS.md/state.md rather than inventing new simulation mechanics under item D's
banner (item D is a UI/routing item per its own checklist text, not a request for new
combat mechanics) -- same "small, honest, incremental slice" discipline as items A-C.
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
Last pass finished: 2026-09-26 14:04 UTC (scheduled dev pass, fired from the normal 3h
cron; cron prompt still says "§56.1" -- that is a stale/generic scheduled-task prompt
that this skill's own instructions say NOT to update via update_trigger, so it is
intentionally ignored in favor of this file, which is the actual source of truth):
implemented and headless-verified §56.3 item C (RMB move order + course-line
visualization) -- scripts/move_order_controller.gd (new), tactical_plot_projector.gd's
unproject(), tactical_plot.gd's RMB handling + _draw_move_orders/_draw_move_order_arrowhead
/_find_icon, main.gd wiring + per-tick prune_completed() call. 2 new/extended test files
(29 + 3 checks, all passing, plus 3 existing regression suites re-run clean:
test_command_group_controller.gd, test_individual_orders.gd, test_command_transmission.gd).
Two non-obvious implementation bugs found and fixed by this pass's own new test before
landing (see ASSUMPTIONS.md "§56.3 item C" for the full explanation -- do not
"re-simplify" issue_formation_order_now back to issue_echelon_order, or the
change_course/change_speed branch back to a single change_speed call, without reading
that entry first). ASSUMPTIONS.md/CHANGELOG.md updated; pushed this pass. D-I not
started.
