extends Control
## OrderMenu
##
## ТЗ §56.3 item D / §1.10.7: the contextual order-menu POPUP itself --
## presentation + click-hit-testing ONLY (§42 convention, same as
## TacticalPlot/CommandGroupPanel): OrderMenuController (scripts/
## order_menu_controller.gd) decides WHICH entries are offered and WHAT
## each one does; this class only reads that controller's plain state
## (`is_open`/`menu_screen_pos`/`menu_entries`) once per tick via
## `sync()` (called from main.gd._on_tick, same convention as
## Hud.update()/TacticalPlot.update()) and draws whatever it was handed,
## reporting back which row was clicked (`controller.execute`) or that
## the menu was dismissed with no choice made (`controller.dismiss`) --
## it invents no order semantics of its own. `controller` is assigned
## once by main.gd (same convention as TacticalPlot.selection/
## move_order_controller), not passed per-call, so OrderMenuController
## itself never needs to hold a reference back to this Control (see that
## class's own doc comment on why -- headless testability).
##
## PLAIN Control, not Godot's own PopupMenu node (ASSUMPTION, see
## ASSUMPTIONS.md "§56.3 item D"): no popup-menu widget is used anywhere
## else in this codebase yet (Hud/CommandGroupPanel are both plain
## Label-based readouts, TacticalPlot's own selection ring/drag-box are
## hand-drawn), so a hand-drawn Control with draw_string/draw_rect rows
## keeps this in the same "no extra UI framework surface" style as every
## other panel here.
##
## MODAL-OVERLAY DISMISS (ASSUMPTION, see ASSUMPTIONS.md "§56.3 item D"):
## while open, this Control covers the FULL viewport with
## mouse_filter STOP, so ANY click other than on one of its own drawn
## rows closes the menu without acting -- the simplest possible "click
## outside to dismiss" behavior. This is why main.gd adds this node
## AFTER TacticalPlot: later siblings receive/consume mouse input first,
## so while the menu is open it transparently sits "on top" and
## intercepts every click (including ones over the plot) until closed;
## while closed (mouse_filter IGNORE, the default), it is fully
## transparent to input and TacticalPlot behaves exactly as before this
## item existed.
class_name OrderMenu

const ROW_HEIGHT_PX: float = 22.0
const ROW_WIDTH_PX: float = 150.0
const PADDING_PX: float = 6.0
const BG_COLOR := Color(0.05, 0.08, 0.07, 0.95)
const BORDER_COLOR := Color(0.5, 0.8, 0.7, 0.8)
const ROW_HOVER_COLOR := Color(0.3, 0.55, 0.5, 0.6)
const TEXT_COLOR := Color(0.9, 0.95, 0.9)

## Assigned once by main.gd, guarded against null everywhere it's read --
## same optional-collaborator convention as TacticalPlot.selection.
var controller: OrderMenuController = null

var _entries: Array = []  # Array[{"label": String, "kind": String}] -- last synced from controller.menu_entries
var _origin_px: Vector2 = Vector2.ZERO  # top-left of the drawn button box, clamped on-screen
var _hover_index: int = -1

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

## Call once per simulation tick (see class doc comment). Mirrors
## `controller`'s is_open/menu_entries/menu_screen_pos into this
## Control's own visible/_entries/_origin_px, recomputing the clamped
## on-screen box position only on the tick the menu actually (re)opens
## -- not every tick -- so an already-open menu's box does not jitter if
## the underlying viewport were ever resized while it's up.
func sync() -> void:
	if controller == null:
		return
	if controller.is_open and not visible:
		_entries = controller.menu_entries
		_hover_index = -1
		var box_size: Vector2 = _box_size()
		var viewport_size: Vector2 = get_viewport_rect().size
		_origin_px = Vector2(
			clampf(controller.menu_screen_pos.x, 0.0, maxf(0.0, viewport_size.x - box_size.x)),
			clampf(controller.menu_screen_pos.y, 0.0, maxf(0.0, viewport_size.y - box_size.y))
		)
		visible = true
		mouse_filter = Control.MOUSE_FILTER_STOP
		queue_redraw()
	elif not controller.is_open and visible:
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_entries = []
		queue_redraw()

func _box_size() -> Vector2:
	return Vector2(ROW_WIDTH_PX + PADDING_PX * 2.0, PADDING_PX * 2.0 + ROW_HEIGHT_PX * _entries.size())

func _draw() -> void:
	if not visible or _entries.is_empty():
		return
	var box_size: Vector2 = _box_size()
	draw_rect(Rect2(_origin_px, box_size), BG_COLOR, true)
	draw_rect(Rect2(_origin_px, box_size), BORDER_COLOR, false, 1.5)
	for i in range(_entries.size()):
		var row_top: Vector2 = _origin_px + Vector2(PADDING_PX, PADDING_PX + ROW_HEIGHT_PX * i)
		if i == _hover_index:
			draw_rect(Rect2(row_top, Vector2(ROW_WIDTH_PX, ROW_HEIGHT_PX)), ROW_HOVER_COLOR, true)
		draw_string(ThemeDB.fallback_font, row_top + Vector2(6, ROW_HEIGHT_PX * 0.7), _entries[i]["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_COLOR)

## Modal while open (see class doc's MODAL-OVERLAY DISMISS section):
## motion updates row hover; a released LMB either fires the hovered
## row's kind (`controller.execute`) or, if outside every row (including
## anywhere in the full-viewport overlay), dismisses with no action
## (`controller.dismiss`). Either call flips `controller.is_open` to
## false immediately (see order_menu_controller.gd), so the NEXT sync()
## (next tick) will hide this Control -- this handler does not hide
## itself directly, keeping "visible" driven entirely by sync() reading
## controller state, per this class's own single-source-of-truth
## convention. Every other event while open is swallowed -- nothing else
## on screen should react while a modal popup is up.
func _gui_input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventMouseMotion:
		var idx: int = _row_at(event.position)
		if idx != _hover_index:
			_hover_index = idx
			queue_redraw()
		accept_event()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var idx: int = _row_at(event.position)
		if controller != null:
			if idx >= 0:
				controller.execute(_entries[idx]["kind"])
			else:
				controller.dismiss()
		accept_event()
		return

	accept_event()

## -1 if `local_pos` is outside the drawn button box entirely, or inside
## it but not over any specific row (padding); else the row index.
func _row_at(local_pos: Vector2) -> int:
	if _entries.is_empty():
		return -1
	var box_size: Vector2 = _box_size()
	if not Rect2(_origin_px, box_size).has_point(local_pos):
		return -1
	var rel_y: float = local_pos.y - (_origin_px.y + PADDING_PX)
	if rel_y < 0.0:
		return -1
	var idx: int = int(rel_y / ROW_HEIGHT_PX)
	if idx < 0 or idx >= _entries.size():
		return -1
	return idx
