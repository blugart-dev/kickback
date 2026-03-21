## Unit tests for HitEvent region classification and property construction.
extends Node


func _ready() -> void:
	print("=== test_hit_event.gd ===")
	var passed := 0
	var failed := 0

	# ── Region classification: head ───────────────────────────────────────────
	for bone in ["mixamorig_Head", "Head", "head", "mixamorig_Neck", "Neck"]:
		if _assert(HitEvent.classify_region(bone) == "head", "'%s' → head" % bone):
			passed += 1
		else:
			failed += 1

	# ── Region classification: torso ──────────────────────────────────────────
	for bone in ["mixamorig_Hips", "Hips", "Pelvis", "mixamorig_Spine", "Spine", "Chest", "mixamorig_Spine2"]:
		if _assert(HitEvent.classify_region(bone) == "torso", "'%s' → torso" % bone):
			passed += 1
		else:
			failed += 1

	# ── Region classification: upper_limb ─────────────────────────────────────
	for bone in ["mixamorig_LeftArm", "UpperArm_L", "mixamorig_LeftForeArm", "LowerArm_R", "mixamorig_LeftHand", "Hand_L"]:
		if _assert(HitEvent.classify_region(bone) == "upper_limb", "'%s' → upper_limb" % bone):
			passed += 1
		else:
			failed += 1

	# ── Region classification: lower_limb ─────────────────────────────────────
	for bone in ["mixamorig_LeftUpLeg", "UpperLeg_L", "mixamorig_LeftLeg", "LowerLeg_R", "mixamorig_LeftFoot", "Foot_R", "mixamorig_LeftToeBase"]:
		if _assert(HitEvent.classify_region(bone) == "lower_limb", "'%s' → lower_limb" % bone):
			passed += 1
		else:
			failed += 1

	# ── Default fallback ──────────────────────────────────────────────────────
	if _assert(HitEvent.classify_region("UnknownBone") == "torso", "'UnknownBone' → torso"):
		passed += 1
	else:
		failed += 1
	if _assert(HitEvent.classify_region("") == "torso", "empty → torso"):
		passed += 1
	else:
		failed += 1

	# ── HitEvent property construction ────────────────────────────────────────
	var event := HitEvent.new()
	if _assert(event.hit_bone_region == "torso", "Default region = 'torso'"):
		passed += 1
	else:
		failed += 1

	event.hit_position = Vector3(1.0, 2.0, 3.0)
	if _assert(event.hit_position == Vector3(1.0, 2.0, 3.0), "hit_position assignable"):
		passed += 1
	else:
		failed += 1

	event.hit_direction = Vector3.FORWARD
	if _assert(event.hit_direction == Vector3.FORWARD, "hit_direction assignable"):
		passed += 1
	else:
		failed += 1

	event.hit_bone_name = "mixamorig_LeftArm"
	if _assert(event.hit_bone_name == "mixamorig_LeftArm", "hit_bone_name assignable"):
		passed += 1
	else:
		failed += 1

	event.impulse_magnitude = 15.5
	if _assert(event.impulse_magnitude == 15.5, "impulse_magnitude assignable"):
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
