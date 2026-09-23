# Honorverse dev state (updated every pass)
Phase: §56.2 UI/control correction -- tactical plot, mouse-first, canon-scale (REPLACES §56.1's closed status as top priority)
Context: §56.1 (camera/geometry/weapon-fx/HUD-text/hotkeys/1v1-scenario/win-lose/Windows-export)
was implemented and its Windows .exe was confirmed launching. The user
live-tested it and explicitly rejected the RESULT as a UI/design
problem, not a bug: ships nearly touching (wrong scale vs canon),
control not mouse-first, no tactical plot, no distinct missile display.
Explicit genre confirmation from the user: tactical strategy, command
from a plot, not a piloted dogfight.
Read AGENTS.md §56.2 in full (right after §56.1, before "### Milestone 1")
and CLOUD.md §1.9 before starting a new item -- do not re-derive from
CHANGELOG alone, the actual requirements are spelled out there in detail.
Checklist (§56.2):
  [x] A. Tactical plot: top-down/God's-eye 2D display, every SensorContact as
      an IFF-colored icon + velocity vector leader, range/bearing from player ship.
      DONE this pass: scripts/tactical_plot.gd (Control, class_name TacticalPlot),
      wired into main.gd alongside Hud (main.gd's HUD_POV_SHIP_ID). Reads
      world.sensor_contacts[pov_ship_id] (NOT world.ships directly) so it
      honestly respects §23 sensor detection/fog-of-war -- see that file's
      own doc comment for the reasoning. Auto-scaling linear-radial plot,
      range rings with km/Mkm labels, own-ship square + velocity leader,
      per-contact triangle icon colored by hostility (red=hostile,
      green=friendly, yellow=neutral) + its own velocity leader + a
      "id  range  bearing" text label. Pure world->screen mapping factored
      into scripts/tactical_plot_projector.gd (class_name
      TacticalPlotProjector, static project() function) so it is
      headless-unit-testable without a live Control/Viewport.
  [x] B. Missiles shown as their own distinctly-marked icon/track on the plot,
      separate from ship contacts. DONE this pass, same TacticalPlot/update()
      pass as A: missile sensor contacts (told apart from ship contacts via
      `contact.target is MissileState`, same duck-type check
      SimulationWorld._update_missiles already uses for counter-missiles)
      are drawn as a yellow X/cross (matches WeaponFx's 3D missile marker
      colour), NOT the ship triangle -- distinct shape, not just colour.
  [ ] C. Mouse-first control: click a contact/icon on the plot to select it;
      click/drag on the plot to set course or designate target; mouse-driven
      weapons-free/hold and other ShipCombatDirective orders. Existing hotkeys
      (scripts/player_input.gd) stay as secondary accelerators, do not remove them.
      NOT STARTED. NOTE: TacticalPlot currently has
      `mouse_filter = Control.MOUSE_FILTER_IGNORE` (placeholder, see its
      _ready() comment) -- this item must change that to actually receive
      clicks, plus do real hit-testing against the same _contacts array
      already built each update() (icon positions are already computed
      every frame via TacticalPlotProjector, just not stored per-contact
      screen-rect yet -- item C will need to keep each contact's last-drawn
      icon_pos/radius for hit-testing, not recompute a parallel copy).
  [ ] D. Canon-scale distances: reposition the hardcoded scenario (main.gd's
      alpha/beta) to a canon-plausible range per §8.1 (hundreds of thousands+
      km), using a documented symbolic distance-compression convention (NOW
      CHOSEN AND LOGGED for the PLOT rendering side -- see ASSUMPTIONS.md
      "§56.2 -- distance-compression convention", "CHOSEN this pass" addendum;
      linear radial auto-scaling plot, exact range always shown as text).
      NOT STARTED: this item is about the SIMULATION scenario itself
      (main.gd's alpha=(-5000,0,0)/beta=(5000,0,0), i.e. ~10km apart today,
      and demo_laser's max_range_m=500_000 i.e. 500km -- BOTH are far short
      of §8.1's ~3,600,000km energy-weapon range / 15-63M km missile
      envelopes). CAUTION for whoever picks this up: repositioning ships to
      a true canon separation without also reconsidering demo_laser's
      max_range_m will put them permanently out of weapon range and silently
      break the already-verified-live "ships actually fire on each other"
      behavior from §56.1 item 6/3 -- decide and document (ASSUMPTIONS.md)
      a deliberate compromise distance/range pair (or bump demo_laser's
      range too) rather than moving ships alone and finding out combat
      stopped firing only via a live run.
  [ ] E. Existing subsystem-text HUD (§56.1 item 4) stays as a secondary panel
      alongside the new plot, not replaced. SATISFIED SO FAR AS A SIDE
      EFFECT of how A/B were wired: hud.update() call in main.gd._on_tick
      was left untouched, tactical_plot.update() was added alongside it,
      not instead of it -- both panels are live in the same scene right
      now. Left unchecked because this needs the user's live confirmation
      like the rest of §56.2 (see IMPORTANT note below), not because
      anything is known to be missing.
Next concrete step: item C (mouse-first control). Start with click-to-select:
on TacticalPlot, switch mouse_filter to STOP, handle
_gui_input()/_unhandled_input() for a left click, hit-test against each
contact's last-drawn icon position (store icon_pos+a small hit radius per
contact in _contacts during _draw(), or compute it once in update() via
TacticalPlotProjector before _draw() so hit-testing does not depend on
_draw() having already run this frame), and on a hit call
world.transmit_ship_target(pov_ship_id, contact_id) for a ship contact
(reuse PlayerInput's existing pattern) -- then click/drag for course-setting
and a weapons-free/hold interaction, per AGENTS.md §56.2 item 1's full text.
Keep scripts/player_input.gd's hotkeys working unchanged (secondary
accelerators, per the checklist item's own text) -- do not remove them.
Tests: still fast-visible-result mode -- skip full simulation suite, headless
import/smoke check only, until §56.2 fully closes. This pass ran: headless
--import (clean), the new simulation/tests/test_tactical_plot_projector.gd
(8/8 pure-geometry tests pass -- bearing conventions, linear-scale-until-
clamped, true range_m preserved through clamping, degenerate same-position
case), and a headless res://scenes/main.tscn --quit-after 120 smoke run
(exit 0, exactly the same 16x baseline "Parameter m is null" dummy-renderer
artifact already documented from the §56.1 item 6 pass, zero NEW error/
warning types -- TacticalPlot's draw_string/ThemeDB.fallback_font/Control
calls did not introduce anything new in headless mode).
IMPORTANT -- do not repeat the §56.1 mistake: do NOT report §56.2 "closed" on
headless verification alone. §56.1 was marked closed on headless evidence and
failed the user's actual first live run (wrong scale, no plot, hotkey-only).
Items A/B above are implemented and headless-verified only -- they still need
the user's live confirmation (does the plot actually show contacts+missiles
distinctly and legibly on their real screen, is the auto-scaling readable in
practice) before being treated as truly done, and C/D are not started at all.
Do not claim §56.2 done until C, D, and E are also implemented AND the user
has confirmed live.
Blockers: none currently. Open question for whoever picks up D: see the
CAUTION paragraph under item D above (ship separation vs weapon range
coupling).
Last pass finished: 2026-09-23 (scheduled dev pass: implemented and
headless-verified §56.2 items A+B -- tactical_plot.gd/
tactical_plot_projector.gd, wired into main.gd, new unit test, ASSUMPTIONS.md
distance-compression convention logged, CHANGELOG.md updated; C/D/E not
started; pushed this pass -- see CHANGELOG.md for full detail).
