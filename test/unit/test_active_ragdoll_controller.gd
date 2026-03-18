extends GutTest

var _character: Node3D
var _spring: SpringResolver
var _rig_builder: PhysicsRigBuilder
var _controller: ActiveRagdollController


func before_each():
	_character = preload("res://assets/characters/ybot/ybot.tscn").instantiate()
	add_child_autofree(_character)

	# Remove simulator (conflicts with active ragdoll)
	var sim := _character.get_node_or_null("Skeleton3D/PhysicalBoneSimulator3D")
	if sim:
		sim.queue_free()

	_rig_builder = PhysicsRigBuilder.new()
	_rig_builder.name = "PhysicsRigBuilder"
	_rig_builder.skeleton_path = NodePath("../Skeleton3D")
	_character.add_child(_rig_builder)

	var sync := PhysicsRigSync.new()
	sync.name = "PhysicsRigSync"
	sync.skeleton_path = NodePath("../Skeleton3D")
	sync.rig_builder_path = NodePath("../PhysicsRigBuilder")
	_character.add_child(sync)

	_spring = SpringResolver.new()
	_spring.name = "SpringResolver"
	_spring.skeleton_path = NodePath("../Skeleton3D")
	_spring.rig_builder_path = NodePath("../PhysicsRigBuilder")
	_character.add_child(_spring)

	_controller = ActiveRagdollController.new()
	_controller.name = "ActiveRagdollController"
	_controller.spring_resolver_path = NodePath("../SpringResolver")
	_controller.rig_builder_path = NodePath("../PhysicsRigBuilder")
	_controller.animation_player_path = NodePath("../AnimationPlayer")
	_controller.character_root_path = NodePath("..")
	_character.add_child(_controller)

	# Wait for initialization (same pattern as production code)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_rig_builder.set_enabled(true)
	sync.set_active(true)
	_spring.set_active(true)


func test_initial_state_is_normal():
	assert_eq(_controller.get_state(), ActiveRagdollController.State.NORMAL)
	assert_eq(_controller.get_state_name(), "NORMAL")


func test_trigger_ragdoll_sets_state():
	_controller.trigger_ragdoll()
	assert_eq(_controller.get_state(), ActiveRagdollController.State.RAGDOLL)
	assert_eq(_controller.get_state_name(), "RAGDOLL")


func test_state_changed_signal_on_ragdoll():
	watch_signals(_controller)
	_controller.trigger_ragdoll()
	assert_signal_emitted(_controller, "state_changed")


func test_all_strengths_zero_after_ragdoll():
	_controller.trigger_ragdoll()
	for bone_name: String in _spring.get_all_bone_names():
		assert_eq(_spring.get_bone_strength(bone_name), 0.0,
			"Bone '%s' should be zero after ragdoll" % bone_name)
