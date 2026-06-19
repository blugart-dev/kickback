extends Node3D
## Runtime test harness for Kickback's physics smoke tests.
##
## Builds a synthetic Mixamo-named humanoid [Skeleton3D] entirely in code (no
## imported asset dependency) and assembles the REAL Kickback active-ragdoll node
## graph around it — [KickbackCharacter] + [PhysicsRigBuilder] + [PhysicsRigSync]
## + [SpringResolver] + [ActiveRagdollController], wired exactly as the setup tool
## wires a live character. A layer-1 ground [StaticBody3D] is added so the ragdoll
## can land and foot-IK raycasts have something to hit.
##
## This is NOT a test script (it does not extend GutTest and lives under helpers/
## without the "test_" prefix, so GUT never collects it). Test scripts preload it,
## add it to the tree, call [method setup], then await [signal
## KickbackCharacter.setup_complete] before stepping physics.

## Bone table: [name, parent_name, local_position]. Parents precede children.
## Identity bases throughout — a plain standing pose is enough to exercise the
## spring/ragdoll/IK math, which is orientation-agnostic. Hips at 0.9 m, feet at
## ~0.03 m above the origin (the character root), legs 0.42 m + 0.40 m long.
const _BONES: Array = [
	["mixamorig_Hips", "", Vector3(0.0, 0.9, 0.0)],
	["mixamorig_Spine", "mixamorig_Hips", Vector3(0.0, 0.12, 0.0)],
	["mixamorig_Spine1", "mixamorig_Spine", Vector3(0.0, 0.12, 0.0)],
	["mixamorig_Spine2", "mixamorig_Spine1", Vector3(0.0, 0.12, 0.0)],
	["mixamorig_Neck", "mixamorig_Spine2", Vector3(0.0, 0.12, 0.0)],
	["mixamorig_Head", "mixamorig_Neck", Vector3(0.0, 0.10, 0.0)],
	["mixamorig_HeadTop_End", "mixamorig_Head", Vector3(0.0, 0.18, 0.0)],
	["mixamorig_LeftArm", "mixamorig_Spine2", Vector3(0.18, 0.10, 0.0)],
	["mixamorig_LeftForeArm", "mixamorig_LeftArm", Vector3(0.28, 0.0, 0.0)],
	["mixamorig_LeftHand", "mixamorig_LeftForeArm", Vector3(0.25, 0.0, 0.0)],
	["mixamorig_RightArm", "mixamorig_Spine2", Vector3(-0.18, 0.10, 0.0)],
	["mixamorig_RightForeArm", "mixamorig_RightArm", Vector3(-0.28, 0.0, 0.0)],
	["mixamorig_RightHand", "mixamorig_RightForeArm", Vector3(-0.25, 0.0, 0.0)],
	["mixamorig_LeftUpLeg", "mixamorig_Hips", Vector3(0.10, -0.05, 0.0)],
	["mixamorig_LeftLeg", "mixamorig_LeftUpLeg", Vector3(0.0, -0.42, 0.0)],
	["mixamorig_LeftFoot", "mixamorig_LeftLeg", Vector3(0.0, -0.40, 0.0)],
	["mixamorig_LeftToeBase", "mixamorig_LeftFoot", Vector3(0.0, -0.05, 0.12)],
	["mixamorig_RightUpLeg", "mixamorig_Hips", Vector3(-0.10, -0.05, 0.0)],
	["mixamorig_RightLeg", "mixamorig_RightUpLeg", Vector3(0.0, -0.42, 0.0)],
	["mixamorig_RightFoot", "mixamorig_RightLeg", Vector3(0.0, -0.40, 0.0)],
	["mixamorig_RightToeBase", "mixamorig_RightFoot", Vector3(0.0, -0.05, 0.12)],
]

## Rig names of the 16 physics bodies the Mixamo profile builds (for assertions).
const RIG_NAMES: Array = [
	"Hips", "Spine", "Chest", "Head",
	"UpperArm_L", "LowerArm_L", "Hand_L",
	"UpperArm_R", "LowerArm_R", "Hand_R",
	"UpperLeg_L", "LowerLeg_L", "Foot_L",
	"UpperLeg_R", "LowerLeg_R", "Foot_R",
]

var skeleton: Skeleton3D
var character: KickbackCharacter
var rig_builder: PhysicsRigBuilder
var rig_sync: PhysicsRigSync
var spring: SpringResolver
var controller: ActiveRagdollController
var ground: StaticBody3D
var tuning: RagdollTuning
var profile: RagdollProfile


## Builds the synthetic skeleton, optional ground, and the full Kickback graph.
## Call after the harness is already inside the SceneTree. Pass a [RagdollTuning]
## and/or [RagdollProfile] to override the Mixamo defaults. After this returns,
## await [member character]'s setup_complete signal before asserting.
func setup(p_tuning: RagdollTuning = null, p_profile: RagdollProfile = null, with_ground: bool = true) -> void:
	tuning = p_tuning if p_tuning else RagdollTuning.create_default()
	profile = p_profile if p_profile else RagdollProfile.create_mixamo_default()

	if with_ground:
		ground = _build_ground()
		add_child(ground)

	skeleton = _build_skeleton()
	add_child(skeleton)

	# Sibling controllers, pre-configured BEFORE entering the tree so their
	# _ready (which builds the rig / adjacency from the profile) sees the right
	# config rather than falling back to defaults. KickbackCharacter re-applies
	# the same config in its own _ready — idempotent.
	rig_builder = PhysicsRigBuilder.new()
	rig_builder.name = "PhysicsRigBuilder"
	rig_builder.skeleton_path = NodePath("../Skeleton3D")
	rig_builder.configure(profile, tuning)
	add_child(rig_builder)

	rig_sync = PhysicsRigSync.new()
	rig_sync.name = "PhysicsRigSync"
	rig_sync.skeleton_path = NodePath("../Skeleton3D")
	rig_sync.rig_builder_path = NodePath("../PhysicsRigBuilder")
	rig_sync.configure(profile)
	add_child(rig_sync)

	spring = SpringResolver.new()
	spring.name = "SpringResolver"
	spring.skeleton_path = NodePath("../Skeleton3D")
	spring.rig_builder_path = NodePath("../PhysicsRigBuilder")
	spring.configure(tuning)
	add_child(spring)

	controller = ActiveRagdollController.new()
	controller.name = "ActiveRagdollController"
	controller.spring_resolver_path = NodePath("../SpringResolver")
	controller.rig_builder_path = NodePath("../PhysicsRigBuilder")
	controller.rig_sync_path = NodePath("../PhysicsRigSync")
	controller.character_root_path = NodePath("..")
	controller.configure(profile, tuning)
	add_child(controller)

	# KickbackCharacter LAST so its sibling scan finds all four controllers.
	character = KickbackCharacter.new()
	character.name = "KickbackCharacter"
	character.skeleton_path = NodePath("../Skeleton3D")
	character.character_root_path = NodePath("..")
	character.ragdoll_profile = profile
	character.ragdoll_tuning = tuning
	add_child(character)


## Awaits Kickback setup with a frame budget. Returns true once the character is
## fully initialized, false if it never completes within [param max_frames].
func await_ready(max_frames: int = 30) -> bool:
	var frames := 0
	while not character.is_setup_complete() and frames < max_frames:
		await get_tree().process_frame
		frames += 1
	return character.is_setup_complete()


func get_body(rig_name: String) -> RigidBody3D:
	return rig_builder.get_bodies().get(rig_name)


func bone_idx(skeleton_bone: String) -> int:
	return skeleton.find_bone(skeleton_bone)


## World-space origin the skeleton currently reports for a bone (override layer
## included — this is what PhysicsRigSync writes the physics pose into).
func skeleton_bone_world_origin(skeleton_bone: String) -> Vector3:
	var idx := skeleton.find_bone(skeleton_bone)
	if idx < 0:
		return Vector3.ZERO
	return (skeleton.global_transform * skeleton.get_bone_global_pose(idx)).origin


func _build_skeleton() -> Skeleton3D:
	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	var name_to_idx: Dictionary = {}
	for entry: Array in _BONES:
		var bone_name: String = entry[0]
		var parent_name: String = entry[1]
		var pos: Vector3 = entry[2]
		var idx := skel.add_bone(bone_name)
		name_to_idx[bone_name] = idx
		if parent_name != "":
			skel.set_bone_parent(idx, name_to_idx[parent_name])
		var rest := Transform3D(Basis(), pos)
		skel.set_bone_rest(idx, rest)
		# Pose defaults to identity until set; copy rest into the pose so the
		# animation target the SpringResolver reads matches the rest layout.
		skel.set_bone_pose_position(idx, pos)
		skel.set_bone_pose_rotation(idx, Quaternion.IDENTITY)
		skel.set_bone_pose_scale(idx, Vector3.ONE)
	return skel


func _build_ground() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = 1  # layer 1 — matches default foot-IK + get-up ray masks
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 0.4, 20.0)
	shape.shape = box
	body.add_child(shape)
	# Top surface flush with the origin (y = 0), where the feet rest.
	body.position = Vector3(0.0, -0.2, 0.0)
	return body
