## Debug overlay showing color-coded bone gizmos for ALL ragdoll characters
## in the scene. Toggle with F3 at runtime. Self-contained — no configuration needed.
@icon("res://addons/kickback/icons/strength_debug_hud.svg")
class_name StrengthDebugHUD
extends Control

var _visible: bool = false
var _active_targets: Array[Dictionary] = []   # [{spring, rig_builder}]
var _partial_targets: Array[Dictionary] = []  # [{partial_ctrl, simulator}]
var _discovered: bool = false

const DOT_RADIUS_BASE := 5.0
const DOT_RADIUS_MIN := 2.0
const DOT_FADE_START := 10.0
const DOT_FADE_END := 50.0
const FONT_SIZE := 10
const WEAK_COLOR := Color(0.9, 0.2, 0.2)
const MID_COLOR := Color(0.9, 0.8, 0.2)
const FULL_COLOR := Color(0.2, 0.9, 0.3)
const PARTIAL_IDLE_COLOR := Color(0.6, 0.8, 0.9, 0.7)
const PARTIAL_REACT_COLOR := Color(1.0, 0.85, 0.2)


func _ready() -> void:
	visible = false
	print("Kickback: Press F3 for debug gizmos")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		_visible = not _visible
		visible = _visible
		if _visible and not _discovered:
			_discover_targets()
		queue_redraw()


func _discover_targets() -> void:
	_active_targets.clear()
	_partial_targets.clear()
	var root := get_tree().current_scene
	if not root:
		return
	var characters := KickbackCharacter.find_all(root)
	for kc: KickbackCharacter in characters:
		var parent := kc.get_parent()
		if not parent:
			continue
		var spring: SpringResolver = null
		var builder: PhysicsRigBuilder = null
		var partial: PartialRagdollController = null
		for sibling in parent.get_children():
			if sibling is SpringResolver:
				spring = sibling
			elif sibling is PhysicsRigBuilder:
				builder = sibling
			elif sibling is PartialRagdollController:
				partial = sibling
		if spring and builder:
			_active_targets.append({"spring": spring, "rig_builder": builder})
		elif partial:
			var skel_path: NodePath = kc.get("skeleton_path")
			var skeleton := kc.get_node_or_null(skel_path) as Skeleton3D
			if skeleton:
				var sim := skeleton.get_node_or_null("PhysicalBoneSimulator3D") as PhysicalBoneSimulator3D
				if sim:
					_partial_targets.append({"partial_ctrl": partial, "simulator": sim})
	_discovered = true


func _process(_delta: float) -> void:
	if _visible:
		queue_redraw()


func _draw() -> void:
	if not _visible:
		return

	var camera := get_viewport().get_camera_3d()
	if not camera:
		return

	if _active_targets.is_empty() and _partial_targets.is_empty():
		_discover_targets()

	var cam_pos := camera.global_position

	# Active ragdoll gizmos — color-coded by spring strength
	for target: Dictionary in _active_targets:
		var builder: PhysicsRigBuilder = target.rig_builder
		var spring: SpringResolver = target.spring
		var bodies := builder.get_bodies()
		for rig_name: String in bodies:
			var body: RigidBody3D = bodies[rig_name]
			var world_pos := body.global_position
			if camera.is_position_behind(world_pos):
				continue
			var screen_pos := camera.unproject_position(world_pos)
			var dist := cam_pos.distance_to(world_pos)
			var strength := spring.get_bone_strength(rig_name)
			var base := spring.get_base_strength(rig_name)
			var ratio := strength / base if base > 0.001 else 1.0
			var color := _ratio_to_color(ratio)
			var dot_radius := _scaled_radius(dist)
			draw_circle(screen_pos, dot_radius, color)
			if dist < 15.0:
				draw_string(ThemeDB.fallback_font, screen_pos + Vector2(dot_radius + 2, 4),
					rig_name, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)

	# Partial ragdoll gizmos — cyan dots, flash yellow when reacting
	for target: Dictionary in _partial_targets:
		var partial: PartialRagdollController = target.partial_ctrl
		var sim: PhysicalBoneSimulator3D = target.simulator
		var reacting := partial.is_reacting()
		var color := PARTIAL_REACT_COLOR if reacting else PARTIAL_IDLE_COLOR
		for child in sim.get_children():
			if not child is PhysicalBone3D:
				continue
			var pb: PhysicalBone3D = child
			var world_pos := pb.global_position
			if camera.is_position_behind(world_pos):
				continue
			var screen_pos := camera.unproject_position(world_pos)
			var dist := cam_pos.distance_to(world_pos)
			var dot_radius := _scaled_radius(dist)
			draw_circle(screen_pos, dot_radius, color)
			if dist < 15.0:
				draw_string(ThemeDB.fallback_font, screen_pos + Vector2(dot_radius + 2, 4),
					pb.bone_name, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)


func _scaled_radius(dist: float) -> float:
	var t := clampf((dist - DOT_FADE_START) / (DOT_FADE_END - DOT_FADE_START), 0.0, 1.0)
	return lerpf(DOT_RADIUS_BASE, DOT_RADIUS_MIN, t)


func _ratio_to_color(ratio: float) -> Color:
	if ratio < 0.5:
		return WEAK_COLOR.lerp(MID_COLOR, ratio * 2.0)
	else:
		return MID_COLOR.lerp(FULL_COLOR, (ratio - 0.5) * 2.0)
