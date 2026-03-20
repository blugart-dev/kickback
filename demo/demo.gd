extends Node3D

var _profiles: Array[ImpactProfile] = []
var _weapon_names := PackedStringArray(["Bullet", "Melee", "Arrow", "Shotgun", "Explosion"])
var _weapon_idx: int = 0

var _active_kickback: KickbackCharacter

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

	# Set up left character as Active Ragdoll
	_active_kickback = _setup_active($ActiveChar)

	# Set up right character as Partial Ragdoll
	_setup_partial($PartialChar)

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


func _setup_partial(char_root: Node3D) -> KickbackCharacter:
	var ybot_name := _get_ybot_name(char_root)
	if ybot_name.is_empty():
		return null

	var skel_path := NodePath("../%s/Skeleton3D" % ybot_name)
	var sim_path := NodePath("../%s/Skeleton3D/PhysicalBoneSimulator3D" % ybot_name)
	var root_path := NodePath("..")

	var partial_ctrl := PartialRagdollController.new()
	partial_ctrl.name = "PartialRagdollController"
	partial_ctrl.simulator_path = sim_path
	partial_ctrl.skeleton_path = skel_path

	var kc := KickbackCharacter.new()
	kc.name = "KickbackCharacter"
	kc.skeleton_path = skel_path
	kc.character_root_path = root_path
	kc.ragdoll_profile = RagdollProfile.create_mixamo_default()
	kc.ragdoll_tuning = RagdollTuning.create_default()

	char_root.add_child(partial_ctrl)
	char_root.add_child(kc)
	return kc


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
					KickbackRaycast.shoot_from_camera(
						get_viewport(), mb.position, _profiles[_weapon_idx])
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
