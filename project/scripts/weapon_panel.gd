extends Control
## WeaponPanel
##
## §56.3 item E ("Weapon-type selection panel for the selected ship",
## §1.10.8) -- the PRESENTATION half. WeaponPanelController (scripts/
## weapon_panel_controller.gd) decides WHAT rows exist and WHAT clicking
## one does; this class only reads that controller's plain state
## (`is_visible`/`rows`) once per tick via `sync()` (called from
## main.gd._on_tick, same convention as Hud.update()/TacticalPlot.
## update()/OrderMenu.sync()) and draws whatever it was handed, reporting
## back which row was clicked (`controller.execute_row`) -- it invents no
## order semantics of its own. Same PLAIN hand-drawn Control convention
## as OrderMenu/TacticalPlot (no popup-menu/slider widget used anywhere
## in this codebase).
##
## UNLIKE OrderMenu, this panel is NOT modal: it is a persistent side
## panel, visible for as long as exactly one own ship is selected (see
## WeaponPanelController's own visibility rule), sized to its own row
## count rather than covering the full viewport -- Godot only routes
## input to a Control within its own rect, so clicks anywhere outside
## this panel's small box (e.g. on the tactical plot or the 3D view)
## pass through to whatever sibling is there exactly as before this item
## existed; nothing else needed to change to keep that working.
##
## LAYOUT (ASSUMPTION, logged in ASSUMPTIONS.md "§56.3 item E", same
## status as CommandGroupPanel's own interim placement note): fixed
## bottom-left position, recomputed against the current viewport size
## every time the panel (re)shows or its row count changes, so it never
## overlaps Hud (top-left) or CommandGroupPanel (also top-left, lower)
## -- not a claim this matches the reference image's exact "weapon/order
## panels on bottom" geometry pixel-for-pixel, which belongs with item
## F's real shared layout pass (see CommandGroupPanel's own doc comment
## for why that is being deferred to item F rather than guessed at panel
## by panel).
class_name WeaponPanel

const ROW_HEIGHT_PX: float = 20.0
const ROW_WIDTH_PX: float = 280.0
const PADDING_PX: float = 6.0
const MARGIN_PX: float = 12.0
const BG_COLOR := Color(0.05, 0.07, 0.09, 0.92)
const BORDER_COLOR := Color(0.55, 0.7, 0.85, 0.85)
const ROW_HOVER_COLOR := Color(0.3, 0.45, 0.55, 0.55)
const TEXT_COLOR := Color(0.85, 0.92, 0.95)
const HEADER_COLOR := Color(0.6, 0.85, 1.0)

## Assigned once by main.gd, guarded against null everywhere it's read --
## same optional-collaborator convention as OrderMenu.controller.
var controller: WeaponPanelController = null

var _entries: Array = []  # Array[{"label": String, "kind": String}], last synced from controller.rows
var _hover_index: int = -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

## Call once per simulation tick (see class doc comment). Mirrors
## `controller.is_visible`/`rows` into this Control's own
## visible/_entries/size/position -- recomputed only while the panel is
## actually visible (or on the tick it (re)appears), same "don't jitter
## an already-open overlay" convention as OrderMenu.sync().
func sync() -> void:
	if controller == null:
		return
	if controller.is_visible:
		_entries = controller.rows
		var box_size: Vector2 = _box_size()
		var viewport_size: Vector2 = get_viewport_rect().size
		position = Vector2(MARGIN_PX, maxf(MARGIN_PX, viewport_size.y - box_size.y - MARGIN_PX))
		size = box_size
		visible = true
		queue_redraw()
	else:
		visible = false
		_entries = []
		_hover_index = -1
		queue_redraw()

func _box_size() -> Vector2:
	return Vector2(ROW_WIDTH_PX + PADDING_PX * 2.0, PADDING_PX * 2.0 + ROW_HEIGHT_PX * maxi(_entries.size(), 1))

func _draw() -> void:
	if not visible or _entries.is_empty():
		return
	var box_size: Vector2 = _box_size()
	draw_rect(Rect2(Vector2.ZERO, box_size), BG_COLOR, true)
	draw_rect(Rect2(Vector2.ZERO, box_size), BORDER_COLOR, false, 1.5)
	for i in range(_entries.size()):
		var row_top: Vector2 = Vector2(PADDING_PX, PADDING_PX + ROW_HEIGHT_PX * i)
		var entry: Dictionary = _entries[i]
		var kind: String = String(entry.get("kind", ""))
		var clickable: bool = kind != ""
		if clickable and i == _hover_index:
			draw_rect(Rect2(row_top, Vector2(ROW_WIDTH_PX, ROW_HEIGHT_PX)), ROW_HOVER_COLOR, true)
		var color: Color = TEXT_COLOR if clickable else HEADER_COLOR
		draw_string(ThemeDB.fallback_font, row_top + Vector2(4, ROW_HEIGHT_PX * 0.72), String(entry.get("label", "")), HORIZONTAL_ALIGNMENT_LEFT, ROW_WIDTH_PX - 4.0, 12, color)

## A released LMB on a clickable row calls `controller.execute_row`;
## anywhere else within this panel's own (small) rect just consumes the
## event harmlessly -- there is nothing to dismiss (see class doc
## comment: this panel is not modal, unlike OrderMenu).
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
		if idx >= 0 and controller != null:
			controller.execute_row(String(_entries[idx].get("kind", "")))
			queue_redraw()
		accept_event()
		return

	accept_event()

## -1 if `local_pos` is outside the drawn box, over a non-clickable
## header/info row, or past the last row; else the row index.
func _row_at(local_pos: Vector2) -> int:
	if _entries.is_empty():
		return -1
	var box_size: Vector2 = _box_size()
	if not Rect2(Vector2.ZERO, box_size).has_point(local_pos):
		return -1
	var rel_y: float = local_pos.y - PADDING_PX
	if rel_y < 0.0:
		return -1
	var idx: int = int(rel_y / ROW_HEIGHT_PX)
	if idx < 0 or idx >= _entries.size():
		return -1
	if String(_entries[idx].get("kind", "")) == "":
		return -1  # header/info row, not clickable
	return idx
