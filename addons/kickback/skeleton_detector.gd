## Auto-detects humanoid bones in a Skeleton3D by pattern-matching bone names.
## Supports Mixamo, Rigify, Unreal Mannequin, and generic naming conventions.
## Used by the editor plugin to auto-generate RagdollProfile and PhysicalBone3D nodes.
class_name SkeletonDetector


# --- Bone detection patterns ---
# Each rig slot maps to an array of pattern rules. A rule is a Dictionary with:
#   "contains": Array of substrings (ALL must match, case-insensitive)
#   "excludes": Array of substrings (NONE may match) — optional
#   "side": "left", "right", or "" (no side requirement)

const RIG_SLOTS := {
	"Hips": [
		{"contains": ["hip"], "side": ""},
		{"contains": ["pelvis"], "side": ""},
	],
	"Spine": [
		{"contains": ["spine"], "excludes": ["spine2", "spine_02", "spine.002", "spine1", "spine_01", "spine.001"], "side": ""},
	],
	"Chest": [
		{"contains": ["chest"], "side": ""},
		{"contains": ["spine2"], "side": ""},
		{"contains": ["spine_02"], "side": ""},
		{"contains": ["upper_chest"], "side": ""},
	],
	"Head": [
		{"contains": ["head"], "excludes": ["headtop", "head_end", "head_nub"], "side": ""},
	],
	"UpperArm_L": [
		{"contains": ["arm"], "excludes": ["forearm", "fore_arm", "lower"], "side": "left"},
		{"contains": ["upperarm"], "side": "left"},
		{"contains": ["upper_arm"], "side": "left"},
	],
	"LowerArm_L": [
		{"contains": ["forearm"], "side": "left"},
		{"contains": ["fore_arm"], "side": "left"},
		{"contains": ["lowerarm"], "side": "left"},
		{"contains": ["lower_arm"], "side": "left"},
	],
	"Hand_L": [
		{"contains": ["hand"], "excludes": ["finger", "thumb", "index", "middle", "ring", "pinky", "little"], "side": "left"},
	],
	"UpperArm_R": [
		{"contains": ["arm"], "excludes": ["forearm", "fore_arm", "lower"], "side": "right"},
		{"contains": ["upperarm"], "side": "right"},
		{"contains": ["upper_arm"], "side": "right"},
	],
	"LowerArm_R": [
		{"contains": ["forearm"], "side": "right"},
		{"contains": ["fore_arm"], "side": "right"},
		{"contains": ["lowerarm"], "side": "right"},
		{"contains": ["lower_arm"], "side": "right"},
	],
	"Hand_R": [
		{"contains": ["hand"], "excludes": ["finger", "thumb", "index", "middle", "ring", "pinky", "little"], "side": "right"},
	],
	"UpperLeg_L": [
		{"contains": ["upleg"], "side": "left"},
		{"contains": ["upperleg"], "side": "left"},
		{"contains": ["upper_leg"], "side": "left"},
		{"contains": ["thigh"], "side": "left"},
	],
	"LowerLeg_L": [
		{"contains": ["leg"], "excludes": ["upleg", "upperleg", "upper_leg", "thigh"], "side": "left"},
		{"contains": ["calf"], "side": "left"},
		{"contains": ["shin"], "side": "left"},
		{"contains": ["lowerleg"], "side": "left"},
		{"contains": ["lower_leg"], "side": "left"},
	],
	"Foot_L": [
		{"contains": ["foot"], "excludes": ["toe"], "side": "left"},
	],
	"UpperLeg_R": [
		{"contains": ["upleg"], "side": "right"},
		{"contains": ["upperleg"], "side": "right"},
		{"contains": ["upper_leg"], "side": "right"},
		{"contains": ["thigh"], "side": "right"},
	],
	"LowerLeg_R": [
		{"contains": ["leg"], "excludes": ["upleg", "upperleg", "upper_leg", "thigh"], "side": "right"},
		{"contains": ["calf"], "side": "right"},
		{"contains": ["shin"], "side": "right"},
		{"contains": ["lowerleg"], "side": "right"},
		{"contains": ["lower_leg"], "side": "right"},
	],
	"Foot_R": [
		{"contains": ["foot"], "excludes": ["toe"], "side": "right"},
	],
}

const LEFT_PATTERNS := ["left", "_l", ".l", "_l_", "left_", "_left"]
const RIGHT_PATTERNS := ["right", "_r", ".r", "_r_", "right_", "_right"]

const MASS_TABLE := {
	"Hips": 15.0, "Spine": 10.0, "Chest": 12.0, "Head": 5.0,
	"UpperArm_L": 3.0, "LowerArm_L": 2.0, "Hand_L": 1.0,
	"UpperArm_R": 3.0, "LowerArm_R": 2.0, "Hand_R": 1.0,
	"UpperLeg_L": 8.0, "LowerLeg_L": 4.0, "Foot_L": 2.0,
	"UpperLeg_R": 8.0, "LowerLeg_R": 4.0, "Foot_R": 2.0,
}

const SHAPE_TABLE := {
	"Hips": "box", "Spine": "box", "Chest": "box", "Head": "sphere",
	"UpperArm_L": "capsule", "LowerArm_L": "capsule", "Hand_L": "box",
	"UpperArm_R": "capsule", "LowerArm_R": "capsule", "Hand_R": "box",
	"UpperLeg_L": "capsule", "LowerLeg_L": "capsule", "Foot_L": "box",
	"UpperLeg_R": "capsule", "LowerLeg_R": "capsule", "Foot_R": "box",
}

# Standard joint topology: parent_rig → child_rig + angular limits
const JOINT_TABLE: Array[Dictionary] = [
	{p = "Hips", c = "Spine", lx = Vector2(-15, 15), ly = Vector2(-15, 15), lz = Vector2(-10, 10)},
	{p = "Spine", c = "Chest", lx = Vector2(-15, 15), ly = Vector2(-15, 15), lz = Vector2(-10, 10)},
	{p = "Chest", c = "Head", lx = Vector2(-40, 40), ly = Vector2(-50, 50), lz = Vector2(-30, 30)},
	{p = "Chest", c = "UpperArm_L", lx = Vector2(-70, 70), ly = Vector2(-70, 70), lz = Vector2(-70, 70)},
	{p = "UpperArm_L", c = "LowerArm_L", lx = Vector2(-65, 65), ly = Vector2(-5, 5), lz = Vector2(-5, 5)},
	{p = "LowerArm_L", c = "Hand_L", lx = Vector2(-40, 40), ly = Vector2(-20, 20), lz = Vector2(-50, 50)},
	{p = "Chest", c = "UpperArm_R", lx = Vector2(-70, 70), ly = Vector2(-70, 70), lz = Vector2(-70, 70)},
	{p = "UpperArm_R", c = "LowerArm_R", lx = Vector2(-65, 65), ly = Vector2(-5, 5), lz = Vector2(-5, 5)},
	{p = "LowerArm_R", c = "Hand_R", lx = Vector2(-40, 40), ly = Vector2(-20, 20), lz = Vector2(-50, 50)},
	{p = "Hips", c = "UpperLeg_L", lx = Vector2(-60, 60), ly = Vector2(-20, 20), lz = Vector2(-30, 30)},
	{p = "UpperLeg_L", c = "LowerLeg_L", lx = Vector2(-60, 60), ly = Vector2(-5, 5), lz = Vector2(-5, 5)},
	{p = "LowerLeg_L", c = "Foot_L", lx = Vector2(-30, 30), ly = Vector2(-10, 10), lz = Vector2(-20, 20)},
	{p = "Hips", c = "UpperLeg_R", lx = Vector2(-60, 60), ly = Vector2(-20, 20), lz = Vector2(-30, 30)},
	{p = "UpperLeg_R", c = "LowerLeg_R", lx = Vector2(-60, 60), ly = Vector2(-5, 5), lz = Vector2(-5, 5)},
	{p = "LowerLeg_R", c = "Foot_R", lx = Vector2(-30, 30), ly = Vector2(-10, 10), lz = Vector2(-20, 20)},
]

# Chain order for finding child bones in the mapping
const BONE_CHAINS := {
	"Hips": "Spine", "Spine": "Chest", "Chest": "",
	"UpperArm_L": "LowerArm_L", "LowerArm_L": "Hand_L", "Hand_L": "",
	"UpperArm_R": "LowerArm_R", "LowerArm_R": "Hand_R", "Hand_R": "",
	"UpperLeg_L": "LowerLeg_L", "LowerLeg_L": "Foot_L", "Foot_L": "",
	"UpperLeg_R": "LowerLeg_R", "LowerLeg_R": "Foot_R", "Foot_R": "",
	"Head": "",
}


## Attempts to auto-detect humanoid bones in a Skeleton3D.
## Returns a Dictionary mapping rig slot names to skeleton bone names.
## Returns empty dict if fewer than 8 bones matched.
static func detect_humanoid_bones(skeleton: Skeleton3D) -> Dictionary:
	var all_bones := PackedStringArray()
	for i in skeleton.get_bone_count():
		all_bones.append(skeleton.get_bone_name(i))

	var mapping := {}

	for slot: String in RIG_SLOTS:
		var patterns: Array = RIG_SLOTS[slot]
		for bone_name: String in all_bones:
			if bone_name in mapping.values():
				continue  # Already assigned to another slot
			if _matches_slot(bone_name, patterns):
				mapping[slot] = bone_name
				break

	# Validate: need at least hips, spine, head, one arm pair, one leg pair
	var required := ["Hips", "Spine", "Head"]
	for req: String in required:
		if req not in mapping:
			return {}

	if mapping.size() < 8:
		return {}

	return mapping


## Generates a RagdollProfile from a detected bone mapping and skeleton rest poses.
static func create_profile_from_skeleton(
	skeleton: Skeleton3D,
	bone_mapping: Dictionary
) -> RagdollProfile:
	var profile := RagdollProfile.new()
	profile.root_bone = bone_mapping.get("Hips", "")

	# Create bone definitions
	for slot: String in bone_mapping:
		var skel_bone: String = bone_mapping[slot]
		var child_slot: String = BONE_CHAINS.get(slot, "")
		var child_bone: String = bone_mapping.get(child_slot, "") if child_slot != "" else ""

		# Find child bone from skeleton hierarchy if not in mapping
		if child_bone == "" and child_slot == "":
			var bone_idx := skeleton.find_bone(skel_bone)
			var children := skeleton.get_bone_children(bone_idx)
			if not children.is_empty():
				child_bone = skeleton.get_bone_name(children[0])

		var bone_def := BoneDefinition.new()
		bone_def.rig_name = slot
		bone_def.skeleton_bone = skel_bone
		bone_def.child_bone = child_bone
		bone_def.mass = MASS_TABLE.get(slot, 5.0)
		bone_def.shape_type = SHAPE_TABLE.get(slot, "box")

		# Estimate shape dimensions from bone length
		_estimate_shape(skeleton, bone_def, child_bone)

		profile.bones.append(bone_def)

	# Create joint definitions (only for pairs where both bones exist)
	for jt: Dictionary in JOINT_TABLE:
		if jt.p in bone_mapping and jt.c in bone_mapping:
			var joint_def := JointDefinition.new()
			joint_def.parent_rig = jt.p
			joint_def.child_rig = jt.c
			joint_def.limit_x = jt.lx
			joint_def.limit_y = jt.ly
			joint_def.limit_z = jt.lz
			profile.joints.append(joint_def)

	# Detect intermediate bones (bones between two mapped bones in the hierarchy)
	_detect_intermediate_bones(skeleton, bone_mapping, profile)

	return profile


## Creates PhysicalBone3D nodes inside a PhysicalBoneSimulator3D for partial ragdoll.
static func populate_physical_bones(
	skeleton: Skeleton3D,
	simulator: PhysicalBoneSimulator3D,
	bone_mapping: Dictionary,
	owner: Node
) -> void:
	for slot: String in bone_mapping:
		var skel_bone: String = bone_mapping[slot]
		var bone_idx := skeleton.find_bone(skel_bone)
		if bone_idx < 0:
			continue

		var pb := PhysicalBone3D.new()
		pb.name = "PhysicalBone_%s" % slot
		pb.bone_name = skel_bone
		pb.mass = MASS_TABLE.get(slot, 5.0)
		pb.collision_layer = 16  # Layer 5 (bit 4) — partial ragdoll bones
		pb.collision_mask = 18   # Layers 2 + 5 (environment + other partial bones)

		# Add collision shape
		var col := CollisionShape3D.new()
		var shape_type: String = SHAPE_TABLE.get(slot, "box")
		match shape_type:
			"box":
				var box := BoxShape3D.new()
				box.size = Vector3(0.15, 0.15, 0.15)
				col.shape = box
			"capsule":
				var capsule := CapsuleShape3D.new()
				capsule.radius = 0.05
				capsule.height = 0.2
				col.shape = capsule
			"sphere":
				var sphere := SphereShape3D.new()
				sphere.radius = 0.1
				col.shape = sphere

		pb.add_child(col)
		col.owner = owner
		simulator.add_child(pb)
		pb.owner = owner


# --- Private helpers ---

static func _matches_slot(bone_name: String, patterns: Array) -> bool:
	var lower := bone_name.to_lower()
	for pattern: Dictionary in patterns:
		if _check_pattern(lower, pattern):
			return true
	return false


static func _check_pattern(lower_name: String, pattern: Dictionary) -> bool:
	# Check all required substrings
	var contains: Array = pattern.get("contains", [])
	for substr: String in contains:
		if substr not in lower_name:
			return false

	# Check exclusions
	var excludes: Array = pattern.get("excludes", [])
	for substr: String in excludes:
		if substr in lower_name:
			return false

	# Check side requirement
	var side: String = pattern.get("side", "")
	if side == "left":
		return _has_side(lower_name, LEFT_PATTERNS)
	elif side == "right":
		return _has_side(lower_name, RIGHT_PATTERNS)

	return true


static func _has_side(lower_name: String, side_patterns: Array) -> bool:
	for pat: String in side_patterns:
		if pat in lower_name:
			return true
	return false


static func _estimate_shape(skeleton: Skeleton3D, bone_def: BoneDefinition, child_bone: String) -> void:
	var bone_idx := skeleton.find_bone(bone_def.skeleton_bone)
	if bone_idx < 0:
		_set_default_shape(bone_def)
		return

	var bone_rest := skeleton.get_bone_global_rest(bone_idx)
	var length := 0.2  # Default

	if child_bone != "":
		var child_idx := skeleton.find_bone(child_bone)
		if child_idx >= 0:
			var child_rest := skeleton.get_bone_global_rest(child_idx)
			length = bone_rest.origin.distance_to(child_rest.origin)

	match bone_def.shape_type:
		"capsule":
			bone_def.capsule_radius = maxf(length * 0.15, 0.03)
			bone_def.capsule_height = maxf(length, 0.1)
		"box":
			var half := maxf(length * 0.5, 0.08)
			bone_def.box_size = Vector3(half * 1.4, half * 0.8, half)
		"sphere":
			bone_def.sphere_radius = maxf(length * 0.5, 0.08)


static func _set_default_shape(bone_def: BoneDefinition) -> void:
	match bone_def.shape_type:
		"capsule":
			bone_def.capsule_radius = 0.05
			bone_def.capsule_height = 0.25
		"box":
			bone_def.box_size = Vector3(0.2, 0.15, 0.15)
		"sphere":
			bone_def.sphere_radius = 0.1


static func _detect_intermediate_bones(
	skeleton: Skeleton3D,
	bone_mapping: Dictionary,
	profile: RagdollProfile
) -> void:
	# For each pair of connected mapped bones, check if there are
	# intermediate skeleton bones between them that need interpolation
	var mapped_bones := {}  # skeleton_bone_name → rig_slot
	for slot: String in bone_mapping:
		mapped_bones[bone_mapping[slot]] = slot

	for slot: String in bone_mapping:
		var child_slot: String = BONE_CHAINS.get(slot, "")
		if child_slot == "" or child_slot not in bone_mapping:
			continue

		var parent_skel: String = bone_mapping[slot]
		var child_skel: String = bone_mapping[child_slot]

		# Walk from child up to parent, collecting intermediate bones
		var current_idx := skeleton.find_bone(child_skel)
		var parent_idx := skeleton.find_bone(parent_skel)
		if current_idx < 0 or parent_idx < 0:
			continue

		var intermediates := PackedStringArray()
		var walk_idx := skeleton.get_bone_parent(current_idx)
		while walk_idx >= 0 and walk_idx != parent_idx:
			var walk_name := skeleton.get_bone_name(walk_idx)
			if walk_name not in mapped_bones:
				intermediates.append(walk_name)
			walk_idx = skeleton.get_bone_parent(walk_idx)

		for inter_bone: String in intermediates:
			var entry := IntermediateBoneEntry.new()
			entry.skeleton_bone = inter_bone
			entry.rig_body_a = slot
			entry.rig_body_b = child_slot
			entry.blend_weight = 0.5
			entry.use_a_basis = true
			profile.intermediate_bones.append(entry)
