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
	var mixamo_result := SkeletonDetector.detect_humanoid_bones(mixamo_bones)
	if _assert(mixamo_result.size() > 0, "Mixamo bones detected (got %d slots)" % mixamo_result.size()):
		passed += 1
	else:
		failed += 1
	if _assert(mixamo_result.size() >= 8, "Mixamo has at least 8 required slots"):
		passed += 1
	else:
		failed += 1

	# Check critical bones are found
	var mixamo_rig_names := []
	for slot: Dictionary in mixamo_result:
		mixamo_rig_names.append(slot.get("rig_name", ""))
	if _assert("Hips" in mixamo_rig_names, "Mixamo: Hips slot detected"):
		passed += 1
	else:
		failed += 1
	if _assert("Head" in mixamo_rig_names, "Mixamo: Head slot detected"):
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
	var rigify_result := SkeletonDetector.detect_humanoid_bones(rigify_bones)
	if _assert(rigify_result.size() >= 8, "Rigify bones detected (got %d slots)" % rigify_result.size()):
		passed += 1
	else:
		failed += 1

	# -- Too few bones (should fail) --
	var sparse_bones := PackedStringArray(["Hips", "Head", "Hand_L"])
	var sparse_result := SkeletonDetector.detect_humanoid_bones(sparse_bones)
	if _assert(sparse_result.size() < 8, "Sparse skeleton rejected (got %d, need 8+)" % sparse_result.size()):
		passed += 1
	else:
		failed += 1

	# -- Empty skeleton --
	var empty_result := SkeletonDetector.detect_humanoid_bones(PackedStringArray())
	if _assert(empty_result.size() == 0, "Empty skeleton returns empty result"):
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
