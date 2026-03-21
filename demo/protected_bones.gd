## Demo: Protected bones comparison. Two identical characters with the same
## loose tuning — left has no protection, right has legs protected.
## Same hit, dramatically different visual result.
extends Node3D

var _profiles: Array[ImpactProfile] = []
var _weapon_names := PackedStringArray(["Light", "Medium", "Heavy", "Shotgun", "Explosion"])
var _weapon_idx: int = 1  # Start on Medium for visible difference
var _kickbacks: Array[KickbackCharacter] = []

# Camera
var _cam: Camera3D
var _cam_distance: float = 5.0
var _cam_yaw: float = 0.0
var _cam_pitch: float = -15.0
var _dragging: bool = false

var _weapon_label: Label


func _ready() -> void:
	_cam = $Camera3D
	_weapon_label = $HUD/WeaponLabel

	_profiles = [
		_make_profile(&"Light",     12.0, 0.40, 0.0,  0.02, 0.50, 2, 0.4),
		_make_profile(&"Medium",    18.0, 0.55, 0.0,  0.05, 0.65, 3, 0.3),
		_make_profile(&"Heavy",     25.0, 0.65, 0.05, 0.10, 0.80, 4, 0.25),
		_make_profile(&"Shotgun",   30.0, 0.70, 0.08, 0.25, 0.85, 5, 0.20),
		_make_profile(&"Explosion", 45.0, 0.95, 0.45, 0.85, 0.95, 99, 0.15),
	]

	# Shared loose tuning — both characters use the same base
	var base_tuning := _make_loose_tuning()

	# Left: NO protection — whole body wobbles
	var tuning_unprotected := base_tuning.duplicate()
	var kc1 := _setup_active($Characters/Unprotected, tuning_unprotected)
	if kc1:
		_kickbacks.append(kc1)

	# Right: legs protected — upper body reacts, feet planted
	var tuning_protected := base_tuning.duplicate()
	tuning_protected.protected_bones = PackedStringArray([
		"UpperLeg_L", "UpperLeg_R", "LowerLeg_L", "LowerLeg_R", "Foot_L", "Foot_R"
	])
	var kc2 := _setup_active($Characters/Protected, tuning_protected)
	if kc2:
		_kickbacks.append(kc2)

	# Debug gizmos
	var debug_hud := StrengthDebugHUD.new()
	debug_hud.name = "StrengthDebugHUD"
	debug_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(debug_hud)

	_update_weapon_label()


func _make_loose_tuning() -> RagdollTuning:
	var t := RagdollTuning.create_default()
	t.strength_map = {
		"Hips": 0.30, "Spine": 0.25, "Chest": 0.25, "Head": 0.15,
		"UpperArm_L": 0.20, "LowerArm_L": 0.15, "Hand_L": 0.08,
		"UpperArm_R": 0.20, "LowerArm_R": 0.15, "Hand_R": 0.08,
		"UpperLeg_L": 0.30, "LowerLeg_L": 0.22, "Foot_L": 0.12,
		"UpperLeg_R": 0.30, "LowerLeg_R": 0.22, "Foot_R": 0.12,
	}
	t.pin_strength_overrides = {"Hips": 0.30, "Foot_L": 0.15, "Foot_R": 0.15}
	t.default_pin_strength = 0.03
	t.stagger_threshold = 0.7
	t.stagger_strength_floor = 0.10
	t.stagger_duration = 1.0
	t.recovery_rate = 0.15
	t.max_angular_velocity = 25.0
	t.max_linear_velocity = 12.0
	return t


func _setup_active(char_root: Node3D, tuning: RagdollTuning) -> KickbackCharacter:
	var ybot_name := ""
	for child in char_root.get_children():
		if _find_child_of_type(child, "Skeleton3D"):
			ybot_name = child.name
			break
	if ybot_name.is_empty():
		return null

	var skel_path := NodePath("../%s/Skeleton3D" % ybot_name)
	var root_path := NodePath("..")
	var builder_path := NodePath("../PhysicsRigBuilder")
	var spring_path := NodePath("../SpringResolver")

	var rb := PhysicsRigBuilder.new()
	rb.name = "PhysicsRigBuilder"
	rb.skeleton_path = skel_path
	var rs := PhysicsRigSync.new()
	rs.name = "PhysicsRigSync"
	rs.skeleton_path = skel_path
	rs.rig_builder_path = builder_path
	var sp := SpringResolver.new()
	sp.name = "SpringResolver"
	sp.skeleton_path = skel_path
	sp.rig_builder_path = builder_path
	var ac := ActiveRagdollController.new()
	ac.name = "ActiveRagdollController"
	ac.spring_resolver_path = spring_path
	ac.rig_builder_path = builder_path
	ac.character_root_path = root_path

	var kc := KickbackCharacter.new()
	kc.name = "KickbackCharacter"
	kc.skeleton_path = skel_path
	kc.character_root_path = root_path
	kc.ragdoll_profile = RagdollProfile.create_mixamo_default()
	kc.ragdoll_tuning = tuning

	char_root.add_child(rb)
	char_root.add_child(rs)
	char_root.add_child(sp)
	char_root.add_child(ac)
	char_root.add_child(kc)
	return kc


func _find_child_of_type(node: Node, type_name: String) -> Node:
	for child in node.get_children():
		if child.get_class() == type_name:
			return child
		var found := _find_child_of_type(child, type_name)
		if found:
			return found
	return null


func _make_profile(pname: StringName, impulse: float, transfer: float, upward: float,
		ragdoll_prob: float, reduction: float, spread: int, recovery: float) -> ImpactProfile:
	var p := ImpactProfile.new()
	p.profile_name = pname
	p.base_impulse = impulse
	p.impulse_transfer_ratio = transfer
	p.upward_bias = upward
	p.ragdoll_probability = ragdoll_prob
	p.strength_reduction = reduction
	p.strength_spread = spread
	p.recovery_rate = recovery
	return p


func _shoot_all() -> void:
	var profile := _profiles[_weapon_idx]
	for kc: KickbackCharacter in _kickbacks:
		var parent := kc.get_parent()
		for sibling in parent.get_children():
			if sibling is PhysicsRigBuilder:
				var bodies: Dictionary = sibling.get_bodies()
				var body: RigidBody3D = bodies.get("Chest", bodies.get("Hips"))
				if body:
					kc.receive_hit(body, -_cam.global_basis.z, body.global_position, profile)
				break


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
					_cam_distance = maxf(_cam_distance - 0.5, 2.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_cam_distance = minf(_cam_distance + 0.5, 15.0)

	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_cam_yaw -= mm.relative.x * 0.3
		_cam_pitch = clampf(_cam_pitch - mm.relative.y * 0.3, -80.0, 80.0)

	elif event is InputEventKey and event.pressed:
		match (event as InputEventKey).keycode:
			KEY_1: _set_weapon(0)
			KEY_2: _set_weapon(1)
			KEY_3: _set_weapon(2)
			KEY_4: _set_weapon(3)
			KEY_5: _set_weapon(4)
			KEY_SPACE: _shoot_all()


func _physics_process(_delta: float) -> void:
	if not _cam:
		return
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
