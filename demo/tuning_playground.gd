extends Node3D

var _profile: ImpactProfile
var _tuning: RagdollTuning
var _kickback: KickbackCharacter

# Camera orbit
var _cam: Camera3D
var _cam_distance: float = 3.5
var _cam_yaw: float = 0.0
var _cam_pitch: float = -15.0
var _dragging: bool = false

# Slider references
var _sliders: Dictionary = {}


func _ready() -> void:
	_cam = $Camera3D
	_profile = ImpactProfile.create_bullet()
	_profile.base_impulse = 15.0
	_profile.impulse_transfer_ratio = 0.55
	_profile.strength_spread = 3

	_tuning = RagdollTuning.create_default()

	_kickback = _setup_active($Character)

	# Debug gizmos
	var debug_hud := StrengthDebugHUD.new()
	debug_hud.name = "StrengthDebugHUD"
	debug_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(debug_hud)

	_build_slider_panel()


func _setup_active(char_root: Node3D) -> KickbackCharacter:
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
	kc.ragdoll_tuning = _tuning

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


func _build_slider_panel() -> void:
	var panel := $HUD/SliderPanel

	_add_section(panel, "IMPACT")
	_add_slider(panel, "base_impulse", 1.0, 50.0, _profile.base_impulse)
	_add_slider(panel, "transfer_ratio", 0.05, 1.0, _profile.impulse_transfer_ratio)
	_add_slider(panel, "strength_spread", 0, 10, _profile.strength_spread)
	_add_slider(panel, "ragdoll_probability", 0.0, 1.0, _profile.ragdoll_probability)

	_add_section(panel, "STAGGER")
	_add_slider(panel, "stagger_threshold", 0.0, 1.0, _tuning.stagger_threshold)
	_add_slider(panel, "stagger_duration", 0.1, 3.0, _tuning.stagger_duration)
	_add_slider(panel, "stagger_floor", 0.05, 0.5, _tuning.stagger_strength_floor)
	_add_slider(panel, "sway_strength", 0.0, 1000.0, _tuning.stagger_sway_strength)
	_add_slider(panel, "sway_frequency", 0.5, 5.0, _tuning.stagger_sway_frequency)
	_add_slider(panel, "stagger_recovery", 0.0, 0.5, _tuning.stagger_recovery_rate)

	_add_section(panel, "ACTIVE RESISTANCE")
	_add_slider(panel, "counter_strength", 0.0, 1.0, _tuning.resistance_counter_strength)
	_add_slider(panel, "core_ramp", 0.0, 1.0, _tuning.resistance_core_ramp)
	_add_slider(panel, "leg_brace", 0.0, 1.0, _tuning.resistance_leg_brace)

	_add_section(panel, "RECOVERY")
	_add_slider(panel, "recovery_rate", 0.05, 2.0, _tuning.recovery_rate)
	_add_slider(panel, "recovery_duration", 0.5, 5.0, _tuning.recovery_duration)

	_add_section(panel, "PAIN & FATIGUE")
	_add_slider(panel, "pain_gain", 0.0, 1.0, _tuning.pain_gain)
	_add_slider(panel, "pain_decay", 0.0, 1.0, _tuning.pain_decay)
	_add_slider(panel, "pain_stagger_thresh", 0.0, 1.0, _tuning.pain_stagger_threshold)
	_add_slider(panel, "fatigue_gain", 0.0, 1.0, _tuning.fatigue_gain)
	_add_slider(panel, "fatigue_impact", 0.0, 1.0, _tuning.fatigue_impact)

	_add_section(panel, "MICRO REACTIONS")
	_add_slider(panel, "micro_strength", 0.0, 2.0, _tuning.micro_reaction_strength)
	_add_slider(panel, "head_whip", 0.0, 5.0, _tuning.micro_head_whip_strength)
	_add_slider(panel, "torso_bend", 0.0, 5.0, _tuning.micro_torso_bend_strength)

	_add_section(panel, "INJURY")
	_add_slider(panel, "injury_gain", 0.0, 1.0, _tuning.injury_gain)
	_add_slider(panel, "injury_decay", 0.0, 0.2, _tuning.injury_decay)
	_add_slider(panel, "injury_impact", 0.0, 1.0, _tuning.injury_impact)


func _add_section(parent: Control, title: String) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 6
	parent.add_child(spacer)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	parent.add_child(label)


func _add_slider(parent: Control, param_name: String, min_val: float, max_val: float, default_val: float) -> void:
	var hbox := HBoxContainer.new()

	var label := Label.new()
	label.text = param_name
	label.custom_minimum_size.x = 130
	label.add_theme_font_size_override("font_size", 11)
	hbox.add_child(label)

	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = 0.01 if max_val <= 1.0 else (1 if max_val > 10 else 0.1)
	slider.value = default_val
	slider.custom_minimum_size.x = 100
	hbox.add_child(slider)

	var value_label := Label.new()
	value_label.text = "%.2f" % default_val
	value_label.custom_minimum_size.x = 40
	value_label.add_theme_font_size_override("font_size", 11)
	hbox.add_child(value_label)

	slider.value_changed.connect(func(val: float):
		value_label.text = "%.2f" % val
		_on_slider_changed(param_name, val)
	)

	_sliders[param_name] = slider
	parent.add_child(hbox)


func _on_slider_changed(param_name: String, value: float) -> void:
	match param_name:
		"base_impulse": _profile.base_impulse = value
		"transfer_ratio": _profile.impulse_transfer_ratio = value
		"strength_spread": _profile.strength_spread = int(value)
		"ragdoll_probability": _profile.ragdoll_probability = value
		"stagger_threshold": _tuning.stagger_threshold = value
		"stagger_duration": _tuning.stagger_duration = value
		"stagger_floor": _tuning.stagger_strength_floor = value
		"sway_strength": _tuning.stagger_sway_strength = value
		"sway_frequency": _tuning.stagger_sway_frequency = value
		"stagger_recovery": _tuning.stagger_recovery_rate = value
		"counter_strength": _tuning.resistance_counter_strength = value
		"core_ramp": _tuning.resistance_core_ramp = value
		"leg_brace": _tuning.resistance_leg_brace = value
		"recovery_rate": _tuning.recovery_rate = value
		"recovery_duration": _tuning.recovery_duration = value
		"pain_gain": _tuning.pain_gain = value
		"pain_decay": _tuning.pain_decay = value
		"pain_stagger_thresh": _tuning.pain_stagger_threshold = value
		"fatigue_gain": _tuning.fatigue_gain = value
		"fatigue_impact": _tuning.fatigue_impact = value
		"micro_strength": _tuning.micro_reaction_strength = value
		"head_whip": _tuning.micro_head_whip_strength = value
		"torso_bend": _tuning.micro_torso_bend_strength = value
		"injury_gain": _tuning.injury_gain = value
		"injury_decay": _tuning.injury_decay = value
		"injury_impact": _tuning.injury_impact = value


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					KickbackRaycast.shoot_from_camera(
						get_viewport(), mb.position, _profile)
			MOUSE_BUTTON_RIGHT:
				_dragging = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_cam_distance = maxf(_cam_distance - 0.5, 1.5)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_cam_distance = minf(_cam_distance + 0.5, 10.0)

	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_cam_yaw -= mm.relative.x * 0.3
		_cam_pitch = clampf(_cam_pitch - mm.relative.y * 0.3, -80.0, 80.0)

	elif event is InputEventKey and event.pressed:
		match (event as InputEventKey).keycode:
			KEY_R:
				if _kickback:
					_kickback.trigger_ragdoll()
			KEY_T:
				if _kickback:
					_kickback.trigger_stagger(-_cam.global_basis.z)


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
