extends GutTest


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
	for bone_def: BoneDefinition in profile.bones:
		if bone_def.rig_name == "Foot_L" or bone_def.rig_name == "Foot_R":
			assert_eq(bone_def.shape_offset, 0.65, "%s should have 0.65 offset" % bone_def.rig_name)
		else:
			assert_eq(bone_def.shape_offset, 0.5, "%s should have 0.5 offset" % bone_def.rig_name)


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
