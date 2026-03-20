## Defines a skeleton bone that is not part of the physics rig but needs
## its pose interpolated from two neighboring rig bodies (e.g. Spine1
## interpolated between Spine and Chest).
class_name IntermediateBoneEntry
extends Resource

## Skeleton bone name to override (e.g. "mixamorig_Spine1").
@export var skeleton_bone: String
## Rig body name for the first interpolation source (e.g. "Spine").
@export var rig_body_a: String
## Rig body name for the second interpolation source (e.g. "Chest").
@export var rig_body_b: String
## Position blend weight between body A (0.0) and body B (1.0).
@export_range(0.0, 1.0) var blend_weight: float = 0.5
## If true, use body A's basis for orientation; otherwise use body B's.
@export var use_a_basis: bool = true
