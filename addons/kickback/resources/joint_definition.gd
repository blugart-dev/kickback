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
