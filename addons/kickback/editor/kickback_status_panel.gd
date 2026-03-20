@tool
extends VBoxContainer

var _kc: KickbackCharacter


func setup(kc: KickbackCharacter) -> void:
	_kc = kc
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
