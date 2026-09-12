## Data object describing a single hit event in the comparison DEMO. Passed to
## the demo-only PartialRagdollController (demo/partial_ragdoll_controller.gd)
## to communicate hit location, direction, and magnitude. Not part of the plugin:
## preload this script instead of relying on a global class name.
extends RefCounted

## World-space position where the hit landed.
var hit_position: Vector3
## World-space direction of the incoming hit (normalized).
var hit_direction: Vector3
## Skeleton bone name that was hit (e.g. "mixamorig_LeftArm").
var hit_bone_name: String
## Final impulse magnitude after weapon profile scaling.
var impulse_magnitude: float
## The PhysicalBone3D that was hit (for partial ragdoll tier).
var hit_bone: PhysicalBone3D
## Body region classification: "head", "torso", "upper_limb", or "lower_limb".
var hit_bone_region: String = "torso"


## Classifies a bone name into a coarse body region so a consumer can pick a
## reaction per region.
static func classify_region(bone_name: String) -> String:
	var n := bone_name.to_lower()
	if "head" in n:                                          return "head"
	if "neck" in n:                                          return "head"
	if "hip" in n or "pelvis" in n:                          return "torso"
	if "spine" in n or "chest" in n:                         return "torso"
	if "upperarm" in n or "upper_arm" in n or "arm" in n:    return "upper_limb"
	if "forearm" in n or "fore_arm" in n or "lower_arm" in n: return "upper_limb"
	if "hand" in n:                                          return "upper_limb"
	if "upleg" in n or "up_leg" in n or "thigh" in n:        return "lower_limb"
	if "leg" in n or "calf" in n or "shin" in n:             return "lower_limb"
	if "foot" in n or "toe" in n:                            return "lower_limb"
	return "torso"
