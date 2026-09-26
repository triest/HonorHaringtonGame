extends RefCounted
## SelectionState
##
## ТЗ §56.3 item A ("Multi-select") / §1.10.4 ("Выбранные объекты должны
## быть объединены в единую командную группу"): the single shared list of
## currently-selected contact/ship ids, independent of any one view.
## Deliberately a plain data holder with no simulation/order logic of its
## own -- same convention as everything else in this codebase that keeps
## presentation/selection state separate from SimulationWorld's actual
## order-issuing API (§42): this class never calls into `world`, it only
## tracks WHICH ids are currently selected so that TacticalPlot (input),
## a future squadron-list panel (§56.3 item B) and a future order-menu
## panel (§56.3 item D) all read/write the exact same selection instead
## of each view inventing its own parallel notion of "what's selected".
##
## Ids are opaque strings -- this class does not care whether an id names
## a ship, a missile, or (later) a formation/group marker; that
## interpretation belongs to whoever issues an order against the
## selection (§56.3 items C/D), not to selection-tracking itself.
##
## INTERACTION MODEL (ASSUMPTION -- §1.10.4's text is explicit about LMB
## and CTRL+LMB, "add to selection", but only says SHIFT+LMB should
## "expand/change the existing group according to the interface's
## context" without pinning down exact semantics; logged in
## ASSUMPTIONS.md "§56.3 item A" the same way §56.2's distance-
## compression convention was logged as a deliberate interpretation of
## ambiguous spec text):
##   - select_only(ids): plain LMB click/drag-box with no modifier --
##     replaces the whole selection.
##   - toggle(id): CTRL+LMB -- adds the id if not selected, REMOVES it if
##     already selected (a true toggle, matching "add to selection" for
##     the common case of clicking something new, while also giving the
##     player an obvious way to deselect one member of a group without
##     starting over).
##   - add_only(ids): SHIFT+LMB / SHIFT+drag-box -- adds any ids not
##     already selected, never removes anything (distinct from toggle()
##     so SHIFT reliably grows a group, matching "extend" more literally
##     than a toggle would).
class_name SelectionState

signal selection_changed(selected_ids: Array)
## §56.3 item D (§1.10.7 "После выбора собственного корабля/группы и
## указания вражеского объекта мышью появляется контекстное меню
## приказов"): a SEPARATE single-id concept from `selected_ids` above --
## deliberately NOT a second multi-select and NOT folded into the
## selection array itself, per this file's own doc comment above ("a
## small new concept... not a second multi-select", see .tools/state.md
## "§56.3 item D" for the exact reasoning this was logged against).
## Designating a target does not touch `selected_ids` at all: the whole
## point of the interaction OrderMenuController implements is that the
## player's own-ship selection stays intact while a hostile contact is
## additionally marked as "the target half" of an order. "" = no target
## currently designated.
signal designated_target_changed(target_id: String)

var selected_ids: Array = []  # Array[String], selection order preserved
var designated_target_id: String = ""

func select_only(ids: Array) -> void:
	selected_ids = ids.duplicate()
	selection_changed.emit(selected_ids)

func toggle(id: String) -> void:
	if selected_ids.has(id):
		selected_ids.erase(id)
	else:
		selected_ids.append(id)
	selection_changed.emit(selected_ids)

func add_only(ids: Array) -> void:
	var changed: bool = false
	for id in ids:
		if not selected_ids.has(id):
			selected_ids.append(id)
			changed = true
	if changed:
		selection_changed.emit(selected_ids)

func clear() -> void:
	if selected_ids.is_empty():
		return
	selected_ids.clear()
	selection_changed.emit(selected_ids)

func is_selected(id: String) -> bool:
	return selected_ids.has(id)

func is_empty() -> bool:
	return selected_ids.is_empty()

## §56.3 item D: mark `id` (expected to be a hostile contact id) as the
## current order-menu target. A no-op (no redundant signal emission) if
## `id` is already the designated target, same idempotence convention as
## clear()/other setters in this class.
func designate_target(id: String) -> void:
	if designated_target_id == id:
		return
	designated_target_id = id
	designated_target_changed.emit(designated_target_id)

func clear_designated_target() -> void:
	if designated_target_id == "":
		return
	designated_target_id = ""
	designated_target_changed.emit(designated_target_id)

func has_designated_target() -> bool:
	return designated_target_id != ""
