## Skeleton-dependent ragdoll configuration. Defines which bones form the
## physics rig, how they connect via joints, and which intermediate bones
## need interpolated overrides. Change this when switching skeleton rigs
## (Mixamo, Rigify, custom, etc.).
class_name RagdollProfile
extends Resource

@export_group("Bone Definitions")
## Each entry maps a rig body name to a skeleton bone, with mass and shape.
@export var bones: Array[BoneDefinition] = []

@export_group("Joint Definitions")
## Each entry connects two rig bodies with angular limits.
@export var joints: Array[JointDefinition] = []

@export_group("Intermediate Bones")
## Skeleton bones not in the physics rig that need interpolated pose overrides.
@export var intermediate_bones: Array[IntermediateBoneEntry] = []

@export_group("Semantic Roles")
## Rig name of the pelvis/root body — centre-of-mass base, root motion, sway anchor.
@export var root_rig: String = "Hips"
## Rig name of the upper-torso/chest body — head-whip + arm attach point.
@export var chest_rig: String = "Chest"
## Rig name of the head body — head-whip, state gizmos.
@export var head_rig: String = "Head"
## Rig names of the torso/core bodies, root→top. Recovery pose blend + sway falloff.
@export var torso_rigs: PackedStringArray = ["Hips", "Spine", "Chest"]
## Rig names of the foot bodies — balance support polygon, foot IK, CoM gizmos.
@export var foot_rigs: PackedStringArray = ["Foot_L", "Foot_R"]
## Ordered left leg chain, hip→knee→foot, used by foot IK.
@export var left_leg_chain: PackedStringArray = ["UpperLeg_L", "LowerLeg_L", "Foot_L"]
## Ordered right leg chain, hip→knee→foot, used by foot IK.
@export var right_leg_chain: PackedStringArray = ["UpperLeg_R", "LowerLeg_R", "Foot_R"]

@export_group("Special Bones")
## Skeleton bone name of the root body — recursion guard for bone-chain traversal.
## Leave empty to derive it from [member root_rig] — see [method get_root_skeleton_bone].
@export var root_bone: String = ""


# ── Semantic role accessors ─────────────────────────────────────────────────
# Consumers (controller, foot IK, debug HUD) query these instead of hardcoding
# rig-name literals, so non-Mixamo rigs work by overriding the role fields above.
# List accessors filter out names that don't map to a defined bone, so a missing
# body degrades gracefully instead of resolving to a null lookup.

## Returns the root rig name if it maps to a defined bone, else "".
func get_root_rig() -> String:
	return root_rig if _has_rig(root_rig) else ""

## Returns the chest rig name if it maps to a defined bone, else "".
func get_chest_rig() -> String:
	return chest_rig if _has_rig(chest_rig) else ""

## Returns the head rig name if it maps to a defined bone, else "".
func get_head_rig() -> String:
	return head_rig if _has_rig(head_rig) else ""

## Returns the torso/core rig names that map to defined bones (root→top order).
func get_torso_rigs() -> PackedStringArray:
	return _filter_present(torso_rigs)

## Returns the foot rig names that map to defined bones.
func get_foot_rigs() -> PackedStringArray:
	return _filter_present(foot_rigs)

## Returns the ordered leg chain (hip→knee→foot) for [param side] ("L" or "R"),
## or an empty array if the chain is incomplete (foot IK needs all three links).
func get_leg_chain(side: String) -> PackedStringArray:
	var chain := left_leg_chain if side == "L" else right_leg_chain
	var present := _filter_present(chain)
	return present if present.size() == chain.size() else PackedStringArray()

## Returns every leg rig name across both sides that maps to a defined bone.
func get_all_leg_rigs() -> PackedStringArray:
	var out := _filter_present(left_leg_chain)
	out.append_array(_filter_present(right_leg_chain))
	return out

## True if [param rig_name] belongs to either leg chain.
func is_leg_rig(rig_name: String) -> bool:
	return rig_name in left_leg_chain or rig_name in right_leg_chain

## Returns "L"/"R" if [param rig_name] is in a leg chain, else "".
func get_leg_side(rig_name: String) -> String:
	if rig_name in left_leg_chain:
		return "L"
	if rig_name in right_leg_chain:
		return "R"
	return ""

## Returns the skeleton bone name of the root body, used as a bone-chain-traversal
## recursion guard. Uses the explicit [member root_bone] if set, otherwise derives
## it from [member root_rig]'s BoneDefinition.
func get_root_skeleton_bone() -> String:
	if root_bone != "":
		return root_bone
	for bone_def: BoneDefinition in bones:
		if bone_def.rig_name == root_rig:
			return bone_def.skeleton_bone
	return ""


func _has_rig(rig_name: String) -> bool:
	if rig_name == "":
		return false
	for bone_def: BoneDefinition in bones:
		if bone_def.rig_name == rig_name:
			return true
	return false


func _filter_present(names: PackedStringArray) -> PackedStringArray:
	var defined := {}
	for bone_def: BoneDefinition in bones:
		defined[bone_def.rig_name] = true
	var out := PackedStringArray()
	for n: String in names:
		if defined.has(n):
			out.append(n)
	return out


## Creates a fully populated profile for Mixamo-compatible humanoid skeletons.
static func create_mixamo_default() -> RagdollProfile:
	var profile := RagdollProfile.new()
	# root_bone derives from root_rig ("Hips" → "mixamorig_Hips") via get_root_skeleton_bone().

	# --- Bone definitions ---
	var bone_data: Array[Array] = [
		# [rig_name, skeleton_bone, child_bone, mass, shape_type, size/radius/height, shape_offset]
		["Hips",       "mixamorig_Hips",           "mixamorig_Spine",          15.0, "box",     Vector3(0.35, 0.20, 0.25),  0.5],
		["Spine",      "mixamorig_Spine",          "mixamorig_Spine2",         10.0, "box",     Vector3(0.30, 0.18, 0.18),  0.5],
		["Chest",      "mixamorig_Spine2",         "mixamorig_Neck",           12.0, "box",     Vector3(0.35, 0.22, 0.22),  0.5],
		["Head",       "mixamorig_Head",           "mixamorig_HeadTop_End",     5.0, "sphere",  Vector3(0.12, 0.0, 0.0),    0.5],
		["UpperArm_L", "mixamorig_LeftArm",        "mixamorig_LeftForeArm",     3.0, "capsule", Vector3(0.055, 0.28, 0.0),  0.5],
		["LowerArm_L", "mixamorig_LeftForeArm",    "mixamorig_LeftHand",        2.0, "capsule", Vector3(0.05, 0.25, 0.0),   0.5],
		["Hand_L",     "mixamorig_LeftHand",       "",                          1.0, "box",     Vector3(0.10, 0.04, 0.12),  0.5],
		["UpperArm_R", "mixamorig_RightArm",       "mixamorig_RightForeArm",    3.0, "capsule", Vector3(0.055, 0.28, 0.0),  0.5],
		["LowerArm_R", "mixamorig_RightForeArm",   "mixamorig_RightHand",       2.0, "capsule", Vector3(0.05, 0.25, 0.0),   0.5],
		["Hand_R",     "mixamorig_RightHand",      "",                          1.0, "box",     Vector3(0.10, 0.04, 0.12),  0.5],
		["UpperLeg_L", "mixamorig_LeftUpLeg",      "mixamorig_LeftLeg",         8.0, "capsule", Vector3(0.08, 0.40, 0.0),   0.5],
		["LowerLeg_L", "mixamorig_LeftLeg",        "mixamorig_LeftFoot",        4.0, "capsule", Vector3(0.065, 0.38, 0.0),  0.5],
		["Foot_L",     "mixamorig_LeftFoot",       "mixamorig_LeftToeBase",     2.0, "box",     Vector3(0.12, 0.07, 0.25),  0.65],
		["UpperLeg_R", "mixamorig_RightUpLeg",     "mixamorig_RightLeg",        8.0, "capsule", Vector3(0.08, 0.40, 0.0),   0.5],
		["LowerLeg_R", "mixamorig_RightLeg",       "mixamorig_RightFoot",       4.0, "capsule", Vector3(0.065, 0.38, 0.0),  0.5],
		["Foot_R",     "mixamorig_RightFoot",      "mixamorig_RightToeBase",    2.0, "box",     Vector3(0.12, 0.07, 0.25),  0.65],
	]

	for entry: Array in bone_data:
		var bone_def := BoneDefinition.new()
		bone_def.rig_name = entry[0]
		bone_def.skeleton_bone = entry[1]
		bone_def.child_bone = entry[2]
		bone_def.mass = entry[3]
		bone_def.shape_type = entry[4]
		var dims: Vector3 = entry[5]
		match entry[4]:
			"box":
				bone_def.box_size = dims
			"capsule":
				bone_def.capsule_radius = dims.x
				bone_def.capsule_height = dims.y
			"sphere":
				bone_def.sphere_radius = dims.x
		bone_def.shape_offset = entry[6]
		profile.bones.append(bone_def)

	# --- Joint definitions ---
	var joint_data: Array[Array] = [
		# [parent, child, x_limits, y_limits, z_limits]
		["Hips",       "Spine",      Vector2(-15, 15),  Vector2(-15, 15),  Vector2(-10, 10)],
		["Spine",      "Chest",      Vector2(-15, 15),  Vector2(-15, 15),  Vector2(-10, 10)],
		["Chest",      "Head",       Vector2(-40, 40),  Vector2(-50, 50),  Vector2(-30, 30)],
		["Chest",      "UpperArm_L", Vector2(-70, 70),  Vector2(-70, 70),  Vector2(-70, 70)],
		["UpperArm_L", "LowerArm_L", Vector2(-65, 65),  Vector2(-5, 5),    Vector2(-5, 5)],
		["LowerArm_L", "Hand_L",     Vector2(-40, 40),  Vector2(-20, 20),  Vector2(-50, 50)],
		["Chest",      "UpperArm_R", Vector2(-70, 70),  Vector2(-70, 70),  Vector2(-70, 70)],
		["UpperArm_R", "LowerArm_R", Vector2(-65, 65),  Vector2(-5, 5),    Vector2(-5, 5)],
		["LowerArm_R", "Hand_R",     Vector2(-40, 40),  Vector2(-20, 20),  Vector2(-50, 50)],
		["Hips",       "UpperLeg_L", Vector2(-60, 60),  Vector2(-20, 20),  Vector2(-30, 30)],
		["UpperLeg_L", "LowerLeg_L", Vector2(-60, 60),  Vector2(-5, 5),    Vector2(-5, 5)],
		["LowerLeg_L", "Foot_L",     Vector2(-30, 30),  Vector2(-10, 10),  Vector2(-20, 20)],
		["Hips",       "UpperLeg_R", Vector2(-60, 60),  Vector2(-20, 20),  Vector2(-30, 30)],
		["UpperLeg_R", "LowerLeg_R", Vector2(-60, 60),  Vector2(-5, 5),    Vector2(-5, 5)],
		["LowerLeg_R", "Foot_R",     Vector2(-30, 30),  Vector2(-10, 10),  Vector2(-20, 20)],
	]

	for entry: Array in joint_data:
		var joint_def := JointDefinition.new()
		joint_def.parent_rig = entry[0]
		joint_def.child_rig = entry[1]
		joint_def.limit_x = entry[2]
		joint_def.limit_y = entry[3]
		joint_def.limit_z = entry[4]
		profile.joints.append(joint_def)

	# --- Intermediate bones ---
	var spine1 := IntermediateBoneEntry.new()
	spine1.skeleton_bone = "mixamorig_Spine1"
	spine1.rig_body_a = "Spine"
	spine1.rig_body_b = "Chest"
	spine1.blend_weight = 0.5
	spine1.use_a_basis = true
	profile.intermediate_bones.append(spine1)

	var neck := IntermediateBoneEntry.new()
	neck.skeleton_bone = "mixamorig_Neck"
	neck.rig_body_a = "Chest"
	neck.rig_body_b = "Head"
	neck.blend_weight = 0.5
	neck.use_a_basis = true
	profile.intermediate_bones.append(neck)

	return profile


## Validates this profile against a Skeleton3D, returning warnings for mismatches.
func validate_against_skeleton(skeleton: Skeleton3D) -> PackedStringArray:
	var warnings := PackedStringArray()
	var rig_names := PackedStringArray()

	for bone_def: BoneDefinition in bones:
		rig_names.append(bone_def.rig_name)
		if skeleton.find_bone(bone_def.skeleton_bone) < 0:
			warnings.append("Bone '%s' maps to '%s' which is not in the skeleton" % [bone_def.rig_name, bone_def.skeleton_bone])
		if bone_def.child_bone != "" and skeleton.find_bone(bone_def.child_bone) < 0:
			warnings.append("Bone '%s' child '%s' is not in the skeleton" % [bone_def.rig_name, bone_def.child_bone])

	for joint_def: JointDefinition in joints:
		if joint_def.parent_rig not in rig_names:
			warnings.append("Joint parent '%s' is not a defined rig bone" % joint_def.parent_rig)
		if joint_def.child_rig not in rig_names:
			warnings.append("Joint child '%s' is not a defined rig bone" % joint_def.child_rig)

	# Semantic roles must reference defined rig bones
	var single_roles := {"root_rig": root_rig, "chest_rig": chest_rig, "head_rig": head_rig}
	for role_name: String in single_roles:
		var rig: String = single_roles[role_name]
		if rig != "" and rig not in rig_names:
			warnings.append("Role '%s' references '%s' which is not a defined rig bone" % [role_name, rig])
	var list_roles := {
		"torso_rigs": torso_rigs, "foot_rigs": foot_rigs,
		"left_leg_chain": left_leg_chain, "right_leg_chain": right_leg_chain,
	}
	for role_name: String in list_roles:
		for rig: String in list_roles[role_name]:
			if rig not in rig_names:
				warnings.append("Role '%s' lists '%s' which is not a defined rig bone" % [role_name, rig])

	# Foot IK requires two feet and a complete leg chain per side (role-based)
	if get_foot_rigs().size() < 2:
		warnings.append("Foot IK requires two foot bodies (foot_rigs role)")
	for side: String in ["L", "R"]:
		if get_leg_chain(side).is_empty():
			warnings.append("Foot IK requires a complete %s leg chain (%s_leg_chain role)" % [
				side, "left" if side == "L" else "right"])

	for entry: IntermediateBoneEntry in intermediate_bones:
		if skeleton.find_bone(entry.skeleton_bone) < 0:
			warnings.append("Intermediate bone '%s' is not in the skeleton" % entry.skeleton_bone)

	return warnings
