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
