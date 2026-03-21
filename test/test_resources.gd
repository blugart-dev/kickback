extends GutTest


# ── ImpactProfile factories ──────────────────────────────────────────────────

func test_bullet_profile():
	var p := ImpactProfile.create_bullet()
	assert_not_null(p)
	assert_eq(p.base_impulse, 8.0)
	assert_eq(p.ragdoll_probability, 0.05)
	assert_eq(p.strength_spread, 1)
	assert_true(p.strength_reduction > 0.0)
	assert_true(p.recovery_rate > 0.0)


func test_shotgun_profile():
	var p := ImpactProfile.create_shotgun()
	assert_not_null(p)
	assert_eq(p.ragdoll_probability, 0.40)
	assert_eq(p.strength_spread, 3)


func test_explosion_profile():
	var p := ImpactProfile.create_explosion()
	assert_not_null(p)
	assert_eq(p.ragdoll_probability, 0.95)
	assert_eq(p.strength_spread, 99)
	assert_true(p.upward_bias > 0.0, "Explosion should have upward bias")


func test_melee_profile():
	var p := ImpactProfile.create_melee()
	assert_not_null(p)
	assert_eq(p.impulse_transfer_ratio, 0.60)


func test_arrow_profile():
	var p := ImpactProfile.create_arrow()
	assert_not_null(p)
	assert_eq(p.base_impulse, 12.0)


func test_all_profiles_have_positive_values():
	var factories: Array[ImpactProfile] = [
		ImpactProfile.create_bullet(), ImpactProfile.create_shotgun(),
		ImpactProfile.create_explosion(), ImpactProfile.create_melee(),
		ImpactProfile.create_arrow(),
	]
	for p: ImpactProfile in factories:
		assert_true(p.base_impulse > 0.0)
		assert_true(p.strength_reduction > 0.0)
		assert_true(p.recovery_rate > 0.0)


# ── RagdollProfile ───────────────────────────────────────────────────────────

func test_mixamo_profile_structure():
	var profile := RagdollProfile.create_mixamo_default()
	assert_not_null(profile)
	assert_eq(profile.bones.size(), 16, "Should have 16 bones")
	assert_eq(profile.joints.size(), 15, "Should have 15 joints")
	assert_eq(profile.root_bone, "mixamorig_Hips")
	assert_true(profile.intermediate_bones.size() > 0)


func test_bone_definitions():
	var profile := RagdollProfile.create_mixamo_default()
	var bone_names: Array[String] = []
	for bone_def: BoneDefinition in profile.bones:
		bone_names.append(bone_def.rig_name)
	assert_has(bone_names, "Hips")
	assert_has(bone_names, "Head")
	assert_has(bone_names, "Foot_L")
	assert_has(bone_names, "Hand_R")


func test_hips_bone_properties():
	var profile := RagdollProfile.create_mixamo_default()
	for bone_def: BoneDefinition in profile.bones:
		if bone_def.rig_name == "Hips":
			assert_eq(bone_def.mass, 15.0)
			assert_true(bone_def.skeleton_bone != "", "Should have skeleton_bone")
			return
	fail_test("Hips bone not found")


func test_head_bone_properties():
	var profile := RagdollProfile.create_mixamo_default()
	for bone_def: BoneDefinition in profile.bones:
		if bone_def.rig_name == "Head":
			assert_eq(bone_def.mass, 5.0)
			return
	fail_test("Head bone not found")


func test_joint_definitions():
	var profile := RagdollProfile.create_mixamo_default()
	var joint_pairs: Array[String] = []
	for jd: JointDefinition in profile.joints:
		joint_pairs.append("%s→%s" % [jd.parent_rig, jd.child_rig])
	assert_has(joint_pairs, "Hips→Spine")
	assert_has(joint_pairs, "Chest→Head")
	assert_has(joint_pairs, "Chest→UpperArm_L")


func test_joint_angular_limits():
	var profile := RagdollProfile.create_mixamo_default()
	for jd: JointDefinition in profile.joints:
		if jd.parent_rig == "Hips" and jd.child_rig == "Spine":
			assert_true(jd.limit_x.y > 0.0, "Hips→Spine X upper limit should be > 0")
			return
	fail_test("Hips→Spine joint not found")


func test_intermediate_bone_entry():
	var profile := RagdollProfile.create_mixamo_default()
	var inter: IntermediateBoneEntry = profile.intermediate_bones[0]
	assert_true(inter is IntermediateBoneEntry)
	assert_true(inter.skeleton_bone != "")
	assert_true(inter.rig_body_a != "")
	assert_true(inter.rig_body_b != "")


# ── RagdollTuning ────────────────────────────────────────────────────────────

func test_tuning_defaults():
	var t := RagdollTuning.create_default()
	assert_not_null(t)
	assert_eq(t.stagger_threshold, 0.70)
	assert_eq(t.stagger_duration, 1.8)
	assert_eq(t.stagger_strength_floor, 0.10)
	assert_eq(t.stagger_sway_strength, 300.0)
	assert_eq(t.stagger_recovery_rate, 0.03)
	assert_eq(t.resistance_counter_strength, 0.40)
	assert_eq(t.resistance_leg_brace, 0.35)
	assert_eq(t.stagger_sway_drift, 0.4)
	assert_eq(t.stagger_sway_twist, 0.15)


func test_tuning_validates_clean():
	var t := RagdollTuning.create_default()
	var profile := RagdollProfile.create_mixamo_default()
	var warnings := t.validate_against_profile(profile)
	assert_eq(warnings.size(), 0, "Default tuning should validate cleanly")
