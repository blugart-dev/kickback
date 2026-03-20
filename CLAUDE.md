# Kickback — Physics-Based Reactive Characters for Godot 4.6+

## What this is

An open-source plugin for Euphoria-like hit reactions in Godot 4.6+.
Characters react dynamically to impacts using physics-driven ragdoll
and spring-based pose matching. Fully configurable and extensible.

**Engine**: Godot 4.6.1+ with Jolt physics.
**Language**: GDScript.

## Project structure

```
kickback/
├── CLAUDE.md
├── README.md
├── LICENSE
├── docs/
│   ├── STEP_BY_STEP.md              # Implementation history
│   ├── GODOT_CONSTRAINTS.md         # Engine quirks and workarounds
│   └── REFERENCE.md                 # Technical reference: math, profiles, bone mapping
├── addons/
│   └── kickback/                    # The plugin (distributable)
│       ├── plugin.cfg
│       ├── kickback_plugin.gd       # Editor tool: "Add Kickback to Selected"
│       ├── kickback_character.gd    # Coordinator (detects controllers, routes hits)
│       ├── kickback_manager.gd      # Global budget manager
│       ├── kickback_raycast.gd      # Hit detection utility (one-liner)
│       ├── skeleton_detector.gd     # Auto-detect humanoid bones in any skeleton
│       ├── physics_rig_builder.gd   # Builds RigidBody3D ragdoll rig
│       ├── physics_rig_sync.gd      # Syncs physics → visible skeleton
│       ├── spring_resolver.gd       # Velocity-based spring pose matching
│       ├── active_ragdoll_controller.gd  # State machine (NORMAL/RAGDOLL/GETTING_UP/PERSISTENT)
│       ├── partial_ragdoll_controller.gd # Selective bone simulation at distance
│       ├── hit_event.gd             # Hit data object
│       ├── jolt_check.gd            # Jolt physics verification
│       ├── strength_debug_hud.gd    # F3 debug overlay
│       ├── editor/                  # Editor-only tooling
│       │   ├── kickback_inspector_plugin.gd
│       │   ├── kickback_status_panel.gd
│       │   └── strip_root_motion.gd # Tool to strip root motion from animations
│       ├── icons/                   # Scene tree icons (SVG)
│       ├── presets/                  # Starter ImpactProfile .tres files
│       │   ├── bullet.tres, shotgun.tres, explosion.tres, melee.tres, arrow.tres
│       └── resources/               # Resource class definitions
│           ├── impact_profile.gd
│           ├── ragdoll_profile.gd
│           ├── ragdoll_tuning.gd
│           ├── bone_definition.gd
│           ├── joint_definition.gd
│           └── intermediate_bone_entry.gd
├── assets/                          # Demo character (not part of plugin)
│   ├── characters/ybot/
│   └── animations/ybot/             # 21 animations (idle, walk, run, flinch, get-up, react, injured, kip-up)
└── project.godot
```

## Architecture

### Design principles
- **Physics controllers emit signals, don't play animations.** Animation handling is the user's responsibility. Connect to `recovery_started`, `recovery_finished`, `hit_absorbed` signals.
- **Animation-agnostic.** The physics core reads `Skeleton3D.get_bone_pose()` — works with AnimationPlayer, AnimationTree, or custom animation systems.
- **All configuration via Resources.** `RagdollProfile` (skeleton mapping) and `RagdollTuning` (physics feel) are assignable on `KickbackCharacter`. Null = auto-detected Mixamo defaults.
- **Node-based configuration.** KickbackCharacter detects available sibling controllers and adapts. Only active ragdoll nodes present? No LOD. Both active + partial? Automatic LOD switching.
- **Always-simulated rig.** Physics bodies never freeze. Springs toggle between active (hit-reactive, low damping) and passive (animation tracking, high damping). This eliminates visual snaps on tier transitions.

### Active Ragdoll
- `PhysicsRigBuilder` creates 16 RigidBody3D + 15 Generic6DOFJoint3D
- `PhysicsRigSync` writes physics transforms to skeleton as bone pose overrides
- `SpringResolver` drives physics bodies toward animation poses via velocity lerp
- `ActiveRagdollController` manages NORMAL → RAGDOLL → GETTING_UP → NORMAL state machine
- `PERSISTENT` state: stays ragdolled until `set_persistent(false)` is called

### Partial Ragdoll (optional, for LOD)
- `PartialRagdollController` uses PhysicalBoneSimulator3D for selective bone simulation
- Only activates when camera is at mid-range distance

### Key technical decisions
- **RigidBody3D + Generic6DOFJoint3D** for active ragdoll (NOT PhysicalBone3D — see GODOT_CONSTRAINTS.md for why)
- **Velocity-based springs**, not torque PD controllers
- **Jolt physics required** — GodotPhysics cannot handle ragdoll joints
- **Animation stays active during ragdoll** — provides target poses for springs
- **Root motion stripping** — XZ position of root bone is zeroed by SpringResolver to prevent drift from Mixamo animations with root motion

## Conventions
- All scripts use `class_name` registration with `@icon()` annotations
- Controllers use `configure(profile, tuning)` pattern called by KickbackCharacter before `_ready()`
- Resources use `create_*_default()` factory methods for zero-config usage
- `SkeletonDetector.detect_humanoid_bones()` for auto-mapping any humanoid skeleton
- `KickbackRaycast.shoot_from_camera()` for one-line hit detection
- Collision: layer 4 (active ragdoll), layer 5 (partial ragdoll)
- Setup tool offers presets: "Full (Active + Partial)" or "Active Ragdoll Only"

## Locomotion with active ragdoll
- **All root movement and rotation MUST happen in `_physics_process`**, not `_process`. The spring resolver runs in `_physics_process` — modifying the root in `_process` causes spring targets to jump.
- Play animations once on state transitions, not every frame.

## What NOT to do
- Don't use PhysicalBone3D for the active ragdoll layer (root bone doesn't simulate in world space — see GODOT_CONSTRAINTS.md)
- Don't disable AnimationTree/AnimationPlayer during ragdoll (springs need target poses)
- Don't play animations directly from physics controllers (use signals)
- Don't move or rotate the character root in `_process` during active ragdoll — use `_physics_process`
