# Kickback — Physics-Based Reactive Characters for Godot 4.7+

## What this is

An open-source plugin for Euphoria-like hit reactions in Godot 4.7+.
Characters react dynamically to impacts using physics-driven ragdoll
and spring-based pose matching. Fully configurable and extensible.

**Engine**: Godot 4.7+ with Jolt physics.
**Language**: GDScript.

## Start here

Autonomous or fresh sessions: read `docs/PLAN.md` first (resume order, ground rules,
current milestone, acceptance numbers, the loop command), then `docs/AUDIT_2026-09-12.md`
§1/§8 and `docs/MUSCLE_SPIKE.md` "Decision".

## Project structure

```
kickback/
├── CLAUDE.md
├── README.md
├── LICENSE
├── docs/
│   ├── STEP_BY_STEP.md              # Implementation history
│   ├── GODOT_CONSTRAINTS.md         # Engine quirks and workarounds
│   ├── REFERENCE.md                 # Technical reference: math, profiles, bone mapping
│   ├── INTEGRATION.md               # Integration guide: timing, layers, state machine, scoring
│   ├── FOOT_IK.md                   # Foot IK solver: planting, pelvis drop, anti-slide
│   ├── EUPHORIA_COMPARISON.md       # Feature-gap analysis vs Euphoria (honest scorecard)
│   ├── ROADMAP.md                   # Difficulty-weighted parity scorecard + milestones
│   ├── VERSIONING.md                # What the version numbers mean
│   ├── SELF_PRESERVATION.md         # 0.4.0 directed stumble + arm bracing (scripted root displacement — see audit)
│   ├── PLAN.md                      # START HERE: execution plan, milestone checklists, acceptance numbers, loop command
│   ├── AUDIT_2026-09-12.md          # Full audit: verdict, defects, docs drift, phase plan (do not edit)
│   ├── MUSCLE_SPIKE.md              # Phase-2 muscle spike results + the 0.5.0 decision (velocity motors)
│   └── SKELETON_MODIFIER_MIGRATION.md  # PhysicsRigSync → SkeletonModifier3D record
├── addons/
│   └── kickback/                    # The plugin (distributable)
│       ├── plugin.cfg
│       ├── kickback_plugin.gd       # Editor tool: "Add Kickback to Selected"
│       ├── kickback_setup.gd        # Runtime setup helper: KickbackSetup.add_active_rig / find_skeleton / child_path_to
│       ├── kickback_character.gd    # Coordinator (detects mode, routes hits)
│       ├── kickback_manager.gd      # Global budget manager
│       ├── kickback_raycast.gd      # Hit detection utility (one-liner)
│       ├── kickback_layers.gd       # Collision-layer constants (active=4, demo godot-ragdoll=5)
│       ├── skeleton_detector.gd     # Auto-detect humanoid bones in any skeleton
│       ├── physics_rig_builder.gd   # Builds RigidBody3D ragdoll rig
│       ├── physics_rig_sync.gd      # Syncs physics → visible skeleton
│       ├── spring_resolver.gd       # Velocity-based spring pose matching
│       ├── foot_ik_solver.gd        # Two-bone foot IK (direct math → spring targets)
│       ├── active_ragdoll_controller.gd  # State machine (NORMAL/STAGGER/RAGDOLL/GETTING_UP/PERSISTENT)
│       ├── physics_collision_monitor.gd # Optional ragdoll-environment collision observer
│       ├── jolt_check.gd            # Jolt physics verification
│       ├── strength_debug_hud.gd    # F3 debug gizmos (auto-discovers all characters)
│       ├── editor/                  # Editor-only tooling
│       │   ├── kickback_inspector_plugin.gd
│       │   ├── kickback_status_panel.gd
│       │   └── rig_baker.gd         # Bake persistent RigidBody3D + Joint nodes to scene
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
├── demo/                            # Demo scenes (not part of plugin) — 8 scenes
│   ├── strip_root_motion.gd         # DEMO-ONLY EditorScript: strips root motion from the ybot clips
│   ├── orbit_camera.gd              # DEMO-ONLY: shared RMB-orbit / scroll-zoom camera rig
│   ├── demo_helpers.gd              # DEMO-ONLY: runtime rig assembly (wires rig_sync_path), weapon picker, HUD log
│   ├── partial_ragdoll_controller.gd # DEMO-ONLY: Godot PhysicalBoneSimulator3D ragdoll (the "built-in" side)
│   ├── hit_event.gd                 # DEMO-ONLY: hit data for partial_ragdoll_controller
│   ├── demo.tscn/gd                 # Kickback active ragdoll vs Godot's built-in PhysicalBoneSimulator3D
│   ├── shooting_range.tscn/gd       # FPS: 5 weapon profiles + ball-throw alt-fire (RMB)
│   ├── tuning_playground.tscn/gd    # Tuning Lab: 5 presets side-by-side + Custom char w/ live sliders
│   ├── signal_showcase.tscn/gd      # Visualizes all signals with floating popups
│   ├── stress_test.tscn/gd          # 20 characters, budget system, mass ragdoll
│   ├── animated_npc.tscn/gd         # Signal-driven NPC: patrol, hit, recover, resume
│   ├── foot_ik_demo.tscn/gd         # Foot IK on vs off over varied terrain
│   └── euphoria_showcase.tscn/gd   # All euphoria features: active resistance, sway, pain, injuries
├── assets/                          # Demo character (not part of plugin)
│   ├── characters/ybot/
│   └── animations/ybot/             # 21 animations (idle, walk, run, flinch, get-up, react, injured, kip-up)
├── test/                            # GUT suite, run headless in CI (helpers/rig_harness.gd drives the real classes)
├── tools/
│   ├── spike/motor_spike.gd         # Standalone headless muscle spike (audit §8): 6DOF-motor muscle A/B vs SpringResolver — results in docs/MUSCLE_SPIKE.md
│   └── bench/ybot_bench.gd         # 0.5.0 acceptance bench on the ybot: both muscle modes, idle/react/hit, BENCH_HZ/DIAG/VARIANT
└── project.godot                    # Names 3D physics layers 1-5 (Environment, Projectiles, Characters, Active Ragdoll, Godot Ragdoll)
```

## Architecture

### Design principles
- **Physics controllers emit signals, don't play animations.** Animation handling is the user's responsibility. Connect to `stagger_started`, `recovery_started`, `recovery_finished`, `hit_absorbed`, `balance_changed`, `fatigue_changed`, `recovery_interrupted`, `pain_changed`, `threat_anticipated`, `region_injured` signals.
- **Animation-agnostic.** The physics core reads `Skeleton3D.get_bone_pose()` — works with AnimationPlayer, AnimationTree, or custom animation systems.
- **All configuration via Resources.** `RagdollProfile` (skeleton mapping) and `RagdollTuning` (physics feel) are assignable on `KickbackCharacter`. Null = auto-detected Mixamo defaults.
- **Always-simulated rig.** Physics bodies never freeze. Springs are always active, driving bodies toward animation poses. Hit reactions reduce spring strength, letting physics take over temporarily. Gravity follows strength: each body's `gravity_scale` is `RagdollTuning.gravity_scale` (default 1.0) × (1 − strength ratio) — none at full strength (the springs hold the pose), real gravity when limp. There is no separate gravity multiplier any more (pre-0.4.1 a hidden 0.5 halved it).

### Active Ragdoll
- `PhysicsRigBuilder` creates 16 RigidBody3D + 15 Generic6DOFJoint3D
- `PhysicsRigSync` (a `SkeletonModifier3D`) writes physics transforms onto the skeleton each frame; the engine rolls the write back after skinning, so the spring's `get_bone_pose()` animation target stays clean
- `SpringResolver` drives physics bodies toward animation poses via velocity lerp
- `ActiveRagdollController` manages NORMAL → STAGGER/RAGDOLL → GETTING_UP → NORMAL state machine
- `STAGGER` state: springs reduced to floor strength, continuous sway force fights springs for visible wobble, Active Resistance dynamically adjusts per-bone strengths based on balance/CoM
- `PERSISTENT` state: stays ragdolled until `set_persistent(false)` is called

### Godot's built-in ragdoll (comparison demo only)
- `demo/partial_ragdoll_controller.gd` drives a `PhysicalBoneSimulator3D` for the
  side-by-side `demo.tscn` that contrasts Godot's built-in ragdoll against Kickback's
  active spring ragdoll. It is NOT part of the plugin — Kickback is the active ragdoll.

### Key technical decisions
- **RigidBody3D + Generic6DOFJoint3D** for active ragdoll (NOT PhysicalBone3D — see GODOT_CONSTRAINTS.md for why)
- **Two muscle modes** (`RagdollTuning.muscle_mode`): the legacy velocity-overwrite resolver (default) and 0.5.0's JOINT_MOTOR — the same command executed through Jolt 6DOF velocity motors with force limit = `muscle_torque` × strength ratio, gravity on (see docs/REFERENCE.md "Muscle layer"); script torque PD was measured and rejected (docs/MUSCLE_SPIKE.md)
- **Jolt physics required** — GodotPhysics cannot handle ragdoll joints
- **Animation stays active during ragdoll** — provides target poses for springs
- **Root motion stripping** — XZ of the root-motion bone's local pose is zeroed inside `SpringResolver.get_animation_bone_global`, so the root body, every descendant, and every other consumer of the animation target (foot/arm IK, the get-up blend) see the same root-motion-free pose — prevents drift from Mixamo animations with root motion
- **Honest status** — the muscle layer is a velocity-overwrite tracker (not bounded torques) and the 0.4.0 directed stumble is a scripted root displacement; see `docs/AUDIT_2026-09-12.md` for what is real, what is nominal, and the phase plan (muscle spike → motor muscle layer → balance/behaviors → arbiter)

## Conventions
- All scripts use `class_name` registration with `@icon()` annotations
- Controllers use `configure(profile, tuning)` pattern called by KickbackCharacter before `_ready()`
- Resources use `create_*_default()` factory methods for zero-config usage
- `SkeletonDetector.detect_humanoid_bones()` for auto-mapping any humanoid skeleton
- `KickbackRaycast.shoot_from_camera()` for one-line hit detection
- Collision: layer 4 (active ragdoll bodies); layer 5 (Godot built-in ragdoll, comparison demo only)
- Setup tool adds the active-ragdoll node set ("Add Kickback to Selected"); the assembly is `KickbackSetup.add_active_rig(root, skeleton, profile, tuning, scene_owner)` (static, editor-free — runtime spawners use the same call; paths are derived with `get_path_to`, so the Skeleton3D may sit at any depth, e.g. `Root/Model/Skeleton3D`)
- `KickbackCharacter.refresh_tuning()` after mutating a `RagdollTuning` at runtime; `get_setup_warnings()` for the validation list (includes `validate_against_skeleton`)

## character_root_path architecture
- `character_root_path` on KickbackCharacter and ActiveRagdollController must point to the gameplay root (the node that represents the character's world position)
- The setup tool defaults to `..` assuming Kickback nodes are direct children of the character root
- If Kickback nodes are inside a model sub-scene, override the path to reach the actual gameplay root (e.g., `../../MyCharacter`)
- Recovery teleports this node to the ragdoll landing position — pointing to the wrong node breaks character positioning

## CharacterBody3D integration

Kickback demos use Node3D roots. If your character uses CharacterBody3D:

- **Stop calling `move_and_slide()`** during RAGDOLL/GETTING_UP/PERSISTENT states — the physics rig drives position
- **Disable the CharacterBody3D collision shape** during reactions, re-enable after `recovery_finished`
- **Set `transfer_character_velocity = false`** in RagdollTuning if enemies walk toward threats (prevents ragdoll launching forward)
- **Use `get_active_state()`** to distinguish states for collision/movement logic:
  ```gdscript
  match kickback.get_active_state():
      ActiveRagdollController.State.RAGDOLL, \
      ActiveRagdollController.State.GETTING_UP, \
      ActiveRagdollController.State.PERSISTENT:
          return  # Ragdoll is driving — skip movement
  ```
- **Use `RagdollTuning.create_game_default()`** for amplified reactions suited to fast-paced games

## Locomotion with active ragdoll
- **All root movement and rotation MUST happen in `_physics_process`**, not `_process`. The spring resolver runs in `_physics_process` — modifying the root in `_process` causes spring targets to jump.
- Play animations once on state transitions, not every frame.

## What NOT to do
- Don't use PhysicalBone3D for the active ragdoll layer (root bone doesn't simulate in world space — see GODOT_CONSTRAINTS.md)
- Don't disable AnimationTree/AnimationPlayer during ragdoll (springs need target poses)
- Don't play animations directly from physics controllers (use signals)
- Don't move or rotate the character root in `_process` during active ragdoll — use `_physics_process`
