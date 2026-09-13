## Demo: Tuning Lab. Five fixed RagdollTuning presets stand side-by-side
## (Tank / Standard / Loose / Fragile / Protected) next to a Custom character
## you tune live with the slider panel. Left-click shoots one; Space shoots ALL
## with the same hit so you can compare how each tuning reacts.
extends Node3D

const DemoHelpers := preload("res://demo/demo_helpers.gd")
const OrbitCamera := preload("res://demo/orbit_camera.gd")

var _profile: ImpactProfile           # shared test-hit profile (IMPACT sliders edit this)
var _custom_tuning: RagdollTuning     # Custom character's body tuning (all other sliders)
var _custom_kickback: KickbackCharacter
var _kickbacks: Array[KickbackCharacter] = []

# Camera orbit
var _cam: Camera3D
var _orbit: OrbitCamera

# Slider references
var _sliders: Dictionary = {}


func _ready() -> void:
	_cam = $Camera3D
	_orbit = OrbitCamera.new(_cam, 12.0, -12.0, 0.5, 5.0, 20.0)
	_profile = ImpactProfile.create_bullet()
	_profile.base_impulse = 18.0
	_profile.impulse_transfer_ratio = 0.6
	_profile.strength_spread = 3

	# Five fixed presets — tuning is assigned at build time (strength_map cannot
	# be hot-swapped at runtime), so each character keeps its preset for life.
	_setup_character($Characters/Tank, RagdollTuning.create_tank())
	_setup_character($Characters/Standard, RagdollTuning.create_default())
	_setup_character($Characters/Loose, _make_loose_tuning())
	_setup_character($Characters/Fragile, RagdollTuning.create_fragile())
	_setup_character($Characters/Protected, _make_protected_tuning())

	# Custom character — the slider panel edits this tuning live.
	_custom_tuning = RagdollTuning.create_default()
	_custom_kickback = _setup_character($Characters/Custom, _custom_tuning)

	# Debug gizmos
	DemoHelpers.add_debug_hud(self)

	_build_slider_panel()


# --- Preset tunings without a factory method ---

func _make_loose_tuning() -> RagdollTuning:
	# Weak springs, low pins, slow recovery — exaggerated whole-body wobble.
	var t := RagdollTuning.create_default()
	t.strength_map = {
		"Hips": 0.25, "Spine": 0.20, "Chest": 0.20, "Head": 0.12,
		"UpperArm_L": 0.15, "LowerArm_L": 0.10, "Hand_L": 0.06,
		"UpperArm_R": 0.15, "LowerArm_R": 0.10, "Hand_R": 0.06,
		"UpperLeg_L": 0.22, "LowerLeg_L": 0.15, "Foot_L": 0.08,
		"UpperLeg_R": 0.22, "LowerLeg_R": 0.15, "Foot_R": 0.08,
	}
	t.pin_strength_overrides = {"Hips": 0.20, "Foot_L": 0.06, "Foot_R": 0.06}
	t.default_pin_strength = 0.02
	t.recovery_rate = 0.12
	t.stagger_threshold = 0.75
	t.stagger_strength_floor = 0.06
	t.stagger_duration = 1.5
	t.max_angular_velocity = 30.0
	t.max_linear_velocity = 15.0
	return t


func _make_protected_tuning() -> RagdollTuning:
	# Loose upper body, but legs stay animated (protected) so feet stay planted.
	var t := RagdollTuning.create_default()
	t.strength_map = {
		"Hips": 0.30, "Spine": 0.25, "Chest": 0.25, "Head": 0.15,
		"UpperArm_L": 0.20, "LowerArm_L": 0.15, "Hand_L": 0.08,
		"UpperArm_R": 0.20, "LowerArm_R": 0.15, "Hand_R": 0.08,
		"UpperLeg_L": 0.55, "LowerLeg_L": 0.45, "Foot_L": 0.30,
		"UpperLeg_R": 0.55, "LowerLeg_R": 0.45, "Foot_R": 0.30,
	}
	t.pin_strength_overrides = {"Hips": 0.30, "Foot_L": 0.4, "Foot_R": 0.4}
	t.default_pin_strength = 0.03
	t.stagger_threshold = 0.7
	t.stagger_strength_floor = 0.10
	t.stagger_duration = 1.0
	t.recovery_rate = 0.15
	t.protected_bones = PackedStringArray([
		"UpperLeg_L", "UpperLeg_R", "LowerLeg_L", "LowerLeg_R", "Foot_L", "Foot_R"
	])
	return t


func _setup_character(char_root: Node3D, tuning: RagdollTuning) -> KickbackCharacter:
	var kc := DemoHelpers.build_active_rig(char_root, "", tuning)
	if kc:
		_kickbacks.append(kc)
	return kc


# --- Slider panel (edits the Custom character) ---

func _build_slider_panel() -> void:
	var panel := $HUD/ScrollContainer/SliderPanel

	var header := Label.new()
	header.text = "CUSTOM TUNING (rightmost character)"
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	panel.add_child(header)

	_add_section(panel, "IMPACT (applies to every shot)")
	_add_slider(panel, "base_impulse", 1.0, 50.0, _profile.base_impulse)
	_add_slider(panel, "transfer_ratio", 0.05, 1.0, _profile.impulse_transfer_ratio)
	_add_slider(panel, "strength_spread", 0, 10, _profile.strength_spread)
	_add_slider(panel, "ragdoll_probability", 0.0, 1.0, _profile.ragdoll_probability)

	_add_section(panel, "STAGGER")
	_add_slider(panel, "stagger_threshold", 0.0, 1.0, _custom_tuning.stagger_threshold)
	_add_slider(panel, "stagger_duration", 0.1, 3.0, _custom_tuning.stagger_duration)
	_add_slider(panel, "stagger_floor", 0.05, 0.5, _custom_tuning.stagger_strength_floor)
	_add_slider(panel, "sway_strength", 0.0, 1000.0, _custom_tuning.stagger_sway_strength)
	_add_slider(panel, "sway_frequency", 0.5, 5.0, _custom_tuning.stagger_sway_frequency)
	_add_slider(panel, "sway_drift", 0.0, 1.0, _custom_tuning.stagger_sway_drift)
	_add_slider(panel, "sway_twist", 0.0, 0.5, _custom_tuning.stagger_sway_twist)
	_add_slider(panel, "sway_secondary", 0.5, 5.0, _custom_tuning.stagger_sway_secondary_ratio)
	_add_slider(panel, "sway_twist_ratio", 0.5, 5.0, _custom_tuning.stagger_sway_twist_ratio)
	_add_slider(panel, "sway_spine", 0.0, 1.0, _custom_tuning.stagger_sway_spine_falloff)
	_add_slider(panel, "sway_chest", 0.0, 1.0, _custom_tuning.stagger_sway_chest_falloff)
	_add_slider(panel, "stagger_recovery", 0.0, 0.5, _custom_tuning.stagger_recovery_rate)

	_add_section(panel, "ACTIVE RESISTANCE")
	_add_slider(panel, "counter_strength", 0.0, 1.0, _custom_tuning.resistance_counter_strength)
	_add_slider(panel, "core_ramp", 0.0, 1.0, _custom_tuning.resistance_core_ramp)
	_add_slider(panel, "leg_brace", 0.0, 1.0, _custom_tuning.resistance_leg_brace)

	_add_section(panel, "MUSCLES (JOINT_MOTOR mode)")
	_add_slider(panel, "muscle_gain", 0.02, 0.3, _custom_tuning.muscle_gain)
	_add_slider(panel, "muscle_strength_scale", 0.0, 3.0, _custom_tuning.muscle_strength_scale)
	_add_slider(panel, "muscle_strength_curve", 0.25, 2.0, _custom_tuning.muscle_strength_curve)
	_add_slider(panel, "muscle_root_torque", 0.0, 2000.0, _custom_tuning.muscle_root_torque)
	_add_slider(panel, "muscle_root_force", 0.0, 10000.0, _custom_tuning.muscle_root_force)

	_add_section(panel, "RECOVERY")
	_add_slider(panel, "recovery_rate", 0.05, 2.0, _custom_tuning.recovery_rate)
	_add_slider(panel, "recovery_duration", 0.5, 5.0, _custom_tuning.recovery_duration)

	_add_section(panel, "PAIN & FATIGUE")
	_add_slider(panel, "pain_gain", 0.0, 1.0, _custom_tuning.pain_gain)
	_add_slider(panel, "pain_decay", 0.0, 1.0, _custom_tuning.pain_decay)
	_add_slider(panel, "pain_stagger_thresh", 0.0, 1.0, _custom_tuning.pain_stagger_threshold)
	_add_slider(panel, "fatigue_gain", 0.0, 1.0, _custom_tuning.fatigue_gain)
	_add_slider(panel, "fatigue_impact", 0.0, 1.0, _custom_tuning.fatigue_impact)

	_add_section(panel, "MICRO REACTIONS")
	_add_slider(panel, "micro_strength", 0.0, 2.0, _custom_tuning.micro_reaction_strength)
	_add_slider(panel, "head_whip", 0.0, 5.0, _custom_tuning.micro_head_whip_strength)
	_add_slider(panel, "torso_bend", 0.0, 5.0, _custom_tuning.micro_torso_bend_strength)

	_add_section(panel, "INJURY")
	_add_slider(panel, "injury_gain", 0.0, 1.0, _custom_tuning.injury_gain)
	_add_slider(panel, "injury_decay", 0.0, 0.2, _custom_tuning.injury_decay)
	_add_slider(panel, "injury_impact", 0.0, 1.0, _custom_tuning.injury_impact)

	_add_section(panel, "FOOT IK")
	_add_slider(panel, "ik_ankle_height", 0.0, 0.2, _custom_tuning.foot_ik_ankle_height)
	_add_slider(panel, "ik_max_pelvis_drop", 0.0, 1.0, _custom_tuning.foot_ik_max_pelvis_drop)
	_add_slider(panel, "ik_max_adjustment", 0.0, 1.0, _custom_tuning.foot_ik_max_adjustment)
	_add_slider(panel, "ik_swing_threshold", 0.1, 0.5, _custom_tuning.foot_ik_swing_threshold)
	_add_slider(panel, "ik_plant_threshold", 0.05, 0.3, _custom_tuning.foot_ik_plant_threshold)
	_add_slider(panel, "ik_pelvis_blend", 1.0, 30.0, _custom_tuning.foot_ik_pelvis_blend_speed)
	_add_slider(panel, "ik_foot_blend", 1.0, 30.0, _custom_tuning.foot_ik_foot_blend_speed)
	_add_slider(panel, "ik_stagger_leg_str", 0.1, 1.0, _custom_tuning.foot_ik_stagger_leg_strength)

	_add_section(panel, "STEPS (balance)")
	_add_slider(panel, "step_trigger_ratio", 0.5, 1.5, _custom_tuning.step_trigger_ratio)
	_add_slider(panel, "step_calm_ratio", 0.0, 1.0, _custom_tuning.step_calm_ratio)
	_add_slider(panel, "step_replant_dist", 0.02, 0.5, _custom_tuning.step_replant_distance)
	_add_slider(panel, "step_duration", 0.05, 1.0, _custom_tuning.step_duration)
	_add_slider(panel, "step_lift", 0.0, 0.3, _custom_tuning.step_lift)
	_add_slider(panel, "step_max_length", 0.1, 1.5, _custom_tuning.step_max_length)
	_add_slider(panel, "step_min_stance", 0.0, 0.4, _custom_tuning.step_min_stance)

	_add_section(panel, "ARM IK")
	_add_slider(panel, "arm_brace_blend", 1.0, 40.0, _custom_tuning.arm_brace_blend_speed)

	_add_section(panel, "ARM FALL REACH")
	_add_slider(panel, "fall_reach_duration", 0.0, 1.5, _custom_tuning.arm_fall_reach_duration)
	_add_slider(panel, "fall_reach_strength", 0.0, 1.0, _custom_tuning.arm_fall_reach_strength)
	_add_slider(panel, "fall_reach_distance", 0.0, 1.0, _custom_tuning.arm_fall_reach_distance)
	_add_slider(panel, "fall_reach_weight", 0.0, 1.0, _custom_tuning.arm_fall_reach_weight)
	_add_slider(panel, "fall_reach_min_facing", -1.0, 1.0, _custom_tuning.arm_fall_reach_min_facing)


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
	if _apply_impact_param(param_name, value):
		return
	_apply_tuning_param(param_name, value)
	# The resolver and controller cache tuning values when configured — push the
	# live edit through the facade so the Custom character actually picks it up.
	if _custom_kickback:
		_custom_kickback.refresh_tuning()


## IMPACT sliders edit the shared test-hit profile. Returns true when
## [param param_name] was one of them.
func _apply_impact_param(param_name: String, value: float) -> bool:
	match param_name:
		"base_impulse": _profile.base_impulse = value
		"transfer_ratio": _profile.impulse_transfer_ratio = value
		"strength_spread": _profile.strength_spread = int(value)
		"ragdoll_probability": _profile.ragdoll_probability = value
		_: return false
	return true


## Every other slider edits the Custom character's body tuning.
func _apply_tuning_param(param_name: String, value: float) -> void:
	match param_name:
		"stagger_threshold": _custom_tuning.stagger_threshold = value
		"stagger_duration": _custom_tuning.stagger_duration = value
		"stagger_floor": _custom_tuning.stagger_strength_floor = value
		"muscle_gain": _custom_tuning.muscle_gain = value
		"muscle_strength_scale": _custom_tuning.muscle_strength_scale = value
		"muscle_strength_curve": _custom_tuning.muscle_strength_curve = value
		"muscle_root_torque": _custom_tuning.muscle_root_torque = value
		"muscle_root_force": _custom_tuning.muscle_root_force = value
		"sway_strength": _custom_tuning.stagger_sway_strength = value
		"sway_frequency": _custom_tuning.stagger_sway_frequency = value
		"sway_drift": _custom_tuning.stagger_sway_drift = value
		"sway_twist": _custom_tuning.stagger_sway_twist = value
		"sway_secondary": _custom_tuning.stagger_sway_secondary_ratio = value
		"sway_twist_ratio": _custom_tuning.stagger_sway_twist_ratio = value
		"sway_spine": _custom_tuning.stagger_sway_spine_falloff = value
		"sway_chest": _custom_tuning.stagger_sway_chest_falloff = value
		"stagger_recovery": _custom_tuning.stagger_recovery_rate = value
		"counter_strength": _custom_tuning.resistance_counter_strength = value
		"core_ramp": _custom_tuning.resistance_core_ramp = value
		"leg_brace": _custom_tuning.resistance_leg_brace = value
		"recovery_rate": _custom_tuning.recovery_rate = value
		"recovery_duration": _custom_tuning.recovery_duration = value
		"pain_gain": _custom_tuning.pain_gain = value
		"pain_decay": _custom_tuning.pain_decay = value
		"pain_stagger_thresh": _custom_tuning.pain_stagger_threshold = value
		"fatigue_gain": _custom_tuning.fatigue_gain = value
		"fatigue_impact": _custom_tuning.fatigue_impact = value
		"micro_strength": _custom_tuning.micro_reaction_strength = value
		"head_whip": _custom_tuning.micro_head_whip_strength = value
		"torso_bend": _custom_tuning.micro_torso_bend_strength = value
		"injury_gain": _custom_tuning.injury_gain = value
		"injury_decay": _custom_tuning.injury_decay = value
		"injury_impact": _custom_tuning.injury_impact = value
		"ik_ankle_height": _custom_tuning.foot_ik_ankle_height = value
		"ik_max_pelvis_drop": _custom_tuning.foot_ik_max_pelvis_drop = value
		"ik_max_adjustment": _custom_tuning.foot_ik_max_adjustment = value
		"ik_swing_threshold": _custom_tuning.foot_ik_swing_threshold = value
		"ik_plant_threshold": _custom_tuning.foot_ik_plant_threshold = value
		"ik_pelvis_blend": _custom_tuning.foot_ik_pelvis_blend_speed = value
		"ik_foot_blend": _custom_tuning.foot_ik_foot_blend_speed = value
		"ik_stagger_leg_str": _custom_tuning.foot_ik_stagger_leg_strength = value
		# Balance: steps
		"step_trigger_ratio": _custom_tuning.step_trigger_ratio = value
		"step_calm_ratio": _custom_tuning.step_calm_ratio = value
		"step_replant_dist": _custom_tuning.step_replant_distance = value
		"step_duration": _custom_tuning.step_duration = value
		"step_lift": _custom_tuning.step_lift = value
		"step_max_length": _custom_tuning.step_max_length = value
		"step_min_stance": _custom_tuning.step_min_stance = value
		# Arm IK
		"arm_brace_blend": _custom_tuning.arm_brace_blend_speed = value
		# Self-preservation: arm fall reach
		"fall_reach_duration": _custom_tuning.arm_fall_reach_duration = value
		"fall_reach_strength": _custom_tuning.arm_fall_reach_strength = value
		"fall_reach_distance": _custom_tuning.arm_fall_reach_distance = value
		"fall_reach_weight": _custom_tuning.arm_fall_reach_weight = value
		"fall_reach_min_facing": _custom_tuning.arm_fall_reach_min_facing = value


# --- Shooting ---

func _shoot_all() -> void:
	for kc: KickbackCharacter in _kickbacks:
		var builder := DemoHelpers.find_rig_builder(kc)
		if not builder:
			continue
		var bodies: Dictionary = builder.get_bodies()
		var body: RigidBody3D = bodies.get("Chest", bodies.get("Hips"))
		if body:
			kc.receive_hit(body, -_cam.global_basis.z, body.global_position, _profile)


# --- Input ---

func _unhandled_input(event: InputEvent) -> void:
	if _orbit.handle_input(event):
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			KickbackRaycast.shoot_from_camera(
				get_viewport(), mb.position, _profile)

	elif event is InputEventKey and event.pressed:
		match (event as InputEventKey).keycode:
			KEY_SPACE: _shoot_all()
			KEY_R:
				if _custom_kickback:
					_custom_kickback.trigger_ragdoll()
			KEY_T:
				if _custom_kickback:
					_custom_kickback.trigger_stagger(-_cam.global_basis.z)


func _physics_process(_delta: float) -> void:
	_orbit.update()
