@tool
extends VBoxContainer

var _kc: KickbackCharacter
var _editor_plugin: EditorPlugin
var _direction_option: OptionButton
var _profile_option: OptionButton
var _intensity_slider: HSlider

const _DIRECTIONS := ["Front", "Back", "Left", "Right", "Up", "Random"]
const _PROFILES := ["Bullet", "Melee", "Shotgun", "Explosion", "Arrow"]


func setup(kc: KickbackCharacter, editor_plugin: EditorPlugin = null) -> void:
	_kc = kc
	_editor_plugin = editor_plugin
	_build_ui()


func _build_ui() -> void:
	# Header
	var header := Label.new()
	header.text = "Kickback Status"
	header.add_theme_font_size_override("font_size", 14)
	add_child(header)

	add_child(HSeparator.new())

	# Detect which mode based on sibling controllers
	var parent := _kc.get_parent()
	var has_active := _has_sibling_of_type(parent, "ActiveRagdollController") if parent else false
	var has_partial := _has_sibling_of_type(parent, "PartialRagdollController") if parent else false

	# Mode label
	var mode_name := "Active Ragdoll" if has_active else ("Partial Ragdoll" if has_partial else "None")
	var mode_label := Label.new()
	mode_label.text = "Mode: %s" % mode_name
	mode_label.add_theme_font_size_override("font_size", 12)
	mode_label.add_theme_color_override("font_color", Color(0.45, 0.75, 0.45))
	add_child(mode_label)

	# Setup validation
	_add_section("Setup")
	_add_check("Skeleton3D", _check_node_path(_kc, "skeleton_path", "Skeleton3D"))
	_add_check("Character Root", _check_node_path(_kc, "character_root_path", "Node3D"))
	_add_check("Jolt Physics", JoltCheck.is_jolt_active())
	_add_check("Skeleton Physics Callback", _check_skeleton_callback_mode())

	# Controller siblings — show only what's relevant
	_add_section("Controllers")
	if has_active:
		_add_check("PhysicsRigBuilder", _has_sibling_of_type(parent, "PhysicsRigBuilder"))
		_add_check("PhysicsRigSync", _has_sibling_of_type(parent, "PhysicsRigSync"))
		_add_check("SpringResolver", _has_sibling_of_type(parent, "SpringResolver"))
		_add_check("ActiveRagdollController", true)
	elif has_partial:
		_add_check("PartialRagdollController", true)
		_add_check("PhysicalBoneSimulator3D", _check_simulator())
	else:
		_add_check("No controller found", false)

	# Physics Rig bake status (Active Ragdoll only)
	if has_active and parent:
		var rig_builder := _find_sibling_rig_builder(parent)
		if rig_builder:
			_add_section("Physics Rig")
			var baked := RigBaker.is_baked(rig_builder)
			if baked:
				var body_count := RigBaker.get_baked_body_count(rig_builder)
				_add_check("Baked (%d bodies)" % body_count, true)
			else:
				_add_check("Runtime (generated at play)", false)

			var bake_btn := Button.new()
			if baked:
				bake_btn.text = "Unbake Rig"
				bake_btn.pressed.connect(_on_unbake.bind(rig_builder))
			else:
				bake_btn.text = "Bake Rig"
				bake_btn.pressed.connect(_on_bake.bind(rig_builder))
			add_child(bake_btn)

	# Test Hit (Active Ragdoll only)
	if has_active:
		_add_section("Test Hit")

		var dir_hbox := HBoxContainer.new()
		var dir_label := Label.new()
		dir_label.text = "Direction"
		dir_label.add_theme_font_size_override("font_size", 11)
		dir_label.custom_minimum_size.x = 60
		dir_hbox.add_child(dir_label)
		_direction_option = OptionButton.new()
		for dir_name: String in _DIRECTIONS:
			_direction_option.add_item(dir_name)
		_direction_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dir_hbox.add_child(_direction_option)
		add_child(dir_hbox)

		var prof_hbox := HBoxContainer.new()
		var prof_label := Label.new()
		prof_label.text = "Profile"
		prof_label.add_theme_font_size_override("font_size", 11)
		prof_label.custom_minimum_size.x = 60
		prof_hbox.add_child(prof_label)
		_profile_option = OptionButton.new()
		for prof_name: String in _PROFILES:
			_profile_option.add_item(prof_name)
		_profile_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		prof_hbox.add_child(_profile_option)
		add_child(prof_hbox)

		var int_hbox := HBoxContainer.new()
		var int_label := Label.new()
		int_label.text = "Intensity"
		int_label.add_theme_font_size_override("font_size", 11)
		int_label.custom_minimum_size.x = 60
		int_hbox.add_child(int_label)
		_intensity_slider = HSlider.new()
		_intensity_slider.min_value = 0.1
		_intensity_slider.max_value = 3.0
		_intensity_slider.step = 0.1
		_intensity_slider.value = 1.0
		_intensity_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		int_hbox.add_child(_intensity_slider)
		add_child(int_hbox)

		var fire_btn := Button.new()
		fire_btn.text = "Fire"
		fire_btn.pressed.connect(_on_test_hit)
		add_child(fire_btn)

	# Tips
	add_child(HSeparator.new())
	var tips := Label.new()
	tips.text = "F3: debug overlay" if has_active else ""
	tips.add_theme_font_size_override("font_size", 11)
	tips.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	add_child(tips)

	# Refresh button
	var btn := Button.new()
	btn.text = "Refresh"
	btn.pressed.connect(_refresh)
	add_child(btn)

	# Bottom margin
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 8
	add_child(spacer)


func _on_bake(rig_builder: PhysicsRigBuilder) -> void:
	if not _editor_plugin:
		push_error("KickbackStatusPanel: no EditorPlugin reference — cannot bake")
		return
	var scene_owner: Node = rig_builder.owner if rig_builder.owner else rig_builder
	RigBaker.bake(rig_builder, _editor_plugin.get_undo_redo(), scene_owner)
	_refresh()


func _on_unbake(rig_builder: PhysicsRigBuilder) -> void:
	if not _editor_plugin:
		push_error("KickbackStatusPanel: no EditorPlugin reference — cannot unbake")
		return
	RigBaker.unbake(rig_builder, _editor_plugin.get_undo_redo())
	_refresh()


func _on_test_hit() -> void:
	if not _kc or not _kc.is_inside_tree():
		push_warning("KickbackStatusPanel: character not in tree — run the scene first")
		return
	var parent := _kc.get_parent()
	if not parent:
		return
	var rig_builder := _find_sibling_rig_builder(parent)
	if not rig_builder:
		push_warning("KickbackStatusPanel: no PhysicsRigBuilder found")
		return
	var bodies: Dictionary = rig_builder.get_bodies()
	if bodies.is_empty():
		push_warning("KickbackStatusPanel: physics rig not built — is the scene running?")
		return

	var target_body: RigidBody3D = bodies.get("Hips", bodies.values()[0])
	var hit_dir := _get_hit_direction()
	var profile := _get_hit_profile()
	_kc.receive_hit(target_body, hit_dir, target_body.global_position, profile)


func _get_hit_direction() -> Vector3:
	if not _direction_option:
		return Vector3.FORWARD
	var selected: String = _DIRECTIONS[_direction_option.selected]
	match selected:
		"Front":
			return -_kc.global_transform.basis.z
		"Back":
			return _kc.global_transform.basis.z
		"Left":
			return -_kc.global_transform.basis.x
		"Right":
			return _kc.global_transform.basis.x
		"Up":
			return Vector3.UP
		"Random":
			var angle := randf() * TAU
			return Vector3(cos(angle), 0.0, sin(angle))
	return Vector3.FORWARD


func _get_hit_profile() -> ImpactProfile:
	var intensity: float = _intensity_slider.value if _intensity_slider else 1.0
	var profile: ImpactProfile
	if not _profile_option:
		profile = ImpactProfile.create_bullet()
	else:
		var selected: String = _PROFILES[_profile_option.selected]
		match selected:
			"Bullet":
				profile = ImpactProfile.create_bullet()
			"Melee":
				profile = ImpactProfile.create_melee()
			"Shotgun":
				profile = ImpactProfile.create_shotgun()
			"Explosion":
				profile = ImpactProfile.create_explosion()
			"Arrow":
				profile = ImpactProfile.create_arrow()
			_:
				profile = ImpactProfile.create_bullet()
	profile.base_impulse *= intensity
	return profile


func _add_section(title: String) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 4
	add_child(spacer)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	add_child(label)


func _add_check(label_text: String, passed: bool) -> void:
	var hbox := HBoxContainer.new()
	var icon_label := Label.new()
	icon_label.text = "+" if passed else "-"
	icon_label.add_theme_color_override("font_color", Color.GREEN if passed else Color(0.9, 0.3, 0.3))
	icon_label.add_theme_font_size_override("font_size", 12)
	icon_label.custom_minimum_size.x = 16
	hbox.add_child(icon_label)

	var text_label := Label.new()
	text_label.text = label_text
	text_label.add_theme_font_size_override("font_size", 11)
	if not passed:
		text_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	hbox.add_child(text_label)
	add_child(hbox)


func _check_node_path(kc: KickbackCharacter, property: String, _expected_type: String) -> bool:
	var path: NodePath = kc.get(property)
	if path.is_empty():
		return false
	var node := kc.get_node_or_null(path)
	return node != null


func _check_simulator() -> bool:
	var skel_path: NodePath = _kc.get("skeleton_path")
	if skel_path.is_empty():
		return false
	var skeleton := _kc.get_node_or_null(skel_path)
	if not skeleton:
		return false
	return skeleton.get_node_or_null("PhysicalBoneSimulator3D") != null


func _check_skeleton_callback_mode() -> bool:
	var skel_path: NodePath = _kc.get("skeleton_path")
	if skel_path.is_empty():
		return false
	var skeleton := _kc.get_node_or_null(skel_path) as Skeleton3D
	if not skeleton:
		return false
	return skeleton.modifier_callback_mode_process == Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS


func _find_sibling_rig_builder(parent: Node) -> PhysicsRigBuilder:
	for child in parent.get_children():
		if child is PhysicsRigBuilder:
			return child
	return null


func _has_sibling_of_type(parent: Node, type_name: String) -> bool:
	for child in parent.get_children():
		if child.get_class() == type_name or (child.get_script() and child.get_script().get_global_name() == type_name):
			return true
	return false


func _refresh() -> void:
	for child in get_children():
		child.queue_free()
	await get_tree().process_frame
	_build_ui()
