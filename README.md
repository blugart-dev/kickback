# Kickback

**Physics-based reactive characters for Godot 4.6+**

Inspired by NaturalMotion's Euphoria engine (GTA IV/V, Red Dead Redemption). Characters react dynamically to gunshots, explosions, melee hits, and arrows using active ragdoll physics — every hit produces a unique, physically-driven reaction.

## Features

- **Active ragdoll** — 16 RigidBody3D physics skeleton tracks animation via velocity-based springs. Hits reduce spring strength so physics temporarily wins. Full ragdoll with automatic get-up recovery.
- **Stagger state** — between absorption and full ragdoll. Character visibly wobbles but stays on feet. Configurable threshold, duration, and escalation on follow-up hits.
- **Balance tracking** — center of mass vs foot support polygon drives stagger behavior. Characters that lean too far ragdoll; balanced characters recover early. Physics-informed, not timer-based.
- **Momentum transfer** — running characters carry their velocity into ragdoll, tumbling forward instead of dropping in place.
- **Fatigue** — repeated hits degrade effective spring strength over time. Fatigued characters wobble more at baseline and recover to lower maxes. Decays slowly between engagements.
- **Hit stacking** — rapid consecutive hits escalate via streak multiplier. Hits during recovery can interrupt get-up and re-ragdoll the character.
- **Reaction pulses** — sub-stagger hits produce a brief visible wobble that fades over 200ms. Even light hits are noticeable.
- **Directional bracing** — during stagger, bones opposite the hit direction strengthen while hit-side bones weaken further. Characters visibly fight to stay upright.
- **Cumulative pain** — sustained fire deterministically escalates reactions (flinch → stagger → ragdoll) instead of relying on dice rolls. Pain decays between engagements.
- **Movement-aware hits** — running characters are less stable and stagger more easily. Stagger direction blends with movement direction for natural stumbling.
- **Threat anticipation** — `anticipate_threat(direction, urgency)` API for pre-hit flinch. Call when bullets fly nearby or an enemy winds up an attack.
- **Micro hit reactions** — torso bend, head whip, and spin torque at the moment of impact. Every hit has a visceral split-second reaction.
- **Regional impairment** — persistent per-bone injury that outlasts spring recovery. Shot in the leg causes visible sag/limp. Shot in the arm makes it dangle. Injuries heal slowly.
- **Protected bones** — mark bones (e.g., legs) that never weaken from hits. Upper body reacts to impacts while legs stay animated and feet stay planted.
- **Partial ragdoll** (standalone alternative) — only the hit limb simulates via PhysicalBoneSimulator3D, blends back smoothly. Best for lightweight reactions on background NPCs.
- **Always-simulated rig** — physics bodies never freeze, springs are always active. Hit reactions feel immediate with no startup delay.
- **Skeleton auto-detection** — `SkeletonDetector` identifies humanoid bones in Mixamo, Rigify, Unreal Mannequin, and custom skeletons.
- **Animation-agnostic** — works with AnimationPlayer, AnimationTree, or any system that drives Skeleton3D bone poses. Controllers emit signals; animation is the user's responsibility.
- **Configurable everything** — skeleton mapping (`RagdollProfile`), physics tuning (`RagdollTuning`), impact parameters (`ImpactProfile`) — all via Resources with sensible defaults.
- **Hit detection utility** — `KickbackRaycast.shoot_from_camera()` handles raycast + routing in one line.
- **Debug gizmos** — F3 cycles through 3 detail levels: bone dots → skeleton wireframe + state labels → full dashboard with status panels, center of mass, velocity vectors, and balance/fatigue bars.
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
- **Query balance:** `active_controller.get_balance_ratio()` — 0.0 = balanced, 1.0+ = off-balance
- **Query fatigue:** `active_controller.get_fatigue()` — 0.0 = fresh, 1.0 = exhausted
- **Reset fatigue:** `active_controller.reset_fatigue()` — on healing or respawn
- **Query hit streak:** `active_controller.get_hit_streak()` — rapid consecutive hit count
- **Query pain:** `active_controller.get_pain()` — cumulative damage level
- **Pre-hit flinch:** `kickback_character.anticipate_threat(direction, urgency)` — defensive lean before impact
- **Query injuries:** `active_controller.get_injury(rig_name)` — per-bone injury level
- **Reset injuries:** `active_controller.reset_injuries()` — heal all injuries
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
- `balance_changed(ratio)` — CoM balance ratio during stagger (0.0 = balanced, 1.0 = falling)
- `fatigue_changed(level)` — fatigue from repeated hits (0.0 = fresh, 1.0 = exhausted)
- `recovery_interrupted()` — hit during get-up knocked character back down
- `pain_changed(level)` — cumulative pain from sustained hits (0.0-1.0)
- `threat_anticipated(direction, urgency)` — anticipate_threat() was called
- `region_injured(rig_name, severity)` — bone sustained persistent injury

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

- **F3** — Cycle debug gizmos: Off → Dots → Wireframe + state → Full dashboard (panels, CoM, velocity)
- **Inspector** — Select KickbackCharacter to see setup status and validation
- **Visible Collision Shapes** (Debug menu) — See ragdoll collision shapes

## License

MIT
