@tool
class_name KickbackPlugin
extends EditorPlugin

var _inspector_plugin: EditorInspectorPlugin


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

	# Validate prerequisites
	var skeleton: Skeleton3D = _find_child_of_type(root, "Skeleton3D")
	if not skeleton:
		_show_error("Selected node has no Skeleton3D child.\nSelect a character node that contains a Skeleton3D.")
		return

	var anim_player: AnimationPlayer = _find_child_of_type(root, "AnimationPlayer")
	if not anim_player:
		_show_error("Selected node has no AnimationPlayer child.\nImport a character with animations first.")
		return

	# Check for existing Kickback nodes by name
	for child in root.get_children():
		if child.name == "KickbackCharacter":
			_show_error("This node already has Kickback controllers.\nRemove existing ones first to re-add.")
			return

	var skeleton_name := skeleton.name
	var anim_name := anim_player.name
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

	# Auto-create PhysicalBoneSimulator3D with physical bones if missing
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
		has_simulator = true

	# Preload all scripts and validate they exist
	var scripts: Dictionary = {}
	var script_paths := [
		"kickback_character", "physics_rig_builder", "physics_rig_sync",
		"spring_resolver", "active_ragdoll_controller",
		"partial_ragdoll_controller", "flinch_controller", "ragdoll_animator",
	]
	for script_name: String in script_paths:
		var path := "res://addons/kickback/%s.gd" % script_name
		var s: GDScript = load(path)
		if not s:
			_show_error("Failed to load '%s'.\nCheck that the Kickback addon is installed correctly." % path)
			return
		scripts[script_name] = s

	# Create all nodes with scripts and properties set BEFORE adding to tree
	var nodes: Array[Node] = []

	# 1. KickbackCharacter
	var kc := Node.new()
	kc.name = "KickbackCharacter"
	kc.set_script(scripts["kickback_character"])
	kc.set("skeleton_path", NodePath("../%s" % skeleton_name))
	kc.set("animation_player_path", NodePath("../%s" % anim_name))
	kc.set("character_root_path", NodePath(".."))
	kc.set("ragdoll_profile", auto_profile)
	nodes.append(kc)

	# 2. PhysicsRigBuilder
	var builder := Node3D.new()
	builder.name = "PhysicsRigBuilder"
	builder.set_script(scripts["physics_rig_builder"])
	builder.set("skeleton_path", NodePath("../%s" % skeleton_name))
	nodes.append(builder)

	# 3. PhysicsRigSync
	var sync := Node.new()
	sync.name = "PhysicsRigSync"
	sync.set_script(scripts["physics_rig_sync"])
	sync.set("skeleton_path", NodePath("../%s" % skeleton_name))
	sync.set("rig_builder_path", NodePath("../PhysicsRigBuilder"))
	nodes.append(sync)

	# 4. SpringResolver
	var spring := Node.new()
	spring.name = "SpringResolver"
	spring.set_script(scripts["spring_resolver"])
	spring.set("skeleton_path", NodePath("../%s" % skeleton_name))
	spring.set("rig_builder_path", NodePath("../PhysicsRigBuilder"))
	nodes.append(spring)

	# 5. ActiveRagdollController
	var active := Node.new()
	active.name = "ActiveRagdollController"
	active.set_script(scripts["active_ragdoll_controller"])
	active.set("spring_resolver_path", NodePath("../SpringResolver"))
	active.set("rig_builder_path", NodePath("../PhysicsRigBuilder"))
	active.set("character_root_path", NodePath(".."))
	nodes.append(active)

	# 6. PartialRagdollController
	var partial := Node.new()
	partial.name = "PartialRagdollController"
	partial.set_script(scripts["partial_ragdoll_controller"])
	partial.set("simulator_path", NodePath(simulator_path))
	partial.set("skeleton_path", NodePath("../%s" % skeleton_name))
	nodes.append(partial)

	# 7. FlinchController
	var flinch := Node.new()
	flinch.name = "FlinchController"
	flinch.set_script(scripts["flinch_controller"])
	flinch.set("character_path", NodePath(".."))
	flinch.set("ragdoll_controller_path", NodePath("../PartialRagdollController"))
	nodes.append(flinch)

	# 8. RagdollAnimator (optional — handles animation playback via signals)
	var animator := Node.new()
	animator.name = "RagdollAnimator"
	animator.set_script(scripts["ragdoll_animator"])
	animator.set("animation_player_path", NodePath("../%s" % anim_name))
	nodes.append(animator)

	# Add all nodes via undo/redo
	var undo := get_undo_redo()
	undo.create_action("Add Kickback to Character")

	for node: Node in nodes:
		undo.add_do_method(self, "_add_node", root, node, scene_owner)
		undo.add_undo_method(self, "_remove_node", root, node)

	undo.commit_action()

	# Build and show setup report
	_show_setup_report(root.name, anim_player, bone_mapping)


func _show_setup_report(character_name: String, anim_player: AnimationPlayer, bone_mapping: Dictionary) -> void:
	var report := "Created 8 controller nodes on '%s'.\n\n" % character_name

	# Bone detection results
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

	# Check animations
	var expected_anims := {
		"idle": "post-recovery idle",
		"get_up_face_up": "ragdoll recovery (face up)",
		"get_up_face_down": "ragdoll recovery (face down)",
		"flinch_front": "flinch from front",
		"flinch_back": "flinch from back",
		"flinch_left": "flinch from left",
		"flinch_right": "flinch from right",
	}

	report += "Animations:\n"
	for anim_name: String in expected_anims:
		var purpose: String = expected_anims[anim_name]
		if anim_player.has_animation(anim_name):
			report += "  + %s (%s)\n" % [anim_name, purpose]
		else:
			report += "  - %s — missing (%s)\n" % [anim_name, purpose]

	report += "\nCollision Layers:\n"
	report += "  Layer 2: Environment (floors/walls)\n"
	report += "  Layer 4: Active ragdoll bodies (auto-configured)\n"
	report += "  Layer 5: Partial ragdoll bones (auto-configured)\n"
	report += "  Weapon raycast mask: layers 4 + 5\n"

	report += "\nQuick Start:\n"
	report += "  KickbackRaycast.shoot_from_camera(get_viewport(), mouse_pos, profile)\n"
	report += "\n  Preset profiles: res://addons/kickback/presets/ (bullet, shotgun, etc.)\n"
	report += "  Or in code: ImpactProfile.create_bullet()"

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
