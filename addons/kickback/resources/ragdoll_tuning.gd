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

@export_group("Body Defaults (Springs Inactive)")
## Gravity scale for ragdoll bodies when springs are inactive (full ragdoll).
@export var gravity_scale: float = 0.8
## Angular damping for ragdoll bodies when springs are inactive.
@export var angular_damp: float = 8.0
## Linear damping for ragdoll bodies when springs are inactive.
@export var linear_damp: float = 2.0

@export_group("Body Defaults (Springs Active)")
## Gravity scale for ragdoll bodies when springs are driving them.
@export var spring_active_gravity: float = 0.0
## Angular damping when springs are active.
@export var spring_active_angular_damp: float = 3.0
## Linear damping when springs are active.
@export var spring_active_linear_damp: float = 2.0

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

@export_group("Recovery Thresholds")
## Fraction of recovery_duration that must elapse before early completion is allowed.
## At this percentage, if rotation error is below recovery_rotation_threshold, recovery completes.
@export_range(0.5, 1.0) var recovery_completion_threshold: float = 0.95
## Maximum rotation error (radians) for recovery to complete early.
## All bones must be within this angle of their animation target.
@export_range(0.1, 1.0) var recovery_rotation_threshold: float = 0.3

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

@export_group("Root Motion")
## Strip horizontal (XZ) root motion from the root bone's animation pose.
## Prevents drift when using animations with root motion (e.g., Mixamo staggers).
## The Y component is preserved for crouch/jump motion.
@export var strip_root_motion: bool = true
## Rig name of the root bone whose root motion should be stripped.
@export var root_motion_bone: String = "Hips"

@export_group("Stagger")
## Average strength ratio below which a non-ragdoll hit triggers stagger.
## Set to 0.0 to disable stagger entirely.
@export_range(0.0, 1.0) var stagger_threshold: float = 0.55
## Duration of stagger state before auto-recovery (seconds).
@export_range(0.1, 3.0) var stagger_duration: float = 0.6
## Minimum strength ratio during stagger (fraction of base_strength per bone).
@export_range(0.1, 0.8) var stagger_strength_floor: float = 0.35
## Multiplier on ragdoll_probability when hit during active stagger.
@export_range(1.0, 5.0) var stagger_ragdoll_bonus: float = 1.5

@export_group("Balance")
## Center-of-mass balance ratio above which a hit triggers stagger (even if
## average spring strength is still above stagger_threshold).
## 0.0 = disabled. Higher = harder to trigger stagger from balance alone.
@export_range(0.0, 1.0) var balance_stagger_threshold: float = 0.5
## Balance ratio above this during stagger forces ragdoll (character is tipping over).
@export_range(0.0, 1.0) var balance_ragdoll_threshold: float = 0.85
## Balance ratio below this during stagger allows early recovery (character regained balance).
@export_range(0.0, 1.0) var balance_recovery_threshold: float = 0.3
## How long balance must stay below recovery threshold before stagger ends.
@export_range(0.0, 1.0) var balance_recovery_hold_time: float = 0.3

@export_group("Fatigue")
## How much fatigue each hit adds, scaled by the hit's strength_reduction.
## Higher = faster fatigue buildup from repeated hits.
@export_range(0.0, 1.0) var fatigue_gain: float = 0.15
## How fast fatigue decays per second when not being hit.
## Lower = fatigue lingers longer between engagements.
@export_range(0.0, 1.0) var fatigue_decay: float = 0.05
## How much fatigue reduces effective base spring strength.
## At fatigue_impact=0.5 and fatigue=1.0, springs recover to 50% of base.
@export_range(0.0, 1.0) var fatigue_impact: float = 0.5

@export_group("Hit Stacking")
## Time window (seconds) within which consecutive hits count as rapid fire.
@export_range(0.05, 1.0) var rapid_fire_window: float = 0.3
## Extra strength reduction per streak hit (e.g., 0.3 = 30% more per consecutive hit).
@export_range(0.0, 1.0) var hit_streak_multiplier: float = 0.3
## Minimum effective strength_reduction to interrupt GETTING_UP and force re-ragdoll.
## Set to 2.0 to effectively disable recovery interruption.
@export_range(0.0, 2.0) var recovery_interrupt_threshold: float = 0.5

@export_group("Protected Bones")
## Bones that stay animated during hits and stagger. Their spring strength
## is never reduced by impacts. Useful for keeping legs planted while the
## upper body reacts. During full ragdoll, all bones still go limp.
@export var protected_bones: PackedStringArray = []


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

	tuning.stagger_threshold = 0.55
	tuning.stagger_duration = 0.6
	tuning.stagger_strength_floor = 0.35
	tuning.stagger_ragdoll_bonus = 1.5

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

	for bone_name: String in protected_bones:
		if bone_name not in valid_names:
			warnings.append("protected_bones entry '%s' not found in profile rig names" % bone_name)

	return warnings
