extends Node3D

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
	var debug_hud := StrengthDebugHUD.new()
	debug_hud.name = "StrengthDebugHUD"
	debug_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(debug_hud)

	_update_weapon_label()


func _setup_active(char_root: Node3D) -> KickbackCharacter:
	var ybot_name := _get_ybot_name(char_root)
	if ybot_name.is_empty():
		return null

	# The active char uses the spring rig; drop the baked PhysicalBoneSimulator3D so
	# its (layer-5) bones can't intercept hits meant for the active RigidBody3D rig.
	var baked_sim := char_root.get_node_or_null("%s/Skeleton3D/PhysicalBoneSimulator3D" % ybot_name)
	if baked_sim:
		baked_sim.queue_free()

	var skel_path := NodePath("../%s/Skeleton3D" % ybot_name)
	var root_path := NodePath("..")
	var builder_path := NodePath("../PhysicsRigBuilder")
	var spring_path := NodePath("../SpringResolver")

	var rig_builder := PhysicsRigBuilder.new()
	rig_builder.name = "PhysicsRigBuilder"
	rig_builder.skeleton_path = skel_path

	var rig_sync := PhysicsRigSync.new()
	rig_sync.name = "PhysicsRigSync"
	rig_sync.skeleton_path = skel_path
	rig_sync.rig_builder_path = builder_path

	var spring := SpringResolver.new()
	spring.name = "SpringResolver"
	spring.skeleton_path = skel_path
	spring.rig_builder_path = builder_path

	var active_ctrl := ActiveRagdollController.new()
	active_ctrl.name = "ActiveRagdollController"
	active_ctrl.spring_resolver_path = spring_path
	active_ctrl.rig_builder_path = builder_path
	active_ctrl.character_root_path = root_path

	var kc := KickbackCharacter.new()
	kc.name = "KickbackCharacter"
	kc.skeleton_path = skel_path
	kc.character_root_path = root_path
	kc.ragdoll_profile = RagdollProfile.create_mixamo_default()
	kc.ragdoll_tuning = RagdollTuning.create_default()

	char_root.add_child(rig_builder)
	char_root.add_child(rig_sync)
	char_root.add_child(spring)
	char_root.add_child(active_ctrl)
	char_root.add_child(kc)
	return kc


# The "what Godot offers" half: a bare PhysicalBoneSimulator3D ragdoll driven by
# the demo-only PartialRagdollController. There is no KickbackCharacter here —
# Kickback is the active spring ragdoll on the left; this side is the engine's
# built-in tool, for contrast.
func _setup_godot_ragdoll(char_root: Node3D) -> void:
	var ybot_name := _get_ybot_name(char_root)
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


func _get_ybot_name(char_root: Node3D) -> String:
	for child in char_root.get_children():
		if _find_child_of_type(child, "Skeleton3D"):
			return child.name
	push_error("Demo: No Skeleton3D found in %s" % char_root.name)
	return ""


func _find_child_of_type(node: Node, type_name: String) -> Node:
	for child in node.get_children():
		if child.get_class() == type_name:
			return child
		var found := _find_child_of_type(child, type_name)
		if found:
			return found
	return null


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
	var pivot := Vector3(0, 1.0, 0)
	var yaw_rad := deg_to_rad(_cam_yaw)
	var pitch_rad := deg_to_rad(_cam_pitch)

	var offset := Vector3(
		sin(yaw_rad) * cos(pitch_rad),
		-sin(pitch_rad),
		cos(yaw_rad) * cos(pitch_rad),
	) * _cam_distance

	_cam.global_position = pivot + offset
	_cam.look_at(pivot)


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
