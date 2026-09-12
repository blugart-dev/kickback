## Auto-detects humanoid bones in a Skeleton3D.
##
## Detection runs in two passes. Bone NAMES are tokenised (separators and
## camelCase boundaries, digits dropped, rig namespaces such as [code]mixamorig[/code]
## / [code]DEF-[/code] stripped) and matched as whole words, so [code]spine_lower[/code]
## never reads as a left-side bone and Unreal's [code]ik_foot_l[/code] never reads
## as a foot. The torso is then classified by POSITION in the bone HIERARCHY: on
## the chain from the head down to the hips, the bone directly above the hips is
## Spine, the chain bone the upper arms (via their clavicles) hang from is Chest,
## and everything in between — neck included — becomes an intermediate bone.
## Hips fall back to the common ancestor of the thighs and Head to the top of the
## torso chain, which is how Rigify's unnamed [code]DEF-spine[/code] /
## [code]DEF-spine.006[/code] resolve.
##
## Verified rig families: Mixamo ([code]mixamorig:[/code] and [code]mixamorig_[/code]),
## Blender Rigify DEF bones, the Unreal Engine 5 Mannequin and generic
## [code]Hips/Spine/Chest/Neck/Head/LeftUpperArm…[/code] rigs.
## Used by the editor plugin to auto-generate a RagdollProfile.
class_name SkeletonDetector


# --- Name classification -----------------------------------------------------
# A bone name is split into tokens at separators (_ . - : space) and camelCase
# boundaries; digit runs are dropped; namespace tokens and the side token are
# removed; what remains is joined into the bone's KEY and matched EXACTLY against
# the tables below. "mixamorig:LeftForeArm", "DEF-forearm.L.001" and "lowerarm_l"
# all reduce to the key "forearm" / "lowerarm" with side "L".

## Leading rig-namespace tokens that carry no anatomical meaning.
const NAMESPACE_TOKENS: Array[String] = ["mixamorig", "def"]
## First tokens marking non-deforming mechanism bones (Rigify ORG-/MCH-). Skipped.
const IGNORED_PREFIX_TOKENS: Array[String] = ["org", "mch"]
const LEFT_TOKENS: Array[String] = ["l", "left"]
const RIGHT_TOKENS: Array[String] = ["r", "right"]

const HIPS_KEYS: Array[String] = ["hips", "hip", "pelvis"]
const HEAD_KEYS: Array[String] = ["head"]
## Limb slot base name → accepted keys. Sides come from the side token, never
## from the key, so the same table serves both sides.
const LIMB_KEYS := {
	"UpperArm": ["arm", "upperarm", "uparm", "humerus"],
	"LowerArm": ["forearm", "lowerarm", "lowarm", "elbow", "ulna"],
	"Hand": ["hand", "wrist"],
	"UpperLeg": ["upleg", "upperleg", "thigh", "femur"],
	"LowerLeg": ["leg", "lowerleg", "lowleg", "calf", "shin", "knee", "tibia"],
	"Foot": ["foot", "ankle"],
}
## Keys of bones that can sit on the hips→head chain. Used by the names-only
## fallback and by the head search on rigs whose head is a numbered spine bone.
const TORSO_KEYS: Array[String] = [
	"spine", "chest", "upperchest", "lowerchest", "torso", "abdomen", "waist",
	"ribcage", "neck", "head",
]
const NECK_KEYS: Array[String] = ["neck"]
const CHEST_KEYS: Array[String] = ["chest", "upperchest", "ribcage"]

const LIMB_SLOT_ORDER: Array[String] = [
	"UpperArm_L", "LowerArm_L", "Hand_L",
	"UpperArm_R", "LowerArm_R", "Hand_R",
	"UpperLeg_L", "LowerLeg_L", "Foot_L",
	"UpperLeg_R", "LowerLeg_R", "Foot_R",
]
const TORSO_SLOTS: Array[String] = ["Hips", "Spine", "Chest"]

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

# Standard joint topology: parent_rig → child_rig + angular limits (degrees) in
# the ANATOMICAL joint frame the builder derives per joint from the skeleton's
# rest geometry (PhysicsRigBuilder.compute_rest_joint_frame): X = flexion / bend
# axis, Y = twist about the child bone, Z = lateral; 0 = the rest pose. Ranges are
# anatomical, a little generous (the springs shape the pose while the character
# is alive — the limits are the ragdoll's safety net and must never fight the
# animation; RagdollTuning.joint_limit_scale widens them further). One-sided X
# ranges (elbow, knee, hip) need the flexion sense: `flex` (JointDefinition.Flex)
# says which way the child folds for +X — FORWARD (elbow, hip), BACKWARD (knee).
const JOINT_TABLE: Array[Dictionary] = [
	{p = "Hips", c = "Spine", lx = Vector2(-35, 35), ly = Vector2(-30, 30), lz = Vector2(-25, 25)},
	{p = "Spine", c = "Chest", lx = Vector2(-35, 35), ly = Vector2(-30, 30), lz = Vector2(-25, 25)},
	{p = "Chest", c = "Head", lx = Vector2(-70, 70), ly = Vector2(-75, 75), lz = Vector2(-50, 50)},
	{p = "Chest", c = "UpperArm_L", lx = Vector2(-90, 150), ly = Vector2(-90, 90), lz = Vector2(-120, 120), flex = JointDefinition.Flex.FORWARD},
	{p = "UpperArm_L", c = "LowerArm_L", lx = Vector2(-10, 150), ly = Vector2(-80, 80), lz = Vector2(-20, 20), flex = JointDefinition.Flex.FORWARD},
	{p = "LowerArm_L", c = "Hand_L", lx = Vector2(-70, 70), ly = Vector2(-80, 80), lz = Vector2(-60, 60)},
	{p = "Chest", c = "UpperArm_R", lx = Vector2(-90, 150), ly = Vector2(-90, 90), lz = Vector2(-120, 120), flex = JointDefinition.Flex.FORWARD},
	{p = "UpperArm_R", c = "LowerArm_R", lx = Vector2(-10, 150), ly = Vector2(-80, 80), lz = Vector2(-20, 20), flex = JointDefinition.Flex.FORWARD},
	{p = "LowerArm_R", c = "Hand_R", lx = Vector2(-70, 70), ly = Vector2(-80, 80), lz = Vector2(-60, 60)},
	{p = "Hips", c = "UpperLeg_L", lx = Vector2(-30, 120), ly = Vector2(-40, 40), lz = Vector2(-45, 45), flex = JointDefinition.Flex.FORWARD},
	{p = "UpperLeg_L", c = "LowerLeg_L", lx = Vector2(-10, 140), ly = Vector2(-25, 25), lz = Vector2(-15, 15), flex = JointDefinition.Flex.BACKWARD},
	{p = "LowerLeg_L", c = "Foot_L", lx = Vector2(-50, 50), ly = Vector2(-35, 35), lz = Vector2(-35, 35)},
	{p = "Hips", c = "UpperLeg_R", lx = Vector2(-30, 120), ly = Vector2(-40, 40), lz = Vector2(-45, 45), flex = JointDefinition.Flex.FORWARD},
	{p = "UpperLeg_R", c = "LowerLeg_R", lx = Vector2(-10, 140), ly = Vector2(-25, 25), lz = Vector2(-15, 15), flex = JointDefinition.Flex.BACKWARD},
	{p = "LowerLeg_R", c = "Foot_R", lx = Vector2(-50, 50), ly = Vector2(-35, 35), lz = Vector2(-35, 35)},
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

## Per-bone-type shape proportions for auto-detection.
## All minimum values are ratios of skeleton height (Hips→Head distance).
## Extremity boxes (feet, hands) use "depth_is_length" mode.
const BONE_PROPORTIONS := {
	# Torso: min_ratio calibrated from Mixamo defaults / 0.60m Hips→Head distance
	"Hips":        {"proportions": Vector3(1.4, 0.8, 1.0), "offset": 0.5, "min_ratio": Vector3(0.583, 0.333, 0.417)},
	"Spine":       {"proportions": Vector3(1.4, 0.8, 1.0), "offset": 0.5, "min_ratio": Vector3(0.500, 0.300, 0.300)},
	"Chest":       {"proportions": Vector3(1.4, 0.8, 1.0), "offset": 0.5, "min_ratio": Vector3(0.583, 0.367, 0.367)},
	# Hands: flat, longer than wide (palm + fingers extent)
	"Hand_L":      {"depth_is_length": true, "width_ratio": 0.48, "height_ratio": 0.28, "offset": 0.5, "min_ratio": Vector3(0.133, 0.050, 0.167)},
	"Hand_R":      {"depth_is_length": true, "width_ratio": 0.48, "height_ratio": 0.28, "offset": 0.5, "min_ratio": Vector3(0.133, 0.050, 0.167)},
	# Feet: narrow, flat, very long (foot + toes extent)
	"Foot_L":      {"depth_is_length": true, "width_ratio": 0.48, "height_ratio": 0.28, "offset": 0.65, "min_ratio": Vector3(0.167, 0.083, 0.333)},
	"Foot_R":      {"depth_is_length": true, "width_ratio": 0.48, "height_ratio": 0.28, "offset": 0.65, "min_ratio": Vector3(0.167, 0.083, 0.333)},
	# Limb capsules
	"UpperArm_L":  {"radius_ratio": 0.15, "height_ratio": 1.0, "offset": 0.5, "min_radius_ratio": 0.050, "min_height_ratio": 0.167},
	"LowerArm_L":  {"radius_ratio": 0.15, "height_ratio": 1.0, "offset": 0.5, "min_radius_ratio": 0.050, "min_height_ratio": 0.167},
	"UpperArm_R":  {"radius_ratio": 0.15, "height_ratio": 1.0, "offset": 0.5, "min_radius_ratio": 0.050, "min_height_ratio": 0.167},
	"LowerArm_R":  {"radius_ratio": 0.15, "height_ratio": 1.0, "offset": 0.5, "min_radius_ratio": 0.050, "min_height_ratio": 0.167},
	"UpperLeg_L":  {"radius_ratio": 0.15, "height_ratio": 1.0, "offset": 0.5, "min_radius_ratio": 0.050, "min_height_ratio": 0.167},
	"LowerLeg_L":  {"radius_ratio": 0.15, "height_ratio": 1.0, "offset": 0.5, "min_radius_ratio": 0.050, "min_height_ratio": 0.167},
	"UpperLeg_R":  {"radius_ratio": 0.15, "height_ratio": 1.0, "offset": 0.5, "min_radius_ratio": 0.050, "min_height_ratio": 0.167},
	"LowerLeg_R":  {"radius_ratio": 0.15, "height_ratio": 1.0, "offset": 0.5, "min_radius_ratio": 0.050, "min_height_ratio": 0.167},
	# Head sphere
	"Head":        {"radius_ratio": 0.5, "offset": 0.5, "min_radius_ratio": 0.133},
}


## The tokenised bone list of one detection run plus its (optional) hierarchy.
## Built once per call so classification and ancestor queries share the work.
class BoneScan extends RefCounted:
	var names: PackedStringArray
	var parents: PackedInt32Array
	var keys: PackedStringArray
	var sides: PackedStringArray
	var has_hierarchy: bool = false

	func _init(p_names: PackedStringArray, p_parents: PackedInt32Array) -> void:
		names = p_names
		has_hierarchy = p_names.size() > 0 and p_parents.size() == p_names.size()
		parents = p_parents if has_hierarchy else PackedInt32Array()
		for bone_name: String in names:
			var cls := SkeletonDetector.classify_bone_name(bone_name)
			keys.append(cls.key)
			sides.append(cls.side)

	func parent_of(idx: int) -> int:
		return parents[idx] if has_hierarchy else -1

	func depth(idx: int) -> int:
		var d := 0
		var walk := parent_of(idx)
		while walk >= 0:
			d += 1
			walk = parent_of(walk)
		return d

	## Nearest common ancestor of [param a] and [param b] (either one itself if
	## it is an ancestor of the other), -1 without a hierarchy or shared root.
	func common_ancestor(a: int, b: int) -> int:
		if not has_hierarchy:
			return -1
		var ancestors := {}
		var walk := a
		while walk >= 0:
			ancestors[walk] = true
			walk = parent_of(walk)
		walk = b
		while walk >= 0:
			if ancestors.has(walk):
				return walk
			walk = parent_of(walk)
		return -1

	## First child of [param idx] (by index) whose key is in [param key_list], -1 if none.
	func child_with_key(idx: int, key_list: Array) -> int:
		for i in names.size():
			if parent_of(i) == idx and keys[i] in key_list:
				return i
		return -1

	## The bone whose key is in [param key_list] with exactly [param side]
	## ("L", "R" or ""). With a hierarchy the shallowest match wins (Rigify's
	## split limbs: `DEF-upper_arm.L` beats `DEF-upper_arm.L.001`); without one
	## the first in list order. -1 if none.
	func find(key_list: Array, side: String) -> int:
		var best := -1
		var best_depth := 0
		for i in names.size():
			if keys[i] == "" or sides[i] != side or keys[i] not in key_list:
				continue
			if not has_hierarchy:
				return i
			var d := depth(i)
			if best < 0 or d < best_depth:
				best = i
				best_depth = d
		return best


## Attempts to auto-detect humanoid bones in a Skeleton3D, using its bone
## hierarchy to classify the torso (see the class description).
## Returns a Dictionary mapping rig slot names to skeleton bone names.
## Returns empty dict if fewer than 8 bones matched or Hips/Spine/Head are missing.
static func detect_humanoid_bones(skeleton: Skeleton3D) -> Dictionary:
	var all_bones := PackedStringArray()
	var all_parents := PackedInt32Array()
	for i in skeleton.get_bone_count():
		all_bones.append(skeleton.get_bone_name(i))
		all_parents.append(skeleton.get_bone_parent(i))
	return detect_from_bone_names(all_bones, all_parents)


## Detects humanoid bones from a list of bone names, plus the parent index of
## each bone ([param bone_parents], -1 for roots) when the hierarchy is known.
## Returns a Dictionary mapping rig slot names to skeleton bone names.
## Returns empty dict if fewer than 8 bones matched or Hips/Spine/Head are missing.
##
## Without [param bone_parents] the torso is ordered by LIST POSITION (every
## importer lists parents before children): Spine is the first torso-keyed bone,
## Chest the last chest-keyed one (else the last non-neck torso bone), and Hips
## / Head must be named. Rigs whose hips and head are unnamed numbered spine
## bones (Rigify DEF) need the hierarchy — use [method detect_humanoid_bones].
static func detect_from_bone_names(bone_names: PackedStringArray, bone_parents: PackedInt32Array = PackedInt32Array()) -> Dictionary:
	var scan := BoneScan.new(bone_names, bone_parents)
	if scan.names.is_empty():
		return {}

	# Limbs by name (whole-token side + exact key)
	var found := {}  # slot → bone index
	for base: String in LIMB_KEYS:
		for side: String in ["L", "R"]:
			var idx := scan.find(LIMB_KEYS[base], side)
			if idx >= 0:
				found["%s_%s" % [base, side]] = idx

	# Anchors: hips by name, else the bone both thighs hang from (Rigify `DEF-spine`)
	var hips := scan.find(HIPS_KEYS, "")
	if hips < 0 and found.has("UpperLeg_L") and found.has("UpperLeg_R"):
		hips = scan.common_ancestor(found["UpperLeg_L"], found["UpperLeg_R"])
	if hips < 0:
		return {}

	var arm_root := _arm_root(scan, found)

	# Head by name, else the top of the torso chain above the arms (Rigify `DEF-spine.006`)
	var head := scan.find(HEAD_KEYS, "")
	if head < 0:
		head = _find_head_by_chain(scan, arm_root)
	if head < 0 or head == hips:
		return {}

	var torso := _classify_torso(scan, hips, head, arm_root)
	if not torso.has("Spine"):
		return {}

	var mapping := {}
	mapping["Hips"] = scan.names[hips]
	mapping["Spine"] = scan.names[torso["Spine"]]
	if torso.has("Chest"):
		mapping["Chest"] = scan.names[torso["Chest"]]
	mapping["Head"] = scan.names[head]
	for slot: String in LIMB_SLOT_ORDER:
		if found.has(slot):
			mapping[slot] = scan.names[found[slot]]

	if mapping.size() < 8:
		return {}
	return mapping


## Returns "L", "R" or "" for [param bone_name]. Sides come only from whole
## tokens (`_l`, `.L`, `Left`, `L_`, `-R`, `RightArm`…), never from substrings —
## `spine_lower` and `clavicle` carry no side.
static func detect_side(bone_name: String) -> String:
	return classify_bone_name(bone_name).side


## Splits [param bone_name] into lowercase tokens at separators (any character
## that is not a letter or digit) and camelCase boundaries; digit runs form
## their own tokens. `mixamorig:LeftForeArm` → [mixamorig, left, fore, arm];
## `DEF-upper_arm.L.001` → [def, upper, arm, l, 001]; `IKFoot` → [ikfoot].
static func tokenize_bone_name(bone_name: String) -> PackedStringArray:
	var tokens := PackedStringArray()
	var current := ""
	var prev_lower := false
	var prev_digit := false
	for i in bone_name.length():
		var code := bone_name.unicode_at(i)
		var is_upper := code >= 65 and code <= 90
		var is_lower := code >= 97 and code <= 122
		var is_digit := code >= 48 and code <= 57
		if not (is_upper or is_lower or is_digit):
			if current != "":
				tokens.append(current)
			current = ""
			prev_lower = false
			prev_digit = false
			continue
		var boundary := (is_upper and prev_lower) or (is_digit != prev_digit and current != "")
		if boundary and current != "":
			tokens.append(current)
			current = ""
		current += char(code).to_lower()
		prev_lower = is_lower
		prev_digit = is_digit
	if current != "":
		tokens.append(current)
	return tokens


## Reduces [param bone_name] to {"key": String, "side": String}: the tokens
## joined with namespaces, digits and the side token removed. Mechanism bones
## (ORG-/MCH-) yield an empty key and never match.
static func classify_bone_name(bone_name: String) -> Dictionary:
	var tokens := tokenize_bone_name(bone_name)
	var side := ""
	var key := ""
	for t_idx in tokens.size():
		var token := tokens[t_idx]
		if t_idx == 0 and token in IGNORED_PREFIX_TOKENS and tokens.size() > 1:
			return {"key": "", "side": ""}
		if token in NAMESPACE_TOKENS or token.is_valid_int():
			continue
		var token_side := _side_of_token(token)
		if token_side.side != "":
			if side == "":
				side = token_side.side
			key += token_side.rest
			continue
		key += token
	return {"key": key, "side": side}


# --- Profile generation ------------------------------------------------------

## Generates a RagdollProfile from a detected bone mapping and skeleton rest poses.
## The semantic roles are set to the rigs actually present (a rig without a
## Chest body gets [member RagdollProfile.chest_rig] = "Spine") and the joints
## come from [method default_joints_for], so no body is left unjointed.
static func create_profile_from_skeleton(
	skeleton: Skeleton3D,
	bone_mapping: Dictionary
) -> RagdollProfile:
	var profile := RagdollProfile.new()
	profile.root_bone = bone_mapping.get("Hips", "")

	# Measure skeleton geometry for scale-independent shape sizing
	var skeleton_height := _measure_skeleton_height(skeleton, bone_mapping)
	# Create bone definitions
	for slot: String in bone_mapping:
		var skel_bone: String = bone_mapping[slot]
		var child_slot: String = BONE_CHAINS.get(slot, "")
		var child_bone: String = bone_mapping.get(child_slot, "") if child_slot != "" else ""

		# No mapped child (leaf rig bone, or the chain's next body is absent —
		# e.g. Spine on a rig without a Chest): measure against the skeleton's
		# own first child. Extremities (feet, hands) with depth_is_length also
		# take the full descendant extent (foot→toeBase→toeEnd).
		var leaf_extent := 0.0
		if child_bone == "":
			var bone_idx := skeleton.find_bone(skel_bone)
			var children := skeleton.get_bone_children(bone_idx) if bone_idx >= 0 else PackedInt32Array()
			if not children.is_empty():
				child_bone = skeleton.get_bone_name(children[0])
				var props: Dictionary = BONE_PROPORTIONS.get(slot, {})
				if props.get("depth_is_length", false):
					leaf_extent = _estimate_leaf_extent(skeleton, bone_idx)

		var bone_def := BoneDefinition.new()
		bone_def.rig_name = slot
		bone_def.skeleton_bone = skel_bone
		bone_def.child_bone = child_bone
		bone_def.mass = MASS_TABLE.get(slot, 5.0)
		bone_def.shape_type = SHAPE_TABLE.get(slot, "box")

		# Estimate shape dimensions from bone length and skeleton geometry
		_estimate_shape(skeleton, bone_def, child_bone, leaf_extent, skeleton_height)

		profile.bones.append(bone_def)

	# Joints: the standard table, re-parented past any absent torso body
	profile.joints = default_joints_for(PackedStringArray(bone_mapping.keys()))

	# Semantic roles restricted to the bodies that exist
	_assign_roles(profile, bone_mapping)

	# Intermediate bones (torso chain by position + split limb segments)
	_detect_intermediate_bones(skeleton, bone_mapping, profile)

	return profile


## The standard humanoid joint set ([constant JOINT_TABLE]) as JointDefinitions
## for the rig bodies in [param rig_names]. A joint whose parent body is absent
## is re-parented to the nearest PRESENT ancestor in the table (see
## [method nearest_present_parent_rig]): on a rig with a single spine bone and
## no Chest, Head and both UpperArms joint to Spine instead of being left loose.
## Joints whose child body is absent are dropped. Shared by
## [method create_profile_from_skeleton] and
## [method RagdollProfile.create_mixamo_default] so there is one table.
static func default_joints_for(rig_names: PackedStringArray) -> Array[JointDefinition]:
	var out: Array[JointDefinition] = []
	for jt: Dictionary in JOINT_TABLE:
		if jt.c not in rig_names:
			continue
		var parent_rig := nearest_present_parent_rig(jt.p, rig_names)
		if parent_rig == "":
			continue
		var joint_def := JointDefinition.new()
		joint_def.parent_rig = parent_rig
		joint_def.child_rig = jt.c
		joint_def.limit_x = jt.lx
		joint_def.limit_y = jt.ly
		joint_def.limit_z = jt.lz
		joint_def.flex_direction = jt.get("flex", JointDefinition.Flex.NONE)
		out.append(joint_def)
	return out


## [param rig_name] itself if it is in [param rig_names], else its closest
## ancestor in the standard humanoid topology ([constant JOINT_TABLE]) that is
## present (torso: Chest → Spine → Hips). "" if none of them is present.
static func nearest_present_parent_rig(rig_name: String, rig_names: PackedStringArray) -> String:
	var current := rig_name
	while current != "":
		if current in rig_names:
			return current
		current = _table_parent_of(current)
	return ""


## Creates PhysicalBone3D nodes inside a PhysicalBoneSimulator3D (Godot's built-in
## ragdoll). General utility — used by the comparison demo, not the Kickback core.
static func populate_physical_bones(
	skeleton: Skeleton3D,
	simulator: PhysicalBoneSimulator3D,
	bone_mapping: Dictionary,
	owner: Node
) -> void:
	# Reuse the active-rig pipeline so the physical-bone shapes scale to the character
	# (instead of fixed 0.15m boxes / 0.05m capsules) and stay the single source of truth.
	var profile := create_profile_from_skeleton(skeleton, bone_mapping)
	for bone_def: BoneDefinition in profile.bones:
		if skeleton.find_bone(bone_def.skeleton_bone) < 0:
			continue

		var pb := PhysicalBone3D.new()
		pb.name = "PhysicalBone_%s" % bone_def.rig_name
		pb.bone_name = bone_def.skeleton_bone
		pb.mass = bone_def.mass
		pb.collision_layer = KickbackLayers.PARTIAL_RAGDOLL_LAYER
		pb.collision_mask = KickbackLayers.ENVIRONMENT_LAYER | KickbackLayers.PARTIAL_RAGDOLL_LAYER

		var col := create_collision_shape(bone_def)
		pb.add_child(col)
		col.owner = owner
		simulator.add_child(pb)
		pb.owner = owner


## Creates a CollisionShape3D from a BoneDefinition's shape parameters.
## Single source of truth — used by PhysicsRigBuilder, RigBaker, and populate_physical_bones.
static func create_collision_shape(bone_def: BoneDefinition) -> CollisionShape3D:
	var col := CollisionShape3D.new()
	match bone_def.shape_type:
		"box":
			var box := BoxShape3D.new()
			box.size = bone_def.box_size
			col.shape = box
		"capsule":
			var capsule := CapsuleShape3D.new()
			capsule.radius = bone_def.capsule_radius
			capsule.height = bone_def.capsule_height
			col.shape = capsule
		"sphere":
			var sphere := SphereShape3D.new()
			sphere.radius = bone_def.sphere_radius
			col.shape = sphere
	return col


# --- Private helpers: name classification ------------------------------------

## {"side": "L"/"R"/"", "rest": token minus the side word}. A token IS a side
## when it equals l/r/left/right, or starts/ends with left/right (all-lowercase
## names such as `lefthand`).
static func _side_of_token(token: String) -> Dictionary:
	for pair: Array in [[LEFT_TOKENS, "L"], [RIGHT_TOKENS, "R"]]:
		var words: Array[String] = pair[0]
		var side: String = pair[1]
		if token in words:
			return {"side": side, "rest": ""}
		var word: String = words[1]  # the long form ("left" / "right")
		if token.length() > word.length():
			if token.begins_with(word):
				return {"side": side, "rest": token.substr(word.length())}
			if token.ends_with(word):
				return {"side": side, "rest": token.substr(0, token.length() - word.length())}
	return {"side": "", "rest": token}


static func _table_parent_of(rig_name: String) -> String:
	for jt: Dictionary in JOINT_TABLE:
		if jt.c == rig_name:
			return jt.p
	return ""


# --- Private helpers: hierarchy classification -------------------------------

## The bone the upper arms hang from: their common ancestor, or the parent of
## the only arm present. -1 without arms or hierarchy.
static func _arm_root(scan: BoneScan, found: Dictionary) -> int:
	if not scan.has_hierarchy:
		return -1
	var left: int = found.get("UpperArm_L", -1)
	var right: int = found.get("UpperArm_R", -1)
	if left >= 0 and right >= 0:
		return scan.common_ancestor(left, right)
	if left >= 0:
		return scan.parent_of(left)
	if right >= 0:
		return scan.parent_of(right)
	return -1


## Head for rigs whose head has no head-keyed name (Rigify `DEF-spine.006`):
## from the torso bone the arms hang from, follow torso-keyed children upward
## to the end of the chain. -1 if the chain ends on the chest itself or on a
## neck-keyed bone (a neck is not a head).
static func _find_head_by_chain(scan: BoneScan, arm_root: int) -> int:
	if arm_root < 0:
		return -1
	var chest := arm_root
	while chest >= 0 and scan.keys[chest] not in TORSO_KEYS:
		chest = scan.parent_of(chest)
	if chest < 0:
		return -1
	var top := chest
	var next := scan.child_with_key(top, TORSO_KEYS)
	while next >= 0:
		top = next
		next = scan.child_with_key(top, TORSO_KEYS)
	if top == chest or scan.keys[top] in NECK_KEYS:
		return -1
	return top


## {"Spine": idx, "Chest": idx} for the torso between [param hips] and
## [param head]; "Chest" is absent when the arms hang from the Spine bone itself
## (single-spine-bone rigs). Empty when no torso bone lies between the two.
static func _classify_torso(scan: BoneScan, hips: int, head: int, arm_root: int) -> Dictionary:
	if scan.has_hierarchy:
		return _classify_torso_by_hierarchy(scan, hips, head, arm_root)
	return _classify_torso_by_order(scan, hips, head)


static func _classify_torso_by_hierarchy(scan: BoneScan, hips: int, head: int, arm_root: int) -> Dictionary:
	# Chain from just below the head down to just above the hips
	var chain := PackedInt32Array()
	var walk := scan.parent_of(head)
	while walk >= 0 and walk != hips:
		chain.append(walk)
		walk = scan.parent_of(walk)
	if walk != hips or chain.is_empty():
		return {}  # head not under the hips, or directly on them: no torso
	chain.reverse()  # bottom-up: chain[0] sits directly above the hips

	var result := {"Spine": chain[0]}
	var chest := -1
	if arm_root >= 0:
		var anchor := arm_root
		while anchor >= 0 and anchor != hips and chain.find(anchor) < 0:
			anchor = scan.parent_of(anchor)
		if anchor >= 0 and anchor != hips:
			chest = anchor  # the chain bone the arms hang from (or its nearest chain ancestor)
		elif anchor < 0:
			chest = _top_non_neck(scan, chain)  # arms not under the torso: best positional guess
		# anchor == hips: arms hang from the hips level — no chest body
	else:
		chest = _top_non_neck(scan, chain)
	if chest >= 0 and chest != chain[0]:
		result["Chest"] = chest
	return result


## Highest chain bone (bottom-up [param chain]) that is not neck-keyed, -1 if
## only the Spine qualifies.
static func _top_non_neck(scan: BoneScan, chain: PackedInt32Array) -> int:
	for i in range(chain.size() - 1, 0, -1):
		if scan.keys[chain[i]] not in NECK_KEYS:
			return chain[i]
	return -1


static func _classify_torso_by_order(scan: BoneScan, hips: int, head: int) -> Dictionary:
	var torso := PackedInt32Array()
	for i in scan.names.size():
		if i == hips or i == head or scan.sides[i] != "":
			continue
		if scan.keys[i] in TORSO_KEYS and scan.keys[i] not in HEAD_KEYS:
			torso.append(i)
	if torso.is_empty():
		return {}
	var result := {"Spine": torso[0]}
	var chest := -1
	for i in torso:
		if scan.keys[i] in CHEST_KEYS:
			chest = i
	if chest < 0:
		for i in torso:
			if scan.keys[i] not in NECK_KEYS:
				chest = i
	if chest >= 0 and chest != torso[0]:
		result["Chest"] = chest
	return result


# --- Private helpers: profile generation -------------------------------------

## Points the profile's semantic roles at the rigs that exist in [param bone_mapping].
static func _assign_roles(profile: RagdollProfile, bone_mapping: Dictionary) -> void:
	var present := PackedStringArray(bone_mapping.keys())
	profile.torso_rigs = _present_of(profile.torso_rigs, present)
	profile.chest_rig = nearest_present_parent_rig("Chest", present)
	profile.foot_rigs = _present_of(profile.foot_rigs, present)
	profile.hand_rigs = _present_of(profile.hand_rigs, present)
	profile.left_leg_chain = _present_of(profile.left_leg_chain, present)
	profile.right_leg_chain = _present_of(profile.right_leg_chain, present)
	profile.left_arm_chain = _present_of(profile.left_arm_chain, present)
	profile.right_arm_chain = _present_of(profile.right_arm_chain, present)


static func _present_of(names: PackedStringArray, present: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for n: String in names:
		if n in present:
			out.append(n)
	return out


## Computes the furthest descendant distance from a bone, walking the full
## skeleton hierarchy. For leaf rig bones (feet, hands, head), this captures
## the real body part extent (e.g., foot → toe_base → toe_end).
static func _estimate_leaf_extent(skeleton: Skeleton3D, bone_idx: int) -> float:
	var origin := skeleton.get_bone_global_rest(bone_idx).origin
	return _max_descendant_distance(skeleton, bone_idx, origin)


static func _max_descendant_distance(skeleton: Skeleton3D, bone_idx: int, origin: Vector3) -> float:
	var children := skeleton.get_bone_children(bone_idx)
	if children.is_empty():
		return skeleton.get_bone_global_rest(bone_idx).origin.distance_to(origin)
	var max_dist := 0.0
	for child_idx: int in children:
		max_dist = maxf(max_dist, _max_descendant_distance(skeleton, child_idx, origin))
	return max_dist


## Measures the vertical distance from Hips to Head in the skeleton rest pose.
## Used as a scale reference so all collision shapes adapt to character size.
static func _measure_skeleton_height(skeleton: Skeleton3D, bone_mapping: Dictionary) -> float:
	var hips_bone: String = bone_mapping.get("Hips", "")
	var head_bone: String = bone_mapping.get("Head", "")
	if hips_bone == "" or head_bone == "":
		return 0.6  # Fallback: typical Hips→Head distance for humanoid rigs
	var hips_idx := skeleton.find_bone(hips_bone)
	var head_idx := skeleton.find_bone(head_bone)
	if hips_idx < 0 or head_idx < 0:
		return 0.6
	var hips_pos := skeleton.get_bone_global_rest(hips_idx).origin
	var head_pos := skeleton.get_bone_global_rest(head_idx).origin
	return maxf(abs(head_pos.y - hips_pos.y), 0.5)  # Floor at 0.5m


static func _estimate_shape(skeleton: Skeleton3D, bone_def: BoneDefinition, child_bone: String, leaf_extent: float = 0.0, skeleton_height: float = 0.6) -> void:
	var bone_idx := skeleton.find_bone(bone_def.skeleton_bone)
	if bone_idx < 0:
		_set_default_shape(bone_def, skeleton_height)
		return

	var bone_rest := skeleton.get_bone_global_rest(bone_idx)
	var length := 0.2  # Default

	if child_bone != "":
		var child_idx := skeleton.find_bone(child_bone)
		if child_idx >= 0:
			var child_rest := skeleton.get_bone_global_rest(child_idx)
			length = bone_rest.origin.distance_to(child_rest.origin)

	# Use leaf extent if available (captures full foot/hand/head extent)
	if leaf_extent > 0.0:
		length = leaf_extent

	var props: Dictionary = BONE_PROPORTIONS.get(bone_def.rig_name, {})

	match bone_def.shape_type:
		"capsule":
			var radius_ratio: float = props.get("radius_ratio", 0.15)
			var height_ratio: float = props.get("height_ratio", 1.0)
			var min_r: float = props.get("min_radius_ratio", 0.050) * skeleton_height
			var min_h: float = props.get("min_height_ratio", 0.167) * skeleton_height
			bone_def.capsule_radius = maxf(length * radius_ratio, min_r)
			bone_def.capsule_height = maxf(length * height_ratio, min_h)
		"box":
			var min_ratio: Vector3 = props.get("min_ratio", Vector3(0.05, 0.03, 0.05))
			var min_s: Vector3 = min_ratio * skeleton_height
			if props.get("depth_is_length", false):
				# Extremities (feet, hands): Z = full length, X/Y = fractions
				var w_ratio: float = props.get("width_ratio", 0.48)
				var h_ratio: float = props.get("height_ratio", 0.28)
				bone_def.box_size = Vector3(
					maxf(length * w_ratio, min_s.x),
					maxf(length * h_ratio, min_s.y),
					maxf(length, min_s.z))
			else:
				# Torso bones: half-based with per-bone proportions + height-scaled minimums
				var proportions: Vector3 = props.get("proportions", Vector3(1.4, 0.8, 1.0))
				var half := length * 0.5
				bone_def.box_size = Vector3(
					maxf(half * proportions.x, min_s.x),
					maxf(half * proportions.y, min_s.y),
					maxf(half * proportions.z, min_s.z))
		"sphere":
			var radius_ratio: float = props.get("radius_ratio", 0.5)
			var min_r: float = props.get("min_radius_ratio", 0.133) * skeleton_height
			bone_def.sphere_radius = maxf(length * radius_ratio, min_r)

	bone_def.shape_offset = props.get("offset", 0.5)


static func _set_default_shape(bone_def: BoneDefinition, skeleton_height: float = 0.6) -> void:
	var props: Dictionary = BONE_PROPORTIONS.get(bone_def.rig_name, {})
	bone_def.shape_offset = props.get("offset", 0.5)
	match bone_def.shape_type:
		"capsule":
			bone_def.capsule_radius = props.get("min_radius_ratio", 0.050) * skeleton_height
			bone_def.capsule_height = props.get("min_height_ratio", 0.167) * skeleton_height
		"box":
			var min_ratio: Vector3 = props.get("min_ratio", Vector3(0.12, 0.09, 0.09))
			bone_def.box_size = min_ratio * skeleton_height
		"sphere":
			bone_def.sphere_radius = props.get("min_radius_ratio", 0.133) * skeleton_height


## Fills [member RagdollProfile.intermediate_bones]: unmapped skeleton bones that
## sit between two rig bodies and need an interpolated pose override.
## Torso: every bone on the Head→Hips chain is assigned by POSITION to the pair
## of mapped torso bodies around it (Spine1 → Spine/Chest, Neck → Chest/Head, or
## Spine/Head when there is no Chest). Limbs: the bones between the two bodies
## of each [constant BONE_CHAINS] pair (Rigify's `DEF-upper_arm.L.001`). A walk
## that reaches the skeleton root without meeting the parent body is discarded —
## an ancestor chain is never collected as "intermediate".
static func _detect_intermediate_bones(
	skeleton: Skeleton3D,
	bone_mapping: Dictionary,
	profile: RagdollProfile
) -> void:
	var mapped_bones := {}  # skeleton_bone_name → rig_slot
	for slot: String in bone_mapping:
		mapped_bones[bone_mapping[slot]] = slot

	_collect_torso_intermediates(skeleton, bone_mapping, mapped_bones, profile)

	for slot: String in bone_mapping:
		if slot in TORSO_SLOTS:
			continue
		var child_slot: String = BONE_CHAINS.get(slot, "")
		if child_slot == "" or child_slot not in bone_mapping:
			continue
		var parent_idx := skeleton.find_bone(bone_mapping[slot])
		var child_idx := skeleton.find_bone(bone_mapping[child_slot])
		if parent_idx < 0 or child_idx < 0:
			continue

		var intermediates := PackedStringArray()
		var walk_idx := skeleton.get_bone_parent(child_idx)
		while walk_idx >= 0 and walk_idx != parent_idx:
			var walk_name := skeleton.get_bone_name(walk_idx)
			if walk_name not in mapped_bones:
				intermediates.append(walk_name)
			walk_idx = skeleton.get_bone_parent(walk_idx)
		if walk_idx != parent_idx:
			continue  # child is not under its parent body: nothing lies "between" them
		for inter_bone: String in intermediates:
			profile.intermediate_bones.append(_intermediate_entry(inter_bone, slot, child_slot))


static func _collect_torso_intermediates(
	skeleton: Skeleton3D,
	bone_mapping: Dictionary,
	mapped_bones: Dictionary,
	profile: RagdollProfile
) -> void:
	var head_idx := skeleton.find_bone(bone_mapping.get("Head", ""))
	var hips_idx := skeleton.find_bone(bone_mapping.get("Hips", ""))
	if head_idx < 0 or hips_idx < 0:
		return

	# Chain top-down from just below the head to just above the hips
	var chain_names := PackedStringArray()
	var walk_idx := skeleton.get_bone_parent(head_idx)
	while walk_idx >= 0 and walk_idx != hips_idx:
		chain_names.append(skeleton.get_bone_name(walk_idx))
		walk_idx = skeleton.get_bone_parent(walk_idx)
	if walk_idx != hips_idx:
		return  # head is not under the hips: no torso chain to interpolate

	var chain_slots := PackedStringArray()
	for bone_name: String in chain_names:
		chain_slots.append(mapped_bones.get(bone_name, ""))

	for k in chain_names.size():
		if chain_slots[k] != "":
			continue
		var above := "Head"
		for j in range(k - 1, -1, -1):
			if chain_slots[j] != "":
				above = chain_slots[j]
				break
		var below := "Hips"
		for j in range(k + 1, chain_names.size()):
			if chain_slots[j] != "":
				below = chain_slots[j]
				break
		profile.intermediate_bones.append(_intermediate_entry(chain_names[k], below, above))


static func _intermediate_entry(skeleton_bone: String, body_a: String, body_b: String) -> IntermediateBoneEntry:
	var entry := IntermediateBoneEntry.new()
	entry.skeleton_bone = skeleton_bone
	entry.rig_body_a = body_a
	entry.rig_body_b = body_b
	entry.blend_weight = 0.5
	entry.use_a_basis = true
	return entry
