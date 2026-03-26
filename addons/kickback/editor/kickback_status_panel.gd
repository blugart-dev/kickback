@tool
extends VBoxContainer

var _kc: KickbackCharacter
var _editor_plugin: EditorPlugin


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

	# Mode + profile summary
	var mode_name := "Active Ragdoll" if has_active else ("Partial Ragdoll" if has_partial else "None")
	var mode_label := Label.new()
	mode_label.text = "Mode: %s" % mode_name
	mode_label.add_theme_font_size_override("font_size", 12)
	mode_label.add_theme_color_override("font_color", Color(0.45, 0.75, 0.45))
	add_child(mode_label)

	var profile: RagdollProfile = _kc.ragdoll_profile if _kc.ragdoll_profile else RagdollProfile.create_mixamo_default()
	var tuning: RagdollTuning = _kc.ragdoll_tuning if _kc.ragdoll_tuning else RagdollTuning.create_default()

	# Bone/joint counts
	var counts_label := Label.new()
	counts_label.text = "Bones: %d  Joints: %d" % [profile.bones.size(), profile.joints.size()]
	counts_label.add_theme_font_size_override("font_size", 11)
	counts_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	add_child(counts_label)

	# Foot IK status
	var ik_enabled: bool = tuning.foot_ik_enabled
	_add_check("Foot IK: %s" % ("Enabled" if ik_enabled else "Disabled"), ik_enabled)

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

	# Validation
	_add_section("Validation")
	var all_warnings := PackedStringArray()

	var skeleton := _kc.get_node_or_null(_kc.skeleton_path) as Skeleton3D
	if skeleton:
		var profile_warnings := profile.validate_against_skeleton(skeleton)
		all_warnings.append_array(profile_warnings)

	# Tuning vs profile (#24)
	var tuning_warnings := tuning.validate_against_profile(profile)
	all_warnings.append_array(tuning_warnings)

	if all_warnings.is_empty():
		_add_check("No issues", true)
	else:
		for w: String in all_warnings:
			_add_check(w, false)

	# Tuning Presets (#30)
	_add_section("Tuning Presets")
	var preset_hbox := HBoxContainer.new()
	var preset_option := OptionButton.new()
	for preset_name: String in ["Default", "Game", "Tank", "Agile", "Fragile"]:
		preset_option.add_item(preset_name)
	preset_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_hbox.add_child(preset_option)
	var apply_btn := Button.new()
	apply_btn.text = "Apply"
	apply_btn.pressed.connect(_on_apply_preset.bind(preset_option))
	preset_hbox.add_child(apply_btn)
	add_child(preset_hbox)

	# Tips
	add_child(HSeparator.new())
	var tips := Label.new()
	if has_active:
		tips.text = "F3: debug overlay\nKickbackRaycast.shoot_from_camera() for testing"
	else:
		tips.text = "KickbackRaycast.shoot_from_camera() for testing"
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


func _on_apply_preset(option: OptionButton) -> void:
	var preset_name: String = option.get_item_text(option.selected)
	var new_tuning: RagdollTuning
	match preset_name:
		"Default":
			new_tuning = RagdollTuning.create_default()
		"Game":
			new_tuning = RagdollTuning.create_game_default()
		"Tank":
			new_tuning = RagdollTuning.create_tank()
		"Agile":
			new_tuning = RagdollTuning.create_agile()
		"Fragile":
			new_tuning = RagdollTuning.create_fragile()
		_:
			new_tuning = RagdollTuning.create_default()

	if _editor_plugin:
		var undo := _editor_plugin.get_undo_redo()
		undo.create_action("Apply Kickback Tuning Preset: %s" % preset_name)
		undo.add_do_property(_kc, "ragdoll_tuning", new_tuning)
		undo.add_undo_property(_kc, "ragdoll_tuning", _kc.ragdoll_tuning)
		undo.commit_action()
	else:
		_kc.ragdoll_tuning = new_tuning
	_refresh()


func _on_unbake(rig_builder: PhysicsRigBuilder) -> void:
	if not _editor_plugin:
		push_error("KickbackStatusPanel: no EditorPlugin reference — cannot unbake")
		return
	RigBaker.unbake(rig_builder, _editor_plugin.get_undo_redo())
	_refresh()


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
