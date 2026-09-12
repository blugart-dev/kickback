extends Node3D

const DemoHelpers := preload("res://demo/demo_helpers.gd")
const OrbitCamera := preload("res://demo/orbit_camera.gd")
const HitEvent := preload("res://demo/hit_event.gd")
const PartialRagdollController := preload("res://demo/partial_ragdoll_controller.gd")

var _profiles: Array[ImpactProfile] = []
var _weapon_names := PackedStringArray(["Bullet", "Melee", "Arrow", "Shotgun", "Explosion"])
var _weapon_idx: int = 0

var _active_kickback: KickbackCharacter
var _godot_ctrl: PartialRagdollController  # the "what Godot offers" comparison char
var _godot_sim: PhysicalBoneSimulator3D

# Camera orbit
var _cam: Camera3D
var _orbit: OrbitCamera

var _persistent: bool = false

var _weapon_label: Label


func _ready() -> void:
	_cam = $Camera3D
	_orbit = OrbitCamera.new(_cam, 5.0, -15.0, 1.0, 2.0, 20.0)
	_weapon_label = $HUD/WeaponLabel

	_profiles = [
		ImpactProfile.create_bullet(),
		ImpactProfile.create_melee(),
		ImpactProfile.create_arrow(),
		ImpactProfile.create_shotgun(),
		ImpactProfile.create_explosion(),
	]

	# Left: Kickback's active spring ragdoll. Right: Godot's built-in ragdoll
	# (PhysicalBoneSimulator3D) — the "what the engine offers" comparison.
	_active_kickback = _setup_active($ActiveChar)
	_setup_godot_ragdoll($PartialChar)

	# Debug gizmos — self-contained, finds all characters
	DemoHelpers.add_debug_hud(self)

	_weapon_idx = DemoHelpers.select_weapon(_weapon_idx, _weapon_names, _weapon_label)


func _setup_active(char_root: Node3D) -> KickbackCharacter:
	var ybot_name := DemoHelpers.find_skeleton_owner(char_root, "Demo")
	if ybot_name.is_empty():
		return null

	# The active char uses the spring rig; drop the baked PhysicalBoneSimulator3D so
	# its (layer-5) bones can't intercept hits meant for the active RigidBody3D rig.
	var baked_sim := char_root.get_node_or_null("%s/Skeleton3D/PhysicalBoneSimulator3D" % ybot_name)
	if baked_sim:
		baked_sim.queue_free()

	return DemoHelpers.build_active_rig(char_root, ybot_name)


# The "what Godot offers" half: a bare PhysicalBoneSimulator3D ragdoll driven by
# the demo-only PartialRagdollController. There is no KickbackCharacter here —
# Kickback is the active spring ragdoll on the left; this side is the engine's
# built-in tool, for contrast.
func _setup_godot_ragdoll(char_root: Node3D) -> void:
	var ybot_name := DemoHelpers.find_skeleton_owner(char_root, "Demo")
	if ybot_name.is_empty():
		return

	var skel_path := NodePath("../%s/Skeleton3D" % ybot_name)
	var sim_path := NodePath("../%s/Skeleton3D/PhysicalBoneSimulator3D" % ybot_name)

	# The baked simulator is inactive by default — enable it so it can ragdoll on hit.
	_godot_sim = char_root.get_node_or_null("%s/Skeleton3D/PhysicalBoneSimulator3D" % ybot_name)
	if _godot_sim:
		_godot_sim.active = true

	_godot_ctrl = PartialRagdollController.new()
	_godot_ctrl.name = "PartialRagdollController"
	_godot_ctrl.simulator_path = sim_path
	_godot_ctrl.skeleton_path = skel_path
	char_root.add_child(_godot_ctrl)


func _unhandled_input(event: InputEvent) -> void:
	if _orbit.handle_input(event):
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_shoot(mb.position)

	elif event is InputEventKey and event.pressed:
		var key := (event as InputEventKey).keycode
		_weapon_idx = DemoHelpers.select_weapon_by_key(key, _weapon_idx, _weapon_names, _weapon_label)
		match key:
			KEY_R:
				if _active_kickback:
					_active_kickback.trigger_ragdoll()
			KEY_T:
				if _active_kickback:
					_active_kickback.trigger_stagger(-_cam.global_basis.z)
			KEY_P:
				if _active_kickback:
					_persistent = not _persistent
					_active_kickback.set_persistent(_persistent)


func _physics_process(_delta: float) -> void:
	# Camera orbits the midpoint between both characters
	_orbit.update()


# Raycasts from the camera and routes the hit by collider type: a RigidBody3D is
# the Kickback active rig (route through the facade); a PhysicalBone3D is the
# Godot-ragdoll char (drive its controller directly).
func _shoot(screen_pos: Vector2) -> void:
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var space := get_viewport().world_3d.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0, KickbackLayers.BOTH_RAGDOLL_MASK)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	var collider: Object = hit.collider
	var profile: ImpactProfile = _profiles[_weapon_idx]
	if collider is RigidBody3D:
		if _active_kickback:
			_active_kickback.receive_hit(collider, dir, hit.position, profile)
	elif collider is PhysicalBone3D and _godot_ctrl:
		var event := HitEvent.new()
		event.hit_position = hit.position
		event.hit_direction = dir
		event.hit_bone_name = collider.bone_name
		event.impulse_magnitude = profile.base_impulse * profile.impulse_transfer_ratio
		event.hit_bone = collider
		event.hit_bone_region = HitEvent.classify_region(collider.bone_name)
		_godot_ctrl.apply_hit(event)
