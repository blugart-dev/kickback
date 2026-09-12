# Foot IK — Architecture & Tuning Guide

## Why Direct Math (Not TwoBoneIK3D)

Godot's `TwoBoneIK3D` is a `SkeletonModifier3D` that runs in the modifier
pipeline after `_physics_process`. Kickback's `PhysicsRigSync` writes bone
pose overrides that contaminate `get_bone_global_pose()` during
`skeleton_updated`, making the IK results unreadable. This creates a
feedback loop with one-frame latency.

**Solution:** Direct two-bone IK math computed in `_physics_process`, fed
directly to `SpringResolver.set_target_overrides()`, with full control over
the solve. The overrides are consumed in the **same physics tick**:
`ActiveRagdollController` runs at `process_physics_priority = -1`, ahead of
the `SpringResolver` (priority 0). Historically this was one tick of latency
— the setup tool created the resolver before the controller, so the resolver
read the previous tick's solve; the priority ordering (0.4.1) is what makes
it same-tick.

## How It Works

### Pipeline

```
_physics_process (each frame)
  │
  ├─ ActiveRagdollController checks state
  │   ├─ NORMAL  → FootIKSolver.process()
  │   ├─ STAGGER → FootIKSolver.process_stagger()
  │   └─ other   → FootIKSolver.reset()
  │
  ├─ FootIKSolver._solve_ik()
  │   ├─ Read animation bone poses from Skeleton3D
  │   ├─ Raycast ground per foot from hip height
  │   ├─ Swing detection (foot height vs character root)
  │   ├─ Pelvis adjustment (drop to lowest foot)
  │   ├─ Full-body shift (all bone targets move with pelvis)
  │   ├─ Two-bone IK solve per leg (law of cosines)
  │   └─ Foot rotation from ground slope
  │
  └─ SpringResolver.set_target_overrides(overrides)
      └─ Springs drive physics bodies toward IK-adjusted targets
```

### Two-Bone IK Solver

Uses the law of cosines to find the knee angle given:
- **Hip position** (upper leg bone origin + pelvis shift)
- **Foot target** (ground hit + ankle height offset)
- **Knee hint** (animation knee position for bend direction)

Reach is never a reason to drop the solve: a target outside the leg's
reach band is **clamped** onto it (no further than full extension, no closer
than full fold) and the chain is always solved — the leg extends fully toward
the target and the foot is placed at the solver's `end` position (the clamped
target, returned by `TwoBoneIK.solve`) so it stays attached to the shin.
Returning nothing for such targets used to make the caller write no override,
snapping the foot to the animation pose.

Segment lengths are measured **per side** from the rest pose (`_rest_length`),
so an asymmetric or retargeted skeleton's right leg is not solved with the
left leg's lengths.

When the animation knee is too close to the hip→foot line to define a bend
plane (a near-straight idle leg), the plane blends toward a fallback axis —
the character's forward, honouring `RagdollTuning.character_forward_sign`, so
knees fold forward whichever way the mesh was authored. The blend
(`TwoBoneIK.COLINEAR_HINT_SIN`) is continuous, so the plane cannot flip from
one frame to the next.

### Foot Target Sources

| State | Foot XZ source | Foot Y source |
|-------|---------------|---------------|
| NORMAL | Animation foot position | Ground raycast + ankle height |
| STAGGER | Pinned position (captured at stagger start) | Ground raycast + ankle height |

### Swing Detection

A foot in the air (walking swing phase) should not be IK'd to the ground.
Detection uses **foot height relative to character root** (not ground):

```
if foot_y - root_y < swing_threshold:
    weight = ramp from plant_threshold to swing_threshold
else:
    weight = 0 (foot is swinging freely)
```

Using character root avoids false positives on slopes where the ground
is at different heights.

### Pelvis Adjustment

When feet are at different heights (stairs, slopes), the pelvis drops
to accommodate the lowest foot:

```
pelvis_offset = min(offset_L * weight_L, offset_R * weight_R)
clamped to [-max_pelvis_drop, 0]
```

All bone targets shift by the pelvis offset (full-body shift), not
just the hips. This prevents the upper body from floating.

### Anti-Foot-Slide (Stagger)

During stagger, sway forces push the upper body while feet stay planted:

1. `begin_stagger()` captures foot body world positions
2. Each frame, IK targets use the captured XZ (feet don't slide)
3. Ground Y is still raycasted to track terrain changes
4. Leg bone spring strengths are boosted above the stagger floor

## Tuning Parameters

All parameters are on `RagdollTuning` in the "Foot IK" export group.

### Core

| Parameter | Default | Description |
|-----------|---------|-------------|
| `foot_ik_enabled` | `true` | Master toggle |
| `foot_ik_ankle_height` | `0.065` | Distance from ankle to sole bottom (m) |
| `foot_ik_max_pelvis_drop` | `0.35` | Max pelvis drop for lowest foot (m) |
| `foot_ik_max_adjustment` | `0.5` | Max per-foot vertical correction (m) |

### Swing Detection

| Parameter | Default | Description |
|-----------|---------|-------------|
| `foot_ik_swing_threshold` | `0.25` | Foot height above root = full swing |
| `foot_ik_plant_threshold` | `0.17` | Foot height above root = fully planted |

### Smoothing

| Parameter | Default | Description |
|-----------|---------|-------------|
| `foot_ik_pelvis_blend_speed` | `8.0` | Pelvis adjustment damping (higher = faster) |
| `foot_ik_foot_blend_speed` | `10.0` | Per-foot weight damping (higher = faster) |

### Raycasting

| Parameter | Default | Description |
|-----------|---------|-------------|
| `foot_ik_ray_above_hip` | `0.3` | Extra height above hip for ray origin (m) |
| `foot_ik_ray_below_hip` | `2.5` | Ray distance below origin (m) |
| `foot_ik_collision_mask` | `1` | Ground collision layers |

### Collision & Stagger

| Parameter | Default | Description |
|-----------|---------|-------------|
| `foot_ik_disable_foot_collision` | `true` | Disable foot body collision during IK |
| `foot_ik_stagger_pin` | `true` | Pin feet during stagger |
| `foot_ik_stagger_leg_strength` | `0.4` | Leg strength floor during pinning |

## Common Issues

**Feet sink into ground:** Increase `foot_ik_ankle_height`. The default
(0.065) is for Mixamo Y-Bot — larger characters need a larger value.

**Feet pop when walking:** Decrease `foot_ik_foot_blend_speed` for
smoother transitions, or increase `foot_ik_swing_threshold` if the
weight is toggling during normal walk cycles.

**Pelvis drops too much on stairs:** Decrease `foot_ik_max_pelvis_drop`.

**IK not working:** Check that terrain collision layers include layer 1
(or match `foot_ik_collision_mask`). The rig needs `Foot_L`, `Foot_R`,
`UpperLeg_L/R`, `LowerLeg_L/R` bones in the `RagdollProfile`.

**Feet slide during stagger:** Ensure `foot_ik_stagger_pin = true` and
`foot_ik_stagger_leg_strength` is high enough (0.3-0.5).
