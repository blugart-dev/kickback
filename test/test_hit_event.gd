## Unit tests for HitEvent region classification.
## Run this scene to verify bone name → region mapping.
extends Node


func _ready() -> void:
	print("=== test_hit_event.gd ===")
	var passed := 0
	var failed := 0

	# -- Head region --
	for bone in ["mixamorig_Head", "Head", "head", "mixamorig_Neck", "Neck"]:
		if _assert(HitEvent.classify_region(bone) == "head", "'%s' → head" % bone):
			passed += 1
		else:
			failed += 1

	# -- Torso region --
	for bone in ["mixamorig_Hips", "Hips", "Pelvis", "mixamorig_Spine", "Spine", "Chest", "mixamorig_Spine2"]:
		if _assert(HitEvent.classify_region(bone) == "torso", "'%s' → torso" % bone):
			passed += 1
		else:
			failed += 1

	# -- Upper limb region --
	for bone in ["mixamorig_LeftArm", "UpperArm_L", "mixamorig_LeftForeArm", "LowerArm_R", "mixamorig_LeftHand", "Hand_L"]:
		if _assert(HitEvent.classify_region(bone) == "upper_limb", "'%s' → upper_limb" % bone):
			passed += 1
		else:
			failed += 1

	# -- Lower limb region --
	for bone in ["mixamorig_LeftUpLeg", "UpperLeg_L", "mixamorig_LeftLeg", "LowerLeg_R", "mixamorig_LeftFoot", "Foot_R", "mixamorig_LeftToeBase"]:
		if _assert(HitEvent.classify_region(bone) == "lower_limb", "'%s' → lower_limb" % bone):
			passed += 1
		else:
			failed += 1

	# -- Default fallback --
	if _assert(HitEvent.classify_region("UnknownBone") == "torso", "'UnknownBone' → torso (default)"):
		passed += 1
	else:
		failed += 1
	if _assert(HitEvent.classify_region("") == "torso", "empty string → torso (default)"):
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
