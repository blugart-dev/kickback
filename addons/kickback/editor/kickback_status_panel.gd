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

	# Setup validation
	_add_section("Setup")
	_add_check("Skeleton3D", _check_node_path(_kc, "skeleton_path", "Skeleton3D"))
	_add_check("AnimationPlayer (optional)", _check_node_path(_kc, "animation_player_path", "AnimationPlayer"))
	_add_check("Character Root", _check_node_path(_kc, "character_root_path", "Node3D"))
	_add_check("PhysicalBoneSimulator3D", _check_simulator())
	_add_check("Jolt Physics", JoltCheck.is_jolt_active())

	# Controller siblings
	_add_section("Controllers")
	var parent := _kc.get_parent()
	if parent:
		_add_check("PhysicsRigBuilder", _has_sibling_of_type(parent, "PhysicsRigBuilder"))
		_add_check("SpringResolver", _has_sibling_of_type(parent, "SpringResolver"))
		_add_check("ActiveRagdollController", _has_sibling_of_type(parent, "ActiveRagdollController"))
		_add_check("PartialRagdollController (optional)", _has_sibling_of_type(parent, "PartialRagdollController"))

	# Tips
	add_child(HSeparator.new())
	var tips := Label.new()
	tips.text = "F3: debug overlay | Shift+F3: LOD zones\nKickbackRaycast.shoot_from_camera() for testing"
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


func _check_node_path(kc: KickbackCharacter, property: String, expected_type: String) -> bool:
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


func _resolve_anim_player() -> AnimationPlayer:
	var path: NodePath = _kc.get("animation_player_path")
	if path.is_empty():
		return null
	return _kc.get_node_or_null(path) as AnimationPlayer


func _refresh() -> void:
	# Clear and rebuild
	for child in get_children():
		child.queue_free()
	await get_tree().process_frame
	_build_ui()
