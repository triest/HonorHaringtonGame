extends CanvasLayer
## ImpactBadgeOverlay
##
## Screen-space "x N" strike badges (ТЗ §42: draws only what ImpactBadgeModel
## already merged from ImpactRecord snapshots; no simulation access). One badge
## per struck ship: a 20-missile salvo shows as a single "x20" tag with the
## yield the defences absorbed and the damage that got through, floating up and
## fading, instead of twenty overlapping labels. Pooled by construction: it
## draws the model's dictionary each frame and allocates no nodes.
class_name ImpactBadgeOverlay

const MissileResolution = preload("res://simulation/missile_resolution.gd")
const ImpactBadgeModel = preload("res://scripts/impact_badge_model.gd")

var director: ImpactFxDirector
var _canvas: Control

class _Canvas extends Control:
	var owner_overlay: ImpactBadgeOverlay

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if owner_overlay != null:
			owner_overlay._paint(self)

func _ready() -> void:
	layer = 4
	_canvas = _Canvas.new()
	_canvas.owner_overlay = self
	add_child(_canvas)

func _process(_delta: float) -> void:
	if director != null and not director.badge_model.badges.is_empty():
		_canvas.queue_redraw()

static func outcome_color(outcome: int) -> Color:
	match outcome:
		MissileResolution.Outcome.WEDGE_BLOCKED:
			return Color(0.65, 0.88, 1.0)
		MissileResolution.Outcome.SIDEWALL_ATTENUATED:
			return Color(0.98, 0.78, 0.2)
		MissileResolution.Outcome.HIT_UNPROTECTED:
			return Color(1.0, 0.35, 0.2)
		MissileResolution.Outcome.FORMATION_COVERED:
			return Color(0.7, 0.75, 0.85)
		_:
			return Color.WHITE

## Text for one badge (pure, testable): "x12" on the first line, then what the
## defences soaked or what got through.
static func badge_lines(badge: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var hits: int = int(badge["hits"])
	lines.append("×%d" % hits if hits > 1 else "УДАР")
	if float(badge["damage"]) > 0.5:
		lines.append("УРОН %d" % int(round(float(badge["damage"]))))
	if float(badge["absorbed"]) > 0.5:
		lines.append("ПОГЛ. %d" % int(round(float(badge["absorbed"]))))
	return lines

func _paint(canvas: Control) -> void:
	if director == null:
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var font: Font = ThemeDB.fallback_font
	var now_s: float = ShipView.fx_clock_s()
	var model: ImpactBadgeModel = director.badge_model
	for ship_id in model.badges.keys():
		var badge: Dictionary = model.badges[ship_id]
		var view: Node3D = director._views.get(ship_id)
		if view == null or not is_instance_valid(view):
			continue
		var world_pos: Vector3 = view.global_position
		if cam.is_position_behind(world_pos):
			continue
		var age: float = now_s - float(badge["last_s"])
		var screen: Vector2 = cam.unproject_position(world_pos) + Vector2(0.0, -34.0 - age * 14.0)
		var alpha: float = ImpactBadgeModel.alpha(badge, now_s)
		var color: Color = outcome_color(ImpactBadgeModel.dominant_outcome(badge))
		var lines: PackedStringArray = badge_lines(badge)
		for i in range(lines.size()):
			var size: int = 22 if i == 0 else 13
			var text: String = lines[i]
			var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			var pos := Vector2(screen.x - width * 0.5, screen.y + float(i) * 15.0 + (4.0 if i > 0 else 0.0))
			canvas.draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.8 * alpha))
			canvas.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(color.r, color.g, color.b, alpha))
