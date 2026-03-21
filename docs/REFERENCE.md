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

| Region        | Bones                                  | Strength | Pin | Notes                    |
|---------------|----------------------------------------|----------|-----|--------------------------|
| Core          | Hips, Spine, Chest                     | 0.40     | 0.3 (hips only) | Highest — keeps upright |
| Head          | Head, Neck                             | 0.15     | —   | Low — head should react freely |
| Upper Limbs   | UpperArm_L/R, LowerArm_L/R            | 0.25     | —   | Arms swing on hit       |
| Hands         | Hand_L/R                               | 0.10     | —   | Floppy hands look natural |
| Upper Legs    | UpperLeg_L/R                           | 0.35     | —   | Support weight           |
| Lower Legs    | LowerLeg_L/R                           | 0.25     | —   | Medium                   |
| Feet          | Foot_L/R                               | 0.15     | —   | Low                      |

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
