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

@export_group("Special Bones")
## Skeleton bone name used as recursion guard in partial ragdoll chain traversal.
@export var root_bone: String = "mixamorig_Hips"


## Creates a fully populated profile for Mixamo-compatible humanoid skeletons.
static func create_mixamo_default() -> RagdollProfile:
	var profile := RagdollProfile.new()
	profile.root_bone = "mixamorig_Hips"

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
