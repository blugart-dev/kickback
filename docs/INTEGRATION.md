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
          ├── RigidBody3D nodes created (live from creation — runtime bodies are never frozen)
          ├── bodies_built signal emitted
          └── set_enabled(false) — a no-op

Frame 5   KickbackCharacter finishes await
          ├── set_enabled(true) — first enable only: snaps a BAKED rig to the skeleton and
          │   unfreezes it (baked bodies are saved frozen); no-op for a runtime-built rig
          ├── PhysicsRigSync / SpringResolver activated
          ├── setup_complete signal emitted
          └── initial_state applied (if set)
```

`set_enabled(false)` does not freeze or stop anything; the rig is always simulated (the
springs are what hold it to the animation). To take a character out of physics, free the
rig or use the budget manager.

### Runtime tuning changes

The controllers copy several values out of `RagdollTuning` at configure time (velocity
clamps, root-motion stripping, chain consistency, feed-forward, protected bones). A bare
property write on the resource is not seen — call `KickbackCharacter.refresh_tuning()`
after mutating it at runtime. Build-time settings (collision layer / mask, joint limits,
`joint_limit_scale`, shapes) still need a rig rebuild.

### Setup warnings

`KickbackCharacter.get_setup_warnings()` returns the list `_ready()` also pushed with
`push_warning`: Jolt not active, the profile's bones / joints / roles / intermediate bones
checked against the real `Skeleton3D` (`RagdollProfile.validate_against_skeleton`), the
tuning checked against the profile, missing controller nodes. Setup is never aborted for
these — the builder skips bones it cannot find, so a mis-mapped rig runs with fewer bodies;
this is how to tell.

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

**queue_persistent_guided()** — the animation-guided death (below), spawn-safe:
```gdscript
anim_player.play("death_back")
kickback_char.queue_persistent_guided(0.5, 0.5)
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
| 5     | Godot built-in ragdoll (comparison demo) |

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

### Animation-guided deaths

`set_persistent(true)` zeroes every spring at once — a marionette with cut strings.
When you have an authored death clip, play it and call
`set_persistent_guided(strength_scale := 0.5, ramp_time := 0.5, ease := 1.0)`
instead: the state is PERSISTENT from the first frame, but every bone's spring keeps
chasing the animation at `base * strength_scale`, ramping to zero over `ramp_time`
(`scale(t) = strength_scale * (1 - t)^ease`; `ease` 1 = linear, 2 = drops fast then
trails off). The clip shapes the fall while physics — contacts, the killing shot's
impulse (hits stay pure impulse during the guide) — increasingly takes over; after
the ramp the body is exactly as limp as a plain persistent ragdoll (`guide_finished`
fires). The protective fall brace is NOT armed (the clip authors the catch).
`set_persistent(false)` releases it at any point. Notes:

- Play the death clip yourself, before or right after the call — the plugin never
  plays animations. In-place clips work best (the Hips XZ of the target is stripped
  by `strip_root_motion`; the clip's hips dropping to the floor is Y and desired).
- A kill on a body that is already RAGDOLL/GETTING_UP has no clip to guide — call
  plain `set_persistent(true)`; the guide is for deaths from NORMAL/STAGGER.
- `queue_persistent_guided(...)` is the spawn-safe form (starts on `setup_complete`).
- `is_guiding()` / `get_guide_scale()` expose the ramp for probes and debug HUDs.

### Get-up recovery moves the character root

When recovery starts, the controller teleports `character_root_path`'s node to
where the hips landed and yaws it to face the way the body lies. Three things
must be right for that to look clean:

- **Model forward axis.** The yaw math assumes the model faces **+Z** (Mixamo
  convention, matching the demos). If your character is authored with Godot's
  forward = **-Z**, set `RagdollTuning.character_forward_sign = -1` or every
  get-up stands the character up facing backwards.
- **`rig_sync_path` must be wired** on the ActiveRagdollController. After the
  teleport the controller forces an immediate skeleton pass (`sync_now`); if
  the path is empty, the character renders one frame with pre-teleport bone
  poses under the post-teleport root — a visible pop. (The editor setup tool,
  `KickbackSetup.add_active_rig()`, and the demos' `demo/demo_helpers.gd` all
  wire it; a hand-rolled runtime assembler must remember to.)
- **Physics interpolation** (`physics/common/physics_interpolation`) is handled:
  the controller calls `reset_physics_interpolation()` on the root and every
  rig body after the teleport, so no streaking occurs. Nothing to configure —
  just don't teleport the root yourself without the same reset.

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

## Muscle Mode (0.5.0)

`RagdollTuning.muscle_mode` selects how the rig is driven:

- `JOINT_MOTOR` (**default since 0.5.0**): every joint's Jolt angular motor drives the
  same command with a force limit of `BoneDefinition.muscle_torque ×
  muscle_strength_scale × strength ratio ^ muscle_strength_curve`; gravity stays on; a
  hit produces a real, torque-bounded reaction; a limp bone has a zero force limit. The
  pelvis gets a world joint for its orientation (`muscle_root_torque`) and keeps a
  scaled position pin (`muscle_root_pin`); both hold at full authority until the bone is
  limp (they stand in for balance until 0.6.0).
- `VELOCITY_OVERWRITE`: the 0.4.x resolver — exact tracking, gravity scaled out at full
  strength, hits erased unless strength drops. Set it on your `RagdollTuning` if you
  need the old feel exactly.

```gdscript
# Opt back into the 0.4.x resolver:
var tuning := RagdollTuning.create_default()
tuning.muscle_mode = RagdollTuning.MuscleMode.VELOCITY_OVERWRITE
kickback.ragdoll_tuning = tuning          # before setup, or at runtime:
kickback.ragdoll_tuning.muscle_mode = RagdollTuning.MuscleMode.VELOCITY_OVERWRITE
kickback.refresh_tuning()                 # the resolver switches modes on its next tick
```

What changes for you: `strength_map` no longer sets stiffness (the strength *ratio*
scales torque); tune `muscle_torque` per bone in the profile and `muscle_strength_scale`
globally; `muscle_gain` (per-tick fraction, default 0.10) is the tracking stiffness — do
not raise it past ~0.15. Measured numbers, tick-rate caveats (30 Hz needs
`foot_ik_disable_foot_collision = false`) and the open items are in REFERENCE.md
"Muscle layer" and docs/PLAN.md.

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

The KickbackCharacter inspector panel's **Tuning Presets** dropdown lists exactly these:
it is built from the zero-argument static `create_*` factories on `RagdollTuning`, so a
new factory shows up there without touching the panel.

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

**Death-only ragdoll:** Set `knockdown_enabled = false`. Hits keep all
their in-animation life (micro-reactions, pulses, stagger, stumble) but a
would-be knockdown downgrades to stagger — enemies never leave their feet
until an explicit `trigger_ragdoll()` / `set_persistent(true)` (the death).
No need to zero `ragdoll_probability` across every ImpactProfile.
