## Demo: 4 identical characters with different RagdollTuning presets.
## Click to shoot all simultaneously — see how tuning affects reactions.
extends Node3D

var _profiles: Array[ImpactProfile] = []
var _weapon_names := PackedStringArray(["Light", "Medium", "Heavy", "Shotgun", "Explosion"])
var _weapon_idx: int = 0
var _kickbacks: Array[KickbackCharacter] = []

# Camera
var _cam: Camera3D
var _cam_distance: float = 7.0
var _cam_yaw: float = 0.0
var _cam_pitch: float = -15.0
var _dragging: bool = false

var _weapon_label: Label


func _ready() -> void:
	_cam = $Camera3D
	_weapon_label = $HUD/WeaponLabel

	# Moderate profiles — tuning differences should be the star, not weapon strength
	_profiles = [
		_make_profile(&"Light",     10.0, 0.35, 0.0,  0.02, 0.40, 1, 0.5),
		_make_profile(&"Medium",    15.0, 0.45, 0.0,  0.05, 0.55, 2, 0.4),
		_make_profile(&"Heavy",     20.0, 0.55, 0.05, 0.10, 0.70, 3, 0.3),
		_make_profile(&"Shotgun",   25.0, 0.60, 0.08, 0.25, 0.80, 4, 0.25),
		_make_profile(&"Explosion", 40.0, 0.90, 0.40, 0.80, 0.95, 99, 0.15),
	]

	var presets := _build_presets()
	var chars := $Characters
	for i in chars.get_child_count():
		var char_root: Node3D = chars.get_child(i)
		var preset: Dictionary = presets[i] if i < presets.size() else presets[0]
		var kc := _setup_active(char_root, preset.tuning)
		if kc:
			_kickbacks.append(kc)

	# Debug gizmos
	var debug_hud := StrengthDebugHUD.new()
	debug_hud.name = "StrengthDebugHUD"
	debug_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(debug_hud)

	_update_weapon_label()


func _build_presets() -> Array[Dictionary]:
	var presets: Array[Dictionary] = []

	# 1. TANK — stiff springs, barely moves
	var tank := RagdollTuning.create_default()
	tank.strength_map = {
		"Hips": 0.90, "Spine": 0.85, "Chest": 0.85, "Head": 0.70,
		"UpperArm_L": 0.75, "LowerArm_L": 0.65, "Hand_L": 0.50,
		"UpperArm_R": 0.75, "LowerArm_R": 0.65, "Hand_R": 0.50,
		"UpperLeg_L": 0.80, "LowerLeg_L": 0.70, "Foot_L": 0.55,
		"UpperLeg_R": 0.80, "LowerLeg_R": 0.70, "Foot_R": 0.55,
	}
	tank.pin_strength_overrides = {"Hips": 0.95, "Foot_L": 0.6, "Foot_R": 0.6}
	tank.default_pin_strength = 0.3
	tank.recovery_rate = 0.8
	tank.stagger_threshold = 0.3  # Hard to stagger
	tank.stagger_strength_floor = 0.50
	tank.stagger_duration = 0.3
	presets.append({"tuning": tank})

	# 2. STANDARD — plugin defaults
	var standard := RagdollTuning.create_default()
	presets.append({"tuning": standard})

	# 3. LOOSE — weak springs, exaggerated reactions
	var loose := RagdollTuning.create_default()
	loose.strength_map = {
		"Hips": 0.25, "Spine": 0.20, "Chest": 0.20, "Head": 0.12,
		"UpperArm_L": 0.15, "LowerArm_L": 0.10, "Hand_L": 0.06,
		"UpperArm_R": 0.15, "LowerArm_R": 0.10, "Hand_R": 0.06,
		"UpperLeg_L": 0.22, "LowerLeg_L": 0.15, "Foot_L": 0.08,
		"UpperLeg_R": 0.22, "LowerLeg_R": 0.15, "Foot_R": 0.08,
	}
	loose.pin_strength_overrides = {"Hips": 0.20, "Foot_L": 0.06, "Foot_R": 0.06}
	loose.default_pin_strength = 0.02
	loose.recovery_rate = 0.12
	loose.stagger_threshold = 0.75  # Staggers very easily
	loose.stagger_strength_floor = 0.06
	loose.stagger_duration = 1.5
	loose.max_angular_velocity = 30.0
	loose.max_linear_velocity = 15.0
	presets.append({"tuning": loose})

	# 4. RAGDOLL-PRONE — normal springs but falls over easily
	var fragile := RagdollTuning.create_default()
	fragile.stagger_threshold = 0.8
	fragile.stagger_strength_floor = 0.10
	fragile.stagger_duration = 0.8
	fragile.stagger_ragdoll_bonus = 3.0  # Hits during stagger almost guarantee ragdoll
	presets.append({"tuning": fragile})

	return presets


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
		# Find any ragdoll body to hit (use the chest for consistent results)
		var parent := kc.get_parent()
		for sibling in parent.get_children():
			if sibling is PhysicsRigBuilder:
				var bodies: Dictionary = sibling.get_bodies()
				var body: RigidBody3D = bodies.get("Chest", bodies.get("Hips"))
				if body:
					var hit_dir := -_cam.global_basis.z
					kc.receive_hit(body, hit_dir, body.global_position, profile)
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
					_cam_distance = maxf(_cam_distance - 0.5, 3.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_cam_distance = minf(_cam_distance + 0.5, 20.0)

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
