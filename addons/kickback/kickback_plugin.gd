@tool
class_name KickbackPlugin
extends EditorPlugin


func _enter_tree() -> void:
	add_tool_menu_item("Add Kickback to Selected", _on_add_kickback)


func _exit_tree() -> void:
	remove_tool_menu_item("Add Kickback to Selected")


func _on_add_kickback() -> void:
	var selection := get_editor_interface().get_selection()
	var selected := selection.get_selected_nodes()
	if selected.is_empty():
		_show_error("No node selected. Select a character node with a Skeleton3D child.")
		return

	var root: Node = selected[0]
	print("Kickback: Selected node '%s' (class: %s)" % [root.name, root.get_class()])

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

	print("Kickback: Found Skeleton3D='%s', AnimationPlayer='%s'" % [skeleton_name, anim_name])

	# Create all nodes with scripts and properties set BEFORE adding to tree
	var nodes: Array[Node] = []

	# 1. KickbackCharacter
	var kc := Node.new()
	kc.name = "KickbackCharacter"
	kc.set_script(load("res://addons/kickback/kickback_character.gd"))
	kc.set("skeleton_path", NodePath("../%s" % skeleton_name))
	kc.set("animation_player_path", NodePath("../%s" % anim_name))
	kc.set("character_root_path", NodePath(".."))
	nodes.append(kc)

	# 2. PhysicsRigBuilder
	var builder := Node3D.new()
	builder.name = "PhysicsRigBuilder"
	builder.set_script(load("res://addons/kickback/physics_rig_builder.gd"))
	builder.set("skeleton_path", NodePath("../%s" % skeleton_name))
	nodes.append(builder)

	# 3. PhysicsRigSync
	var sync := Node.new()
	sync.name = "PhysicsRigSync"
	sync.set_script(load("res://addons/kickback/physics_rig_sync.gd"))
	sync.set("skeleton_path", NodePath("../%s" % skeleton_name))
	sync.set("rig_builder_path", NodePath("../PhysicsRigBuilder"))
	nodes.append(sync)

	# 4. SpringResolver
	var spring := Node.new()
	spring.name = "SpringResolver"
	spring.set_script(load("res://addons/kickback/spring_resolver.gd"))
	spring.set("skeleton_path", NodePath("../%s" % skeleton_name))
	spring.set("rig_builder_path", NodePath("../PhysicsRigBuilder"))
	nodes.append(spring)

	# 5. ActiveRagdollController
	var active := Node.new()
	active.name = "ActiveRagdollController"
	active.set_script(load("res://addons/kickback/active_ragdoll_controller.gd"))
	active.set("spring_resolver_path", NodePath("../SpringResolver"))
	active.set("rig_builder_path", NodePath("../PhysicsRigBuilder"))
	active.set("animation_player_path", NodePath("../%s" % anim_name))
	active.set("character_root_path", NodePath(".."))
	nodes.append(active)

	# 6. PartialRagdollController
	var partial := Node.new()
	partial.name = "PartialRagdollController"
	partial.set_script(load("res://addons/kickback/partial_ragdoll_controller.gd"))
	partial.set("simulator_path", NodePath(simulator_path))
	partial.set("skeleton_path", NodePath("../%s" % skeleton_name))
	partial.set("animation_player_path", NodePath("../%s" % anim_name))
	nodes.append(partial)

	# 7. FlinchController
	var flinch := Node.new()
	flinch.name = "FlinchController"
	flinch.set_script(load("res://addons/kickback/flinch_controller.gd"))
	flinch.set("animation_player_path", NodePath("../%s" % anim_name))
	flinch.set("character_path", NodePath(".."))
	flinch.set("ragdoll_controller_path", NodePath("../PartialRagdollController"))
	nodes.append(flinch)

	# Add all nodes via undo/redo (only add_child/remove_child)
	var undo := get_undo_redo()
	undo.create_action("Add Kickback to Character")

	for node: Node in nodes:
		undo.add_do_method(self, "_add_node", root, node, scene_owner)
		undo.add_undo_method(self, "_remove_node", root, node)

	undo.commit_action()

	for node: Node in nodes:
		print("Kickback: Created '%s' — script: %s" % [node.name, node.get_script() != null])
	print("Kickback: Added %d controller nodes to '%s'" % [nodes.size(), root.name])


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
