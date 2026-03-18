## Debug overlay that displays per-bone spring strength as colored dots projected
## onto the viewport. Toggle with F3 at runtime. Red = weak, green = full strength.
class_name StrengthDebugHUD
extends Control

@export var spring_resolver_path: NodePath
@export var rig_builder_path: NodePath

var _spring: SpringResolver
var _rig_builder: PhysicsRigBuilder
var _visible: bool = false

const DOT_RADIUS := 6.0
const FONT_SIZE := 12


func _ready() -> void:
	if not spring_resolver_path.is_empty():
		_spring = get_node_or_null(spring_resolver_path) as SpringResolver
	if not rig_builder_path.is_empty():
		_rig_builder = get_node_or_null(rig_builder_path) as PhysicsRigBuilder
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		_visible = not _visible
		visible = _visible
		queue_redraw()


func _process(_delta: float) -> void:
	if _visible:
		queue_redraw()


func _draw() -> void:
	if not _visible or not _spring or not _rig_builder:
		return

	var camera := get_viewport().get_camera_3d()
	if not camera:
		return

	var bodies := _rig_builder.get_bodies()
	for rig_name: String in bodies:
		var body: RigidBody3D = bodies[rig_name]
		var world_pos := body.global_position

		# Skip if behind camera
		if not camera.is_position_behind(world_pos):
			var screen_pos := camera.unproject_position(world_pos)
			var strength := _spring.get_bone_strength(rig_name)
			var base := _spring.get_base_strength(rig_name)
			var ratio := strength / base if base > 0.001 else 1.0

			# Color: red (0) → yellow (0.5) → green (1.0)
			var color: Color
			if ratio < 0.5:
				color = Color.RED.lerp(Color.YELLOW, ratio * 2.0)
			else:
				color = Color.YELLOW.lerp(Color.GREEN, (ratio - 0.5) * 2.0)

			draw_circle(screen_pos, DOT_RADIUS, color)
			draw_string(ThemeDB.fallback_font, screen_pos + Vector2(DOT_RADIUS + 2, 4),
				"%s %.2f" % [rig_name, strength], HORIZONTAL_ALIGNMENT_LEFT,
				-1, FONT_SIZE, color)
