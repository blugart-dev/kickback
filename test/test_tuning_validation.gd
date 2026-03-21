extends GutTest


var _profile: RagdollProfile


func before_all():
	_profile = RagdollProfile.create_mixamo_default()


func test_clean_tuning_no_warnings():
	var t := RagdollTuning.create_default()
	assert_eq(t.validate_against_profile(_profile).size(), 0)


func test_bad_strength_map_key():
	var t := RagdollTuning.create_default()
	t.strength_map["FAKE_BONE"] = 0.5
	var w := t.validate_against_profile(_profile)
	assert_true(w.size() > 0, "Should catch bad strength_map key")
	var found := false
	for warning: String in w:
		if "strength_map" in warning:
			found = true
	assert_true(found, "Warning should mention strength_map")


func test_bad_pin_strength_key():
	var t := RagdollTuning.create_default()
	t.pin_strength_overrides["Ghost"] = 0.5
	assert_true(t.validate_against_profile(_profile).size() > 0)


func test_bad_ramp_delay_key():
	var t := RagdollTuning.create_default()
	t.ramp_delay["Phantom"] = 0.1
	assert_true(t.validate_against_profile(_profile).size() > 0)


func test_bad_min_strength_key():
	var t := RagdollTuning.create_default()
	t.min_strength["Bogus"] = 0.05
	assert_true(t.validate_against_profile(_profile).size() > 0)


func test_bad_protected_bones():
	var t := RagdollTuning.create_default()
	t.protected_bones = PackedStringArray(["BadBone123"])
	assert_eq(t.validate_against_profile(_profile).size(), 1)


func test_valid_protected_bones():
	var t := RagdollTuning.create_default()
	t.protected_bones = PackedStringArray(["UpperLeg_L", "LowerLeg_L", "Foot_L"])
	assert_eq(t.validate_against_profile(_profile).size(), 0)


func test_bad_core_bracing_bones():
	var t := RagdollTuning.create_default()
	t.core_bracing_bones = PackedStringArray(["Hips", "Spine", "GhostBone"])
	assert_eq(t.validate_against_profile(_profile).size(), 1)


func test_multiple_errors_accumulate():
	var t := RagdollTuning.create_default()
	t.strength_map["Bad1"] = 0.5
	t.pin_strength_overrides["Bad2"] = 0.5
	t.ramp_delay["Bad3"] = 0.1
	t.protected_bones = PackedStringArray(["Bad4"])
	assert_eq(t.validate_against_profile(_profile).size(), 4)


func test_empty_dicts_valid():
	var t := RagdollTuning.create_default()
	t.strength_map = {}
	t.pin_strength_overrides = {}
	t.ramp_delay = {}
	t.min_strength = {}
	assert_eq(t.validate_against_profile(_profile).size(), 0)


func test_all_default_bone_names_valid():
	var t := RagdollTuning.create_default()
	var valid_names: Array[String] = []
	for bone_def: BoneDefinition in _profile.bones:
		valid_names.append(bone_def.rig_name)
	for key: String in t.strength_map:
		assert_has(valid_names, key, "strength_map key '%s' should be valid" % key)
