class_name HitEvent
extends RefCounted

var hit_position: Vector3
var hit_direction: Vector3
var hit_bone_name: String
var impulse_magnitude: float
var hit_bone: PhysicalBone3D
var hit_bone_region: String = "torso"


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
