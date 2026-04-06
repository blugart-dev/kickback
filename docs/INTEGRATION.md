# Integration Guide

Practical guide for integrating Kickback into a game project. Covers the
timing contracts, collision setup, state machine, and common patterns that
aren't obvious from the API reference alone.

---

## Setup Timing

KickbackCharacter defers initialization across multiple frames to let Godot
finish scene instantiation. Understanding this timing is essential.

### Timeline

```
Frame 0   KickbackCharacter._ready() starts
          ├── configure() called on all controllers
          ├── PhysicsRigBuilder._ready() starts (awaits 2 frames)
          └── begins 5-frame await

Frame 2   PhysicsRigBuilder._build_rig() runs
          ├── RigidBody3D nodes created
          ├── bodies_built signal emitted
          └── set_enabled(false) freezes bodies

Frame 5   KickbackCharacter finishes await
          ├── set_enabled(true) unfreezes bodies
          ├── setup_complete signal emitted
          └── initial_state applied (if set)
```

### When is it safe to call APIs?

| API                         | Safe after             |
|-----------------------------|------------------------|
| `get_bodies()`              | `bodies_built` signal  |
| `trigger_ragdoll()`         | `setup_complete` signal|
| `receive_hit()`             | `setup_complete` signal|
| `get_active_state()`        | Immediately            |
| `is_setup_complete()`       | Immediately            |

### Spawning ragdolled characters

Three options, from simplest to most flexible:

**Inspector export** — set `initial_state` to "Ragdoll" or "Persistent":
```gdscript
# In the scene tree, set KickbackCharacter.initial_state = "Ragdoll"
# The character will ragdoll automatically after setup completes.
```

**queue_ragdoll()** — safe to call immediately after instantiation:
```gdscript
var character = preload("res://enemy.tscn").instantiate()
add_child(character)
character.get_node("KickbackCharacter").queue_ragdoll()
# No need to wait for setup — it will ragdoll when ready.
```

**queue_persistent()** — same pattern for death/knockdown:
```gdscript
kickback_char.queue_persistent()
```

### Configuring bodies after spawn

Use `await_bodies()` on PhysicsRigBuilder to wait for bodies to exist:
```gdscript
var bodies: Dictionary = await rig_builder.await_bodies()
for body: RigidBody3D in bodies.values():
    body.contact_monitor = true
    body.max_contacts_reported = 4
```

Or connect to `bodies_built`:
```gdscript
rig_builder.bodies_built.connect(func():
    var bodies = rig_builder.get_bodies()
    # configure bodies here
)
```

---

## Physics Layers

### Defaults

| Property         | Value | Meaning                              |
|------------------|-------|--------------------------------------|
| `collision_layer`| 8     | Layer 4 — ragdoll bodies live here   |
| `collision_mask` | 15    | Layers 1,2,3,4 — what bodies collide with |

### Layer 1 (environment)

Layer 1 is Godot's default collision layer for all physics bodies. Kickback's
default mask includes layer 1, so ragdoll bodies collide with standard
environment geometry out of the box.

If your environment uses a non-default layer, update `RagdollTuning.collision_mask`
to include it.

### Recommended layer assignment

| Layer | Purpose              |
|-------|----------------------|
| 1     | Environment (floors, walls, static geometry) |
| 2     | Projectiles / raycasts |
| 3     | Player               |
| 4     | Active ragdoll bodies |
| 5     | Partial ragdoll bones |

These are suggestions — adapt to your project's layer scheme. The important
thing is that `collision_mask` on RagdollTuning overlaps with your environment's
`collision_layer`.

### Overriding per-character

```gdscript
var tuning := RagdollTuning.create_default()
tuning.collision_layer = 1 << 5  # Layer 6
tuning.collision_mask = 1 | (1 << 5)  # Layers 1 and 6
kickback_char.ragdoll_tuning = tuning
```

---

## State Machine

```
NORMAL ────hit────→ STAGGER ───balance/timer──→ NORMAL
  │                    │                          ↑
  │ (ragdoll_prob)     │ (balance_ragdoll)        │
  ↓                    ↓                          │
RAGDOLL ──settle──→ GETTING_UP ──converge─────────┘
  │
  │ set_persistent(true)
  ↓
PERSISTENT ──set_persistent(false)──→ GETTING_UP
```

### Signal timing

| Transition                | Signal emitted          | When to use                |
|---------------------------|-------------------------|----------------------------|
| Any → STAGGER             | `stagger_started`       | Play stumble animation     |
| STAGGER → NORMAL          | `stagger_finished`      | Return to idle/locomotion  |
| Any → RAGDOLL             | `ragdoll_started`       | Disable movement, stop AI  |
| RAGDOLL → GETTING_UP      | `recovery_started`      | Play get-up animation      |
| GETTING_UP → NORMAL       | `recovery_finished`     | Re-enable movement/AI      |
| GETTING_UP → RAGDOLL      | `recovery_interrupted`  | Hit during get-up          |
| Each hit (sub-stagger)    | `hit_absorbed`          | Flinch VFX, UI feedback    |
| Every STAGGER frame       | `balance_changed`       | UI balance meter           |
| Pain changes              | `pain_changed`          | Injury animations, limp    |
| Fatigue changes           | `fatigue_changed`       | Exhaustion animations      |
| Bone injury               | `region_injured`        | Persistent impairment VFX  |

### Checking state in code

```gdscript
match kickback_char.get_active_state():
    ActiveRagdollController.State.NORMAL:
        # Full animation control
        pass
    ActiveRagdollController.State.STAGGER:
        # On feet but unsteady — consider reducing movement speed
        pass
    ActiveRagdollController.State.RAGDOLL, \
    ActiveRagdollController.State.GETTING_UP, \
    ActiveRagdollController.State.PERSISTENT:
        # Physics is driving — skip movement/navigation
        return
```

---

## Impact Scoring (Collision Monitoring)

To detect when ragdoll bodies hit the environment (for scoring, sound, VFX),
use `PhysicsCollisionMonitor` — an optional sibling component.

### Setup

Add `PhysicsCollisionMonitor` as a sibling to your `KickbackCharacter` node.
It auto-discovers the character and connects after setup completes.

### Connecting

```gdscript
@onready var monitor: PhysicsCollisionMonitor = $PhysicsCollisionMonitor

func _ready():
    monitor.body_impact.connect(_on_body_impact)

func _on_body_impact(bone_name: String, velocity: float, contact_body: Node3D):
    var score = velocity * 10.0
    if bone_name == "Head":
        score *= 2.0
    add_score(score)
    spawn_impact_vfx(contact_body.global_position)
```

### Configuration

| Property              | Default | Description                                  |
|-----------------------|---------|----------------------------------------------|
| `velocity_threshold`  | 2.0     | Minimum speed (m/s) to emit signal           |
| `cooldown`            | 0.3     | Per-bone silence period after each emission   |
| `monitored_bones`     | `[]`    | Empty = all bones; populate to filter         |
| `filter_self_collisions` | true | Ignore bone-on-bone contacts from same rig   |

### Do NOT route through receive_hit()

`body_impact` is for passive observation only. Calling `receive_hit()` from
a `body_entered` or `body_impact` callback creates a feedback loop:

```
hit → impulse → body moves → new contact → receive_hit() → impulse → ...
```

The per-frame debounce guard in `apply_hit()` mitigates crashes, but the
pattern is still wrong. Use `body_impact` for scoring and VFX; use
`receive_hit()` only for discrete external events (bullets, explosions, melee).

---

## Tuning Presets

Factory methods on `RagdollTuning` for common character archetypes:

| Method                | Use case                                    |
|-----------------------|---------------------------------------------|
| `create_default()`    | Balanced baseline                           |
| `create_game_default()` | Action games — amplified micro-reactions  |
| `create_tank()`       | Tough enemies — high thresholds, fast recovery |
| `create_agile()`      | Nimble characters — stagger easy, recover fast |
| `create_fragile()`    | Ragdoll-prone — falls under sustained fire  |
| `create_responsive()` | Fast-paced action — low stagger, snappy reactions |
| `create_heavy()`      | Realistic sims — high damping, slow recovery |

### Composing custom presets

Start from a factory method and override specific values:

```gdscript
var tuning := RagdollTuning.create_responsive()
tuning.stagger_threshold = 0.5  # harder to stagger than default responsive
tuning.protected_bones = PackedStringArray(["Foot_L", "Foot_R"])
kickback_char.ragdoll_tuning = tuning
```

### Key tuning parameters by game type

**Action / arcade:** Low `stagger_duration` (0.3–0.5), high `recovery_rate`
(0.8–1.0), high `micro_reaction_strength` (1.2+). Players want snappy
feedback and fast return to gameplay.

**Realistic / simulation:** High `stagger_duration` (1.5–2.5), low
`recovery_rate` (0.1–0.3), high `angular_damp` (3.0+). Characters feel
heavy and grounded.

**Comedy / slapstick:** Low `stagger_strength_floor` (0.05–0.15), high
`stagger_ragdoll_bonus` (2.0+), low spring strengths across the board.
Characters flop dramatically.

**Boss enemies:** Use `create_tank()` as a base. High `stagger_threshold`
(0.2–0.3) so most hits are absorbed. High `protected_bones` to keep legs
locked. Slow `fatigue_decay` so sustained fire eventually overwhelms.
