## Skeleton-independent physics tuning for ragdoll behavior. Controls spring
## strengths, recovery timing, collision layers, velocity clamps, and animation
## names. Change this to alter the "feel" without changing the skeleton mapping.
class_name RagdollTuning
extends Resource

@export_group("Collision")
## Physics collision layer for ragdoll bodies.
@export_flags_3d_physics var collision_layer: int = 8
## Physics collision mask for ragdoll bodies.
@export_flags_3d_physics var collision_mask: int = 14

@export_group("Body Defaults")
## Default gravity scale for ragdoll bodies when springs are inactive.
@export var gravity_scale: float = 0.8
## Default angular damping for ragdoll bodies when springs are inactive.
@export var angular_damp: float = 8.0
## Default linear damping for ragdoll bodies when springs are inactive.
@export var linear_damp: float = 2.0

@export_group("Spring Strengths")
## Per-bone base spring strength. Keys are rig names (e.g. "Hips": 0.65).
## Bones not listed use default_spring_strength.
@export var strength_map: Dictionary = {}
## Fallback spring strength for bones not in strength_map.
@export var default_spring_strength: float = 0.25

@export_group("Pin Strengths")
## Per-bone position tracking strength. Keys are rig names (e.g. "Hips": 0.85).
## Bones not listed use default_pin_strength.
@export var pin_strength_overrides: Dictionary = {}
## Fallback pin strength for bones not in pin_strength_overrides.
@export var default_pin_strength: float = 0.1

@export_group("Recovery")
## Per-bone staggered recovery delay in seconds. Keys are rig names.
@export var ramp_delay: Dictionary = {}
## Per-bone minimum strength floor. Keys are rig names.
@export var min_strength: Dictionary = {}
## Base spring strength recovery rate per second.
@export var recovery_rate: float = 0.3
## Total duration of the get-up recovery sequence in seconds.
@export var recovery_duration: float = 2.5
## Maximum time in ragdoll state before forced recovery.
@export var ragdoll_force_recovery_time: float = 3.0
## Duration of pose interpolation from ragdoll landing to animation target.
@export var pose_blend_duration: float = 0.75
## Maximum recovery time before forced completion.
@export var safety_timeout: float = 3.5

@export_group("Settle Detection")
## How long bodies must be below velocity thresholds to count as settled.
@export var settle_duration: float = 0.6
## Linear velocity threshold for settle detection.
@export var settle_linear_threshold: float = 0.5
## Angular velocity threshold for settle detection.
@export var settle_angular_threshold: float = 0.3

@export_group("Velocity Clamps")
## Maximum angular velocity for spring-driven bodies.
@export var max_angular_velocity: float = 20.0
## Maximum linear velocity for spring-driven bodies.
@export var max_linear_velocity: float = 10.0

@export_group("Ground Detection")
## Collision mask for ground raycasts during get-up recovery.
@export_flags_3d_physics var ground_raycast_mask: int = 2
## Whether to align the character root to the ground slope during recovery.
## If false (default), the character stays upright regardless of slope angle.
@export var align_to_slope: bool = false


## Creates a RagdollTuning with the default values matching the original
## hardcoded constants from the Kickback plugin.
static func create_default() -> RagdollTuning:
	var tuning := RagdollTuning.new()

	tuning.strength_map = {
		"Hips": 0.65, "Spine": 0.60, "Chest": 0.60,
		"Head": 0.35,
		"UpperArm_L": 0.45, "LowerArm_L": 0.40, "Hand_L": 0.25,
		"UpperArm_R": 0.45, "LowerArm_R": 0.40, "Hand_R": 0.25,
		"UpperLeg_L": 0.55, "LowerLeg_L": 0.45, "Foot_L": 0.30,
		"UpperLeg_R": 0.55, "LowerLeg_R": 0.45, "Foot_R": 0.30,
	}

	tuning.pin_strength_overrides = {
		"Hips": 0.85,
		"Foot_L": 0.4,
		"Foot_R": 0.4,
	}

	tuning.ramp_delay = {
		"Hips": 0.0, "Spine": 0.0, "Chest": 0.05,
		"Head": 0.25,
		"UpperArm_L": 0.2, "LowerArm_L": 0.25, "Hand_L": 0.3,
		"UpperArm_R": 0.2, "LowerArm_R": 0.25, "Hand_R": 0.3,
		"UpperLeg_L": 0.1, "LowerLeg_L": 0.15, "Foot_L": 0.2,
		"UpperLeg_R": 0.1, "LowerLeg_R": 0.15, "Foot_R": 0.2,
	}

	tuning.min_strength = {
		"Hips": 0.15, "Spine": 0.10, "Chest": 0.10,
		"UpperLeg_L": 0.10, "UpperLeg_R": 0.10,
		"LowerLeg_L": 0.08, "LowerLeg_R": 0.08,
		"Foot_L": 0.05, "Foot_R": 0.05,
	}

	return tuning


## Validates that all dictionary keys in this tuning reference valid rig names
## defined in the given [param profile]. Returns an array of warning strings.
## An empty array means all keys are valid.
func validate_against_profile(profile: RagdollProfile) -> PackedStringArray:
	var warnings := PackedStringArray()
	var valid_names := {}
	for bone_def: BoneDefinition in profile.bones:
		valid_names[bone_def.rig_name] = true

	var dicts: Array[Array] = [
		["strength_map", strength_map],
		["pin_strength_overrides", pin_strength_overrides],
		["ramp_delay", ramp_delay],
		["min_strength", min_strength],
	]
	for entry: Array in dicts:
		var dict_name: String = entry[0]
		var dict: Dictionary = entry[1]
		for key: String in dict:
			if key not in valid_names:
				warnings.append("%s key '%s' not found in profile rig names" % [dict_name, key])

	return warnings
