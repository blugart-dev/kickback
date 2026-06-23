## Tests for RagdollProfile semantic role accessors — the API the controller,
## foot IK solver, and debug HUD use instead of hardcoded bone-name literals.
extends GutTest


func _profile_with_rigs(rig_names: Array) -> RagdollProfile:
	var p := RagdollProfile.new()
	for rn: String in rig_names:
		var bd := BoneDefinition.new()
		bd.rig_name = rn
		bd.skeleton_bone = "sk_" + rn
		p.bones.append(bd)
	return p


# ── Convention defaults (Mixamo profile) ────────────────────────────────────

func test_default_profile_roles():
	var p := RagdollProfile.create_mixamo_default()
	assert_eq(p.get_root_rig(), "Hips")
	assert_eq(p.get_chest_rig(), "Chest")
	assert_eq(p.get_head_rig(), "Head")
	assert_eq(p.get_foot_rigs(), PackedStringArray(["Foot_L", "Foot_R"]))
	assert_eq(p.get_torso_rigs(), PackedStringArray(["Hips", "Spine", "Chest"]))
	assert_eq(p.get_leg_chain("L"), PackedStringArray(["UpperLeg_L", "LowerLeg_L", "Foot_L"]))
	assert_eq(p.get_leg_chain("R"), PackedStringArray(["UpperLeg_R", "LowerLeg_R", "Foot_R"]))
	assert_eq(p.get_all_leg_rigs().size(), 6)


func test_leg_membership_and_side():
	var p := RagdollProfile.create_mixamo_default()
	assert_true(p.is_leg_rig("Foot_L"))
	assert_true(p.is_leg_rig("UpperLeg_R"))
	assert_false(p.is_leg_rig("Head"))
	assert_eq(p.get_leg_side("Foot_L"), "L")
	assert_eq(p.get_leg_side("LowerLeg_R"), "R")
	assert_eq(p.get_leg_side("Head"), "")


# ── Arm chains (mirror the leg-chain API, for arm IK / bracing) ──────────────

func test_default_arm_roles():
	var p := RagdollProfile.create_mixamo_default()
	assert_eq(p.get_hand_rigs(), PackedStringArray(["Hand_L", "Hand_R"]))
	assert_eq(p.get_arm_chain("L"), PackedStringArray(["UpperArm_L", "LowerArm_L", "Hand_L"]))
	assert_eq(p.get_arm_chain("R"), PackedStringArray(["UpperArm_R", "LowerArm_R", "Hand_R"]))
	assert_eq(p.get_all_arm_rigs().size(), 6)


func test_arm_membership_and_side():
	var p := RagdollProfile.create_mixamo_default()
	assert_true(p.is_arm_rig("Hand_L"))
	assert_true(p.is_arm_rig("UpperArm_R"))
	assert_false(p.is_arm_rig("Foot_L"))
	assert_eq(p.get_arm_side("Hand_L"), "L")
	assert_eq(p.get_arm_side("LowerArm_R"), "R")
	assert_eq(p.get_arm_side("Head"), "")


func test_arm_chain_filters_incomplete():
	# Only part of the left arm exists → the chain is dropped (arm IK needs all three).
	var p := _profile_with_rigs(["UpperArm_L", "LowerArm_L"])  # no Hand_L
	assert_eq(p.get_arm_chain("L"), PackedStringArray())
	assert_eq(p.get_hand_rigs(), PackedStringArray())


func test_custom_arm_overrides():
	var p := _profile_with_rigs(["l_clavicle", "l_uparm", "l_forearm", "l_hand"])
	p.left_arm_chain = PackedStringArray(["l_uparm", "l_forearm", "l_hand"])
	p.hand_rigs = PackedStringArray(["l_hand"])
	assert_eq(p.get_arm_chain("L"), PackedStringArray(["l_uparm", "l_forearm", "l_hand"]))
	assert_eq(p.get_hand_rigs(), PackedStringArray(["l_hand"]))
	assert_true(p.is_arm_rig("l_forearm"))
	assert_eq(p.get_arm_side("l_hand"), "L")


# ── Root skeleton bone derivation (replaces hardcoded "mixamorig_Hips") ──────

func test_root_skeleton_bone_derived():
	var p := RagdollProfile.create_mixamo_default()
	assert_eq(p.root_bone, "", "root_bone is no longer a hardcoded default")
	assert_eq(p.get_root_skeleton_bone(), "mixamorig_Hips", "derives from root_rig's bone")


func test_root_skeleton_bone_explicit_override():
	var p := RagdollProfile.create_mixamo_default()
	p.root_bone = "custom_pelvis"
	assert_eq(p.get_root_skeleton_bone(), "custom_pelvis")


# ── Robustness: missing bones are filtered, not returned as dead names ───────

func test_roles_filter_missing_bones():
	# Only the left foot exists → get_foot_rigs() drops the missing right foot.
	var p := _profile_with_rigs(["Hips", "Foot_L"])
	assert_eq(p.get_foot_rigs(), PackedStringArray(["Foot_L"]))
	# Incomplete leg chains → empty (foot IK needs all three links).
	assert_eq(p.get_leg_chain("L"), PackedStringArray())
	assert_eq(p.get_leg_chain("R"), PackedStringArray())


func test_missing_root_returns_empty():
	var p := _profile_with_rigs(["Spine", "Chest"])  # no root bone defined
	assert_eq(p.get_root_rig(), "")
	assert_eq(p.get_root_skeleton_bone(), "")


# ── Custom (non-Mixamo) rig: roles overridden to match the rig's own names ───

func test_custom_rig_overrides():
	var p := _profile_with_rigs(["pelvis", "l_thigh", "l_shin", "l_ankle"])
	p.root_rig = "pelvis"
	p.foot_rigs = PackedStringArray(["l_ankle"])
	p.left_leg_chain = PackedStringArray(["l_thigh", "l_shin", "l_ankle"])
	assert_eq(p.get_root_rig(), "pelvis")
	assert_eq(p.get_foot_rigs(), PackedStringArray(["l_ankle"]))
	assert_eq(p.get_leg_chain("L"), PackedStringArray(["l_thigh", "l_shin", "l_ankle"]))
	assert_true(p.is_leg_rig("l_shin"))
	assert_eq(p.get_leg_side("l_ankle"), "L")
	assert_eq(p.get_root_skeleton_bone(), "sk_pelvis", "derives skeleton bone from custom root")
