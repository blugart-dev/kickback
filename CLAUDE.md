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
│       ├── kickback_character.gd    # Coordinator (detects mode, routes hits)
│       ├── kickback_manager.gd      # Global budget manager
│       ├── kickback_raycast.gd      # Hit detection utility (one-liner)
│       ├── skeleton_detector.gd     # Auto-detect humanoid bones in any skeleton
│       ├── physics_rig_builder.gd   # Builds RigidBody3D ragdoll rig
│       ├── physics_rig_sync.gd      # Syncs physics → visible skeleton
│       ├── spring_resolver.gd       # Velocity-based spring pose matching
│       ├── active_ragdoll_controller.gd  # State machine (NORMAL/STAGGER/RAGDOLL/GETTING_UP/PERSISTENT)
│       ├── partial_ragdoll_controller.gd # Standalone selective bone simulation
│       ├── physics_collision_monitor.gd # Optional ragdoll-environment collision observer
│       ├── hit_event.gd             # Hit data object
│       ├── jolt_check.gd            # Jolt physics verification
│       ├── strength_debug_hud.gd    # F3 debug gizmos (auto-discovers all characters)
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
├── demo/                            # Demo scenes (not part of plugin)
│   ├── demo.tscn/gd                 # Side-by-side Active vs Partial comparison
│   ├── shooting_range.tscn/gd       # FPS shooting range with 5 weapon profiles
│   ├── signal_showcase.tscn/gd      # Visualizes all signals with floating popups
│   ├── tuning_playground.tscn/gd    # Live sliders to tweak physics parameters
│   ├── stress_test.tscn/gd          # 20 characters, budget system, mass ragdoll
│   ├── animated_npc.tscn/gd         # Signal-driven NPC with full animation lifecycle
│   ├── ball_throw.tscn/gd           # Throw physics balls, velocity-scaled impact
│   ├── tuning_presets.tscn/gd       # 5 characters: Tank/Standard/Loose/Fragile/Protected
│   ├── protected_bones.tscn/gd      # Protected vs unprotected legs comparison
│   └── euphoria_showcase.tscn/gd   # All v0.7 features: active resistance, sway, pain, injuries
├── assets/                          # Demo character (not part of plugin)
│   ├── characters/ybot/
│   └── animations/ybot/             # 21 animations (idle, walk, run, flinch, get-up, react, injured, kip-up)
└── project.godot
```

## Architecture

### Design principles
- **Physics controllers emit signals, don't play animations.** Animation handling is the user's responsibility. Connect to `stagger_started`, `recovery_started`, `recovery_finished`, `hit_absorbed`, `balance_changed`, `fatigue_changed`, `recovery_interrupted`, `pain_changed`, `threat_anticipated`, `region_injured` signals.
- **Animation-agnostic.** The physics core reads `Skeleton3D.get_bone_pose()` — works with AnimationPlayer, AnimationTree, or custom animation systems.
- **All configuration via Resources.** `RagdollProfile` (skeleton mapping) and `RagdollTuning` (physics feel) are assignable on `KickbackCharacter`. Null = auto-detected Mixamo defaults.
- **Pick one mode per character.** Active Ragdoll or Partial Ragdoll — KickbackCharacter detects which controller is present and uses it. No runtime switching between modes.
- **Always-simulated rig (Active Ragdoll).** Physics bodies never freeze. Springs are always active, driving bodies toward animation poses. Hit reactions reduce spring strength, letting physics take over temporarily.

### Active Ragdoll
- `PhysicsRigBuilder` creates 16 RigidBody3D + 15 Generic6DOFJoint3D
- `PhysicsRigSync` writes physics transforms to skeleton as bone pose overrides
- `SpringResolver` drives physics bodies toward animation poses via velocity lerp
- `ActiveRagdollController` manages NORMAL → STAGGER/RAGDOLL → GETTING_UP → NORMAL state machine
- `STAGGER` state: springs reduced to floor strength, continuous sway force fights springs for visible wobble, Active Resistance dynamically adjusts per-bone strengths based on balance/CoM
- `PERSISTENT` state: stays ragdolled until `set_persistent(false)` is called

### Partial Ragdoll (standalone alternative)
- `PartialRagdollController` uses PhysicalBoneSimulator3D for selective bone simulation
- Independent mode — not used alongside Active Ragdoll on the same character
- Best for lightweight bone-level reactions on background NPCs

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
- Setup tool offers presets: "Active Ragdoll" or "Partial Ragdoll"

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
- Don't use Active Ragdoll and Partial Ragdoll on the same character simultaneously
