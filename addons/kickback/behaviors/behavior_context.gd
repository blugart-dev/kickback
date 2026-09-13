## What a [KickbackBehavior] may read and ask of the rig, handed to every tick by the
## controller. Behaviors get the solvers and the rig, not the controller, so they cannot
## reach into the state machine.
@icon("res://addons/kickback/icons/active_ragdoll_controller.svg")
class_name BehaviorContext
extends RefCounted

var spring: SpringResolver
var rig_builder: PhysicsRigBuilder
var profile: RagdollProfile
var tuning: RagdollTuning
var character_root: Node3D
## Foot IK solver (locks, steps, plants); null when the rig has no complete leg chains.
var foot_ik: FootIKSolver
## Arm IK solver (reaches); null when the rig has no complete arm chains.
var arm_ik: ArmIKSolver
## The controller's current [enum ActiveRagdollController.State].
var state: int = 0
## Emitted-signal hooks the controller wires for the behaviors (a step started, ...):
## Callable(foot_rig: String, target: Vector3).
var on_step_started: Callable = Callable()


## World-space animation target of a rig body this tick (root motion stripped, no IK
## override) — where the animation wants the bone.
func animation_global(rig_name: String) -> Transform3D:
	var idx := spring.get_bone_idx(rig_name)
	if idx < 0:
		return Transform3D.IDENTITY
	return spring.get_skeleton().global_transform * spring.get_animation_bone_global(idx)


func body(rig_name: String) -> RigidBody3D:
	return rig_builder.get_bodies().get(rig_name)
