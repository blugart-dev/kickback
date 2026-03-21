# Technical Reference

## Spring resolver (velocity-based)

For each RigidBody3D bone, every `_physics_process(delta)`:

```gdscript
# 1. Get target rotation from animation skeleton
# Note: actual code uses get_bone_pose() + parent walk-up instead of get_bone_global_pose()
# because get_bone_global_pose() can return stale data (see GODOT_CONSTRAINTS.md).
var target_xform = anim_skeleton.global_transform * get_animation_bone_global(anim_bone_idx)
var current_xform = rigid_body.global_transform

# 2. Compute rotation error as axis-angle
var error_quat = (target_xform.basis * current_xform.basis.inverse()).get_rotation_quaternion()
if error_quat.w < 0:
    error_quat = -error_quat  # Ensure shortest path

var angle = 2.0 * acos(clampf(error_quat.w, -1.0, 1.0))
var axis_raw = Vector3(error_quat.x, error_quat.y, error_quat.z)
var axis = axis_raw.normalized() if axis_raw.length_squared() > 0.0001 else Vector3.UP

var angular_error = axis * angle

# 3. Compute target angular velocity and lerp toward it
var target_angular_vel = angular_error / delta
rigid_body.angular_velocity = rigid_body.angular_velocity.lerp(target_angular_vel, strength)
```

For hips (position pinning):
```gdscript
var pos_error = target_xform.origin - current_xform.origin
rigid_body.linear_velocity = rigid_body.linear_velocity.lerp(pos_error / delta, pin_strength)
```

`strength` is the key parameter: 0.0 = pure ragdoll, 1.0 = perfect tracking.
`pin_strength` should be lower than rotational strength (0.2-0.3) to prevent floating.

## Center of mass balance ratio

Computes how off-balance the character is by comparing the mass-weighted center
of mass to the support polygon (midpoint between feet):

```gdscript
# Center of mass: mass-weighted average of all body positions
var com := Vector3.ZERO
var total_mass := 0.0
for body in bodies.values():
    com += body.global_position * body.mass
    total_mass += body.mass
com /= total_mass

# Support polygon: midpoint between feet on XZ plane
var support_center := (foot_l.global_position + foot_r.global_position) * 0.5
var foot_spread := foot_l.global_position.distance_to(foot_r.global_position)
var support_radius := maxf(foot_spread * 0.5, 0.1)

# Distance of CoM projection from support center on XZ plane
var offset := Vector2(com.x, com.z).distance_to(Vector2(support_center.x, support_center.z))

# 0.0 = perfectly balanced, 1.0 = edge of support, >1.0 = outside support
var balance_ratio := clampf(offset / support_radius, 0.0, 1.5)
```

Used by `ActiveRagdollController` to drive stagger behavior:
- `balance > balance_ragdoll_threshold (0.85)` → forced ragdoll (tipping over)
- `balance < balance_recovery_threshold (0.3)` for `balance_recovery_hold_time (0.3s)` → early stagger recovery
- `balance > balance_stagger_threshold (0.5)` on hit → triggers stagger independently of spring strength

## Per-bone strength values

| Region        | Bones                                  | Strength | Pin  | Notes                    |
|---------------|----------------------------------------|----------|------|--------------------------|
| Core          | Hips                                   | 0.65     | 0.85 | Highest — anchors body   |
| Core          | Spine, Chest                           | 0.60     | 0.1  | Torso stability          |
| Head          | Head                                   | 0.35     | 0.1  | Reacts freely to hits    |
| Upper Arms    | UpperArm_L/R                           | 0.45     | 0.1  | Arms swing on hit        |
| Lower Arms    | LowerArm_L/R                           | 0.40     | 0.1  | Medium tracking          |
| Hands         | Hand_L/R                               | 0.25     | 0.1  | Loose hands look natural |
| Upper Legs    | UpperLeg_L/R                           | 0.55     | 0.1  | Support weight           |
| Lower Legs    | LowerLeg_L/R                           | 0.45     | 0.1  | Medium                   |
| Feet          | Foot_L/R                               | 0.30     | 0.4  | Foot planting            |

## Bone list for physics rig (Step 3)

16 RigidBody3D bodies, 15 Generic6DOFJoint3D connections:

```
Hips (root, no parent joint)
├── Spine          (joint → Hips)
│   └── Chest      (joint → Spine)
│       ├── Head       (joint → Chest, optionally via Neck)
│       ├── UpperArm_L (joint → Chest)
│       │   └── LowerArm_L (joint → UpperArm_L)
│       │       └── Hand_L    (joint → LowerArm_L)
│       └── UpperArm_R (joint → Chest)
│           └── LowerArm_R (joint → UpperArm_R)
│               └── Hand_R    (joint → LowerArm_R)
├── UpperLeg_L (joint → Hips)
│   └── LowerLeg_L (joint → UpperLeg_L)
│       └── Foot_L    (joint → LowerLeg_L)
└── UpperLeg_R (joint → Hips)
    └── LowerLeg_R (joint → UpperLeg_R)
        └── Foot_R    (joint → LowerLeg_R)
```

## Mass distribution (kg)

| Bone       | Mass | Shape             | Approximate dimensions       |
|------------|------|-------------------|------------------------------|
| Hips       | 15   | BoxShape3D        | 0.30 × 0.15 × 0.20          |
| Spine      | 10   | BoxShape3D        | 0.25 × 0.15 × 0.15          |
| Chest      | 12   | BoxShape3D        | 0.30 × 0.20 × 0.20          |
| Head       | 5    | SphereShape3D     | radius 0.10                  |
| UpperArm   | 3    | CapsuleShape3D    | radius 0.04, height 0.28     |
| LowerArm   | 2    | CapsuleShape3D    | radius 0.035, height 0.25    |
| Hand       | 1    | BoxShape3D        | 0.08 × 0.03 × 0.10          |
| UpperLeg   | 8    | CapsuleShape3D    | radius 0.06, height 0.40     |
| LowerLeg   | 4    | CapsuleShape3D    | radius 0.045, height 0.38    |
| Foot       | 2    | BoxShape3D        | 0.10 × 0.05 × 0.22          |

## Joint angular limits (degrees)

| Joint             | X (flexion)     | Y (twist)      | Z (lateral)    |
|-------------------|-----------------|----------------|----------------|
| Hips→Spine        | -30 to 30       | -30 to 30      | -20 to 20      |
| Spine→Chest       | -30 to 30       | -30 to 30      | -20 to 20      |
| Chest→Head        | -60 to 60       | -70 to 70      | -45 to 45      |
| Chest→UpperArm    | -90 to 90       | -90 to 90      | -90 to 90      |
| UpperArm→LowerArm | 0 to 150        | -10 to 10      | -10 to 10      |
| LowerArm→Hand     | -60 to 60       | -30 to 30      | -80 to 80      |
| Hips→UpperLeg     | -90 to 90       | -30 to 30      | -45 to 45      |
| UpperLeg→LowerLeg | -150 to 0       | -10 to 10      | -10 to 10      |
| LowerLeg→Foot     | -45 to 45       | -20 to 20      | -30 to 30      |

Note: "0 to 150" for elbows/knees means they can only bend one way. Tune in-engine
with Debug → Visible Collision Shapes.

## Impact profiles

### ImpactProfile resource properties

```gdscript
class_name ImpactProfile extends Resource

@export var profile_name: StringName = &""
@export_range(0.0, 100.0) var base_impulse: float = 8.0           # Force applied to hit body
@export_range(0.0, 1.0) var impulse_transfer_ratio: float = 0.3   # Fraction transferred
@export_range(0.0, 1.0) var upward_bias: float = 0.0              # Extra upward force
@export_range(0.0, 1.0) var ragdoll_probability: float = 0.0      # Chance of full ragdoll
@export_range(0.0, 1.0) var strength_reduction: float = 0.4       # Spring strength drop on hit
@export_range(0, 10) var strength_spread: int = 1                  # Neighbor bones affected
@export_range(0.0, 5.0) var recovery_rate: float = 1.0            # Strength recovery per second
```

Factory methods: `ImpactProfile.create_bullet()`, `.create_shotgun()`, `.create_explosion()`, `.create_melee()`, `.create_arrow()`

Presets shipped in `addons/kickback/presets/`.

### Preset values

| Profile   | impulse | transfer | upward | ragdoll_prob | str_reduc | str_spread | recovery |
|-----------|---------|----------|--------|--------------|-----------|------------|----------|
| Bullet    | 8       | 0.15     | 0.0    | 0.05         | 0.85      | 1          | 0.4      |
| Shotgun   | 20      | 0.40     | 0.05   | 0.40         | 0.92      | 3          | 0.25     |
| Explosion | 40      | 1.00     | 0.40   | 0.95         | 1.0       | 99         | 0.15     |
| Melee     | 15      | 0.60     | 0.0    | 0.15         | 0.88      | 2          | 0.3      |
| Arrow     | 12      | 0.30     | 0.0    | 0.10         | 0.88      | 1          | 0.3      |

### Impulse calculation

```gdscript
var final_impulse = profile.base_impulse * profile.impulse_transfer_ratio
var direction = (hit_direction + Vector3.UP * profile.upward_bias).normalized()
body.apply_impulse(direction * final_impulse, local_hit_offset)
```

### Strength reduction on hit

```gdscript
func reduce_strength(hit_bone: StringName, profile: ImpactProfile):
    # Hit bone: full reduction
    bones[hit_bone].strength *= (1.0 - profile.strength_reduction)

    # Neighbors: reduction with distance falloff
    for i in range(profile.strength_spread):
        var falloff = 1.0 - (float(i + 1) / float(profile.strength_spread + 1))
        for neighbor in get_neighbors_at_distance(hit_bone, i + 1):
            bones[neighbor].strength *= (1.0 - profile.strength_reduction * falloff)
```

### Strength recovery

```gdscript
# Every _physics_process:
for bone in bones.values():
    bone.strength = move_toward(bone.strength, bone.base_strength, profile.recovery_rate * delta)
```

## Fatigue system

Repeated hits accumulate fatigue that degrades effective spring strength ceiling.
Fatigued characters recover to lower maxes and wobble more at baseline.

```gdscript
# On each hit:
_fatigue = clampf(_fatigue + profile.strength_reduction * tuning.fatigue_gain, 0.0, 1.0)

# Effective base strength (used everywhere instead of raw base):
func _effective_base_strength(rig_name) -> float:
    var base = spring.get_base_strength(rig_name)
    var fatigue_factor = 1.0 - _fatigue * tuning.fatigue_impact      # 0.5 default
    var injury_factor = 1.0 - injuries[rig_name] * tuning.injury_impact  # 0.4 default
    return base * fatigue_factor * injury_factor

# Decay per second when not hit:
_fatigue = move_toward(_fatigue, 0.0, tuning.fatigue_decay * delta)  # 0.05/s default
```

| Parameter | Default | Effect |
|-----------|---------|--------|
| `fatigue_gain` | 0.15 | Fatigue added per hit (scaled by strength_reduction) |
| `fatigue_decay` | 0.05/s | Recovery rate (~20s full recovery) |
| `fatigue_impact` | 0.5 | How much fatigue reduces effective base (50% at max) |

Signal: `fatigue_changed(level: float)` — emitted when fatigue changes.
API: `get_fatigue() -> float`, `reset_fatigue()`.

## Pain system

Cumulative pain deterministically escalates reactions instead of relying on dice rolls.
Sustained fire reliably progresses: flinch → stagger → ragdoll.

```gdscript
# On each hit:
_pain = clampf(_pain + effective_reduction * tuning.pain_gain, 0.0, 1.0)

# Thresholds (checked in apply_hit):
if _pain >= tuning.pain_ragdoll_threshold:   # 0.9 — force ragdoll
elif _pain >= tuning.pain_stagger_threshold: # 0.5 — force stagger

# Decay:
_pain = move_toward(_pain, 0.0, tuning.pain_decay * delta)  # 0.15/s default
```

| Parameter | Default | Effect |
|-----------|---------|--------|
| `pain_gain` | 0.2 | Pain added per hit (scaled by effective reduction) |
| `pain_decay` | 0.15/s | Pain recovery rate |
| `pain_stagger_threshold` | 0.5 | Forces stagger regardless of strength |
| `pain_ragdoll_threshold` | 0.9 | Forces ragdoll regardless of probability |

Signal: `pain_changed(level: float)`. API: `get_pain() -> float`, `reset_pain()`.

## Hit stacking

Rapid consecutive hits escalate via streak multiplier.

```gdscript
# Track streak (within rapid_fire_window of 0.3s):
if time_since_last_hit < tuning.rapid_fire_window:
    _hit_streak += 1
else:
    _hit_streak = 1

# Escalation:
var streak_multiplier = 1.0 + (_hit_streak * tuning.hit_streak_multiplier)  # 0.3 default
effective_reduction = profile.strength_reduction * streak_multiplier
```

Hits during GETTING_UP above `recovery_interrupt_threshold` (0.5) abort recovery
and re-ragdoll. Signal: `recovery_interrupted()`. API: `get_hit_streak() -> int`.

## Movement-aware instability

Moving characters are less stable and stagger more easily.

```gdscript
var speed = character_velocity.length()
var speed_ratio = clampf(
    (speed - tuning.movement_instability_min_speed) /
    (tuning.movement_instability_max_speed - tuning.movement_instability_min_speed),
    0.0, 1.0)
var movement_multiplier = 1.0 + speed_ratio * tuning.movement_instability_bonus  # 0.3 max

# Applied to effective_reduction:
effective_reduction *= movement_multiplier

# Stagger direction blends with movement:
hit_dir = hit_dir.lerp(char_vel.normalized(), tuning.movement_stagger_blend)  # 0.3
```

| Parameter | Default | Effect |
|-----------|---------|--------|
| `movement_instability_min_speed` | 1.0 m/s | Below this, no instability |
| `movement_instability_max_speed` | 5.0 m/s | Full instability at this speed |
| `movement_instability_bonus` | 0.3 | Max extra reduction (30%) |
| `movement_stagger_blend` | 0.3 | Stagger direction blend with velocity |

## Injury system

Persistent per-bone damage that outlasts spring recovery. Injured bones have
reduced effective strength and reduced pin strength (visible sag/limp).

```gdscript
# On significant hit (effective_reduction > injury_threshold):
injuries[rig_name] += effective_reduction * tuning.injury_gain  # 0.15 default

# Effects on springs:
effective_base *= (1.0 - injury * tuning.injury_impact)     # 0.4 — reduces spring ceiling
pin *= (1.0 - injury * tuning.injury_pin_impact)             # 0.7 — reduces position tracking

# Very slow decay:
injury = move_toward(injury, 0.0, tuning.injury_decay * delta)  # 0.02/s
```

| Parameter | Default | Effect |
|-----------|---------|--------|
| `injury_gain` | 0.15 | Injury per hit (scaled by reduction) |
| `injury_decay` | 0.02/s | Very slow recovery (~50s) |
| `injury_threshold` | 0.3 | Minimum hit strength to cause injury |
| `injury_impact` | 0.4 | Effective base strength reduction per injury |
| `injury_pin_impact` | 0.7 | Pin strength reduction (visible sag) |

Signal: `region_injured(rig_name: String, severity: float)`.
API: `get_injury(rig_name) -> float`, `get_all_injuries() -> Dictionary`, `reset_injuries()`.

## Micro-reactions

Immediate torque impulses at the moment of impact for visceral feedback.

```gdscript
# On hit, applied to specific bones:
# Head: whip in hit direction
head_body.apply_torque_impulse(hit_dir.cross(Vector3.UP) * micro_head_whip_strength)
# Spine/Chest: bend away from hit
torso_body.apply_torque_impulse(-hit_dir.cross(Vector3.UP) * micro_torso_bend_strength)
# High-caliber (base_impulse > 10): spin twist
torso_body.apply_torque_impulse(Vector3.UP * micro_spin_strength)
```

| Parameter | Default | Effect |
|-----------|---------|--------|
| `micro_reaction_strength` | 0.5 | Overall multiplier (0.0 = disabled) |
| `micro_head_whip_strength` | 2.0 | Head whip torque |
| `micro_torso_bend_strength` | 1.5 | Torso bend torque |
| `micro_spin_strength` | 1.0 | Spin twist for heavy hits |

## Threat anticipation

Pre-hit defensive flinch. Call when bullets fly nearby or an enemy winds up.

```gdscript
# API:
kickback_character.anticipate_threat(threat_direction, urgency)  # urgency 0.0-1.0

# Effect: finds bone closest to threat direction, applies reaction pulse
# Only works in NORMAL state (not during stagger/ragdoll)
```

| Parameter | Default | Effect |
|-----------|---------|--------|
| `threat_anticipation_strength` | 0.4 | Pulse intensity for anticipation |

Signal: `threat_anticipated(direction: Vector3, urgency: float)`.

## Directional bracing

Applied once at stagger entry. Classifies bones by their XZ position relative
to Hips vs hit direction. Creates asymmetric "fighting to stay up" posture.

```gdscript
# For each bone, compute dot product of (bone_offset from hips) with (hit_dir on XZ):
var dot = bone_offset.normalized().dot(hit_xz)

if bone in core_bracing_bones:  # ["Hips", "Spine", "Chest"]
    # Core resistance: boosted above floor
    strength = effective_base * (floor_ratio + brace_bonus * 0.5)
elif dot > bracing_direction_threshold:  # 0.1
    # Hit side: weakened further below floor
    strength = effective_base * floor_ratio * (1.0 - dot * bracing_hit_side_multiplier)
elif dot < -bracing_direction_threshold:
    # Brace side: strengthened above floor
    strength = effective_base * (floor_ratio + brace_bonus * abs(dot))
```

| Parameter | Default | Effect |
|-----------|---------|--------|
| `brace_strength_bonus` | 0.25 | Extra strength on brace-side bones |
| `bracing_direction_threshold` | 0.1 | Dot product threshold for classification |
| `bracing_hit_side_multiplier` | 0.3 | Extra weakening on hit-side bones |
| `core_bracing_bones` | ["Hips", "Spine", "Chest"] | Always-braced bones |

## Active Resistance

Dynamic per-frame spring adjustment during stagger. Three components run every
physics frame, scaling with `balance_ratio` and degrading with fatigue:

**1. Counter-imbalance stiffening**: Bones opposite the CoM drift direction stiffen.
```gdscript
var counter_dot = -bone_offset.normalized().dot(imbalance_dir)
boost += max(0, counter_dot) * balance_ratio * resistance_counter_strength * capacity
```

**2. Core progressive engagement**: Hips/Spine/Chest ramp toward effective base.
```gdscript
var core_urgency = clampf(balance_ratio / balance_ragdoll_threshold, 0.0, 1.0)
boost += core_urgency * resistance_core_ramp * capacity
```

**3. Load-bearing leg bracing**: Leg on the fall side stiffens as a pillar.
```gdscript
boost += balance_ratio * resistance_leg_brace * capacity
```

All boosts multiplied by velocity spike: `1.0 + clamp(com_speed / velocity_scale) * velocity_spike`.
Clamped to `effective_base_strength` ceiling. Only increases strength, never weakens.

| Parameter | Default | Effect |
|-----------|---------|--------|
| `resistance_counter_strength` | 0.40 | Counter-lean intensity |
| `resistance_core_ramp` | 0.40 | Core engagement intensity |
| `resistance_leg_brace` | 0.35 | Load-bearing leg boost |
| `resistance_velocity_spike` | 1.0 | Multiplier on fast CoM sway (up to 2x) |
| `resistance_velocity_scale` | 2.0 m/s | CoM speed for full velocity spike |

## Stagger sway force

Continuous oscillating force on core bones during stagger. Springs fight this
force, producing visible wobble. Without it, the initial hit impulse dissipates
in 2-3 frames and the character snaps back to animation pose.

**Organic sway** uses layered oscillation at irrational frequency ratios
(never repeats), perpendicular drift for figure-8 wobble, independent upper body
twist torque, and per-stagger random phase offset.

```gdscript
var osc_primary = sin(t * freq * TAU)
var osc_secondary = sin(t * freq * secondary_ratio * TAU) * drift
var perp = hit_dir.cross(Vector3.UP).normalized()
var force = (hit_dir * osc_primary + perp * osc_secondary) * sway_strength * decay

hips.apply_central_force(force)
spine.apply_central_force(force * spine_falloff)
chest.apply_central_force(force * chest_falloff)

# Upper body twist (independent rotation):
var twist = sin(t * freq * twist_ratio * TAU)
var torque = Vector3.UP * sway_strength * twist * decay * sway_twist
spine.apply_torque(torque)
chest.apply_torque(torque * chest_falloff)
```

| Parameter | Default | Effect |
|-----------|---------|--------|
| `stagger_sway_strength` | 300 N | Force magnitude (0 = disabled) |
| `stagger_sway_frequency` | 1.5 Hz | Primary oscillation speed |
| `stagger_sway_drift` | 0.4 | Perpendicular wobble (0 = straight line) |
| `stagger_sway_twist` | 0.15 | Upper body twist intensity |
| `stagger_sway_secondary_ratio` | 1.73 | Secondary frequency ratio (irrational = non-repeating) |
| `stagger_sway_twist_ratio` | 2.17 | Twist frequency ratio |
| `stagger_sway_spine_falloff` | 0.7 | Spine force as fraction of Hips |
| `stagger_sway_chest_falloff` | 0.5 | Chest force as fraction of Hips |

Decay is quadratic: `(1.0 - progress)^2` over `stagger_duration`.

## Stagger recovery rate

During stagger, natural spring recovery is suppressed so Active Resistance
becomes the sole driver of strength changes.

| Parameter | Default | Effect |
|-----------|---------|--------|
| `stagger_recovery_rate` | 0.03/s | Near-zero vs normal 0.3/s |

Set on stagger entry, restored to default on stagger exit.

## Bone name matching

Support common naming conventions (Mixamo, Rigify, etc.):

```gdscript
func classify_region(bone_name: StringName) -> StringName:
    var n = bone_name.to_lower()
    if "hip" in n or "pelvis" in n:       return &"core"
    if "spine" in n:                       return &"core"
    if "chest" in n or "upper_chest" in n: return &"core"
    if "head" in n or "neck" in n:         return &"head"
    if "upperarm" in n or "upper_arm" in n or "shoulder" in n: return &"upper_limb"
    if "lowerarm" in n or "lower_arm" in n or "forearm" in n:  return &"upper_limb"
    if "hand" in n:                        return &"hand"
    if "upperleg" in n or "upper_leg" in n or "thigh" in n:    return &"upper_leg"
    if "lowerleg" in n or "lower_leg" in n or "calf" in n or "shin" in n: return &"lower_leg"
    if "foot" in n or "toe" in n:          return &"foot"
    return &"core"  # Default
```

## Animation requirements

### Minimum set (Step 0-2)

| Animation         | Type     | Duration | Loop | Source     |
|-------------------|----------|----------|------|------------|
| idle              | Full     | 2-4s     | Yes  | Mixamo     |
| walk              | Full     | 0.8-1.2s | Yes  | Mixamo     |
| flinch_front      | Additive | 0.2-0.3s | No   | Mixamo "Hit Reaction" |
| flinch_back       | Additive | 0.2-0.3s | No   | Mixamo     |
| flinch_left       | Additive | 0.2-0.3s | No   | Mixamo     |
| flinch_right      | Additive | 0.2-0.3s | No   | Mixamo     |

### For recovery (Step 7)

| Animation         | Type     | Duration | Loop | Notes                    |
|-------------------|----------|----------|------|--------------------------|
| getup_faceup      | Full     | 2-3s     | No   | Starts from lying on back |
| getup_facedown    | Full     | 2-3s     | No   | Starts from lying face down |

### Additive animation setup

Flinch animations must be additive — they represent the DIFFERENCE from base pose.
In AnimationTree, use `AnimationNodeAdd2`:
- Input 0 (in): current locomotion output
- Input 1 (add): flinch animation
- `add_amount`: 0.0 (no flinch) to 1.0+ (full flinch)

The Add2 node automatically computes the delta from the base pose.
