extends GutTest

const RigHarness = preload("res://test/helpers/rig_harness.gd")


var _mixamo_bones := PackedStringArray([
	"mixamorig_Hips", "mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2",
	"mixamorig_Neck", "mixamorig_Head",
	"mixamorig_LeftShoulder", "mixamorig_LeftArm", "mixamorig_LeftForeArm", "mixamorig_LeftHand",
	"mixamorig_RightShoulder", "mixamorig_RightArm", "mixamorig_RightForeArm", "mixamorig_RightHand",
	"mixamorig_LeftUpLeg", "mixamorig_LeftLeg", "mixamorig_LeftFoot", "mixamorig_LeftToeBase",
	"mixamorig_RightUpLeg", "mixamorig_RightLeg", "mixamorig_RightFoot", "mixamorig_RightToeBase",
])


# ── Real rig hierarchies ([bone, parent] pairs, parents first) ──────────────

## Mixamo as the FBX/glTF importer names it (colon namespace), fingers included.
const MIXAMO_COLON: Array = [
	["mixamorig:Hips", ""],
	["mixamorig:Spine", "mixamorig:Hips"], ["mixamorig:Spine1", "mixamorig:Spine"],
	["mixamorig:Spine2", "mixamorig:Spine1"], ["mixamorig:Neck", "mixamorig:Spine2"],
	["mixamorig:Head", "mixamorig:Neck"], ["mixamorig:HeadTop_End", "mixamorig:Head"],
	["mixamorig:LeftShoulder", "mixamorig:Spine2"], ["mixamorig:LeftArm", "mixamorig:LeftShoulder"],
	["mixamorig:LeftForeArm", "mixamorig:LeftArm"], ["mixamorig:LeftHand", "mixamorig:LeftForeArm"],
	["mixamorig:LeftHandThumb1", "mixamorig:LeftHand"], ["mixamorig:LeftHandIndex1", "mixamorig:LeftHand"],
	["mixamorig:RightShoulder", "mixamorig:Spine2"], ["mixamorig:RightArm", "mixamorig:RightShoulder"],
	["mixamorig:RightForeArm", "mixamorig:RightArm"], ["mixamorig:RightHand", "mixamorig:RightForeArm"],
	["mixamorig:RightHandThumb1", "mixamorig:RightHand"], ["mixamorig:RightHandIndex1", "mixamorig:RightHand"],
	["mixamorig:LeftUpLeg", "mixamorig:Hips"], ["mixamorig:LeftLeg", "mixamorig:LeftUpLeg"],
	["mixamorig:LeftFoot", "mixamorig:LeftLeg"], ["mixamorig:LeftToeBase", "mixamorig:LeftFoot"],
	["mixamorig:LeftToe_End", "mixamorig:LeftToeBase"],
	["mixamorig:RightUpLeg", "mixamorig:Hips"], ["mixamorig:RightLeg", "mixamorig:RightUpLeg"],
	["mixamorig:RightFoot", "mixamorig:RightLeg"], ["mixamorig:RightToeBase", "mixamorig:RightFoot"],
	["mixamorig:RightToe_End", "mixamorig:RightToeBase"],
]

## Blender Rigify, deform bones only (the Godot import). No bone is named hips,
## chest or head: DEF-spine is the pelvis, .003 the chest, .004/.005 the neck,
## .006 the head. Limbs are split in two segments (`.001`). DEF-pelvis.L/R are
## sided helper bones, not the hips.
const RIGIFY_DEF: Array = [
	["DEF-spine", ""],
	["DEF-pelvis.L", "DEF-spine"], ["DEF-pelvis.R", "DEF-spine"],
	["DEF-spine.001", "DEF-spine"], ["DEF-spine.002", "DEF-spine.001"],
	["DEF-spine.003", "DEF-spine.002"], ["DEF-spine.004", "DEF-spine.003"],
	["DEF-spine.005", "DEF-spine.004"], ["DEF-spine.006", "DEF-spine.005"],
	["DEF-jaw", "DEF-spine.006"], ["DEF-eye.L", "DEF-spine.006"], ["DEF-eye.R", "DEF-spine.006"],
	["DEF-forehead.L", "DEF-spine.006"], ["DEF-forehead.R", "DEF-spine.006"],
	["DEF-breast.L", "DEF-spine.003"], ["DEF-breast.R", "DEF-spine.003"],
	["DEF-shoulder.L", "DEF-spine.003"], ["DEF-upper_arm.L", "DEF-shoulder.L"],
	["DEF-upper_arm.L.001", "DEF-upper_arm.L"], ["DEF-forearm.L", "DEF-upper_arm.L.001"],
	["DEF-forearm.L.001", "DEF-forearm.L"], ["DEF-hand.L", "DEF-forearm.L.001"],
	["DEF-palm.01.L", "DEF-hand.L"], ["DEF-f_index.01.L", "DEF-palm.01.L"], ["DEF-thumb.01.L", "DEF-hand.L"],
	["DEF-shoulder.R", "DEF-spine.003"], ["DEF-upper_arm.R", "DEF-shoulder.R"],
	["DEF-upper_arm.R.001", "DEF-upper_arm.R"], ["DEF-forearm.R", "DEF-upper_arm.R.001"],
	["DEF-forearm.R.001", "DEF-forearm.R"], ["DEF-hand.R", "DEF-forearm.R.001"],
	["DEF-palm.01.R", "DEF-hand.R"], ["DEF-f_index.01.R", "DEF-palm.01.R"], ["DEF-thumb.01.R", "DEF-hand.R"],
	["DEF-thigh.L", "DEF-spine"], ["DEF-thigh.L.001", "DEF-thigh.L"],
	["DEF-shin.L", "DEF-thigh.L.001"], ["DEF-shin.L.001", "DEF-shin.L"],
	["DEF-foot.L", "DEF-shin.L.001"], ["DEF-toe.L", "DEF-foot.L"], ["DEF-heel.02.L", "DEF-foot.L"],
	["DEF-thigh.R", "DEF-spine"], ["DEF-thigh.R.001", "DEF-thigh.R"],
	["DEF-shin.R", "DEF-thigh.R.001"], ["DEF-shin.R.001", "DEF-shin.R"],
	["DEF-foot.R", "DEF-shin.R.001"], ["DEF-toe.R", "DEF-foot.R"], ["DEF-heel.02.R", "DEF-foot.R"],
]

## Unreal Engine 5 Mannequin (SK_Mannequin): five spine bones, two neck bones,
## clavicles on spine_05, twist / corrective helpers, IK and utility bones
## parented to root.
const UE5_MANNEQUIN: Array = [
	["root", ""],
	["pelvis", "root"],
	["spine_01", "pelvis"], ["spine_02", "spine_01"], ["spine_03", "spine_02"],
	["spine_04", "spine_03"], ["spine_05", "spine_04"],
	["spine_04_latissimus_l", "spine_04"], ["spine_04_latissimus_r", "spine_04"],
	["neck_01", "spine_05"], ["neck_02", "neck_01"], ["head", "neck_02"],
	["clavicle_l", "spine_05"], ["clavicle_pec_l", "clavicle_l"],
	["upperarm_l", "clavicle_l"], ["upperarm_twist_01_l", "upperarm_l"],
	["upperarm_correctiveRoot_l", "upperarm_l"], ["lowerarm_l", "upperarm_l"],
	["lowerarm_twist_01_l", "lowerarm_l"], ["lowerarm_correctiveRoot_l", "lowerarm_l"],
	["hand_l", "lowerarm_l"], ["index_metacarpal_l", "hand_l"], ["index_01_l", "index_metacarpal_l"],
	["thumb_01_l", "hand_l"],
	["clavicle_r", "spine_05"], ["clavicle_pec_r", "clavicle_r"],
	["upperarm_r", "clavicle_r"], ["upperarm_twist_01_r", "upperarm_r"],
	["upperarm_correctiveRoot_r", "upperarm_r"], ["lowerarm_r", "upperarm_r"],
	["lowerarm_twist_01_r", "lowerarm_r"], ["lowerarm_correctiveRoot_r", "lowerarm_r"],
	["hand_r", "lowerarm_r"], ["index_metacarpal_r", "hand_r"], ["index_01_r", "index_metacarpal_r"],
	["thumb_01_r", "hand_r"],
	["thigh_l", "pelvis"], ["thigh_twist_01_l", "thigh_l"], ["thigh_correctiveRoot_l", "thigh_l"],
	["calf_l", "thigh_l"], ["calf_twist_01_l", "calf_l"], ["calf_kneeBack_l", "calf_l"],
	["foot_l", "calf_l"], ["ball_l", "foot_l"],
	["thigh_r", "pelvis"], ["thigh_twist_01_r", "thigh_r"], ["thigh_correctiveRoot_r", "thigh_r"],
	["calf_r", "thigh_r"], ["calf_twist_01_r", "calf_r"], ["calf_kneeBack_r", "calf_r"],
	["foot_r", "calf_r"], ["ball_r", "foot_r"],
	["ik_foot_root", "root"], ["ik_foot_l", "ik_foot_root"], ["ik_foot_r", "ik_foot_root"],
	["ik_hand_root", "root"], ["ik_hand_gun", "ik_hand_root"],
	["ik_hand_l", "ik_hand_gun"], ["ik_hand_r", "ik_hand_gun"],
	["interaction", "root"], ["center_of_mass", "root"],
]

## Generic Hips/Spine/Chest/Neck/Head rig with Left/Right camelCase limbs.
const GENERIC: Array = [
	["Hips", ""], ["Spine", "Hips"], ["Chest", "Spine"], ["Neck", "Chest"], ["Head", "Neck"],
	["LeftShoulder", "Chest"], ["LeftUpperArm", "LeftShoulder"], ["LeftLowerArm", "LeftUpperArm"],
	["LeftHand", "LeftLowerArm"],
	["RightShoulder", "Chest"], ["RightUpperArm", "RightShoulder"], ["RightLowerArm", "RightUpperArm"],
	["RightHand", "RightLowerArm"],
	["LeftUpperLeg", "Hips"], ["LeftLowerLeg", "LeftUpperLeg"], ["LeftFoot", "LeftLowerLeg"],
	["LeftToes", "LeftFoot"],
	["RightUpperLeg", "Hips"], ["RightLowerLeg", "RightUpperLeg"], ["RightFoot", "RightLowerLeg"],
	["RightToes", "RightFoot"],
]

## A rig with ONE torso bone between hips and neck: the arms hang from Spine,
## there is no Chest.
const SINGLE_SPINE: Array = [
	["Hips", ""], ["Spine", "Hips"], ["Neck", "Spine"], ["Head", "Neck"],
	["UpperArm_L", "Spine"], ["LowerArm_L", "UpperArm_L"], ["Hand_L", "LowerArm_L"],
	["UpperArm_R", "Spine"], ["LowerArm_R", "UpperArm_R"], ["Hand_R", "LowerArm_R"],
	["UpperLeg_L", "Hips"], ["LowerLeg_L", "UpperLeg_L"], ["Foot_L", "LowerLeg_L"],
	["UpperLeg_R", "Hips"], ["LowerLeg_R", "UpperLeg_R"], ["Foot_R", "LowerLeg_R"],
]

const ALL_SLOTS: Array = [
	"Hips", "Spine", "Chest", "Head",
	"UpperArm_L", "LowerArm_L", "Hand_L", "UpperArm_R", "LowerArm_R", "Hand_R",
	"UpperLeg_L", "LowerLeg_L", "Foot_L", "UpperLeg_R", "LowerLeg_R", "Foot_R",
]


## Builds a Skeleton3D from [bone, parent] pairs. Rest = identity (detection is
## purely topological); autofreed by GUT.
func _build_skeleton(bones: Array) -> Skeleton3D:
	var skel: Skeleton3D = autofree(Skeleton3D.new())
	for entry: Array in bones:
		var idx := skel.add_bone(entry[0])
		if entry[1] != "":
			skel.set_bone_parent(idx, skel.find_bone(entry[1]))
	return skel


## [bone, parent] pairs → [names, parent indices], for detect_from_bone_names
## with a hierarchy. Needed where Skeleton3D cannot hold the raw names (it
## rejects ':' — the importer renames `mixamorig:` to `mixamorig_`).
func _names_and_parents(bones: Array) -> Array:
	var names := PackedStringArray()
	var parents := PackedInt32Array()
	for entry: Array in bones:
		parents.append(names.find(entry[1]) if entry[1] != "" else -1)
		names.append(entry[0])
	return [names, parents]


func _assert_mapping(result: Dictionary, expected: Dictionary, rig: String) -> void:
	for slot: String in expected:
		assert_eq(result.get(slot, "<missing>"), expected[slot], "%s: slot %s" % [rig, slot])
	assert_eq(result.size(), expected.size(), "%s: exactly the expected slots (got %s)" % [rig, str(result.keys())])


func _intermediate_pairs(profile: RagdollProfile) -> Dictionary:
	var out := {}
	for entry: IntermediateBoneEntry in profile.intermediate_bones:
		out[entry.skeleton_bone] = [entry.rig_body_a, entry.rig_body_b]
	return out


# ── Rig families (hierarchy-aware) ──────────────────────────────────────────

func test_mixamo_colon_namespace_hierarchy():
	var np := _names_and_parents(MIXAMO_COLON)
	var result := SkeletonDetector.detect_from_bone_names(np[0], np[1])
	_assert_mapping(result, {
		"Hips": "mixamorig:Hips", "Spine": "mixamorig:Spine", "Chest": "mixamorig:Spine2",
		"Head": "mixamorig:Head",
		"UpperArm_L": "mixamorig:LeftArm", "LowerArm_L": "mixamorig:LeftForeArm", "Hand_L": "mixamorig:LeftHand",
		"UpperArm_R": "mixamorig:RightArm", "LowerArm_R": "mixamorig:RightForeArm", "Hand_R": "mixamorig:RightHand",
		"UpperLeg_L": "mixamorig:LeftUpLeg", "LowerLeg_L": "mixamorig:LeftLeg", "Foot_L": "mixamorig:LeftFoot",
		"UpperLeg_R": "mixamorig:RightUpLeg", "LowerLeg_R": "mixamorig:RightLeg", "Foot_R": "mixamorig:RightFoot",
	}, "Mixamo (colon)")


func test_rigify_def_bones_resolve_hips_chest_head_by_hierarchy():
	# Audit #18 regression: Rigify never matched Head/Chest (DEF-spine.006 / .003)
	# and fell back to Mixamo names. Nothing here is named hips, chest or head.
	var result := SkeletonDetector.detect_humanoid_bones(_build_skeleton(RIGIFY_DEF))
	_assert_mapping(result, {
		"Hips": "DEF-spine", "Spine": "DEF-spine.001", "Chest": "DEF-spine.003", "Head": "DEF-spine.006",
		"UpperArm_L": "DEF-upper_arm.L", "LowerArm_L": "DEF-forearm.L", "Hand_L": "DEF-hand.L",
		"UpperArm_R": "DEF-upper_arm.R", "LowerArm_R": "DEF-forearm.R", "Hand_R": "DEF-hand.R",
		"UpperLeg_L": "DEF-thigh.L", "LowerLeg_L": "DEF-shin.L", "Foot_L": "DEF-foot.L",
		"UpperLeg_R": "DEF-thigh.R", "LowerLeg_R": "DEF-shin.R", "Foot_R": "DEF-foot.R",
	}, "Rigify DEF")


func test_rigify_split_limb_segments_become_intermediates():
	var skel := _build_skeleton(RIGIFY_DEF)
	var mapping := SkeletonDetector.detect_humanoid_bones(skel)
	var profile := SkeletonDetector.create_profile_from_skeleton(skel, mapping)
	var pairs := _intermediate_pairs(profile)
	assert_eq(pairs.get("DEF-spine.002"), ["Spine", "Chest"], "spine.002 interpolates Spine/Chest")
	assert_eq(pairs.get("DEF-spine.004"), ["Chest", "Head"], "spine.004 (neck) interpolates Chest/Head")
	assert_eq(pairs.get("DEF-spine.005"), ["Chest", "Head"], "spine.005 (neck) interpolates Chest/Head")
	assert_eq(pairs.get("DEF-upper_arm.L.001"), ["UpperArm_L", "LowerArm_L"], "second upper-arm segment")
	assert_eq(pairs.get("DEF-forearm.R.001"), ["LowerArm_R", "Hand_R"], "second forearm segment")
	assert_eq(pairs.get("DEF-thigh.L.001"), ["UpperLeg_L", "LowerLeg_L"], "second thigh segment")
	assert_eq(pairs.get("DEF-shin.R.001"), ["LowerLeg_R", "Foot_R"], "second shin segment")
	assert_false(pairs.has("DEF-shoulder.L"), "clavicles are not between two chain bodies")
	assert_eq(profile.joints.size(), 15, "full 16-body rig → 15 joints")
	assert_eq(profile.validate_against_skeleton(skel).size(), 0,
		"generated Rigify profile validates clean; got %s" % str(profile.validate_against_skeleton(skel)))


func test_ue5_mannequin_spine_order_and_intermediates():
	# Audit #18 regression: Chest=spine_02 sat BELOW Spine=spine_03 (inverted
	# torso) and the child→parent walk collected every ancestor up to root.
	var skel := _build_skeleton(UE5_MANNEQUIN)
	var result := SkeletonDetector.detect_humanoid_bones(skel)
	_assert_mapping(result, {
		"Hips": "pelvis", "Spine": "spine_01", "Chest": "spine_05", "Head": "head",
		"UpperArm_L": "upperarm_l", "LowerArm_L": "lowerarm_l", "Hand_L": "hand_l",
		"UpperArm_R": "upperarm_r", "LowerArm_R": "lowerarm_r", "Hand_R": "hand_r",
		"UpperLeg_L": "thigh_l", "LowerLeg_L": "calf_l", "Foot_L": "foot_l",
		"UpperLeg_R": "thigh_r", "LowerLeg_R": "calf_r", "Foot_R": "foot_r",
	}, "UE5 Mannequin")

	var profile := SkeletonDetector.create_profile_from_skeleton(skel, result)
	var pairs := _intermediate_pairs(profile)
	assert_eq(pairs.size(), 5, "exactly spine_02..04 + neck_01/02 are intermediate; got %s" % str(pairs.keys()))
	for b: String in ["spine_02", "spine_03", "spine_04"]:
		assert_eq(pairs.get(b), ["Spine", "Chest"], "%s interpolates Spine/Chest" % b)
	for b: String in ["neck_01", "neck_02"]:
		assert_eq(pairs.get(b), ["Chest", "Head"], "%s interpolates Chest/Head" % b)
	assert_false(pairs.has("root"), "the skeleton root is never an intermediate")
	assert_false(pairs.has("pelvis"), "a mapped body is never an intermediate")


func test_ue5_ik_twist_and_corrective_bones_are_ignored():
	var result := SkeletonDetector.detect_humanoid_bones(_build_skeleton(UE5_MANNEQUIN))
	var used: Array = result.values()
	for helper: String in ["ik_foot_l", "ik_hand_l", "ik_hand_gun", "upperarm_twist_01_l",
			"calf_kneeBack_l", "spine_04_latissimus_l", "clavicle_pec_l", "ball_l"]:
		assert_false(helper in used, "%s must not be mapped to a rig slot" % helper)


func test_generic_camelcase_rig_hierarchy():
	var result := SkeletonDetector.detect_humanoid_bones(_build_skeleton(GENERIC))
	_assert_mapping(result, {
		"Hips": "Hips", "Spine": "Spine", "Chest": "Chest", "Head": "Head",
		"UpperArm_L": "LeftUpperArm", "LowerArm_L": "LeftLowerArm", "Hand_L": "LeftHand",
		"UpperArm_R": "RightUpperArm", "LowerArm_R": "RightLowerArm", "Hand_R": "RightHand",
		"UpperLeg_L": "LeftUpperLeg", "LowerLeg_L": "LeftLowerLeg", "Foot_L": "LeftFoot",
		"UpperLeg_R": "RightUpperLeg", "LowerLeg_R": "RightLowerLeg", "Foot_R": "RightFoot",
	}, "generic")


func test_chest_is_the_chain_bone_the_arms_hang_from_not_the_topmost():
	# Arms on Spine2 while Spine3 sits above it and below the neck: Chest is
	# where the arms attach; Spine3 becomes a Chest/Head intermediate.
	var bones: Array = [
		["Hips", ""], ["Spine1", "Hips"], ["Spine2", "Spine1"], ["Spine3", "Spine2"],
		["Neck", "Spine3"], ["Head", "Neck"],
		["Arm_L", "Spine2"], ["ForeArm_L", "Arm_L"], ["Hand_L", "ForeArm_L"],
		["Arm_R", "Spine2"], ["ForeArm_R", "Arm_R"], ["Hand_R", "ForeArm_R"],
		["UpLeg_L", "Hips"], ["Leg_L", "UpLeg_L"], ["Foot_L", "Leg_L"],
		["UpLeg_R", "Hips"], ["Leg_R", "UpLeg_R"], ["Foot_R", "Leg_R"],
	]
	var skel := _build_skeleton(bones)
	var result := SkeletonDetector.detect_humanoid_bones(skel)
	assert_eq(result.get("Spine"), "Spine1")
	assert_eq(result.get("Chest"), "Spine2")
	var pairs := _intermediate_pairs(SkeletonDetector.create_profile_from_skeleton(skel, result))
	assert_eq(pairs.get("Spine3"), ["Chest", "Head"])
	assert_eq(pairs.get("Neck"), ["Chest", "Head"])


# ── Missing Chest: graceful degradation ─────────────────────────────────────

func test_single_spine_bone_rig_has_no_chest_and_no_unjointed_bodies():
	var skel := _build_skeleton(SINGLE_SPINE)
	var result := SkeletonDetector.detect_humanoid_bones(skel)
	assert_eq(result.size(), 15, "15 slots: everything but Chest")
	assert_eq(result.get("Spine"), "Spine")
	assert_false(result.has("Chest"), "a single torso bone is Spine, never doubled as Chest")

	var profile := SkeletonDetector.create_profile_from_skeleton(skel, result)
	assert_eq(profile.bones.size(), 15)
	assert_eq(profile.joints.size(), 14, "15 bodies → 14 joints (a tree)")
	var parent_of := {}
	for jd: JointDefinition in profile.joints:
		parent_of[jd.child_rig] = jd.parent_rig
	assert_eq(parent_of.get("Head"), "Spine", "Head joints to the nearest present torso body")
	assert_eq(parent_of.get("UpperArm_L"), "Spine", "left arm joints to Spine when there is no Chest")
	assert_eq(parent_of.get("UpperArm_R"), "Spine", "right arm joints to Spine when there is no Chest")
	for bd: BoneDefinition in profile.bones:
		if bd.rig_name != "Hips":
			assert_true(parent_of.has(bd.rig_name), "%s is jointed" % bd.rig_name)

	assert_eq(profile.chest_rig, "Spine", "chest role falls back to the top present torso body")
	assert_eq(profile.torso_rigs, PackedStringArray(["Hips", "Spine"]))
	var pairs := _intermediate_pairs(profile)
	assert_eq(pairs.get("Neck"), ["Spine", "Head"], "neck interpolates Spine/Head without a Chest")
	var w := profile.validate_against_skeleton(skel)
	assert_eq(w.size(), 0, "no-Chest profile validates clean; got %s" % str(w))


func test_default_joints_reparent_past_absent_torso_bodies():
	var names := PackedStringArray(["Hips", "Head", "UpperArm_L", "LowerArm_L"])
	var joints := SkeletonDetector.default_joints_for(names)
	var parent_of := {}
	for jd: JointDefinition in joints:
		parent_of[jd.child_rig] = jd.parent_rig
	assert_eq(joints.size(), 3, "Head, UpperArm_L, LowerArm_L each get exactly one joint")
	assert_eq(parent_of.get("Head"), "Hips", "Chest and Spine absent → Head joints to Hips")
	assert_eq(parent_of.get("UpperArm_L"), "Hips")
	assert_eq(parent_of.get("LowerArm_L"), "UpperArm_L", "present parent is used as-is")
	assert_eq(SkeletonDetector.nearest_present_parent_rig("Chest", names), "Hips")
	assert_eq(SkeletonDetector.nearest_present_parent_rig("Hips", PackedStringArray()), "",
		"nothing present → empty")


func test_full_rig_joints_are_unchanged_by_reparenting():
	var joints := SkeletonDetector.default_joints_for(PackedStringArray(ALL_SLOTS))
	assert_eq(joints.size(), 15)
	for i in joints.size():
		assert_eq(joints[i].parent_rig, SkeletonDetector.JOINT_TABLE[i].p, "joint %d keeps its table parent" % i)
		assert_eq(joints[i].child_rig, SkeletonDetector.JOINT_TABLE[i].c)


# ── Side detection: whole tokens, not substrings ────────────────────────────

func test_side_detection_is_token_anchored():
	# `_l` inside spine_lower / clavicle / lowerarm is not a side.
	for unsided: String in ["spine_lower", "spine_02", "clavicle", "pelvis", "lowerarm", "ring_01",
			"mixamorig:Hips", "DEF-spine.003", "head", "neck_01", "little_finger"]:
		assert_eq(SkeletonDetector.detect_side(unsided), "", "%s has no side" % unsided)
	for left: String in ["hand_l", "DEF-hand.L", "LeftHand", "L_Hand", "Hand-L", "mixamorig:LeftArm",
			"clavicle_l", "lowerarm_l", "lefthand", "DEF-upper_arm.L.001", "l_foot"]:
		assert_eq(SkeletonDetector.detect_side(left), "L", "%s is left" % left)
	for right: String in ["hand_r", "DEF-hand.R", "RightHand", "R_Hand", "Hand.R", "mixamorig:RightForeArm",
			"ring_01_r", "righthand", "thigh_twist_01_r"]:
		assert_eq(SkeletonDetector.detect_side(right), "R", "%s is right" % right)


func test_keys_are_exact_not_substrings():
	assert_eq(SkeletonDetector.classify_bone_name("mixamorig:LeftForeArm").key, "forearm")
	assert_eq(SkeletonDetector.classify_bone_name("DEF-upper_arm.L.001").key, "upperarm")
	assert_eq(SkeletonDetector.classify_bone_name("HeadTop_End").key, "headtopend")
	assert_eq(SkeletonDetector.classify_bone_name("ik_foot_l").key, "ikfoot")
	assert_eq(SkeletonDetector.classify_bone_name("LeftHandThumb1").key, "handthumb")
	assert_eq(SkeletonDetector.classify_bone_name("spine_04_latissimus_l").key, "spinelatissimus")
	assert_eq(SkeletonDetector.classify_bone_name("ORG-hand.L").key, "", "mechanism bones never match")
	assert_eq(SkeletonDetector.classify_bone_name("MCH-thigh_ik.L").key, "")


# ── Names-only API (no hierarchy) ───────────────────────────────────────────

func test_mixamo_detection():
	var result := SkeletonDetector.detect_from_bone_names(_mixamo_bones)
	assert_true(result.size() >= 8, "Should detect at least 8 slots")
	assert_eq(result.size(), 16, "Should detect all 16 slots")
	assert_has(result, "Hips")
	assert_has(result, "Head")
	assert_has(result, "UpperArm_L")
	assert_has(result, "Foot_R")
	assert_eq(result["Spine"], "mixamorig_Spine")
	assert_eq(result["Chest"], "mixamorig_Spine2", "names-only: Chest is the last non-neck torso bone")
	assert_eq(result["LowerLeg_L"], "mixamorig_LeftLeg")


func test_ue_names_only_keeps_spine_below_chest():
	var names := PackedStringArray()
	for entry: Array in UE5_MANNEQUIN:
		names.append(entry[0])
	var result := SkeletonDetector.detect_from_bone_names(names)
	assert_eq(result.get("Hips"), "pelvis")
	assert_eq(result.get("Spine"), "spine_01")
	assert_eq(result.get("Chest"), "spine_05")
	assert_eq(result.get("Head"), "head")
	assert_eq(result.size(), 16)


func test_generic_underscore_rig_names_only():
	var bones := PackedStringArray([
		"Hips", "Spine", "Spine1", "Chest", "Neck", "Head",
		"UpperArm_L", "LowerArm_L", "Hand_L",
		"UpperArm_R", "LowerArm_R", "Hand_R",
		"UpperLeg_L", "LowerLeg_L", "Foot_L",
		"UpperLeg_R", "LowerLeg_R", "Foot_R",
	])
	var result := SkeletonDetector.detect_from_bone_names(bones)
	assert_eq(result.size(), 16)
	assert_eq(result["Chest"], "Chest", "a chest-keyed bone wins over the last spine bone")
	assert_eq(result["Spine"], "Spine")


func test_rigify_names_only_needs_hierarchy():
	# Documented limit: without parents nothing tells DEF-spine from DEF-spine.006.
	var names := PackedStringArray()
	for entry: Array in RIGIFY_DEF:
		names.append(entry[0])
	assert_eq(SkeletonDetector.detect_from_bone_names(names).size(), 0,
		"names-only Rigify is rejected rather than mis-mapped")


func test_sparse_skeleton_rejected():
	var sparse := PackedStringArray(["Hips", "Head", "Hand_L"])
	var result := SkeletonDetector.detect_from_bone_names(sparse)
	assert_eq(result.size(), 0, "Too few bones should be rejected")


func test_missing_required_bone_rejected():
	var no_spine := PackedStringArray([
		"Hips", "Head",
		"UpperArm_L", "LowerArm_L", "Hand_L",
		"UpperArm_R", "LowerArm_R", "Hand_R",
		"UpperLeg_L", "LowerLeg_L", "Foot_L",
		"UpperLeg_R", "LowerLeg_R", "Foot_R",
	])
	var result := SkeletonDetector.detect_from_bone_names(no_spine)
	assert_eq(result.size(), 0, "Missing Spine should be rejected")


func test_head_directly_on_hips_rejected():
	var bones: Array = [
		["Hips", ""], ["Head", "Hips"],
		["UpperArm_L", "Hips"], ["LowerArm_L", "UpperArm_L"], ["Hand_L", "LowerArm_L"],
		["UpperArm_R", "Hips"], ["LowerArm_R", "UpperArm_R"], ["Hand_R", "LowerArm_R"],
		["UpperLeg_L", "Hips"], ["LowerLeg_L", "UpperLeg_L"], ["Foot_L", "LowerLeg_L"],
		["UpperLeg_R", "Hips"], ["LowerLeg_R", "UpperLeg_R"], ["Foot_R", "LowerLeg_R"],
	]
	assert_eq(SkeletonDetector.detect_humanoid_bones(_build_skeleton(bones)).size(), 0,
		"no bone between hips and head → no Spine → rejected")


func test_empty_skeleton():
	var result := SkeletonDetector.detect_from_bone_names(PackedStringArray())
	assert_eq(result.size(), 0)
	assert_eq(SkeletonDetector.detect_humanoid_bones(autofree(Skeleton3D.new())).size(), 0)


func test_consistent_results():
	var r1 := SkeletonDetector.detect_from_bone_names(_mixamo_bones)
	var r2 := SkeletonDetector.detect_from_bone_names(_mixamo_bones)
	assert_eq(r1, r2, "Re-call should produce same result")


func test_bone_definition_shape_offset_default():
	var bone_def := BoneDefinition.new()
	assert_eq(bone_def.shape_offset, 0.5, "Default shape_offset should be 0.5")


func test_mixamo_default_has_foot_offset():
	var profile := RagdollProfile.create_mixamo_default()
	assert_eq(profile.bones.size(), 16, "Mixamo default should have 16 bones")
	for bone_def: BoneDefinition in profile.bones:
		if bone_def.rig_name == "Foot_L" or bone_def.rig_name == "Foot_R":
			assert_eq(bone_def.shape_offset, 0.65, "%s should have 0.65 offset" % bone_def.rig_name)
		else:
			assert_eq(bone_def.shape_offset, 0.5, "%s should have 0.5 offset" % bone_def.rig_name)


func test_mixamo_default_head_has_child_bone():
	var profile := RagdollProfile.create_mixamo_default()
	for bone_def: BoneDefinition in profile.bones:
		if bone_def.rig_name == "Head":
			assert_eq(bone_def.child_bone, "mixamorig_HeadTop_End", "Head should have HeadTop_End as child")


func test_proportions_table_has_all_slots():
	for slot: String in ALL_SLOTS:
		assert_has(SkeletonDetector.BONE_PROPORTIONS, slot, "BONE_PROPORTIONS should have %s" % slot)


func test_proportions_table_feet_have_depth_is_length():
	var foot_l: Dictionary = SkeletonDetector.BONE_PROPORTIONS["Foot_L"]
	var foot_r: Dictionary = SkeletonDetector.BONE_PROPORTIONS["Foot_R"]
	assert_true(foot_l.get("depth_is_length", false), "Foot_L should have depth_is_length")
	assert_true(foot_r.get("depth_is_length", false), "Foot_R should have depth_is_length")


func test_proportions_table_hands_have_depth_is_length():
	var hand_l: Dictionary = SkeletonDetector.BONE_PROPORTIONS["Hand_L"]
	var hand_r: Dictionary = SkeletonDetector.BONE_PROPORTIONS["Hand_R"]
	assert_true(hand_l.get("depth_is_length", false), "Hand_L should have depth_is_length")
	assert_true(hand_r.get("depth_is_length", false), "Hand_R should have depth_is_length")


# --- create_collision_shape: single source of truth for box/capsule/sphere ---

func test_create_collision_shape_box():
	var bd := BoneDefinition.new()
	bd.shape_type = "box"
	bd.box_size = Vector3(0.3, 0.2, 0.25)
	var col: CollisionShape3D = autofree(SkeletonDetector.create_collision_shape(bd))
	assert_true(col.shape is BoxShape3D, "box shape_type yields a BoxShape3D")
	assert_eq((col.shape as BoxShape3D).size, Vector3(0.3, 0.2, 0.25))


func test_create_collision_shape_capsule():
	var bd := BoneDefinition.new()
	bd.shape_type = "capsule"
	bd.capsule_radius = 0.08
	bd.capsule_height = 0.4
	var col: CollisionShape3D = autofree(SkeletonDetector.create_collision_shape(bd))
	assert_true(col.shape is CapsuleShape3D, "capsule shape_type yields a CapsuleShape3D")
	var cap := col.shape as CapsuleShape3D
	assert_almost_eq(cap.radius, 0.08, 0.0001)
	assert_almost_eq(cap.height, 0.4, 0.0001)


func test_create_collision_shape_sphere():
	var bd := BoneDefinition.new()
	bd.shape_type = "sphere"
	bd.sphere_radius = 0.12
	var col: CollisionShape3D = autofree(SkeletonDetector.create_collision_shape(bd))
	assert_true(col.shape is SphereShape3D, "sphere shape_type yields a SphereShape3D")
	assert_almost_eq((col.shape as SphereShape3D).radius, 0.12, 0.0001)


# --- create_profile_from_skeleton: full generation pipeline (round-trip) ---

func test_create_profile_from_skeleton_round_trips():
	var skel: Skeleton3D = autofree(RigHarness.build_mixamo_skeleton())
	var mapping := SkeletonDetector.detect_humanoid_bones(skel)
	assert_eq(mapping.size(), 16, "synthetic Mixamo skeleton detects all 16 slots")
	var profile := SkeletonDetector.create_profile_from_skeleton(skel, mapping)
	assert_eq(profile.bones.size(), 16, "generated profile has 16 bodies")
	assert_eq(profile.joints.size(), 15, "generated profile has 15 joints")
	assert_eq(profile.root_bone, "mixamorig_Hips", "root_bone set from the Hips mapping")
	var pairs := _intermediate_pairs(profile)
	assert_eq(pairs.get("mixamorig_Spine1"), ["Spine", "Chest"], "Spine1 interpolates Spine/Chest")
	assert_eq(pairs.get("mixamorig_Neck"), ["Chest", "Head"], "Neck interpolates Chest/Head")
	assert_eq(pairs.size(), 2, "only Spine1 and Neck are intermediate; got %s" % str(pairs.keys()))
	assert_eq(profile.chest_rig, "Chest")
	assert_eq(profile.torso_rigs, PackedStringArray(["Hips", "Spine", "Chest"]))
	# Round-trip: a generated profile must validate clean against its own skeleton.
	var w := profile.validate_against_skeleton(skel)
	assert_eq(w.size(), 0, "generated profile validates clean against its skeleton; got %s" % str(w))


func test_create_profile_foot_shape_is_box_with_depth():
	var skel: Skeleton3D = autofree(RigHarness.build_mixamo_skeleton())
	var mapping := SkeletonDetector.detect_humanoid_bones(skel)
	var profile := SkeletonDetector.create_profile_from_skeleton(skel, mapping)
	var checked := false
	for bd: BoneDefinition in profile.bones:
		if bd.rig_name == "Foot_L":
			checked = true
			assert_eq(bd.shape_type, "box", "foot uses a box shape")
			var col: CollisionShape3D = autofree(SkeletonDetector.create_collision_shape(bd))
			assert_true((col.shape as BoxShape3D).size.z > 0.0, "foot box has positive toe-depth")
	assert_true(checked, "Foot_L should be present in the generated profile")
