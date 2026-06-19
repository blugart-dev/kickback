## Defines a Generic6DOFJoint3D connecting two ragdoll rig bodies.
## Angular limits are in degrees; the joint locks linear axes.
class_name JointDefinition
extends Resource

## Rig name of the parent body (e.g. "Hips").
@export var parent_rig: String
## Rig name of the child body (e.g. "Spine").
@export var child_rig: String

@export_group("Angular Limits (degrees)")
## X-axis angular limit: (lower, upper) in degrees.
@export var limit_x: Vector2 = Vector2(-15, 15)
## Y-axis angular limit: (lower, upper) in degrees.
@export var limit_y: Vector2 = Vector2(-15, 15)
## Z-axis angular limit: (lower, upper) in degrees.
@export var limit_z: Vector2 = Vector2(-10, 10)

@export_group("Compliance")
## How soft the angular limit boundaries are. 0 = hard stop, 1 = fully soft.
@export_range(0.0, 1.0) var angular_softness: float = 0.0
## Damping applied when approaching angular limits. Higher = more resistance.
@export_range(0.0, 10.0) var angular_damping: float = 0.0
## Bounciness at angular limit boundaries. 0 = no bounce, 1 = full bounce.
@export_range(0.0, 1.0) var angular_restitution: float = 0.0


## Configures a Generic6DOFJoint3D from this definition: locks the linear axes,
## applies the per-axis angular limits (degrees → radians), and optional compliance.
## Single source of truth shared by the runtime PhysicsRigBuilder and the editor
## RigBaker — typed per-axis calls (no `joint.call("set_flag_" + axis, ...)` dispatch).
func apply_to(joint: Generic6DOFJoint3D) -> void:
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

	# Enable angular limits, then set per-axis lower/upper bounds.
	joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(limit_x.x))
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(limit_x.y))
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(limit_y.x))
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(limit_y.y))
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(limit_z.x))
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(limit_z.y))

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
