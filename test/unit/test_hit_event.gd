extends GutTest


func test_classify_region_head():
	assert_eq(HitEvent.classify_region("mixamorig_Head"), "head")
	assert_eq(HitEvent.classify_region("mixamorig_Neck"), "head")


func test_classify_region_torso():
	assert_eq(HitEvent.classify_region("mixamorig_Hips"), "torso")
	assert_eq(HitEvent.classify_region("mixamorig_Spine"), "torso")
	assert_eq(HitEvent.classify_region("mixamorig_Spine2"), "torso")


func test_classify_region_upper_limb():
	assert_eq(HitEvent.classify_region("mixamorig_LeftArm"), "upper_limb")
	assert_eq(HitEvent.classify_region("mixamorig_RightForeArm"), "upper_limb")
	assert_eq(HitEvent.classify_region("mixamorig_LeftHand"), "upper_limb")


func test_classify_region_lower_limb():
	assert_eq(HitEvent.classify_region("mixamorig_LeftUpLeg"), "lower_limb")
	assert_eq(HitEvent.classify_region("mixamorig_LeftLeg"), "lower_limb")
	assert_eq(HitEvent.classify_region("mixamorig_RightFoot"), "lower_limb")


func test_classify_region_unknown_defaults_torso():
	assert_eq(HitEvent.classify_region("SomeRandomBone"), "torso")
	assert_eq(HitEvent.classify_region(""), "torso")


func test_default_properties():
	var ev := HitEvent.new()
	assert_eq(ev.hit_position, Vector3.ZERO, "Default hit_position should be ZERO")
	assert_eq(ev.hit_direction, Vector3.ZERO, "Default hit_direction should be ZERO")
	assert_eq(ev.hit_bone_name, "", "Default hit_bone_name should be empty")
	assert_eq(ev.impulse_magnitude, 0.0, "Default impulse_magnitude should be 0")
	assert_eq(ev.hit_bone_region, "torso", "Default hit_bone_region should be torso")
	assert_null(ev.hit_bone, "Default hit_bone should be null")


func test_property_assignment():
	var ev := HitEvent.new()
	ev.hit_position = Vector3(1, 2, 3)
	ev.hit_direction = Vector3.RIGHT
	ev.hit_bone_name = "mixamorig_Head"
	ev.impulse_magnitude = 15.5
	ev.hit_bone_region = "head"
	assert_eq(ev.hit_position, Vector3(1, 2, 3))
	assert_eq(ev.hit_direction, Vector3.RIGHT)
	assert_eq(ev.hit_bone_name, "mixamorig_Head")
	assert_eq(ev.impulse_magnitude, 15.5)
	assert_eq(ev.hit_bone_region, "head")


func test_classify_region_non_mixamo_naming():
	assert_eq(HitEvent.classify_region("Head"), "head")
	assert_eq(HitEvent.classify_region("Neck"), "head")
	assert_eq(HitEvent.classify_region("LeftArm"), "upper_limb")
	assert_eq(HitEvent.classify_region("right_foot"), "lower_limb")
	assert_eq(HitEvent.classify_region("Spine1"), "torso")
	assert_eq(HitEvent.classify_region("LeftUpLeg"), "lower_limb")
