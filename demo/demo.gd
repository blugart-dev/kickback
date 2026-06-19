extends Node3D

const DemoHelpers := preload("res://demo/demo_helpers.gd")

var _profiles: Array[ImpactProfile] = []
var _weapon_names := PackedStringArray(["Bullet", "Melee", "Arrow", "Shotgun", "Explosion"])
var _weapon_idx: int = 0

var _active_kickback: KickbackCharacter
var _godot_ctrl: PartialRagdollController  # the "what Godot offers" comparison char
var _godot_sim: PhysicalBoneSimulator3D

# Camera orbit
var _cam: Camera3D
var _cam_distance: float = 5.0
var _cam_yaw: float = 0.0
var _cam_pitch: float = -15.0
var _dragging: bool = false

var _persistent: bool = false

var _weapon_label: Label


func _ready() -> void:
	_cam = $Camera3D
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

	_update_weapon_label()


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
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_shoot(mb.position)
			MOUSE_BUTTON_RIGHT:
				_dragging = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_cam_distance = maxf(_cam_distance - 1.0, 2.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_cam_distance = minf(_cam_distance + 1.0, 20.0)

	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_cam_yaw -= mm.relative.x * 0.3
		_cam_pitch = clampf(_cam_pitch - mm.relative.y * 0.3, -80.0, 80.0)

	elif event is InputEventKey and event.pressed:
		var key := (event as InputEventKey).keycode
		match key:
			KEY_1: _set_weapon(0)
			KEY_2: _set_weapon(1)
			KEY_3: _set_weapon(2)
			KEY_4: _set_weapon(3)
			KEY_5: _set_weapon(4)
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


func _physics_process(delta: float) -> void:
	if not _cam:
		return

	# Camera orbits the midpoint between both characters
	DemoHelpers.orbit_camera(_cam, _cam_yaw, _cam_pitch, _cam_distance)


func _set_weapon(idx: int) -> void:
	_weapon_idx = clampi(idx, 0, _profiles.size() - 1)
	_update_weapon_label()


func _update_weapon_label() -> void:
	if _weapon_label:
		_weapon_label.text = "Weapon: %s  [1-5]" % _weapon_names[_weapon_idx]


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
