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
