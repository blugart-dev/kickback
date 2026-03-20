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
│   ├── STEP_BY_STEP.md              # Implementation history (8 steps)
│   ├── GODOT_CONSTRAINTS.md         # Engine quirks and workarounds
│   └── REFERENCE.md                 # Technical reference: math, profiles, bone mapping
├── addons/
│   └── kickback/                    # The plugin (distributable)
│       ├── plugin.cfg
│       ├── kickback_plugin.gd       # Editor tool: "Add Kickback to Selected"
│       ├── kickback_character.gd    # LOD tier coordinator
│       ├── kickback_manager.gd      # Global budget manager
│       ├── kickback_raycast.gd      # Hit detection utility (one-liner)
│       ├── skeleton_detector.gd     # Auto-detect humanoid bones in any skeleton
│       ├── physics_rig_builder.gd   # Builds RigidBody3D ragdoll rig
│       ├── physics_rig_sync.gd      # Syncs physics → visible skeleton
│       ├── spring_resolver.gd       # Velocity-based spring pose matching
│       ├── active_ragdoll_controller.gd  # Close-range state machine
│       ├── partial_ragdoll_controller.gd # Mid-range bone simulation
│       ├── flinch_controller.gd     # Far-range direction calculator
│       ├── ragdoll_animator.gd      # Optional animation handler (signals)
│       ├── hit_event.gd             # Hit data object
│       ├── jolt_check.gd            # Jolt physics verification
│       ├── strength_debug_hud.gd    # F3 debug overlay with LOD zones
│       ├── editor/                  # Editor-only tooling
│       │   ├── kickback_inspector_plugin.gd  # Inspector integration
│       │   └── kickback_status_panel.gd      # Status panel UI
│       ├── icons/                   # Scene tree icons (16x16 SVG)
│       │   └── *.svg (9 icons)
│       ├── presets/                  # Starter ImpactProfile .tres files
│       │   ├── bullet.tres
│       │   ├── shotgun.tres
│       │   ├── explosion.tres
│       │   ├── melee.tres
│       │   └── arrow.tres
│       └── resources/               # Resource class definitions
│           ├── impact_profile.gd    # Impact parameters (impulse, ragdoll chance, etc.)
│           ├── ragdoll_profile.gd   # Skeleton mapping (bones, joints, shapes)
│           ├── ragdoll_tuning.gd    # Physics tuning (strengths, recovery, collision)
│           ├── bone_definition.gd
│           ├── joint_definition.gd
│           └── intermediate_bone_entry.gd
├── test/
│   ├── helpers/                     # Test utility scripts
│   │   ├── orbit_camera.gd
│   │   ├── free_camera.gd
│   │   └── raycast_weapon.gd
│   ├── scenes/                      # 7 interactive test scenes
│   ├── resources/                   # Test-only impact presets
│   └── unit/                        # GUT unit tests (27 tests)
├── assets/                          # Demo character (not part of plugin)
└── project.godot
```

## Architecture

### Design principles
- **Physics controllers emit signals, don't play animations.** Animation is handled by the optional `RagdollAnimator` node. Users can replace or extend it.
- **All configuration via Resources.** `RagdollProfile` (skeleton mapping) and `RagdollTuning` (physics feel) are assignable on `KickbackCharacter`. Null = auto-detected or Mixamo defaults.
- **Auto-detection.** `SkeletonDetector` pattern-matches bone names to identify humanoid bones in any skeleton (Mixamo, Rigify, Unreal Mannequin, custom). Generates a `RagdollProfile` and `PhysicalBone3D` nodes automatically during setup.
- **Composable node structure.** Each controller is an independent node. Users add/remove as needed.

### LOD tiers (by camera distance)

**Tier 1 — Active Ragdoll (< 10m):**
- `PhysicsRigBuilder` creates 16 RigidBody3D + 15 Generic6DOFJoint3D
- `PhysicsRigSync` writes physics transforms to skeleton
- `SpringResolver` drives physics bodies toward animation poses via velocity lerp
- `ActiveRagdollController` manages NORMAL → RAGDOLL → GETTING_UP → NORMAL state machine
- `PERSISTENT` state: stays ragdolled until `set_persistent(false)` is called (for death/knockdown)

**Tier 2 — Partial Ragdoll (10-25m):**
- `PartialRagdollController` uses PhysicalBoneSimulator3D for selective bone simulation

**Tier 3 — Flinch (25-50m):**
- `FlinchController` computes hit direction, emits `flinch_triggered(Direction)` signal

**Optional — Animation:**
- `RagdollAnimator` connects to controller signals and plays get-up/flinch/idle animations

### Key technical decisions
- **RigidBody3D + Generic6DOFJoint3D** for active ragdoll (NOT PhysicalBone3D)
- **Velocity-based springs**, not torque PD controllers
- **Jolt physics required** — GodotPhysics cannot handle ragdoll joints
- **AnimationTree stays active** during ragdoll — provides target poses for springs

## Conventions
- All scripts use `class_name` registration with `@icon()` annotations
- Controllers use `configure(profile, tuning)` pattern called by KickbackCharacter before `_ready()`
- Resources use `create_*_default()` factory methods for zero-config usage
- Signals for extensibility: controllers emit intent, RagdollAnimator handles behavior
- `SkeletonDetector.detect_humanoid_bones()` for auto-mapping any humanoid skeleton
- `KickbackRaycast.shoot_from_camera()` for one-line hit detection
- Impact profiles in `addons/kickback/presets/` and via `ImpactProfile.create_bullet()` etc.
- Collision: layer 4 (active ragdoll, mask 2+3+4), layer 5 (partial ragdoll, mask 2+5) — same-tier cross-character collision enabled
- `RagdollTuning.align_to_slope` for slope-adapted recovery positioning (opt-in, default off)
- Editor integration: `EditorInspectorPlugin` shows status panel on KickbackCharacter

## What NOT to do
- Don't use PhysicalBone3D for the active ragdoll layer
- Don't disable AnimationTree during ragdoll
- Don't play animations directly from physics controllers (use signals + RagdollAnimator)
- Don't hardcode animation names in controllers (they belong on RagdollAnimator)
- Don't hardcode bone names in controllers (they come from RagdollProfile)
