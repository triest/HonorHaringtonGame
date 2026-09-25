# Honorverse dev state (updated every pass)
Phase: §56.3 full tactical command UI (REPLACES §56.2 as top priority; §56.2's finished pieces are the foundation, not discarded)
Context: user rejected §56.2's result as too minimal/single-ship and supplied a detailed
UI spec (AGENTS.md §56.3, verbatim from project's CHATGPT.md) plus a reference image at
docs/reference/tactical_command_ui_reference.png (VIEW THIS IMAGE FIRST -- it is the visual
target: fleet-view squadron list + tactical-plot minimap on top, closer 3D view with
weapon/order panels on bottom). Read AGENTS.md §56.3 and CLOUD.md §1.10 in full before
starting -- they are long and detailed, do not skim.
What already exists from §56.2/§56.3 items A-B (do NOT rebuild, extend it):
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
    worlds in unit tests, see simulation/tests/test_command_group_controller.gd, 8/8
    passing) -- NOT yet confirmed with a real player (scenario is still 1v1, so live
    grouping of 2+ own ships isn't exercisable yet; item H upgrades that). Explicitly NOT
    done as part of B: disbanding/merging/renaming a group after creation -- open
    follow-up, see ASSUMPTIONS.md "§56.3 item B".
Checklist (§56.3, new scope, roughly in an order that builds incrementally toward the
15-step MVP acceptance test in AGENTS.md §56.3 / §1.10.14):
  [x] A. Multi-select: Ctrl+LMB add to selection, Shift+LMB extend, LMB drag-box select
      multiple contacts. (See CHANGELOG.md 2026-09-23 entry for full detail.)
  [x] B. Selection becomes a named command group (visual list, left-side squadron-list
      panel) -- reuses CommandEchelon/FormationState via CommandGroupController/
      CommandGroupPanel (see "What already exists" above and CHANGELOG.md 2026-09-25
      entry for full detail). Headless-verified only, not live-confirmed.
  [ ] C. RMB-on-space move order for the current selection (single ship or group), with a
      visual course line/vector/predicted-turn-point per §1.10.6 -- routes into existing
      IndividualOrder/FormationOrder, ship still obeys real acceleration/inertia (no
      teleport). For a grouped selection (a CommandGroupController-created echelon), route
      the order through world.issue_formation_order*/issue_echelon_order rather than
      individually ordering each member.
  [ ] D. Contextual order menu after selecting own + designating enemy: at minimum ATTACK,
      FOCUS FIRE, HOLD FIRE, WEAPONS FREE, DEFEND, MAINTAIN FORMATION (full list in
      §1.10.7) -- routes into ShipCombatDirective/FormationOrder, no UI-only order model.
  [ ] E. Weapon-type selection panel for the selected ship: missiles (type + salvo size +
      target + FIRE), counter-missiles (auto/manual/hold), energy weapons, PD
      (auto/hold/priority-target) -- must only show weapons the selected ship's class
      actually has mounted (no showing weapons it doesn't carry).
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
Next concrete step: item C -- RMB-on-space move order for the current selection, per
§1.10.6 (AGENTS.md ~line 2382). Needs: (1) a new input handler (likely extending
tactical_plot.gd's existing _gui_input, or a new small controller alongside
CommandGroupController -- read tactical_plot.gd's current mouse handling first, RMB is
not yet consumed there) that on RMB click against the plot computes a world-space target
point from the click (TacticalPlotProjector has the plot's own screen<->world math, reuse
it, do not re-derive a second projection), (2) routing: if `selection.selected_ids`
resolves (via the same team/ship filtering CommandGroupController uses) to a ship that is
a formation guide OR any member of a CommandGroupController-created echelon, issue the
order at the FORMATION/ECHELON level (world.issue_formation_order/issue_echelon_order),
not per-ship; a lone selected ship (not in any formation) uses the existing
IndividualOrder path (see IndividualOrder.change_course/change_speed, already used by
player_input.gd -- reuse that, don't invent a second order type), (3) visualization: a
drawn line/vector from ship to target point plus predicted turn point, added to
tactical_plot.gd's _draw() (it already draws contact icons/velocity leaders there -- same
per-frame draw, no new Control needed) per §1.10.6's explicit list (course line, arrow,
endpoint, predicted vector, turn point if needed) -- ASSUMPTION calls on exact visual
style are fine, log them in ASSUMPTIONS.md same as items A/B did. Read AGENTS.md
§1.10.6's full text again before starting (sed -n '2382,2413p' AGENTS.md) -- it was only
skimmed via CommandGroupController's own build this pass, not fully re-read against C's
exact requirements yet.
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
Last pass finished: 2026-09-25 10:xx UTC (scheduled dev pass, fired from the normal 3h
cron; cron prompt still says "§56.1" -- that is a stale/generic scheduled-task prompt
that this skill's own instructions say NOT to update via update_trigger, so it is
intentionally ignored in favor of this file, which is the actual source of truth):
implemented and headless-verified §56.3 item B (named command group + squadron-list
panel) -- command_group_controller.gd, command_group_panel.gd, main.gd wiring,
project.godot input action, 1 new test file (8 checks, all passing, plus 2 regression
test files re-run clean), ASSUMPTIONS.md "§56.3 item B" entry, CHANGELOG.md updated;
pushed this pass. C-I not started.
