@tool
class_name KickbackPlugin
extends EditorPlugin

var _inspector_plugin: EditorInspectorPlugin
var _pending_root: Node
var _pending_skeleton: Skeleton3D


func _enter_tree() -> void:
	add_tool_menu_item("Add Kickback to Selected", _on_add_kickback)
	_inspector_plugin = preload("res://addons/kickback/editor/kickback_inspector_plugin.gd").new()
	_inspector_plugin._editor_plugin = self
	add_inspector_plugin(_inspector_plugin)


func _exit_tree() -> void:
	remove_tool_menu_item("Add Kickback to Selected")
	if _inspector_plugin:
		remove_inspector_plugin(_inspector_plugin)


func _on_add_kickback() -> void:
	var selection := EditorInterface.get_selection()
	var selected := selection.get_selected_nodes()
	if selected.is_empty():
		_show_error("No node selected. Select a character node with a Skeleton3D child.")
		return

	var root: Node = selected[0]

	var skeleton := KickbackSetup.find_skeleton(root)
	if not skeleton:
		_show_error("Selected node has no Skeleton3D anywhere below it.\nSelect a character node that contains a Skeleton3D (e.g. Root/Model/Skeleton3D).")
		return

	for child in root.get_children():
		if child is KickbackCharacter:
			_show_error("This node already has Kickback controllers.\nRemove existing ones first to re-add.")
			return

	_pending_root = root
	_pending_skeleton = skeleton

	_show_preset_dialog()


func _show_preset_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Kickback Setup"
	dialog.ok_button_text = "Create"

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var header := Label.new()
	header.text = "Add Kickback to '%s'" % _pending_root.name
	header.add_theme_font_size_override("font_size", 13)
	vbox.add_child(header)

	vbox.add_child(HSeparator.new())

	var btn_group := ButtonGroup.new()

	# Kickback is the active spring ragdoll; the dialog previews what gets created.
	var presets := [
		[
			"Active Ragdoll",
			"Full physics rig with spring-driven joints.\nStagger, ragdoll, and physics-driven recovery.",
			"5 nodes — PhysicsRigBuilder, PhysicsRigSync, SpringResolver, ActiveRagdollController, KickbackCharacter",
		],
	]

	var first := true
	for preset: Array in presets:
		var radio := CheckBox.new()
		radio.text = preset[0]
		radio.button_group = btn_group
		radio.button_pressed = first
		first = false
		vbox.add_child(radio)

		var desc := Label.new()
		desc.text = preset[1]
		desc.add_theme_font_size_override("font_size", 11)
		desc.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		vbox.add_child(desc)

		var nodes_label := Label.new()
		nodes_label.text = preset[2]
		nodes_label.add_theme_font_size_override("font_size", 10)
		nodes_label.add_theme_color_override("font_color", Color(0.45, 0.75, 0.45))
		vbox.add_child(nodes_label)

		var spacer := Control.new()
		spacer.custom_minimum_size.y = 2
		vbox.add_child(spacer)

	vbox.add_child(HSeparator.new())

	var note := Label.new()
	note.text = "Adds the active-ragdoll node set under the selected character.\nThe character must contain a Skeleton3D."
	note.add_theme_font_size_override("font_size", 10)
	note.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(note)

	dialog.add_child(vbox)

	dialog.confirmed.connect(func():
		var pressed: BaseButton = btn_group.get_pressed_button()
		var preset_label: String = pressed.text if pressed else "Active Ragdoll"
		dialog.queue_free()
		_execute_preset(preset_label)
	)
	dialog.canceled.connect(dialog.queue_free)

	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered()


func _execute_preset(preset_name: String) -> void:
	var root := _pending_root
	var skeleton := _pending_skeleton
	var scene_owner: Node = root.owner if root.owner else root

	# Auto-detect humanoid bones
	var bone_mapping := SkeletonDetector.detect_humanoid_bones(skeleton)
	var auto_profile: RagdollProfile = null

	if not bone_mapping.is_empty():
		auto_profile = SkeletonDetector.create_profile_from_skeleton(skeleton, bone_mapping)
	else:
		push_warning("Kickback: could not auto-detect humanoid bones — using Mixamo defaults")
		auto_profile = RagdollProfile.create_mixamo_default()

	# Kickback is the active spring ragdoll — always create the active node set.
	# add_active_rig parents the nodes itself (the shared runtime-spawner path);
	# the undo/redo action is registered around that already-performed "do"
	# (commit_action(false)), so Undo removes the nodes and Redo re-adds them
	# with their scene ownership.
	var nodes := KickbackSetup.add_active_rig(root, skeleton, auto_profile, null, scene_owner)

	var undo := get_undo_redo()
	undo.create_action("Add Kickback to Character (%s)" % preset_name)
	for node: Node in nodes:
		undo.add_do_method(self, "_add_node", root, node, scene_owner)
		undo.add_undo_method(self, "_remove_node", root, node)
		undo.add_do_reference(node)
	undo.commit_action(false)

	# Set skeleton modifier callback to Physics for IK + spring sync
	# Done outside undo/redo because the skeleton may belong to an instantiated sub-scene
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS

	_show_setup_report(root.name, bone_mapping, nodes.size(), preset_name)


func _show_setup_report(character_name: String, bone_mapping: Dictionary, node_count: int, preset_name: String) -> void:
	var report := "Mode: %s\nCreated %d nodes on '%s'.\n\n" % [preset_name, node_count, character_name]

	if not bone_mapping.is_empty():
		report += "Skeleton: Auto-detected %d bones\n" % bone_mapping.size()
		var all_slots := ["Hips", "Spine", "Chest", "Head",
			"UpperArm_L", "LowerArm_L", "Hand_L",
			"UpperArm_R", "LowerArm_R", "Hand_R",
			"UpperLeg_L", "LowerLeg_L", "Foot_L",
			"UpperLeg_R", "LowerLeg_R", "Foot_R"]
		for slot: String in all_slots:
			if slot in bone_mapping:
				report += "  + %s = %s\n" % [slot, bone_mapping[slot]]
			else:
				report += "  - %s — not found\n" % slot
		report += "\n"
	else:
		report += "Skeleton: Using Mixamo defaults (auto-detection failed)\n\n"

	report += "Collision Layers:\n"
	report += "  Layer 1: Environment (foot-IK + recovery ground raycasts)\n"
	report += "  Layer 4: Active ragdoll bodies (RigidBody3D)\n"

	report += "\nSignals (connect in your code to handle animations):\n"
	report += "  stagger_started(hit_direction)  — character wobbles, stays on feet\n"
	report += "  stagger_finished()              — recovered from stagger\n"
	report += "  ragdoll_started()               — full ragdoll triggered\n"
	report += "  recovery_started(face_up)       — getting up from ragdoll\n"
	report += "  recovery_finished()             — fully recovered\n"
	report += "  hit_absorbed(rig_name, strength) — light hit, no state change\n"

	report += "\nQuick Start:\n"
	report += "  KickbackRaycast.shoot_from_camera(get_viewport(), mouse_pos, profile)\n"
	report += "  Preset profiles: res://addons/kickback/presets/\n"
	report += "  F3 at runtime: debug overlay\n"

	var dialog := AcceptDialog.new()
	dialog.title = "Kickback Setup Complete"
	dialog.dialog_text = report
	dialog.dialog_close_on_escape = true
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered(Vector2i(500, 450))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


func _add_node(parent: Node, child: Node, owner: Node) -> void:
	parent.add_child(child)
	child.owner = owner


func _remove_node(parent: Node, child: Node) -> void:
	parent.remove_child(child)


func _show_error(msg: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Kickback Setup"
	dialog.dialog_text = msg
	dialog.dialog_close_on_escape = true
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
