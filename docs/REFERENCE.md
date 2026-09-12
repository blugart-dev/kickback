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
`pin_strength` is the position-tracking blend. Shipped defaults
(`RagdollTuning.pin_strength_overrides`): **Hips 0.85**, feet 0.4, every other body 0.1
(`default_pin_strength`). The Hips pin is what holds the character up — the
[audit](AUDIT_2026-09-12.md) §3.1 calls it a kinematic anchor, and replacing it with a
weak safety-net pin plus an upright torque is part of the planned muscle layer; the
light 0.1 pins elsewhere let the joints, not the pins, place the limbs.

**Gravity.** Every tick each body's `gravity_scale` is written as
`RagdollTuning.gravity_scale × (1 − strength / base_strength)` (`gravity_scale` default
1.0). A bone at full strength has no gravity (the springs hold the pose); a limp bone
falls at exactly `gravity_scale` — real gravity by default. Pre-0.4.1 a separate hidden
0.5 multiplier halved that and the tuning knob was overwritten on the first tick.

**Root motion.** The target walk-up (`get_animation_bone_global`) zeroes the XZ of the
root-motion bone's *local* pose when `RagdollTuning.strip_root_motion` is on, so the root
body, every descendant, and every other consumer of the animation target (foot/arm IK,
the get-up blend) see the same root-motion-free pose. Stripping only the root body's own
target (pre-0.4.1) left its children's targets displaced by the clip's root motion.

### Rig fidelity additions (1.4)

Three terms were added after measuring, on a 16-body auto-detected rig in a real
game, that a spring-driven idle sat 5-15 deg off its animation and wobbled — and that
the springs were not the cause; the *solver* rewrote 50-90 % of the commanded angular
velocity every tick (a head's came back reversed). Diagnosis and defaults:

1. **Self-collision off** (`RagdollTuning.self_collision = false`, builder adds a
   collision exception for every body pair). Only jointed pairs were excluded before;
   the auto-generated torso boxes and limb capsules overlap in ordinary poses (Chest-Hips
   in contact 170 of 180 idle frames, forearms inside the chest box), and every contact is
   a solver impulse against the springs.
2. **Chain-consistent linear commands** (`spring_chain_consistency`, 0..1, default 1).
   Bodies update parent-first (`PhysicsRigBuilder.get_joints()` gives the topology and
   the joint anchor in both bodies' local frames). A jointed child's linear velocity is
   commanded as the kinematic identity the joint enforces anyway,
   `v_child = v_parent + w_parent x r_parent - w_child x r_child` (parent velocities as
   written this tick), and its own position pin is scaled out by the same factor.
   Reason: the anchor sits half a bone from each body's centre of mass, so the impulse
   the point constraint applies to reconcile an inconsistent command *spins* the bodies —
   a 0.1-0.3 m/s pull on a light body (head, hand, foot: tiny inertia) becomes several
   rad/s. With consistent commands the anchor velocity mismatch after the spring's writes
   is 0.000 m/s and the solver has nothing to fight. Positions of children follow from
   their ancestors' orientation springs and the root pin (the joint holds them there).
3. **Feed-forward** (`spring_feed_forward`, 0..1, default 1). The error term alone reaches
   where the target *was*; the target's own rotation / translation since the previous
   tick is added to the commanded velocity, so a moving target is tracked with zero
   steady-state lag (a 150 deg/s idle twitch used to read 3-8 deg behind). Scaled by
   strength like the error term, so weakened bones still let go; a limp bone (strength
   ~0) drops its target history so no stale motion is fed forward when it wakes.

`spring_angular_settle_deadband` default 0.04 -> 0.01 rad: with the rig no longer
fighting itself the wide band only left every bone wandering 2 deg off its target
(and measured *more* frame-to-frame jitter, not less).

Set `self_collision = true`, `spring_chain_consistency = 0`, `spring_feed_forward = 0`,
deadband `0.04` for the pre-1.4 behaviour.

One thing the pass measured but did NOT change, worth knowing (the joint limits it
also flagged — build-pose-centred, Mixamo-axis — were fixed next, see "Joint limit
frames" below):

- Headless, the process loop can stall (~140 ms) and the engine catches up with
  `max_physics_steps_per_frame` (8) ticks in one frame; an AnimationPlayer in the default
  IDLE callback mode then stands still for 8 ticks and jumps 0.14 s. Any headless
  measurement of tracking should run the AnimationPlayer in PHYSICS callback mode (after
  the rig is built — before, a physics-mode player hasn't ticked and the joints would be
  centred on the rest pose).

## Muscle layer — JOINT_MOTOR mode (0.5.0)

`RagdollTuning.muscle_mode = MuscleMode.JOINT_MOTOR` swaps the velocity overwrite above
for **torque-bounded joint motors** while keeping the same command. The legacy mode is
untouched (bit-identical, still the default until the visual gate passes).

**Per jointed body, every physics tick** (`SpringResolver._drive_joint_motor`):

```
A   = parent.basis * frame_parent          # the joint limit frame on the parent (world)
B   = child.basis  * frame_child           # the same frame carried by the child
PA  = parent_target.basis * frame_parent   # animation (or IK override) targets
CA  = child_target.basis  * frame_child
R_rel = A^-1 * B                           # current  parent→child rotation
R_tgt = PA^-1 * CA                         # target   parent→child rotation
err   = axis_angle(R_tgt * R_rel^-1)       # rotation vector, frame A, settle deadband applied
ff    = axis_angle(R_tgt * R_tgt_prev^-1) / dt * spring_feed_forward
w     = clamp(err * muscle_gain / dt + ff, muscle_max_angular_velocity)
motor.target = -( w.x, (R_rel^-1 * w).y, (R_rel^-1 * w).z )   # see "frames" below
motor.force_limit = BoneDefinition.muscle_torque * muscle_strength_scale * (strength / base_strength)
```

- **Strength is a torque.** `strength / base_strength` scales the motor force limit;
  a limp bone (strength ≈ 0) gets a zero limit and the motor lets go. Hit reductions,
  fatigue, injury and the recovery ramp all still work through strength, now as torque
  modulation. `strength_map` / `default_spring_strength` no longer set stiffness in this
  mode — the ratio is what matters.
- **Gravity stays on** for every jointed body (`gravity_scale`, not scaled by strength);
  damping is `muscle_angular_damp` / `muscle_linear_damp`.
- **Frames.** Two engine facts measured under Jolt 4.7.2 (`tools/spike/motor_spike.gd`,
  `tools/bench/ybot_bench.gd BENCH_DIAG=1`): the motor target velocity is **mirrored**
  (`MOTOR_AXIS_SIGN = -1`, the same convention `JointDefinition.apply_to` compensates on
  the limits), and the 6DOF angular motor is solved on **swing-twist axes** — the twist
  axis is the **parent** frame's X, the two swing axes are the **child** frame's Y and Z.
  Commanding everything in the parent frame left every joint of a real idle 2–4° short
  on the swing axes; everything in the child frame tripled the twist error.
- **The root** has no parent joint: entering motor mode attaches it to the world with a
  limit-free `Generic6DOFJoint3D` (`<Root>_world_motor`, node_a empty = world) whose
  motor drives the pelvis' world orientation with `muscle_root_torque`; its position
  keeps the legacy pin scaled by `muscle_root_pin` until the balance layer exists.
- **Gain is a per-tick fraction** (`muscle_gain`, default 0.10): the stability of a
  velocity motor under an explicit position loop is set by gain × tick. Measured at 60 Hz
  on the harness: 0.10 holds within 0.5° and settles a 60° elbow step without ringing;
  0.15 rings once the pelvis is a bounded motor; 0.20+ limit-cycles on the light arm.

**Torque table** (`SkeletonDetector.MUSCLE_TORQUE_TABLE`, N·m, on the child body of each
joint): Spine 150, Chest 150, Head 30, UpperArm 60, LowerArm 40, Hand 10, UpperLeg 200,
LowerLeg 150, Foot 60; root `muscle_root_torque` 400. Physically honest by construction:
a 3 N·m shoulder cannot hold a horizontal arm (test), 60 N·m can.

**Ybot bench** (`tools/bench/ybot_bench.gd`, idle / react_front / bullet on the hand,
foot IK on, 2026-09-13):

| Mode | Hz | IDLE mean / max | REACT mean | HIT peak / recover | resolver ms/tick |
|---|---:|---|---:|---|---|
| legacy | 60 | 0.78 / 1.65 | 10.1 | 1.3° / 4 ticks | 0.17 |
| **JOINT_MOTOR** | 60 | **0.80 / 3.42** | 16.3 | **6.3° / 4 ticks** | 0.19–0.43 (noisy) |
| legacy | 120 | 0.86 / 1.40 | 13.1 | 1.2° / 4 | 0.25 |
| JOINT_MOTOR | 120 | 0.71 / 2.28 | 11.6 | 6.2° / 4 | 0.46 |
| legacy | 30 | 1.06 / 7.17 | 10.0 | 1.7° / 4 | 0.15 |
| JOINT_MOTOR, feet off (default) | 30 | 15.0 / 41.8 (rings) | 39.9 | never | 0.19 |
| JOINT_MOTOR, feet colliding | 30 | 3.64 / 19.4 | 40.4 | never (joint wraps) | 0.18 |

Read: at 60 Hz the motor layer matches the legacy cheat on idle under real gravity with
bounded torques, tracks a violent react clip 1.6× worse (torque-limited, by design), and
gives a real hit reaction (4.8× the legacy deflection, muscle recovery in 4 ticks). At
120 Hz it beats legacy everywhere. **30 Hz is an open item**: with foot IK's default
(feet don't collide in NORMAL) the body hangs from the pelvis pin and rings at 30 Hz;
`foot_ik_disable_foot_collision = false` (feet load-bearing) brings idle to 3.6°, and the
hand-hit recovery at 30 Hz still wraps a wrist joint past its limit (Jolt limit
tunnelling on a light body in a 33 ms step). The resolver tick timing is µs-level and
noisy on Windows; the motor path is roughly 1.5–2.5× the legacy path.

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
- `balance < balance_recovery_threshold (0.3)` for `balance_recovery_hold_time (0.5s)` → early stagger recovery
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

The shipped Mixamo profile (`RagdollProfile.create_mixamo_default`). `shape_offset` is the
fraction of the bone→child-bone vector the collision shape is pushed along.

| Bone       | Mass | Shape             | Dimensions                    | shape_offset |
|------------|------|-------------------|-------------------------------|--------------|
| Hips       | 15   | BoxShape3D        | 0.35 × 0.20 × 0.25            | 0.5          |
| Spine      | 10   | BoxShape3D        | 0.30 × 0.18 × 0.18            | 0.5          |
| Chest      | 12   | BoxShape3D        | 0.35 × 0.22 × 0.22            | 0.5          |
| Head       | 5    | SphereShape3D     | radius 0.12                   | 0.5          |
| UpperArm   | 3    | CapsuleShape3D    | radius 0.055, height 0.28     | 0.5          |
| LowerArm   | 2    | CapsuleShape3D    | radius 0.05, height 0.25      | 0.5          |
| Hand       | 1    | BoxShape3D        | 0.10 × 0.04 × 0.12            | 0.5          |
| UpperLeg   | 8    | CapsuleShape3D    | radius 0.08, height 0.40      | 0.5          |
| LowerLeg   | 4    | CapsuleShape3D    | radius 0.065, height 0.38     | 0.5          |
| Foot       | 2    | BoxShape3D        | 0.12 × 0.07 × 0.25            | 0.65         |

Auto-detected profiles (`SkeletonDetector.create_profile_from_skeleton`) use the same
masses (`SkeletonDetector.MASS_TABLE`) and shape types (`SHAPE_TABLE`), but size each shape
from the skeleton's own bone lengths via `BONE_PROPORTIONS`, so their dimensions differ.

## Joint angular limits (degrees)

The shipped table (`SkeletonDetector.JOINT_TABLE`, shared by `create_profile_from_skeleton`
and `RagdollProfile.create_mixamo_default` through `default_joints_for()`). Axes are the
joint's ANATOMICAL limit frame (below): X = flexion / bend, Y = twist about the child
bone, Z = lateral; 0 = the rest pose. `flex` is `JointDefinition.flex_direction`.

| Joint             | X (flexion)  | Y (twist)   | Z (lateral)  | flex     |
|-------------------|--------------|-------------|--------------|----------|
| Hips→Spine        | -35 to 35    | -30 to 30   | -25 to 25    |          |
| Spine→Chest       | -35 to 35    | -30 to 30   | -25 to 25    |          |
| Chest→Head        | -70 to 70    | -75 to 75   | -50 to 50    |          |
| Chest→UpperArm    | -90 to 150   | -90 to 90   | -120 to 120  | FORWARD  |
| UpperArm→LowerArm | -10 to 150   | -80 to 80   | -20 to 20    | FORWARD  |
| LowerArm→Hand     | -70 to 70    | -80 to 80   | -60 to 60    |          |
| Hips→UpperLeg     | -30 to 120   | -40 to 40   | -45 to 45    | FORWARD  |
| UpperLeg→LowerLeg | -10 to 140   | -25 to 25   | -15 to 15    | BACKWARD |
| LowerLeg→Foot     | -50 to 50    | -35 to 35   | -35 to 35    |          |

Ranges are anatomical and a little generous on purpose: while the character is alive the
springs shape the pose and the limits must never hold a bone back from its animation (a
limit the animation crosses is a steady error the spring cannot close — measured 17.6 deg
mean head error on a head-lolling idle with the pre-1.4 +-40 head range); when limp they
are the corpse's safety net (elbows / knees fold one way only). Retargeted mocap puts
forearm pronation on the wrist / forearm twist and reads 15-20 deg of "lateral" at the
elbow, hence those widths. `RagdollTuning.joint_limit_scale` (default 1.0) multiplies every
bound at build time — the softness dial: Jolt ignores the Generic6DOFJoint3D angular limit
softness / damping / restitution parameters (`JointDefinition`'s compliance group is a
no-op under Jolt and the engine says so once).

### Joint limit frames (1.4)

Godot captures a Generic6DOFJoint3D's two local frames from the joint node's and the two
bodies' transforms at the moment `node_a` / `node_b` are assigned, and the relative
rotation the angular limits are measured against is ZERO in that configuration. Before
1.4 the runtime rig assigned them with the bodies on whatever pose the AnimationPlayer
had written two frames after spawn, so an arbitrary idle frame was every limit's centre,
and the frame's axes were the child bone's own local axes — the table assumed Mixamo's
Y-along-bone roll. `RagdollProfile.joint_frame` now selects:

- `ANATOMICAL` (default) — `PhysicsRigBuilder.compute_rest_joint_frame(skeleton, profile,
  joint_def)` (static; the RigBaker uses it too), from the skeleton's REST geometry:
  origin = the child bone's rest origin; +Y = the child bone's long axis (its own local
  axis nearest the direction toward its `BoneDefinition.child_bone`, or that raw direction
  when no local axis is within 35 deg — identity-basis rigs); +X = the flexion axis: the
  authored rest bend's axis (parent bone direction x child bone direction, +rotation
  increases the bend) when the joint is authored bent by 3-45 deg (A-pose elbows / knees
  with a pole bend), sign-corrected to `flex_direction`; otherwise bone x forward
  (+rotation folds the child toward the character's front, or toward its back for
  `Flex.BACKWARD`), falling back to bone x up / bone x lateral for bones that point
  forward (feet); +Z = X x Y. "Forward" is the character's own — left x up from the rest
  positions of the profile's leg (or arm) chains and root / head roles — so Mixamo, Rigify,
  the Godot humanoid profile and UE-style X-along-bone rigs all get the same semantic
  axes. The builder parks the child body at `parent_now * parent_rest^-1 * child_rest`
  (and the joint at the rest frame in the same parent-relative sense) for the one instant
  the frames are captured, then restores its animation pose — nothing has been simulated
  yet, and frames already captured by the body's other joints are stored local to the
  bodies. The registered anchors are the rest offsets (pose independent).
- `BONE_REST` — the child bone's rest basis, rest-centred (what RigBaker used to bake;
  the pre-1.4 axis assumption without the build-pose centre).
- `BUILD_POSE` — the pre-1.4 behaviour, for comparison.

Sign: `JointDefinition` limits are the allowed rotation of the CHILD about each frame
axis (right-hand rule); Godot's Generic6DOFJoint3D measures the angle with the opposite
sign (under Jolt, with (0, 150) on X the child could turn -150..0 about +X and nothing
positive), so `apply_to` mirrors the bounds on the way in. Jolt decomposes the relative
rotation swing-twist with X as the twist axis (Y/Z swing, pyramid) — per-axis for pure
rotations, and one-sided ranges are safe on every axis; the wide one-sided flexion ranges
sit on X on purpose. `PhysicsRigBuilder.get_joint_angles(child_rig)` returns the current
angles in that decomposition (0 = rest), and takes optional parent / child transforms to
evaluate the animation pose instead of the bodies — the "is this limit fighting the
animation" probe (`get_joints()` entries expose `frame_parent` / `frame_child`).

Measured on a 16-body auto-detected rig in a real game (four characters, lockstep
idles) after the change: every joint's animation inside its limits 100 % of frames (elbow
lateral / wrist twist / ankle were at a limit 30-90 % of frames before), worst-idle head
error 17.6/37.7 -> 7.1/20.8 deg mean/max — and identical numbers with the angular limits
disabled entirely, i.e. the residual is the game's low extremity spring strengths, not
the joints.

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
@export_range(0, 99) var strength_spread: int = 1                  # Neighbor bones affected (99 = whole rig)
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
    bone.strength = move_toward(bone.strength, bone.base_strength, spring.recovery_rate * delta)
```

`SpringResolver.recovery_rate` holds one value at a time and has several writers.
Precedence (from the `RagdollTuning.recovery_rate` doc comment): `RagdollTuning.recovery_rate`
(0.3/s) is the default the resolver returns to in NORMAL; an `ImpactProfile.recovery_rate`
replaces it for the reaction to that hit; `stagger_recovery_rate` (0.03/s) applies while
staggering; 0 while ragdolled; the controller restores the tuning value when the character
returns to NORMAL. A value you write to the resolver directly survives only until the next
of those events.

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

Done by `SkeletonDetector` (the plugin has no separate region classifier). Bone names are
tokenised — split at `_ . - :` / space and camelCase boundaries, digit runs dropped, the
`mixamorig` / `DEF-` namespace tokens and the side token (`l`/`r`/`left`/`right`) removed —
and the remaining key is matched *exactly* against the tables (`HIPS_KEYS`, `HEAD_KEYS`,
`LIMB_KEYS`, `TORSO_KEYS`), so `spine_lower` is never a left-side bone and UE's `ik_foot_l`
is never a foot. Torso slots are then classified by position in the hierarchy: on the
head→hips chain the bone directly above the hips is Spine, the chain bone the upper arms
(via their clavicles) hang from is Chest, and everything between (neck included) becomes an
intermediate bone. Hips fall back to the common ancestor of the thighs and Head to the top
of the torso chain, which is how Rigify's unnamed `DEF-spine` / `DEF-spine.006` resolve. A
rig with a single torso bone gets no Chest; `default_joints_for` re-parents the head and
upper-arm joints to the nearest present torso body. Rig families exercised by
`test/test_skeleton_detector.gd`: Mixamo (`mixamorig:` and `mixamorig_`), Blender Rigify
DEF bones, the UE5 Mannequin, generic `Hips/Spine/Chest/Neck/Head` rigs, single-spine rigs.

## Semantic roles (custom rigs)

The controller, foot IK solver, and debug HUD never hardcode bone names. They ask
`RagdollProfile` which rig bodies play each role, via accessors that default to the
canonical convention (`Hips`, `Chest`, `Head`, `Foot_L/R`, `UpperLeg_*`…):

| Role field (export)             | Accessor                  | Used for |
|---------------------------------|---------------------------|----------|
| `root_rig` (`"Hips"`)           | `get_root_rig()`          | CoM base, root motion, sway anchor |
| `chest_rig` (`"Chest"`)         | `get_chest_rig()`         | head-whip, recovery orientation |
| `head_rig` (`"Head"`)           | `get_head_rig()`          | head-whip, state gizmo |
| `torso_rigs`                    | `get_torso_rigs()`        | torso bend, sway falloff |
| `foot_rigs`                     | `get_foot_rigs()`         | balance support polygon, foot IK, CoM gizmo |
| `left_leg_chain`/`right_leg_chain` | `get_leg_chain("L"/"R")` | two-bone foot IK (hip→knee→foot) |
| `hand_rigs`                     | `get_hand_rigs()`         | arm IK end effectors (fall-reach contact pass) |
| `left_arm_chain`/`right_arm_chain` | `get_arm_chain("L"/"R")` | two-bone arm IK (shoulder→elbow→hand): windmill, fall reach |

Also: `get_all_leg_rigs()` / `get_all_arm_rigs()`, `is_leg_rig()` / `is_arm_rig()`,
`get_leg_side()` / `get_arm_side()`.

A profile that follows the convention needs **zero** configuration. For a non-Mixamo
rig with different rig names, override the role fields to match:

```gdscript
profile.root_rig = "pelvis"
profile.foot_rigs = PackedStringArray(["l_ankle", "r_ankle"])
profile.left_leg_chain = PackedStringArray(["l_thigh", "l_shin", "l_ankle"])
profile.right_leg_chain = PackedStringArray(["r_thigh", "r_shin", "r_ankle"])
```

List accessors filter out names that don't map to a defined bone, so a missing body
degrades gracefully instead of resolving to a null lookup. `root_bone` (the bone-chain
traversal recursion guard) derives from `root_rig` when left empty — see
`get_root_skeleton_bone()`.
Run `validate_against_skeleton()` to flag role names that don't reference a defined bone.

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
