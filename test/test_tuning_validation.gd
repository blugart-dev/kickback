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


# --- Foot-IK validation resolves via semantic roles, not hardcoded Mixamo names ---

func _make_custom_leg_profile() -> RagdollProfile:
	# A non-Mixamo rig: feet/legs use custom names exposed via the role fields.
	var p := RagdollProfile.new()
	for rig_name: String in ["pelvis", "thighL", "shinL", "footL", "thighR", "shinR", "footR"]:
		var bd := BoneDefinition.new()
		bd.rig_name = rig_name
		bd.skeleton_bone = rig_name
		p.bones.append(bd)
	p.root_rig = "pelvis"
	p.foot_rigs = PackedStringArray(["footL", "footR"])
	p.left_leg_chain = PackedStringArray(["thighL", "shinL", "footL"])
	p.right_leg_chain = PackedStringArray(["thighR", "shinR", "footR"])
	return p


func _bare_tuning() -> RagdollTuning:
	# Default tuning with the rig-name dicts cleared, so only the foot-IK role check
	# can contribute warnings (the default dicts hold Mixamo keys absent from custom rigs).
	var t := RagdollTuning.create_default()
	t.strength_map = {}
	t.pin_strength_overrides = {}
	t.ramp_delay = {}
	t.min_strength = {}
	t.protected_bones = PackedStringArray()
	t.core_bracing_bones = PackedStringArray()
	return t


func test_foot_ik_accepts_role_mapped_non_mixamo_legs():
	# Regression: the validator used to hardcode "Foot_L"/"UpperLeg_L"/... and would
	# wrongly warn here even though foot IK actually resolves feet/legs via roles.
	var t := _bare_tuning()
	t.foot_ik_enabled = true
	var w := t.validate_against_profile(_make_custom_leg_profile())
	assert_eq(w.size(), 0, "role-mapped feet/legs should satisfy foot_ik_enabled; got %s" % str(w))


func test_foot_ik_warns_when_feet_absent():
	var p := RagdollProfile.new()
	var bd := BoneDefinition.new()
	bd.rig_name = "pelvis"
	p.bones.append(bd)
	p.root_rig = "pelvis"
	p.foot_rigs = PackedStringArray()
	p.left_leg_chain = PackedStringArray()
	p.right_leg_chain = PackedStringArray()
	var t := _bare_tuning()
	t.foot_ik_enabled = true
	assert_true(t.validate_against_profile(p).size() >= 1, "foot_ik_enabled with no feet must warn")


func test_foot_ik_disabled_skips_role_checks():
	var p := RagdollProfile.new()  # no bones, no leg roles
	var t := _bare_tuning()
	t.foot_ik_enabled = false
	assert_eq(t.validate_against_profile(p).size(), 0, "disabled foot_ik must not warn about missing feet")
