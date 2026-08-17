## Defines a Generic6DOFJoint3D connecting two ragdoll rig bodies.
## Angular limits are in degrees; the joint locks linear axes.
##
## Limit axes are the JOINT FRAME's axes, which the builder derives per joint
## (see [enum RagdollProfile.JointFrame]). In the default ANATOMICAL frame:
## +Y runs along the child bone (twist), +X is the flexion / bend axis and +Z
## the remaining lateral axis, and the frame is centred on the skeleton's REST
## pose (a limit of 0 = the rest pose), whatever pose the rig happens to be
## built in. So a one-sided limit_x such as (-10, 150) reads: 10 deg of
## hyperextension, 150 deg of flexion, with the flexion sense set by
## [member flex_direction].
class_name JointDefinition
extends Resource

## Which way the child bone folds under a POSITIVE rotation about the joint's
## X (flexion) axis in the ANATOMICAL frame. FORWARD = toward the character's
## front (elbows, hips), BACKWARD = toward its back (knees). NONE = the sign is
## whatever the geometry gives (fine for symmetric limits). When the rest pose
## already bends the joint (an A-pose with slightly bent elbows/knees), the bend
## itself supplies the axis and this only fixes the sign.
enum Flex { NONE, FORWARD, BACKWARD }

## Rig name of the parent body (e.g. "Hips").
@export var parent_rig: String
## Rig name of the child body (e.g. "Spine").
@export var child_rig: String

@export_group("Angular Limits (degrees)")
## X-axis (flexion / bend) angular limit: (lower, upper) in degrees. May be
## one-sided, e.g. (-10, 150) for an elbow — see [member flex_direction].
@export var limit_x: Vector2 = Vector2(-15, 15)
## Y-axis (twist about the bone) angular limit: (lower, upper) in degrees.
@export var limit_y: Vector2 = Vector2(-15, 15)
## Z-axis (lateral) angular limit: (lower, upper) in degrees.
@export var limit_z: Vector2 = Vector2(-10, 10)
## Flexion sense of +X, see [enum Flex]. Only meaningful with the ANATOMICAL
## joint frame; ignored by BONE_REST / BUILD_POSE frames.
@export var flex_direction: Flex = Flex.NONE

@export_group("Compliance")
## NOTE: Jolt Physics ignores all three of these (the engine prints "6DOF joint
## angular limit softness/damping/restitution is not supported when using Jolt
## Physics" the first time they are non-zero). Use
## [member RagdollTuning.joint_limit_scale] to soften limits under Jolt.
## How soft the angular limit boundaries are. 0 = hard stop, 1 = fully soft.
@export_range(0.0, 1.0) var angular_softness: float = 0.0
## Damping applied when approaching angular limits. Higher = more resistance.
@export_range(0.0, 10.0) var angular_damping: float = 0.0
## Bounciness at angular limit boundaries. 0 = no bounce, 1 = full bounce.
@export_range(0.0, 1.0) var angular_restitution: float = 0.0


## Configures a Generic6DOFJoint3D from this definition: locks the linear axes,
## applies the per-axis angular limits (degrees → radians, each bound multiplied
## by [param limit_scale] — [member RagdollTuning.joint_limit_scale]), and
## optional compliance. Single source of truth shared by the runtime
## PhysicsRigBuilder and the editor RigBaker — typed per-axis calls (no
## `joint.call("set_flag_" + axis, ...)` dispatch).
func apply_to(joint: Generic6DOFJoint3D, limit_scale: float = 1.0) -> void:
	# Lock all linear axes (ball-joint behaviour: position pinned, rotation limited).
	joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)

	# Enable angular limits, then set per-axis lower/upper bounds. Our limits
	# are the allowed rotation of the CHILD (node_b) about each joint-frame axis,
	# right-hand rule; Godot's Generic6DOFJoint3D measures the angle with the
	# opposite sign (measured under Jolt: with (0, 150) on X the child could turn
	# -150..0 about the joint's +X and nothing positive), so the bounds are
	# mirrored on the way in. Symmetric limits are unaffected.
	joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	var s := maxf(limit_scale, 0.0)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-limit_x.y * s))
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(-limit_x.x * s))
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-limit_y.y * s))
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(-limit_y.x * s))
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-limit_z.y * s))
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(-limit_z.x * s))

	# Optional compliance on all axes.
	if angular_softness > 0.0 or angular_damping > 0.0 or angular_restitution > 0.0:
		joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LIMIT_SOFTNESS, angular_softness)
		joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LIMIT_SOFTNESS, angular_softness)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LIMIT_SOFTNESS, angular_softness)
		joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_DAMPING, angular_damping)
		joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_DAMPING, angular_damping)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_DAMPING, angular_damping)
		joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_RESTITUTION, angular_restitution)
		joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_RESTITUTION, angular_restitution)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_RESTITUTION, angular_restitution)
