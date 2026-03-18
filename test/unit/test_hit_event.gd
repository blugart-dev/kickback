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
