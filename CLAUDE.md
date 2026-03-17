# Kickback — Physics-Based Reactive Characters for Godot 4.6+

## What this is

An open-source system for Euphoria-like hit reactions in Godot 4.6+.
Characters react dynamically to shots, explosions, melee, and arrows using
physics-driven ragdoll and additive animation blending.

**Engine**: Godot 4.6.1+ with Jolt physics (built-in default).
**Language**: GDScript. No C#, no GDExtension unless profiling demands it.

## Project structure

```
kickback/
├── CLAUDE.md                        # You are here
├── README.md                        # Public repo readme
├── LICENSE                          # MIT
├── docs/
│   ├── STEP_BY_STEP.md             # Implementation plan (8 steps, do them in order)
│   ├── GODOT_CONSTRAINTS.md        # Engine-specific quirks, API gaps, workarounds
│   └── REFERENCE.md                # Technical reference: PD math, weapon profiles, bone mapping
├── addons/
│   └── kickback/                      # The plugin (all source goes here)
│       ├── plugin.cfg
│       └── ... (scripts, resources)
├── test/                           # Test scenes (one per step)
│   ├── test_passive_ragdoll.tscn
│   ├── test_partial_ragdoll.tscn
│   ├── test_flinch.tscn
│   ├── test_active_ragdoll.tscn
│   └── ...
└── project.godot
```

## How to work

1. Read `docs/STEP_BY_STEP.md` — it defines 8 incremental steps
2. Read `docs/GODOT_CONSTRAINTS.md` before writing any physics code
3. Use `docs/REFERENCE.md` for math, gain values, and weapon profiles
4. Implement ONE step at a time. Each step has a test scene and pass criteria.
5. Do NOT skip ahead. Each step validates assumptions the next step depends on.

## Architecture overview

Two parallel approaches, layered by distance to camera:

### Close range (< 10m): Dual-skeleton active ragdoll
- **Animation Skeleton** (invisible): plays animations via AnimationTree, provides target poses
- **Physics Skeleton** (invisible): RigidBody3D nodes connected by Generic6DOFJoint3D
- **Visible Mesh**: reads transforms from whichever skeleton has authority
- A spring resolver drives each physics body toward the animation pose
- Hit reactions reduce spring strength → physics wins → character reacts → strength recovers

### Mid range (10-25m): Partial ragdoll via PhysicalBoneSimulator3D
- Uses Godot's built-in PhysicalBone3D system
- On hit: selectively simulate hit bone + neighbors, apply impulse, blend back

### Far range (25m+): Additive animation only
- Directional flinch animations layered via AnimationTree Add2 nodes
- No physics involvement

**CRITICAL DECISION**: The active ragdoll layer uses raw RigidBody3D + Generic6DOFJoint3D,
NOT PhysicalBone3D. PhysicalBone3D lacks apply_force(), apply_torque(), collision signals,
and has broken joint springs in Jolt. Every successful Godot active ragdoll project
bypasses PhysicalBone3D. PhysicalBoneSimulator3D is ONLY used for the mid-range partial
ragdoll tier where its limitations are acceptable.

## Key technical decisions

- **Velocity-based spring resolver**, not torque-based PD controller. Simpler, more stable with Jolt.
  Each frame: compute rotation error → convert to target angular velocity → lerp current velocity toward target.
- **Jolt physics only**. Verify in Project Settings → Physics → 3D. GodotPhysics cannot handle ragdolls.
- **AnimationTree stays active** during all ragdoll states. It provides target poses for the spring resolver.
- **Collision layers**: character controller on layer 1, ragdoll physics bodies on layer 4,
  environment on layer 2. Physics bodies collide with environment but not with the character controller.
- **One test scene per step**. Each must be runnable independently. Include a simple raycast weapon
  (click to shoot) and on-screen debug info.

## Conventions

- All scripts use `class_name` registration
- Resources (weapon profiles) go in `addons/kickback/resources/`
- Node naming: PascalCase for nodes, snake_case for scripts
- Export key tuning parameters with `@export` and sensible defaults
- Every script that touches physics must handle the case where Jolt is not active (print warning, return)
- Prefer `lerp` / `move_toward` over tweens for per-frame physics blending
- Use `Tween` only for one-shot time-based transitions (influence blend-back, flinch fadeout)

## What NOT to do

- Don't use PhysicalBone3D for the active ragdoll layer
- Don't disable AnimationTree during ragdoll
- Don't use Engine.time_scale for per-character hitstop
- Don't use _integrate_forces() unless absolutely necessary (velocity modification is simpler)
- Don't over-engineer. Each step should be < 200 lines of new code.
- Don't add any UI framework, menu system, or game logic. Test scenes are minimal: character + weapon + floor.
