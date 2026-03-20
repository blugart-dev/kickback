# Kickback

**Physics-based reactive characters for Godot 4.6+**

Inspired by NaturalMotion's Euphoria engine (GTA IV/V, Red Dead Redemption). Characters react dynamically to gunshots, explosions, melee hits, and arrows using active ragdoll physics — every hit produces a unique, physically-driven reaction.

## Features

- **Active ragdoll** (close range) — physics skeleton tracks animation via velocity-based springs. Hits reduce spring strength so physics temporarily wins. Full ragdoll with get-up recovery.
- **Partial ragdoll** (mid range) — only the hit limb goes physics via PhysicalBoneSimulator3D, blends back smoothly.
- **Flinch direction detection** (far range) — lightweight directional hit reactions, no physics cost.
- **Automatic LOD** — selects the right tier based on camera distance. Caps active ragdoll count for performance.
- **Composable animation** — `RagdollAnimator` handles animation playback via signals. Replace, extend, or remove it.
- **Skeleton auto-detection** — `SkeletonDetector` identifies humanoid bones in Mixamo, Rigify, Unreal Mannequin, and custom skeletons. Generates `RagdollProfile` and `PhysicalBone3D` nodes automatically.
- **Configurable everything** — skeleton mapping (`RagdollProfile`), physics tuning (`RagdollTuning`), impact parameters (`ImpactProfile`) — all via Resources with sensible defaults.
- **Editor tooling** — one-click setup creates 8 nodes, auto-detects bones, populates physical skeleton, shows setup report with animation checklist. Custom inspector panel shows validation status. Scene tree icons for all node types.
- **Hit detection utility** — `KickbackRaycast.shoot_from_camera()` handles raycast + routing in one line.
- **Debug overlay** — F3 for per-bone spring strength, tier, state, FPS. Shift+F3 for LOD zone visualization.

## Requirements

- Godot 4.6.1+
- Jolt Physics (Project Settings > Physics > 3D > Physics Engine = "Jolt Physics")

## Installation

1. Copy the `addons/kickback/` folder into your project's `addons/` directory
2. Enable the plugin: Project > Project Settings > Plugins > Kickback > Enable
3. Verify Jolt Physics is active in Project Settings > Physics > 3D

## Quick Start

### 1. Add Kickback to your character

Select your character node (must have a `Skeleton3D` and `AnimationPlayer` child), then:

**Project > Tools > "Add Kickback to Selected"**

The plugin will:
- Auto-detect humanoid bones (works with Mixamo, Rigify, Unreal Mannequin, and most naming conventions)
- Generate a `RagdollProfile` matched to your skeleton
- Create `PhysicalBoneSimulator3D` with physical bones if missing
- Wire up all 8 controller nodes
- Show a setup report with bone detection results and animation checklist

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

Use built-in factory methods:
```gdscript
ImpactProfile.create_bullet()     # Low impulse, high reduction, fast recovery
ImpactProfile.create_shotgun()    # Wide spread, 40% ragdoll chance
ImpactProfile.create_explosion()  # Massive impulse, upward bias, near-certain ragdoll
ImpactProfile.create_melee()      # Strong transfer, moderate ragdoll chance
ImpactProfile.create_arrow()      # Localized, moderate impulse
```

Or use the preset `.tres` files in `addons/kickback/presets/` for inspector drag-and-drop.

### 4. Customize (optional)

- **Different skeleton?** The plugin auto-detects — or create a `RagdollProfile` resource manually
- **Different physics feel?** Create a `RagdollTuning` resource (spring strengths, recovery timing, collision layers)
- **Custom animations?** Modify exports on `RagdollAnimator` or extend it
- **No animations?** Remove `RagdollAnimator` — pure physics ragdoll with spring-driven recovery
- **Force ragdoll from code?** `kickback_character.trigger_ragdoll()` (auto-recovers)
- **Persistent ragdoll (death/knockdown)?** `kickback_character.set_persistent(true)` — revive with `set_persistent(false)`
- **Override LOD tier?** `kickback_character.force_tier(KickbackCharacter.Tier.ACTIVE_RAGDOLL)`
- **Slope-adapted recovery?** Set `RagdollTuning.align_to_slope = true`

## Collision Layers

| Layer | Purpose | Used by |
|-------|---------|---------|
| 1 | Character controllers | CharacterBody3D |
| 2 | Environment | StaticBody3D (floors, walls) |
| 4 | Active ragdoll bodies | PhysicsRigBuilder creates these |
| 5 | Partial ragdoll bones | PhysicalBone3D |

Your weapon raycast should target layers 4 and 5.
Or use `KickbackRaycast` which handles this automatically.

## Architecture

```
Character
├── KickbackCharacter (LOD routing + configuration)
├── Tier 1: Active Ragdoll (<10m)
│   ├── PhysicsRigBuilder (16 RigidBody3D + 15 joints)
│   ├── PhysicsRigSync (physics → skeleton)
│   ├── SpringResolver (animation → physics springs)
│   └── ActiveRagdollController (hit/ragdoll/recovery state machine)
├── Tier 2: Partial Ragdoll (10-25m)
│   └── PartialRagdollController (selective bone simulation)
├── Tier 3: Flinch (25-50m)
│   └── FlinchController (direction calculator, emits signal)
└── Animation (optional)
    └── RagdollAnimator (listens to signals, plays animations)
```

Controllers emit signals — `RagdollAnimator` is a default handler you can replace or remove.

## Debug Tools

- **F3** — Toggle debug overlay (per-bone spring strength, tier, state, distance, FPS)
- **Shift+F3** — Toggle LOD zone visualization (colored ground circles at 10m/25m/50m)
- **Inspector** — Select KickbackCharacter to see setup status, animation checklist, and tips
- **Visible Collision Shapes** (Debug menu) — See ragdoll collision shapes

## Testing

27 automated tests using [GUT](https://github.com/bitwes/Gut):

```bash
godot --headless -s addons/gut/gut_cmdln.gd
```

8 interactive test scenes in `test/scenes/` for visual verification, including a full demo with 5 patrolling AI agents (`test_demo.tscn`).

**Important:** When moving characters with active ragdoll, all root movement and rotation must happen in `_physics_process`, not `_process`. See `test/helpers/patrol_agent.gd` for a reference implementation.

## License

MIT
