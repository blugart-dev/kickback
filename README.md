# Kickback

**Physics-based reactive characters for Godot 4.6+**

Inspired by NaturalMotion's Euphoria engine (GTA IV/V, Red Dead Redemption). Characters react dynamically to gunshots, explosions, melee hits, and arrows using active ragdoll physics — every hit produces a unique, physically-driven reaction.

## Features

- **Active ragdoll** — 16 RigidBody3D physics skeleton tracks animation via velocity-based springs. Hits reduce spring strength so physics temporarily wins. Full ragdoll with automatic get-up recovery.
- **Partial ragdoll** (optional) — only the hit limb simulates via PhysicalBoneSimulator3D, blends back smoothly. Used as a cheaper alternative at distance.
- **Automatic LOD** — when both active and partial controllers are present, switches automatically based on camera distance with hysteresis to prevent flickering.
- **Always-simulated rig** — physics bodies never freeze, springs toggle between active (hit-reactive) and passive (animation tracking) modes. Zero visual snap on LOD transitions.
- **Node-based configuration** — add only the controllers you need. KickbackCharacter detects available siblings and adapts. One tier? No LOD switching.
- **Configurable setup tool** — "Add Kickback to Selected" offers presets: Full (Active + Partial) or Active Ragdoll Only.
- **Skeleton auto-detection** — `SkeletonDetector` identifies humanoid bones in Mixamo, Rigify, Unreal Mannequin, and custom skeletons.
- **Animation-agnostic** — works with AnimationPlayer, AnimationTree, or any system that drives Skeleton3D bone poses. No AnimationPlayer dependency in the physics core.
- **Configurable everything** — skeleton mapping (`RagdollProfile`), physics tuning (`RagdollTuning`), impact parameters (`ImpactProfile`) — all via Resources with sensible defaults.
- **Root motion stripping** — automatically strips horizontal root motion from the root bone so Mixamo animations with root motion work without drift.
- **Hit detection utility** — `KickbackRaycast.shoot_from_camera()` handles raycast + routing in one line.
- **Debug overlay** — F3 for per-bone spring strength, state, distance, FPS.

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

Choose a preset:
- **Full (Active + Partial)** — active ragdoll up close, partial ragdoll at distance
- **Active Ragdoll Only** — full physics at all distances, no LOD

The plugin will auto-detect humanoid bones, generate a `RagdollProfile`, and create the controller nodes.

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

- **Force ragdoll:** `kickback_character.trigger_ragdoll()`
- **Persistent ragdoll (death):** `kickback_character.set_persistent(true)` — revive with `set_persistent(false)`
- **Different skeleton?** Auto-detects, or create a `RagdollProfile` manually
- **Different physics feel?** Create a `RagdollTuning` resource
- **Find all characters:** `KickbackCharacter.find_all(scene_root)`

## Architecture

```
Character
├── KickbackCharacter (coordinator + configuration)
├── PhysicsRigBuilder (16 RigidBody3D + 15 Generic6DOFJoint3D)
├── PhysicsRigSync (physics → skeleton overrides)
├── SpringResolver (animation → physics velocity springs)
├── ActiveRagdollController (NORMAL/RAGDOLL/GETTING_UP/PERSISTENT state machine)
└── PartialRagdollController (optional — selective bone simulation at distance)
```

Controllers emit signals — connect to `recovery_started`, `recovery_finished`, `hit_absorbed` for custom animation handling.

**Important:** All root movement and rotation must happen in `_physics_process`, not `_process`, to stay in sync with the spring resolver.

## Collision Layers

| Layer | Purpose | Used by |
|-------|---------|---------|
| 2 | Environment | StaticBody3D (floors, walls) |
| 4 | Active ragdoll bodies | PhysicsRigBuilder |
| 5 | Partial ragdoll bones | PhysicalBone3D |

Use `KickbackRaycast` which targets layers 4+5 automatically.

## Debug Tools

- **F3** — Toggle debug overlay (per-bone spring strength, state, FPS)
- **Inspector** — Select KickbackCharacter to see setup status and validation
- **Visible Collision Shapes** (Debug menu) — See ragdoll collision shapes

## License

MIT
