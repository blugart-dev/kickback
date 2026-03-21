## Unit tests for SkeletonDetector bone pattern matching.
## Run this scene to verify humanoid bone detection across naming conventions.
extends Node


func _ready() -> void:
	print("=== test_skeleton_detector.gd ===")
	var passed := 0
	var failed := 0

	# -- Mixamo naming --
	var mixamo_bones := PackedStringArray([
		"mixamorig_Hips", "mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2",
		"mixamorig_Neck", "mixamorig_Head",
		"mixamorig_LeftShoulder", "mixamorig_LeftArm", "mixamorig_LeftForeArm", "mixamorig_LeftHand",
		"mixamorig_RightShoulder", "mixamorig_RightArm", "mixamorig_RightForeArm", "mixamorig_RightHand",
		"mixamorig_LeftUpLeg", "mixamorig_LeftLeg", "mixamorig_LeftFoot", "mixamorig_LeftToeBase",
		"mixamorig_RightUpLeg", "mixamorig_RightLeg", "mixamorig_RightFoot", "mixamorig_RightToeBase",
	])
	var mixamo_result := SkeletonDetector.detect_from_bone_names(mixamo_bones)
	if _assert(mixamo_result.size() > 0, "Mixamo: bones detected (%d slots)" % mixamo_result.size()):
		passed += 1
	else:
		failed += 1
	if _assert(mixamo_result.size() >= 8, "Mixamo: at least 8 required slots"):
		passed += 1
	else:
		failed += 1
	if _assert("Hips" in mixamo_result, "Mixamo: Hips slot detected"):
		passed += 1
	else:
		failed += 1
	if _assert("Head" in mixamo_result, "Mixamo: Head slot detected"):
		passed += 1
	else:
		failed += 1
	if _assert("UpperArm_L" in mixamo_result, "Mixamo: UpperArm_L slot detected"):
		passed += 1
	else:
		failed += 1
	if _assert("Foot_R" in mixamo_result, "Mixamo: Foot_R slot detected"):
		passed += 1
	else:
		failed += 1

	# -- Generic/Rigify naming --
	var rigify_bones := PackedStringArray([
		"Hips", "Spine", "Spine1", "Chest",
		"Neck", "Head",
		"UpperArm_L", "LowerArm_L", "Hand_L",
		"UpperArm_R", "LowerArm_R", "Hand_R",
		"UpperLeg_L", "LowerLeg_L", "Foot_L",
		"UpperLeg_R", "LowerLeg_R", "Foot_R",
	])
	var rigify_result := SkeletonDetector.detect_from_bone_names(rigify_bones)
	if _assert(rigify_result.size() >= 8, "Rigify: at least 8 slots (%d)" % rigify_result.size()):
		passed += 1
	else:
		failed += 1
	if _assert("Hips" in rigify_result, "Rigify: Hips slot detected"):
		passed += 1
	else:
		failed += 1

	# -- Too few bones (should fail) --
	var sparse_bones := PackedStringArray(["Hips", "Head", "Hand_L"])
	var sparse_result := SkeletonDetector.detect_from_bone_names(sparse_bones)
	if _assert(sparse_result.size() == 0, "Sparse skeleton rejected (got %d, need 8+)" % sparse_result.size()):
		passed += 1
	else:
		failed += 1

	# -- Missing required bone (no Spine) --
	var no_spine := PackedStringArray([
		"Hips", "Head",
		"UpperArm_L", "LowerArm_L", "Hand_L",
		"UpperArm_R", "LowerArm_R", "Hand_R",
		"UpperLeg_L", "LowerLeg_L", "Foot_L",
		"UpperLeg_R", "LowerLeg_R", "Foot_R",
	])
	var no_spine_result := SkeletonDetector.detect_from_bone_names(no_spine)
	if _assert(no_spine_result.size() == 0, "Missing Spine → rejected"):
		passed += 1
	else:
		failed += 1

	# -- Empty skeleton --
	var empty_result := SkeletonDetector.detect_from_bone_names(PackedStringArray())
	if _assert(empty_result.size() == 0, "Empty skeleton → empty result"):
		passed += 1
	else:
		failed += 1

	# -- Verify detect_humanoid_bones wraps detect_from_bone_names --
	# (Can't test without Skeleton3D, but verify the function exists)
	if _assert(SkeletonDetector.has_method("detect_humanoid_bones"), "detect_humanoid_bones() exists"):
		passed += 1
	else:
		failed += 1
	if _assert(SkeletonDetector.has_method("detect_from_bone_names"), "detect_from_bone_names() exists"):
		passed += 1
	else:
		failed += 1

	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	if failed > 0:
		print("FAIL")
	else:
		print("ALL TESTS PASSED")


func _assert(condition: bool, message: String) -> bool:
	if condition:
		print("  PASS: %s" % message)
	else:
		print("  FAIL: %s" % message)
	return condition
