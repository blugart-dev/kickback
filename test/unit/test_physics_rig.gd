extends GutTest

var _character: Node3D
var _rig_builder: PhysicsRigBuilder
var _spring: SpringResolver


func before_each():
	_character = preload("res://assets/characters/ybot/ybot.tscn").instantiate()
	add_child_autofree(_character)

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

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_rig_builder.set_enabled(true)
	sync.set_active(true)
	_spring.set_active(true)


func test_rig_builder_creates_16_bodies():
	var bodies := _rig_builder.get_bodies()
	assert_eq(bodies.size(), 16, "Should create 16 RigidBody3D nodes")


func test_rig_builder_bodies_have_correct_names():
	var bodies := _rig_builder.get_bodies()
	var expected := ["Hips", "Spine", "Chest", "Head",
		"UpperArm_L", "LowerArm_L", "Hand_L",
		"UpperArm_R", "LowerArm_R", "Hand_R",
		"UpperLeg_L", "LowerLeg_L", "Foot_L",
		"UpperLeg_R", "LowerLeg_R", "Foot_R"]
	for name: String in expected:
		assert_true(name in bodies, "Body '%s' should exist" % name)


func test_spring_resolver_has_all_bones():
	var bone_names := _spring.get_all_bone_names()
	assert_eq(bone_names.size(), 16, "Should track 16 bones")


func test_spring_resolver_default_strengths():
	assert_almost_eq(_spring.get_base_strength("Hips"), 0.65, 0.01)
	assert_almost_eq(_spring.get_base_strength("Head"), 0.35, 0.01)
	assert_almost_eq(_spring.get_base_strength("Hand_L"), 0.25, 0.01)


func test_spring_set_and_get_strength():
	_spring.set_bone_strength("Hips", 0.1)
	assert_almost_eq(_spring.get_bone_strength("Hips"), 0.1, 0.001)


func test_jolt_check_detects_jolt():
	assert_true(JoltCheck.is_jolt_active(), "Jolt should be active in this project")


func test_bodies_use_correct_collision_layer():
	var tuning := RagdollTuning.create_default()
	var bodies := _rig_builder.get_bodies()
	for rig_name: String in bodies:
		var body: RigidBody3D = bodies[rig_name]
		assert_eq(body.collision_layer, tuning.collision_layer,
			"Body '%s' collision_layer should match tuning default" % rig_name)


func test_bodies_use_correct_collision_mask():
	var tuning := RagdollTuning.create_default()
	var bodies := _rig_builder.get_bodies()
	for rig_name: String in bodies:
		var body: RigidBody3D = bodies[rig_name]
		assert_eq(body.collision_mask, tuning.collision_mask,
			"Body '%s' collision_mask should match tuning default" % rig_name)


func test_all_base_strengths_match_tuning():
	var tuning := RagdollTuning.create_default()
	for rig_name: String in _spring.get_all_bone_names():
		var expected: float = tuning.strength_map.get(rig_name, tuning.default_spring_strength)
		assert_almost_eq(_spring.get_base_strength(rig_name), expected, 0.01,
			"Base strength for '%s' should match tuning" % rig_name)


func test_root_motion_stripping_enabled_by_default():
	var tuning := RagdollTuning.create_default()
	assert_true(tuning.strip_root_motion, "Root motion stripping should be on by default")
	assert_eq(tuning.root_motion_bone, "Hips", "Root motion bone should default to Hips")
