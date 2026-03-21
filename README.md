# Kickback

**Physics-based reactive characters for Godot 4.6+**

Inspired by NaturalMotion's Euphoria engine (GTA IV/V, Red Dead Redemption). Characters react dynamically to gunshots, explosions, melee hits, and arrows using active ragdoll physics — every hit produces a unique, physically-driven reaction.

## Features

- **Active ragdoll** — 16 RigidBody3D physics skeleton tracks animation via velocity-based springs. Hits reduce spring strength so physics temporarily wins. Full ragdoll with automatic get-up recovery.
- **Stagger state** — between absorption and full ragdoll. Character visibly wobbles but stays on feet. Configurable threshold, duration, and escalation on follow-up hits.
- **Protected bones** — mark bones (e.g., legs) that never weaken from hits. Upper body reacts to impacts while legs stay animated and feet stay planted.
- **Partial ragdoll** (standalone alternative) — only the hit limb simulates via PhysicalBoneSimulator3D, blends back smoothly. Best for lightweight reactions on background NPCs.
- **Always-simulated rig** — physics bodies never freeze, springs are always active. Hit reactions feel immediate with no startup delay.
- **Skeleton auto-detection** — `SkeletonDetector` identifies humanoid bones in Mixamo, Rigify, Unreal Mannequin, and custom skeletons.
- **Animation-agnostic** — works with AnimationPlayer, AnimationTree, or any system that drives Skeleton3D bone poses. Controllers emit signals; animation is the user's responsibility.
- **Configurable everything** — skeleton mapping (`RagdollProfile`), physics tuning (`RagdollTuning`), impact parameters (`ImpactProfile`) — all via Resources with sensible defaults.
- **Hit detection utility** — `KickbackRaycast.shoot_from_camera()` handles raycast + routing in one line.
- **Debug gizmos** — F3 for color-coded bone dots on all characters (red=weak, yellow=recovering, green=full).
- **9 demo scenes** — comparison, shooting range, signals, tuning playground, stress test, animated NPC, ball throwing, tuning presets, protected bones.

## Requirements

- Godot 4.6.1+
- Jolt Physics (Project Settings > Physics > 3D > Physics Engine = "Jolt Physics")

## Installation

1. Copy the `addons/kickback/` folder into your project's `addons/` directory
2. Enable the plugin: Project > Project Settings > Plugins > Kickback > Enable
3. Verify Jolt Physics is active in Project Settings > Physics > 3D

## Quick Start

### 1. Add Kickback to your character

Select your character node (must have a `Skeleton3D` child), then:

**Project > Tools > "Add Kickback to Selected"**

Choose a mode:
- **Active Ragdoll** — full physics rig with springs. Stagger, ragdoll, recovery.
- **Partial Ragdoll** — lightweight bone-level reactions using PhysicalBoneSimulator3D.

Pick one per character. The plugin auto-detects humanoid bones and creates the controller nodes.

### 2. Send hits from your game

```gdscript
# One-line hit detection + routing:
func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        var profile := ImpactProfile.create_bullet()
        KickbackRaycast.shoot_from_camera(get_viewport(), event.position, profile)
```

Or manual routing:
```gdscript
var kickback: KickbackCharacter = character.get_node("KickbackCharacter")
kickback.receive_hit(hit_collider, hit_direction, hit_position, profile)
```

### 3. Impact profiles

```gdscript
ImpactProfile.create_bullet()     # Low impulse, high reduction, fast recovery
ImpactProfile.create_shotgun()    # Wide spread, 40% ragdoll chance
ImpactProfile.create_explosion()  # Massive impulse, upward bias, near-certain ragdoll
ImpactProfile.create_melee()      # Strong transfer, moderate ragdoll chance
ImpactProfile.create_arrow()      # Localized, moderate impulse
```

Or use the preset `.tres` files in `addons/kickback/presets/`.

### 4. Customize

- **Force stagger:** `kickback_character.trigger_stagger(hit_direction)`
- **Force ragdoll:** `kickback_character.trigger_ragdoll()`
- **Persistent ragdoll (death):** `kickback_character.set_persistent(true)` — revive with `set_persistent(false)`
- **Protected bones:** set `ragdoll_tuning.protected_bones` to keep legs (or any bones) animated during hits
- **Query state:** `is_ragdolled()`, `is_staggering()`, `get_active_state_name()`
- **Different skeleton?** Auto-detects, or create a `RagdollProfile` manually
- **Different physics feel?** Create a `RagdollTuning` resource
- **Find all characters:** `KickbackCharacter.find_all(scene_root)`

## Architecture

```
Character (Node3D)
├── KickbackCharacter (coordinator — detects mode, routes hits)
├── PhysicsRigBuilder (creates 16 RigidBody3D + 15 joints)
├── PhysicsRigSync (physics → skeleton bone overrides)
├── SpringResolver (animation → physics velocity springs)
└── ActiveRagdollController (NORMAL/STAGGER/RAGDOLL/GETTING_UP/PERSISTENT)
```

**Active Ragdoll signals** (connect for custom animation handling):
- `stagger_started(hit_direction)` — character wobbles, stays on feet
- `stagger_finished()` — recovered from stagger
- `ragdoll_started()` — full ragdoll triggered
- `recovery_started(face_up)` — getting up from ragdoll
- `recovery_finished()` — fully recovered
- `hit_absorbed(rig_name, strength)` — light hit, no state change

**Important:** All root movement and rotation must happen in `_physics_process`, not `_process`, to stay in sync with the spring resolver.

## Demo Scenes

Run any scene from `demo/` to see the plugin in action:

| Scene | What it shows |
|-------|--------------|
| `demo.tscn` | Active vs Partial side-by-side comparison |
| `shooting_range.tscn` | FPS controller, 5 targets, 5 weapon profiles |
| `signal_showcase.tscn` | Floating popups + log showing every signal |
| `tuning_playground.tscn` | Live sliders to adjust physics parameters |
| `stress_test.tscn` | 20 characters, mass ragdoll, budget system |
| `animated_npc.tscn` | Signal-driven NPC with full animation integration |
| `ball_throw.tscn` | Throw physics balls, velocity-scaled impact |
| `tuning_presets.tscn` | 5 characters: Tank/Standard/Loose/Fragile/Protected side-by-side |
| `protected_bones.tscn` | Protected vs unprotected legs — same hit, different result |

## Collision Layers

| Layer | Purpose | Used by |
|-------|---------|---------|
| 2 | Environment | StaticBody3D (floors, walls) |
| 4 | Active ragdoll bodies | PhysicsRigBuilder |
| 5 | Partial ragdoll bones | PhysicalBone3D |

Use `KickbackRaycast` which targets layers 4+5 automatically.

## Debug Tools

- **F3** — Toggle bone gizmos (color-coded dots on all characters)
- **Inspector** — Select KickbackCharacter to see setup status and validation
- **Visible Collision Shapes** (Debug menu) — See ragdoll collision shapes

## License

MIT
