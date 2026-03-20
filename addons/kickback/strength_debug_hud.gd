## Debug overlay showing per-bone spring strength, LOD tier, ragdoll state,
## and optional LOD zone visualization. Toggle with F3 at runtime.
## Shift+F3 toggles LOD distance zone circles.
@icon("res://addons/kickback/icons/strength_debug_hud.svg")
class_name StrengthDebugHUD
extends Control

## Path to the SpringResolver for reading per-bone strength values.
@export var spring_resolver_path: NodePath
## Path to the PhysicsRigBuilder for accessing body world positions.
@export var rig_builder_path: NodePath
## Path to the KickbackCharacter for displaying tier, state, and distance info.
@export var kickback_character_path: NodePath

var _spring: SpringResolver
var _rig_builder: PhysicsRigBuilder
var _kickback_char: KickbackCharacter
var _visible: bool = false
var _show_lod_zones: bool = false

const DOT_RADIUS := 5.0
const FONT_SIZE := 12
const LINE_HEIGHT := 16.0
const PANEL_MARGIN := 8.0
const PANEL_COLOR := Color(0.0, 0.0, 0.0, 0.65)
const HEADER_COLOR := Color(0.9, 0.9, 0.9)
const VALUE_COLOR := Color(0.75, 0.75, 0.75)
const LEGEND_WEAK := Color(0.9, 0.2, 0.2)
const LEGEND_MID := Color(0.9, 0.8, 0.2)
const LEGEND_FULL := Color(0.2, 0.9, 0.3)

const LOD_COLORS := [
	Color(0.2, 0.9, 0.3, 0.6),   # Active ragdoll — green
	Color(0.9, 0.8, 0.2, 0.6),   # Partial ragdoll — yellow
	Color(0.9, 0.5, 0.2, 0.6),   # Flinch — orange
]
const LOD_LABELS := ["ACTIVE", "PARTIAL", "FLINCH"]
const DEFAULT_LOD_DISTANCES := [10.0, 25.0, 50.0]
const LOD_SEGMENTS := 48

var _lod_distances: Array = [10.0, 25.0, 50.0]


func _ready() -> void:
	if not spring_resolver_path.is_empty():
		_spring = get_node_or_null(spring_resolver_path) as SpringResolver
	if not rig_builder_path.is_empty():
		_rig_builder = get_node_or_null(rig_builder_path) as PhysicsRigBuilder
	if not kickback_character_path.is_empty():
		_kickback_char = get_node_or_null(kickback_character_path) as KickbackCharacter
	_discover_lod_distances()
	visible = false
	print("Kickback: Press F3 for debug overlay (Shift+F3 for LOD zones)")


func _discover_lod_distances() -> void:
	# Check autoload first (same pattern as KickbackCharacter)
	var manager := get_node_or_null("/root/KickbackManager") as KickbackManager
	if not manager:
		var root := get_tree().current_scene
		if root:
			manager = _find_manager(root)
	if manager:
		_lod_distances = manager.lod_distances
	else:
		_lod_distances = DEFAULT_LOD_DISTANCES.duplicate()


func _find_manager(node: Node) -> KickbackManager:
	if node is KickbackManager:
		return node
	for child in node.get_children():
		var found := _find_manager(child)
		if found:
			return found
	return null


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		if event.shift_pressed:
			_show_lod_zones = not _show_lod_zones
		else:
			_visible = not _visible
			visible = _visible
		queue_redraw()


func _process(_delta: float) -> void:
	if _visible:
		queue_redraw()


func _draw() -> void:
	if not _visible:
		return

	var camera := get_viewport().get_camera_3d()
	if not camera:
		return

	# --- Status panel ---
	var lines: Array[Dictionary] = []  # [{text, color}]
	lines.append({"text": "KICKBACK DEBUG", "color": HEADER_COLOR})

	if _kickback_char:
		lines.append({"text": "Tier:     %s" % _kickback_char.get_tier_name(), "color": VALUE_COLOR})
		lines.append({"text": "State:    %s" % _kickback_char.get_active_state_name(), "color": VALUE_COLOR})
		var char_root := _kickback_char.get_character_root()
		if char_root:
			var dist := camera.global_position.distance_to(char_root.global_position)
			lines.append({"text": "Distance: %.1fm" % dist, "color": VALUE_COLOR})

	lines.append({"text": "FPS:      %d" % Engine.get_frames_per_second(), "color": VALUE_COLOR})

	# Per-bone strength section
	if _spring and _rig_builder:
		lines.append({"text": "", "color": Color.TRANSPARENT})  # spacer
		lines.append({"text": "BONE STRENGTH", "color": HEADER_COLOR})

		var bodies := _rig_builder.get_bodies()
		for rig_name: String in bodies:
			var strength := _spring.get_bone_strength(rig_name)
			var base := _spring.get_base_strength(rig_name)
			var ratio := strength / base if base > 0.001 else 1.0
			var color := _ratio_to_color(ratio)
			lines.append({"text": "  %s: %.2f / %.2f" % [rig_name, strength, base], "color": color})

		# Legend
		lines.append({"text": "", "color": Color.TRANSPARENT})
		lines.append({"text": "LEGEND", "color": HEADER_COLOR})

	# Calculate panel size and draw background
	var panel_w := 220.0
	var panel_h := PANEL_MARGIN * 2.0 + lines.size() * LINE_HEIGHT
	if _spring and _rig_builder:
		panel_h += LINE_HEIGHT * 3.0  # legend entries

	draw_rect(Rect2(0, 0, panel_w, panel_h), PANEL_COLOR)

	# Draw text lines
	var y := PANEL_MARGIN + LINE_HEIGHT * 0.8
	for entry: Dictionary in lines:
		if entry.color != Color.TRANSPARENT:
			draw_string(ThemeDB.fallback_font, Vector2(PANEL_MARGIN, y),
				entry.text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, entry.color)
		y += LINE_HEIGHT

	# Legend entries (colored squares + labels)
	if _spring and _rig_builder:
		var legend_items := [
			[LEGEND_WEAK, "Weak (< 50%)"],
			[LEGEND_MID, "Recovering (50-80%)"],
			[LEGEND_FULL, "Full (> 80%)"],
		]
		for item: Array in legend_items:
			draw_rect(Rect2(PANEL_MARGIN + 2, y - 9, 10, 10), item[0])
			draw_string(ThemeDB.fallback_font, Vector2(PANEL_MARGIN + 16, y),
				item[1], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, VALUE_COLOR)
			y += LINE_HEIGHT

	# --- Bone dots projected on 3D viewport ---
	if _spring and _rig_builder:
		var bodies := _rig_builder.get_bodies()
		for rig_name: String in bodies:
			var body: RigidBody3D = bodies[rig_name]
			var world_pos := body.global_position
			if not camera.is_position_behind(world_pos):
				var screen_pos := camera.unproject_position(world_pos)
				var strength := _spring.get_bone_strength(rig_name)
				var base := _spring.get_base_strength(rig_name)
				var ratio := strength / base if base > 0.001 else 1.0
				var color := _ratio_to_color(ratio)
				draw_circle(screen_pos, DOT_RADIUS, color)
				draw_string(ThemeDB.fallback_font, screen_pos + Vector2(DOT_RADIUS + 2, 4),
					rig_name, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)

	# --- LOD zone circles ---
	if _show_lod_zones and _kickback_char:
		var char_root := _kickback_char.get_character_root()
		if char_root:
			_draw_lod_zones(camera, char_root.global_position)


func _ratio_to_color(ratio: float) -> Color:
	if ratio < 0.5:
		return LEGEND_WEAK.lerp(LEGEND_MID, ratio * 2.0)
	else:
		return LEGEND_MID.lerp(LEGEND_FULL, (ratio - 0.5) * 2.0)


func _draw_lod_zones(camera: Camera3D, center: Vector3) -> void:
	for i in _lod_distances.size():
		var radius: float = _lod_distances[i]
		var color: Color = LOD_COLORS[i]
		var label: String = LOD_LABELS[i]
		var points := PackedVector2Array()

		for seg in LOD_SEGMENTS + 1:
			var angle := (float(seg) / LOD_SEGMENTS) * TAU
			var world_pt := center + Vector3(cos(angle) * radius, 0.1, sin(angle) * radius)
			if camera.is_position_behind(world_pt):
				if not points.is_empty():
					draw_polyline(points, color, 1.5, true)
					points.clear()
				continue
			points.append(camera.unproject_position(world_pt))

		if points.size() > 1:
			draw_polyline(points, color, 1.5, true)

		# Label at the front of each circle
		var label_world := center + Vector3(0, 0.1, -radius)
		if not camera.is_position_behind(label_world):
			var label_screen := camera.unproject_position(label_world)
			draw_string(ThemeDB.fallback_font, label_screen + Vector2(-20, -8),
				"%s (%dm)" % [label, int(radius)], HORIZONTAL_ALIGNMENT_LEFT,
				-1, FONT_SIZE, color)
