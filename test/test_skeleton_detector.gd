extends GutTest

const RigHarness = preload("res://test/helpers/rig_harness.gd")


var _mixamo_bones := PackedStringArray([
	"mixamorig_Hips", "mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2",
	"mixamorig_Neck", "mixamorig_Head",
	"mixamorig_LeftShoulder", "mixamorig_LeftArm", "mixamorig_LeftForeArm", "mixamorig_LeftHand",
	"mixamorig_RightShoulder", "mixamorig_RightArm", "mixamorig_RightForeArm", "mixamorig_RightHand",
	"mixamorig_LeftUpLeg", "mixamorig_LeftLeg", "mixamorig_LeftFoot", "mixamorig_LeftToeBase",
	"mixamorig_RightUpLeg", "mixamorig_RightLeg", "mixamorig_RightFoot", "mixamorig_RightToeBase",
])


func test_mixamo_detection():
	var result := SkeletonDetector.detect_from_bone_names(_mixamo_bones)
	assert_true(result.size() >= 8, "Should detect at least 8 slots")
	assert_eq(result.size(), 16, "Should detect all 16 slots")
	assert_has(result, "Hips")
	assert_has(result, "Head")
	assert_has(result, "UpperArm_L")
	assert_has(result, "Foot_R")


func test_rigify_detection():
	var rigify_bones := PackedStringArray([
		"Hips", "Spine", "Spine1", "Chest", "Neck", "Head",
		"UpperArm_L", "LowerArm_L", "Hand_L",
		"UpperArm_R", "LowerArm_R", "Hand_R",
		"UpperLeg_L", "LowerLeg_L", "Foot_L",
		"UpperLeg_R", "LowerLeg_R", "Foot_R",
	])
	var result := SkeletonDetector.detect_from_bone_names(rigify_bones)
	assert_true(result.size() >= 8, "Rigify should detect at least 8 slots")
	assert_has(result, "Hips")


func test_sparse_skeleton_rejected():
	var sparse := PackedStringArray(["Hips", "Head", "Hand_L"])
	var result := SkeletonDetector.detect_from_bone_names(sparse)
	assert_eq(result.size(), 0, "Too few bones should be rejected")


func test_missing_required_bone_rejected():
	var no_spine := PackedStringArray([
		"Hips", "Head",
		"UpperArm_L", "LowerArm_L", "Hand_L",
		"UpperArm_R", "LowerArm_R", "Hand_R",
		"UpperLeg_L", "LowerLeg_L", "Foot_L",
		"UpperLeg_R", "LowerLeg_R", "Foot_R",
	])
	var result := SkeletonDetector.detect_from_bone_names(no_spine)
	assert_eq(result.size(), 0, "Missing Spine should be rejected")


func test_empty_skeleton():
	var result := SkeletonDetector.detect_from_bone_names(PackedStringArray())
	assert_eq(result.size(), 0)


func test_consistent_results():
	var r1 := SkeletonDetector.detect_from_bone_names(_mixamo_bones)
	var r2 := SkeletonDetector.detect_from_bone_names(_mixamo_bones)
	assert_eq(r1.size(), r2.size(), "Re-call should produce same result")


func test_bone_definition_shape_offset_default():
	var bone_def := BoneDefinition.new()
	assert_eq(bone_def.shape_offset, 0.5, "Default shape_offset should be 0.5")


func test_mixamo_default_has_foot_offset():
	var profile := RagdollProfile.create_mixamo_default()
	assert_eq(profile.bones.size(), 16, "Mixamo default should have 16 bones")
	for bone_def: BoneDefinition in profile.bones:
		if bone_def.rig_name == "Foot_L" or bone_def.rig_name == "Foot_R":
			assert_eq(bone_def.shape_offset, 0.65, "%s should have 0.65 offset" % bone_def.rig_name)
		else:
			assert_eq(bone_def.shape_offset, 0.5, "%s should have 0.5 offset" % bone_def.rig_name)


func test_mixamo_default_head_has_child_bone():
	var profile := RagdollProfile.create_mixamo_default()
	for bone_def: BoneDefinition in profile.bones:
		if bone_def.rig_name == "Head":
			assert_eq(bone_def.child_bone, "mixamorig_HeadTop_End", "Head should have HeadTop_End as child")




func test_proportions_table_has_all_slots():
	var all_slots := [
		"Hips", "Spine", "Chest", "Head",
		"UpperArm_L", "LowerArm_L", "Hand_L",
		"UpperArm_R", "LowerArm_R", "Hand_R",
		"UpperLeg_L", "LowerLeg_L", "Foot_L",
		"UpperLeg_R", "LowerLeg_R", "Foot_R",
	]
	for slot: String in all_slots:
		assert_has(SkeletonDetector.BONE_PROPORTIONS, slot, "BONE_PROPORTIONS should have %s" % slot)


func test_proportions_table_feet_have_depth_is_length():
	var foot_l: Dictionary = SkeletonDetector.BONE_PROPORTIONS["Foot_L"]
	var foot_r: Dictionary = SkeletonDetector.BONE_PROPORTIONS["Foot_R"]
	assert_true(foot_l.get("depth_is_length", false), "Foot_L should have depth_is_length")
	assert_true(foot_r.get("depth_is_length", false), "Foot_R should have depth_is_length")


func test_proportions_table_hands_have_depth_is_length():
	var hand_l: Dictionary = SkeletonDetector.BONE_PROPORTIONS["Hand_L"]
	var hand_r: Dictionary = SkeletonDetector.BONE_PROPORTIONS["Hand_R"]
	assert_true(hand_l.get("depth_is_length", false), "Hand_L should have depth_is_length")
	assert_true(hand_r.get("depth_is_length", false), "Hand_R should have depth_is_length")


# --- create_collision_shape: single source of truth for box/capsule/sphere ---

func test_create_collision_shape_box():
	var bd := BoneDefinition.new()
	bd.shape_type = "box"
	bd.box_size = Vector3(0.3, 0.2, 0.25)
	var col: CollisionShape3D = autofree(SkeletonDetector.create_collision_shape(bd))
	assert_true(col.shape is BoxShape3D, "box shape_type yields a BoxShape3D")
	assert_eq((col.shape as BoxShape3D).size, Vector3(0.3, 0.2, 0.25))


func test_create_collision_shape_capsule():
	var bd := BoneDefinition.new()
	bd.shape_type = "capsule"
	bd.capsule_radius = 0.08
	bd.capsule_height = 0.4
	var col: CollisionShape3D = autofree(SkeletonDetector.create_collision_shape(bd))
	assert_true(col.shape is CapsuleShape3D, "capsule shape_type yields a CapsuleShape3D")
	var cap := col.shape as CapsuleShape3D
	assert_almost_eq(cap.radius, 0.08, 0.0001)
	assert_almost_eq(cap.height, 0.4, 0.0001)


func test_create_collision_shape_sphere():
	var bd := BoneDefinition.new()
	bd.shape_type = "sphere"
	bd.sphere_radius = 0.12
	var col: CollisionShape3D = autofree(SkeletonDetector.create_collision_shape(bd))
	assert_true(col.shape is SphereShape3D, "sphere shape_type yields a SphereShape3D")
	assert_almost_eq((col.shape as SphereShape3D).radius, 0.12, 0.0001)


# --- create_profile_from_skeleton: full generation pipeline (round-trip) ---

func test_create_profile_from_skeleton_round_trips():
	var skel: Skeleton3D = autofree(RigHarness.build_mixamo_skeleton())
	var mapping := SkeletonDetector.detect_humanoid_bones(skel)
	assert_eq(mapping.size(), 16, "synthetic Mixamo skeleton detects all 16 slots")
	var profile := SkeletonDetector.create_profile_from_skeleton(skel, mapping)
	assert_eq(profile.bones.size(), 16, "generated profile has 16 bodies")
	assert_eq(profile.joints.size(), 15, "generated profile has 15 joints")
	assert_eq(profile.root_bone, "mixamorig_Hips", "root_bone set from the Hips mapping")
	assert_true(profile.intermediate_bones.size() >= 1, "intermediate bones (Spine1/Neck) detected")
	# Round-trip: a generated profile must validate clean against its own skeleton.
	var w := profile.validate_against_skeleton(skel)
	assert_eq(w.size(), 0, "generated profile validates clean against its skeleton; got %s" % str(w))


func test_create_profile_foot_shape_is_box_with_depth():
	var skel: Skeleton3D = autofree(RigHarness.build_mixamo_skeleton())
	var mapping := SkeletonDetector.detect_humanoid_bones(skel)
	var profile := SkeletonDetector.create_profile_from_skeleton(skel, mapping)
	var checked := false
	for bd: BoneDefinition in profile.bones:
		if bd.rig_name == "Foot_L":
			checked = true
			assert_eq(bd.shape_type, "box", "foot uses a box shape")
			var col: CollisionShape3D = autofree(SkeletonDetector.create_collision_shape(bd))
			assert_true((col.shape as BoxShape3D).size.z > 0.0, "foot box has positive toe-depth")
	assert_true(checked, "Foot_L should be present in the generated profile")
