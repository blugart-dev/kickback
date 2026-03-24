## Skeleton-independent physics tuning for ragdoll behavior. Controls spring
## strengths, recovery timing, collision layers, velocity clamps, and more.
## Change this to alter the "feel" without changing the skeleton mapping.
##
## All properties have sensible defaults for Mixamo humanoids. Create a new
## RagdollTuning resource in the inspector — it works out of the box.
class_name RagdollTuning
extends Resource

# ── Hit Reactions (most-tweaked) ────────────────────────────────────────────

@export_group("Hit Reactions")
## Average strength ratio below which a non-ragdoll hit triggers stagger.
## Set to 0.0 to disable stagger entirely.
@export_range(0.0, 1.0) var stagger_threshold: float = 0.70
## Duration of stagger state before auto-recovery (seconds).
@export_range(0.1, 3.0) var stagger_duration: float = 1.8
## Minimum strength ratio during stagger (fraction of base_strength per bone).
@export_range(0.05, 0.8) var stagger_strength_floor: float = 0.10
## Spring recovery rate during stagger (per second). Low = bones stay weak,
## active resistance becomes the sole driver. 0.0 = no natural recovery during stagger.
@export_range(0.0, 0.5) var stagger_recovery_rate: float = 0.03
## Force (Newtons) applied to core bones during stagger, creating visible wobble.
## Springs fight this force, producing back-and-forth sway. 0.0 = disabled.
@export_range(0.0, 1000.0) var stagger_sway_strength: float = 300.0
## Oscillation frequency of the sway force (Hz). Higher = faster wobble.
@export_range(0.5, 5.0) var stagger_sway_frequency: float = 1.5
## Perpendicular drift amount relative to primary sway. 0.0 = straight back-and-forth,
## 1.0 = equal perpendicular wobble (figure-8 pattern).
@export_range(0.0, 1.0) var stagger_sway_drift: float = 0.4
## Upper body twist intensity relative to sway force.
## 0.0 = no independent twist. Higher = more visible torso rotation.
@export_range(0.0, 0.5) var stagger_sway_twist: float = 0.15
## Frequency ratio for secondary oscillation (perpendicular drift).
## Irrational values (1.73, 2.37) prevent repeating patterns. Integer values create synchronized wobble.
@export_range(0.5, 5.0) var stagger_sway_secondary_ratio: float = 1.73
## Frequency ratio for upper body twist oscillation.
@export_range(0.5, 5.0) var stagger_sway_twist_ratio: float = 2.17
## Spine force/torque as fraction of Hips force. Lower = less spine involvement.
@export_range(0.0, 1.0) var stagger_sway_spine_falloff: float = 0.7
## Chest force/torque as fraction of Hips force. Lower = less chest involvement.
@export_range(0.0, 1.0) var stagger_sway_chest_falloff: float = 0.5
## Multiplier on ragdoll_probability when hit during active stagger.
@export_range(1.0, 5.0) var stagger_ragdoll_bonus: float = 1.5
## Extra strength ratio applied to brace-side bones during stagger.
## Creates asymmetric "fighting to stay up" posture. 0.0 = disabled (symmetric wobble).
@export_range(0.0, 0.5) var brace_strength_bonus: float = 0.25
## How much of a sub-stagger hit's strength_reduction becomes a visible pulse.
## Higher = light hits produce more visible jolt. 0.0 = disabled.
@export_range(0.0, 1.0) var reaction_pulse_strength: float = 0.6
## Duration of the reaction pulse in seconds.
@export_range(0.05, 0.5) var reaction_pulse_duration: float = 0.2
## Center-of-mass balance ratio above which a hit triggers stagger (even if
## average spring strength is still above stagger_threshold).
## 0.0 = disabled. Higher = harder to trigger stagger from balance alone.
@export_range(0.0, 1.0) var balance_stagger_threshold: float = 0.5
## Balance ratio above this during stagger forces ragdoll (character is tipping over).
@export_range(0.0, 1.0) var balance_ragdoll_threshold: float = 0.85
## Balance ratio below this during stagger allows early recovery (character regained balance).
@export_range(0.0, 1.0) var balance_recovery_threshold: float = 0.3
## How long balance must stay below recovery threshold before stagger ends.
@export_range(0.0, 1.0) var balance_recovery_hold_time: float = 0.5
## Pain accumulated per hit, scaled by effective strength_reduction.
## Pain deterministically escalates reactions (supplements random ragdoll_probability).
## 0.0 = disabled (dice-roll only).
@export_range(0.0, 1.0) var pain_gain: float = 0.2
## Pain decay per second when not being hit.
@export_range(0.0, 1.0) var pain_decay: float = 0.15
## Pain level above which a hit forces stagger (even if strength is high). 0.0 = disabled.
@export_range(0.0, 1.0) var pain_stagger_threshold: float = 0.5
## Pain level above which a hit forces ragdoll. 0.0 = disabled.
@export_range(0.0, 1.0) var pain_ragdoll_threshold: float = 0.9
## Pulse intensity for threat anticipation (pre-hit flinch). 0.0 = disabled.
@export_range(0.0, 1.0) var threat_anticipation_strength: float = 0.4
## Minimum speed (m/s) before movement instability bonus applies.
@export var movement_instability_min_speed: float = 1.0
## Speed (m/s) at which movement instability bonus is fully applied.
@export var movement_instability_max_speed: float = 5.0
## Extra strength reduction when moving at max speed (e.g., 0.3 = 30% more).
@export_range(0.0, 1.0) var movement_instability_bonus: float = 0.3
## How much movement direction blends into stagger direction (0.0 = pure hit dir, 1.0 = pure movement dir).
@export_range(0.0, 1.0) var movement_stagger_blend: float = 0.3
## Overall intensity of micro-reactions (torso bend, head whip, spin) at impact moment.
## 0.0 = disabled. Higher = more visible immediate reaction.
@export_range(0.0, 2.0) var micro_reaction_strength: float = 0.5
## Head whip torque multiplier. Head gets pushed in hit direction.
@export_range(0.0, 5.0) var micro_head_whip_strength: float = 2.0
## Torso bend torque multiplier. Spine/Chest bend away from hit.
@export_range(0.0, 5.0) var micro_torso_bend_strength: float = 1.5
## Spin torque multiplier for high-caliber hits (base_impulse > 10). Twists the torso.
@export_range(0.0, 5.0) var micro_spin_strength: float = 1.0
## Injury accumulated per significant hit, scaled by reduction. Injuries persist
## much longer than spring strength and cause functional impairment (limp, dangle).
## 0.0 = disabled.
@export_range(0.0, 1.0) var injury_gain: float = 0.15
## Injury decay per second. Much slower than fatigue — injuries linger.
@export_range(0.0, 0.2) var injury_decay: float = 0.02
## Minimum strength_reduction to cause injury. Light hits don't injure.
@export_range(0.0, 1.0) var injury_threshold: float = 0.3
## How much injury reduces effective base spring strength (per bone).
@export_range(0.0, 1.0) var injury_impact: float = 0.4
## How much injury reduces pin strength (position tracking). Injured legs sag.
@export_range(0.0, 1.0) var injury_pin_impact: float = 0.7

# ── Spring Strengths ────────────────────────────────────────────────────────

@export_group("Spring Strengths")
## Per-bone base spring strength. Keys are rig names (e.g. "Hips": 0.65).
## Bones not listed use default_spring_strength. Higher = stiffer tracking.
@export var strength_map: Dictionary = {
	"Hips": 0.65, "Spine": 0.60, "Chest": 0.60,
	"Head": 0.35,
	"UpperArm_L": 0.45, "LowerArm_L": 0.40, "Hand_L": 0.25,
	"UpperArm_R": 0.45, "LowerArm_R": 0.40, "Hand_R": 0.25,
	"UpperLeg_L": 0.55, "LowerLeg_L": 0.45, "Foot_L": 0.30,
	"UpperLeg_R": 0.55, "LowerLeg_R": 0.45, "Foot_R": 0.30,
}
## Fallback spring strength for bones not in strength_map.
@export var default_spring_strength: float = 0.25

@export_group("Pin Strengths")
## Per-bone position tracking strength. Keys are rig names (e.g. "Hips": 0.85).
## Bones not listed use default_pin_strength. Hips + feet keep character planted.
@export var pin_strength_overrides: Dictionary = {
	"Hips": 0.85,
	"Foot_L": 0.4,
	"Foot_R": 0.4,
}
## Fallback pin strength for bones not in pin_strength_overrides.
@export var default_pin_strength: float = 0.1

# ── Recovery ────────────────────────────────────────────────────────────────

@export_group("Recovery")
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
## Fraction of recovery_duration that must elapse before early completion is allowed.
@export_range(0.5, 1.0) var recovery_completion_threshold: float = 0.95
## Maximum rotation error (radians) for recovery to complete early.
@export_range(0.1, 1.0) var recovery_rotation_threshold: float = 0.3
## Per-bone staggered recovery delay in seconds. Keys are rig names.
## Core bones recover first, extremities follow.
@export var ramp_delay: Dictionary = {
	"Hips": 0.0, "Spine": 0.0, "Chest": 0.05,
	"Head": 0.25,
	"UpperArm_L": 0.2, "LowerArm_L": 0.25, "Hand_L": 0.3,
	"UpperArm_R": 0.2, "LowerArm_R": 0.25, "Hand_R": 0.3,
	"UpperLeg_L": 0.1, "LowerLeg_L": 0.15, "Foot_L": 0.2,
	"UpperLeg_R": 0.1, "LowerLeg_R": 0.15, "Foot_R": 0.2,
}
## Per-bone minimum strength floor. Keys are rig names.
## Prevents bones from being fully zeroed by hits.
@export var min_strength: Dictionary = {
	"Hips": 0.15, "Spine": 0.10, "Chest": 0.10,
	"UpperLeg_L": 0.10, "UpperLeg_R": 0.10,
	"LowerLeg_L": 0.08, "LowerLeg_R": 0.08,
	"Foot_L": 0.05, "Foot_R": 0.05,
}

# ── Fatigue & Hit Stacking ──────────────────────────────────────────────────

@export_group("Fatigue & Hit Stacking")
## How much fatigue each hit adds, scaled by the hit's strength_reduction.
## Higher = faster fatigue buildup from repeated hits.
@export_range(0.0, 1.0) var fatigue_gain: float = 0.15
## How fast fatigue decays per second when not being hit.
## Lower = fatigue lingers longer between engagements.
@export_range(0.0, 1.0) var fatigue_decay: float = 0.05
## How much fatigue reduces effective base spring strength.
## At fatigue_impact=0.5 and fatigue=1.0, springs recover to 50% of base.
@export_range(0.0, 1.0) var fatigue_impact: float = 0.5
## Time window (seconds) within which consecutive hits count as rapid fire.
@export_range(0.05, 1.0) var rapid_fire_window: float = 0.3
## Extra strength reduction per streak hit (e.g., 0.3 = 30% more per consecutive hit).
@export_range(0.0, 1.0) var hit_streak_multiplier: float = 0.3
## Minimum effective strength_reduction to interrupt GETTING_UP and force re-ragdoll.
## Set to 2.0 to effectively disable recovery interruption.
@export_range(0.0, 2.0) var recovery_interrupt_threshold: float = 0.5

# ── Protected Bones ─────────────────────────────────────────────────────────

@export_group("Protected Bones")
## Bones that stay animated during hits and stagger. Their spring strength
## is never reduced by impacts. Useful for keeping legs planted while the
## upper body reacts. During full ragdoll, all bones still go limp.
@export var protected_bones: PackedStringArray = []

# ── Collision ───────────────────────────────────────────────────────────────

@export_group("Collision")
## Physics collision layer for ragdoll bodies.
@export_flags_3d_physics var collision_layer: int = 8
## Physics collision mask for ragdoll bodies.
@export_flags_3d_physics var collision_mask: int = 14

# ── Advanced: Spring Dynamics ───────────────────────────────────────────────

@export_group("Advanced: Spring Dynamics")
## Gravity multiplier when springs are active. Formula: (1 - ratio) * multiplier.
## Higher = more gravity pull on weakened bones. 0.0 = no gravity during spring mode.
@export var spring_gravity_multiplier: float = 0.5
## Base angular damping when springs are active. Formula: base + scale * ratio.
@export var spring_angular_damp_base: float = 1.0
## Angular damping scale factor per strength ratio.
@export var spring_angular_damp_scale: float = 2.0
## Base linear damping when springs are active. Formula: base + scale * ratio.
@export var spring_linear_damp_base: float = 0.5
## Linear damping scale factor per strength ratio.
@export var spring_linear_damp_scale: float = 1.5
## Extra angular damping added in passive tracking mode (springs inactive).
@export var spring_passive_angular_damp_offset: float = 5.0
## Extra linear damping added in passive tracking mode (springs inactive).
@export var spring_passive_linear_damp_offset: float = 3.0

# ── Advanced: Directional Bracing ───────────────────────────────────────────

@export_group("Advanced: Directional Bracing")
## Bones that receive a core resistance boost during directional bracing.
## These resist torso rotation on stagger entry.
@export var core_bracing_bones: PackedStringArray = PackedStringArray(["Hips", "Spine", "Chest"])
## Dot product threshold for classifying bones as hit-side or brace-side.
## Bones with dot > threshold are hit-side; dot < -threshold are brace-side.
@export_range(0.0, 0.5) var bracing_direction_threshold: float = 0.1
## Extra reduction multiplier applied to hit-side bones during stagger.
## Higher = hit-side bones weaken more relative to the stagger floor.
@export_range(0.0, 1.0) var bracing_hit_side_multiplier: float = 0.3

# ── Advanced: Active Resistance ───────────────────────────────────────────

@export_group("Advanced: Active Resistance")
## How strongly counter-side bones stiffen against the imbalance direction.
## Higher = more aggressive counter-lean. 0.0 disables active resistance entirely.
@export_range(0.0, 1.0) var resistance_counter_strength: float = 0.40
## How much core bones (Hips/Spine/Chest) ramp toward effective base as balance worsens.
@export_range(0.0, 1.0) var resistance_core_ramp: float = 0.40
## Strength boost for the load-bearing leg on the fall side.
@export_range(0.0, 1.0) var resistance_leg_brace: float = 0.35
## Extra resistance multiplier when center-of-mass velocity is high (reflexive tensing).
@export_range(0.0, 2.0) var resistance_velocity_spike: float = 1.0
## CoM speed (m/s) at which velocity spike reaches full effect.
@export_range(0.5, 5.0) var resistance_velocity_scale: float = 2.0

# ── Advanced: Physics ───────────────────────────────────────────────────────

@export_group("Advanced: Physics")
## Gravity scale for ragdoll bodies when springs are inactive (full ragdoll).
@export var gravity_scale: float = 0.8
## Angular damping for ragdoll bodies when springs are inactive.
@export var angular_damp: float = 8.0
## Linear damping for ragdoll bodies when springs are inactive.
@export var linear_damp: float = 2.0
## Gravity scale for ragdoll bodies when springs are driving them.
@export var spring_active_gravity: float = 0.0
## Angular damping when springs are active (used for passive tracking base).
@export var spring_active_angular_damp: float = 3.0
## Linear damping when springs are active (used for passive tracking base).
@export var spring_active_linear_damp: float = 2.0
## Maximum angular velocity for spring-driven bodies.
@export var max_angular_velocity: float = 20.0
## Maximum linear velocity for spring-driven bodies.
@export var max_linear_velocity: float = 10.0
## Transfer the character's movement velocity to ragdoll bodies on ragdoll entry.
## Disable for enemies walking toward the player to prevent forward-launching.
@export var transfer_character_velocity: bool = true
## Scale factor for velocity transfer (0.0–1.0). Only used when transfer is enabled.
@export_range(0.0, 1.0) var velocity_transfer_scale: float = 1.0
## How long bodies must be below velocity thresholds to count as settled.
@export var settle_duration: float = 0.6
## Linear velocity threshold for settle detection.
@export var settle_linear_threshold: float = 0.5
## Angular velocity threshold for settle detection.
@export var settle_angular_threshold: float = 0.3
## Minimum support radius for balance calculation (prevents division artifacts
## when feet are very close together).
@export var balance_support_radius_min: float = 0.1
## Maximum balance ratio value (clamp). Values above 1.0 mean the CoM is
## outside the support polygon.
@export var balance_max_ratio: float = 1.5

# ── Advanced: Ground & Root Motion ──────────────────────────────────────────

@export_group("Advanced: Ground & Root Motion")
## Collision mask for ground raycasts during get-up recovery.
## Defaults to layer 1 (world geometry in standard Godot projects).
@export_flags_3d_physics var ground_raycast_mask: int = 1
## Whether to align the character root to the ground slope during recovery.
@export var align_to_slope: bool = false
## Raycast origin offset above the hip position (meters).
@export var ground_raycast_up_offset: float = 1.0
## Raycast distance below the hip position (meters).
@export var ground_raycast_down_distance: float = 3.0
## Ground normal must have this dot product with UP to count as a slope.
@export_range(0.0, 1.0) var slope_alignment_threshold: float = 0.5
## Strip horizontal (XZ) root motion from the root bone's animation pose.
## Prevents drift when using animations with root motion (e.g., Mixamo).
@export var strip_root_motion: bool = true
## Rig name of the root bone whose root motion should be stripped.
@export var root_motion_bone: String = "Hips"


# ── Foot IK ─────────────────────────────────────────────────────────────────

@export_group("Foot IK")
## Enable foot IK to plant feet on uneven terrain during NORMAL state.
## When enabled, a foot IK solver adjusts leg targets based on ground raycasts.
@export var foot_ik_enabled: bool = true
## Distance from ankle joint center to the bottom of the foot sole (meters).
## Offsets the IK target upward so feet don't sink into the ground.
@export_range(0.0, 0.2) var foot_ik_ankle_height: float = 0.065
## Maximum distance the pelvis can drop to accommodate the lowest foot (meters).
## Prevents unrealistic leg stretching when one foot is much lower than the other.
@export_range(0.0, 1.0) var foot_ik_max_pelvis_drop: float = 0.35
## Maximum vertical foot correction per foot (meters).
## Limits how far a foot can be adjusted from its animation position.
@export_range(0.0, 1.0) var foot_ik_max_adjustment: float = 0.5
## Foot height above character root beyond which the foot is in swing phase.
## During swing, IK weight ramps to 0 to allow free animation movement.
@export_range(0.1, 0.5) var foot_ik_swing_threshold: float = 0.25
## Foot height above character root below which the foot is fully planted.
## Between this and swing_threshold, IK weight blends gradually.
@export_range(0.05, 0.3) var foot_ik_plant_threshold: float = 0.17
## Smoothing speed for pelvis height adjustment (higher = faster response).
## Uses exponential damping: lerp(current, target, 1 - exp(-speed * delta)).
@export_range(1.0, 30.0) var foot_ik_pelvis_blend_speed: float = 8.0
## Smoothing speed for per-foot IK weight transitions (higher = faster blend).
@export_range(1.0, 30.0) var foot_ik_foot_blend_speed: float = 10.0
## Extra height above the hip joint to start ground raycasts (meters).
## Ensures rays start above the character to detect ground reliably.
@export_range(0.0, 1.0) var foot_ik_ray_above_hip: float = 0.3
## Distance below ray origin to cast for ground detection (meters).
@export_range(1.0, 5.0) var foot_ik_ray_below_hip: float = 2.5
## Physics collision layers used for foot IK ground raycasts.
## Must include layers that your terrain/ground uses.
@export_flags_3d_physics var foot_ik_collision_mask: int = 1


## Creates a RagdollTuning with standard defaults. Equivalent to RagdollTuning.new()
## since all property defaults are pre-populated.
static func create_default() -> RagdollTuning:
	return RagdollTuning.new()


## Creates a RagdollTuning for fast-paced action games with amplified reactions.
## Increases micro-reaction intensity, sway force, and pain escalation
## for more visible hit feedback compared to the realistic defaults.
static func create_game_default() -> RagdollTuning:
	var t := RagdollTuning.new()
	t.micro_reaction_strength = 1.2
	t.micro_head_whip_strength = 3.5
	t.micro_torso_bend_strength = 2.5
	t.micro_spin_strength = 2.0
	t.stagger_sway_strength = 600.0
	t.reaction_pulse_strength = 0.9
	t.stagger_duration = 1.2
	t.pain_gain = 0.35
	return t


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

	for bone_name: String in core_bracing_bones:
		if bone_name not in valid_names:
			warnings.append("core_bracing_bones entry '%s' not found in profile rig names" % bone_name)

	if foot_ik_enabled:
		for foot_name in ["Foot_L", "Foot_R", "UpperLeg_L", "UpperLeg_R", "LowerLeg_L", "LowerLeg_R"]:
			if foot_name not in valid_names:
				warnings.append("foot_ik requires '%s' in profile but not found" % foot_name)

	return warnings
