@tool
class_name KickbackPlugin
extends EditorPlugin

var _inspector_plugin: EditorInspectorPlugin
var _pending_root: Node
var _pending_skeleton: Skeleton3D
var _pending_anim_player: AnimationPlayer


func _enter_tree() -> void:
	add_tool_menu_item("Add Kickback to Selected", _on_add_kickback)
	_inspector_plugin = preload("res://addons/kickback/editor/kickback_inspector_plugin.gd").new()
	add_inspector_plugin(_inspector_plugin)


func _exit_tree() -> void:
	remove_tool_menu_item("Add Kickback to Selected")
	if _inspector_plugin:
		remove_inspector_plugin(_inspector_plugin)


func _on_add_kickback() -> void:
	var selection := get_editor_interface().get_selection()
	var selected := selection.get_selected_nodes()
	if selected.is_empty():
		_show_error("No node selected. Select a character node with a Skeleton3D child.")
		return

	var root: Node = selected[0]

	var skeleton: Skeleton3D = _find_child_of_type(root, "Skeleton3D")
	if not skeleton:
		_show_error("Selected node has no Skeleton3D child.\nSelect a character node that contains a Skeleton3D.")
		return

	for child in root.get_children():
		if child.name == "KickbackCharacter":
			_show_error("This node already has Kickback controllers.\nRemove existing ones first to re-add.")
			return

	_pending_root = root
	_pending_skeleton = skeleton
	_pending_anim_player = _find_child_of_type(root, "AnimationPlayer")

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

	# Each preset: [radio_label, description, nodes_created]
	var presets := [
		[
			"Active Ragdoll",
			"Full physics rig with spring-driven joints.\nStagger, ragdoll, and physics-driven recovery.\nBest for main characters and close-range NPCs.",
			"5 nodes — PhysicsRigBuilder, PhysicsRigSync, SpringResolver, ActiveRagdollController, KickbackCharacter",
		],
		[
			"Partial Ragdoll",
			"Lightweight bone-level reactions using PhysicalBoneSimulator3D.\nHit bones simulate briefly then blend back to animation.\nBest for background NPCs or when full ragdoll isn't needed.",
			"2 nodes — PartialRagdollController, KickbackCharacter + PhysicalBoneSimulator3D",
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
	note.text = "Active and Partial are independent modes — pick one per character.\nKickbackCharacter detects which controller is present."
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

	get_editor_interface().get_base_control().add_child(dialog)
	dialog.popup_centered()


func _execute_preset(preset_name: String) -> void:
	var root := _pending_root
	var skeleton := _pending_skeleton
	var anim_player := _pending_anim_player

	var skeleton_name := skeleton.name
	var anim_name: String = anim_player.name if anim_player else ""
	var simulator_path := "../%s/PhysicalBoneSimulator3D" % skeleton_name
	var scene_owner: Node = root.owner if root.owner else root

	# Auto-detect humanoid bones
	var bone_mapping := SkeletonDetector.detect_humanoid_bones(skeleton)
	var auto_profile: RagdollProfile = null

	if not bone_mapping.is_empty():
		auto_profile = SkeletonDetector.create_profile_from_skeleton(skeleton, bone_mapping)
		print("Kickback: Auto-detected %d humanoid bones" % bone_mapping.size())
	else:
		print("Kickback: Could not auto-detect humanoid bones — using Mixamo defaults")
		auto_profile = RagdollProfile.create_mixamo_default()

	# Determine which controllers to create based on preset
	var include_active := false
	var include_partial := false

	match preset_name:
		"Active Ragdoll":
			include_active = true
		"Partial Ragdoll":
			include_partial = true

	# Auto-create PhysicalBoneSimulator3D if partial ragdoll is included
	if include_partial:
		var has_simulator := false
		for child in skeleton.get_children():
			if child is PhysicalBoneSimulator3D:
				has_simulator = true
				break
		if not has_simulator:
			var sim := PhysicalBoneSimulator3D.new()
			sim.name = "PhysicalBoneSimulator3D"
			skeleton.add_child(sim)
			sim.owner = scene_owner
			if not bone_mapping.is_empty():
				SkeletonDetector.populate_physical_bones(skeleton, sim, bone_mapping, scene_owner)
				print("Kickback: Created PhysicalBoneSimulator3D with %d physical bones" % bone_mapping.size())
			else:
				print("Kickback: Created empty PhysicalBoneSimulator3D — add physical bones manually")

	# Preload scripts
	var scripts: Dictionary = {}
	var script_paths := [
		"kickback_character", "physics_rig_builder", "physics_rig_sync",
		"spring_resolver", "active_ragdoll_controller",
		"partial_ragdoll_controller",
	]
	for script_name: String in script_paths:
		var path := "res://addons/kickback/%s.gd" % script_name
		var s: GDScript = load(path)
		if not s:
			_show_error("Failed to load '%s'.\nCheck that the Kickback addon is installed correctly." % path)
			return
		scripts[script_name] = s

	# Create nodes
	var nodes: Array[Node] = []

	# KickbackCharacter (always created)
	var kc := Node.new()
	kc.name = "KickbackCharacter"
	kc.set_script(scripts["kickback_character"])
	kc.set("skeleton_path", NodePath("../%s" % skeleton_name))
	if anim_player:
		kc.set("animation_player_path", NodePath("../%s" % anim_name))
	kc.set("character_root_path", NodePath(".."))
	kc.set("ragdoll_profile", auto_profile)
	nodes.append(kc)

	if include_active:
		var builder := Node3D.new()
		builder.name = "PhysicsRigBuilder"
		builder.set_script(scripts["physics_rig_builder"])
		builder.set("skeleton_path", NodePath("../%s" % skeleton_name))
		nodes.append(builder)

		var sync := Node.new()
		sync.name = "PhysicsRigSync"
		sync.set_script(scripts["physics_rig_sync"])
		sync.set("skeleton_path", NodePath("../%s" % skeleton_name))
		sync.set("rig_builder_path", NodePath("../PhysicsRigBuilder"))
		nodes.append(sync)

		var spring := Node.new()
		spring.name = "SpringResolver"
		spring.set_script(scripts["spring_resolver"])
		spring.set("skeleton_path", NodePath("../%s" % skeleton_name))
		spring.set("rig_builder_path", NodePath("../PhysicsRigBuilder"))
		nodes.append(spring)

		var active := Node.new()
		active.name = "ActiveRagdollController"
		active.set_script(scripts["active_ragdoll_controller"])
		active.set("spring_resolver_path", NodePath("../SpringResolver"))
		active.set("rig_builder_path", NodePath("../PhysicsRigBuilder"))
		active.set("character_root_path", NodePath(".."))
		active.set("rig_sync_path", NodePath("../PhysicsRigSync"))
		nodes.append(active)

	if include_partial:
		var partial := Node.new()
		partial.name = "PartialRagdollController"
		partial.set_script(scripts["partial_ragdoll_controller"])
		partial.set("simulator_path", NodePath(simulator_path))
		partial.set("skeleton_path", NodePath("../%s" % skeleton_name))
		nodes.append(partial)

	# Add all nodes via undo/redo
	var undo := get_undo_redo()
	undo.create_action("Add Kickback to Character (%s)" % preset_name)

	for node: Node in nodes:
		undo.add_do_method(self, "_add_node", root, node, scene_owner)
		undo.add_undo_method(self, "_remove_node", root, node)

	undo.commit_action()

	# Set skeleton modifier callback to Physics for IK + spring sync
	# Done outside undo/redo because the skeleton may belong to an instantiated sub-scene
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS

	_show_setup_report(root.name, anim_player, bone_mapping, nodes.size(), preset_name)


func _show_setup_report(character_name: String, anim_player: AnimationPlayer, bone_mapping: Dictionary, node_count: int, preset_name: String) -> void:
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
	if preset_name == "Active Ragdoll":
		report += "  Layer 2: Environment (ground raycasts during recovery)\n"
		report += "  Layer 4: Active ragdoll bodies (RigidBody3D)\n"
	elif preset_name == "Partial Ragdoll":
		report += "  Layer 2: Environment\n"
		report += "  Layer 5: Partial ragdoll bones (PhysicalBone3D)\n"

	report += "\nSignals (connect in your code to handle animations):\n"
	if preset_name == "Active Ragdoll":
		report += "  stagger_started(hit_direction)  — character wobbles, stays on feet\n"
		report += "  stagger_finished()              — recovered from stagger\n"
		report += "  ragdoll_started()               — full ragdoll triggered\n"
		report += "  recovery_started(face_up)       — getting up from ragdoll\n"
		report += "  recovery_finished()             — fully recovered\n"
		report += "  hit_absorbed(rig_name, strength) — light hit, no state change\n"
	elif preset_name == "Partial Ragdoll":
		report += "  state_changed(is_reacting)      — true on hit, false on blend-out\n"

	report += "\nQuick Start:\n"
	report += "  KickbackRaycast.shoot_from_camera(get_viewport(), mouse_pos, profile)\n"
	report += "  Preset profiles: res://addons/kickback/presets/\n"
	report += "  F3 at runtime: debug overlay (Active Ragdoll only)\n"

	var dialog := AcceptDialog.new()
	dialog.title = "Kickback Setup Complete"
	dialog.dialog_text = report
	dialog.dialog_close_on_escape = true
	get_editor_interface().get_base_control().add_child(dialog)
	dialog.popup_centered(Vector2i(500, 450))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


func _add_node(parent: Node, child: Node, owner: Node) -> void:
	parent.add_child(child)
	child.owner = owner


func _remove_node(parent: Node, child: Node) -> void:
	parent.remove_child(child)


func _find_child_of_type(node: Node, type_name: String) -> Node:
	for child in node.get_children():
		if child.get_class() == type_name:
			return child
	return null


func _show_error(msg: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Kickback Setup"
	dialog.dialog_text = msg
	dialog.dialog_close_on_escape = true
	get_editor_interface().get_base_control().add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
