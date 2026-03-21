extends GutTest


func test_head_region_classification():
	for bone in ["mixamorig_Head", "Head", "head", "mixamorig_Neck", "Neck"]:
		assert_eq(HitEvent.classify_region(bone), "head", "'%s' should be head" % bone)


func test_torso_region_classification():
	for bone in ["mixamorig_Hips", "Hips", "Pelvis", "mixamorig_Spine", "Spine", "Chest", "mixamorig_Spine2"]:
		assert_eq(HitEvent.classify_region(bone), "torso", "'%s' should be torso" % bone)


func test_upper_limb_region_classification():
	for bone in ["mixamorig_LeftArm", "UpperArm_L", "mixamorig_LeftForeArm", "LowerArm_R", "mixamorig_LeftHand", "Hand_L"]:
		assert_eq(HitEvent.classify_region(bone), "upper_limb", "'%s' should be upper_limb" % bone)


func test_lower_limb_region_classification():
	for bone in ["mixamorig_LeftUpLeg", "UpperLeg_L", "mixamorig_LeftLeg", "LowerLeg_R", "mixamorig_LeftFoot", "Foot_R", "mixamorig_LeftToeBase"]:
		assert_eq(HitEvent.classify_region(bone), "lower_limb", "'%s' should be lower_limb" % bone)


func test_unknown_bone_defaults_to_torso():
	assert_eq(HitEvent.classify_region("UnknownBone"), "torso")
	assert_eq(HitEvent.classify_region(""), "torso")


func test_hit_event_default_region():
	var event := HitEvent.new()
	assert_eq(event.hit_bone_region, "torso")


func test_hit_event_property_assignment():
	var event := HitEvent.new()
	event.hit_position = Vector3(1.0, 2.0, 3.0)
	event.hit_direction = Vector3.FORWARD
	event.hit_bone_name = "mixamorig_LeftArm"
	event.impulse_magnitude = 15.5

	assert_eq(event.hit_position, Vector3(1.0, 2.0, 3.0))
	assert_eq(event.hit_direction, Vector3.FORWARD)
	assert_eq(event.hit_bone_name, "mixamorig_LeftArm")
	assert_eq(event.impulse_magnitude, 15.5)
