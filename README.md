# Kickback

**Physics-based reactive characters for Godot 4.6+**

Inspired by NaturalMotion's Euphoria engine (GTA IV/V, Red Dead Redemption). Characters react dynamically to gunshots, explosions, melee hits, and arrows using active ragdoll physics — every hit produces a unique, physically-driven reaction.

## Features

- **Active ragdoll** (close range) — physics skeleton tracks animation via velocity-based springs. Hits reduce spring strength so physics temporarily wins, producing unique reactions every time. Full ragdoll with get-up recovery.
- **Partial ragdoll** (mid range) — only the hit limb goes physics via PhysicalBoneSimulator3D, blends back smoothly.
- **Flinch animations** (far range) — lightweight directional hit reactions, no physics cost.
- **Automatic LOD** — selects the right tier based on camera distance. Caps active ragdoll count for performance.
- **Weapon profiles** — resource-based presets (bullet, shotgun, explosion, melee, arrow) control impulse, ragdoll chance, recovery speed.
- **Editor tooling** — one-click "Add Kickback to Selected" sets up all 7 controller nodes automatically.

## Requirements

- Godot 4.6.1+
- Jolt Physics (Project Settings > Physics > 3D > Physics Engine = "Jolt Physics")
- Humanoid skeleton with Mixamo-compatible bone naming

## Installation

1. Copy the `addons/kickback/` folder into your project's `addons/` directory
2. Enable the plugin: Project > Project Settings > Plugins > Kickback > Enable
3. Verify Jolt Physics is active in Project Settings > Physics > 3D

## Quick Start

### 1. Add Kickback to your character

Select your character node (must have a `Skeleton3D` and `AnimationPlayer` child), then:

**Project > Tools > "Add Kickback to Selected"**

This creates all required controller nodes with pre-wired paths:
- `KickbackCharacter` — LOD coordinator
- `PhysicsRigBuilder` — creates the physics ragdoll rig
- `PhysicsRigSync` — syncs physics bodies to visible skeleton
- `SpringResolver` — drives springs toward animation poses
- `ActiveRagdollController` — close-range state machine
- `PartialRagdollController` — mid-range hit reactions
- `FlinchController` — far-range animation reactions

### 2. Send hits from your game

```gdscript
# Get the KickbackCharacter node on your character
var kickback: KickbackCharacter = character.get_node("KickbackCharacter")

# Route a hit through the LOD system (picks the right tier automatically)
kickback.receive_hit(hit_collider, hit_direction, hit_position, weapon_profile)
```

### 3. Create weapon profiles

Create `.tres` resources extending `WeaponProfile`:

```
Impulse:
  base_impulse: 8.0        # Force applied to hit body
  impulse_transfer_ratio: 0.3  # Fraction transferred (0-1)
  upward_bias: 0.0         # Extra upward force (explosions: 0.4)

Ragdoll:
  ragdoll_probability: 0.05  # Chance of full ragdoll (0-1)
  strength_reduction: 0.4    # Spring strength drop on hit (0-1)
  strength_spread: 1         # Neighbor bones affected

Recovery:
  recovery_rate: 1.5         # Spring recovery per second
```

Presets included: `bullet.tres`, `shotgun.tres`, `explosion.tres`, `melee.tres`, `arrow.tres`

## Collision Layers

Kickback uses these collision layers (configure in Project Settings):

| Layer | Purpose | Used by |
|-------|---------|---------|
| 1 | Character controllers | CharacterBody3D |
| 2 | Environment | StaticBody3D (floors, walls) |
| 3 | Props / dynamic objects | Interactable RigidBody3D |
| 4 | Active ragdoll bodies | PhysicsRigBuilder creates these |
| 5 | Partial ragdoll bones | PhysicalBone3D |

Your weapon raycast should target layers 4 and 5: `collision_mask = (1 << 3) | (1 << 4)`

## Architecture

The active ragdoll uses **RigidBody3D + Generic6DOFJoint3D**, not PhysicalBone3D. This is deliberate — PhysicalBone3D lacks `apply_force()`, `apply_torque()`, collision signals, and has broken joint springs with Jolt.

The spring resolver uses velocity-based control (not torque PD). Each frame: compute rotation error per bone, convert to target angular velocity, lerp current velocity toward target weighted by per-bone strength. Strength reduction on hit lets physics win temporarily.

```
Character
├── KickbackCharacter (LOD routing)
├── Tier 1: Active Ragdoll (<10m)
│   ├── PhysicsRigBuilder (16 RigidBody3D + 15 joints)
│   ├── PhysicsRigSync (physics → skeleton)
│   ├── SpringResolver (animation → physics springs)
│   └── ActiveRagdollController (hit/ragdoll/recovery state machine)
├── Tier 2: Partial Ragdoll (10-25m)
│   └── PartialRagdollController (selective bone simulation)
└── Tier 3: Flinch (25-50m)
    └── FlinchController (directional animations)
```

## Debug Tools

- **F3** — Toggle strength debug overlay (colored dots showing per-bone spring strength)
- **Visible Collision Shapes** (Debug menu) — See ragdoll collision shapes

## Testing

27 automated tests using [GUT](https://github.com/bitwes/Gut):

```bash
# Headless
godot --headless -s addons/gut/gut_cmdln.gd

# In-editor
# GUT bottom panel > Run All
```

12 manual test scenes in `test/` for visual verification.

## Documentation

- `docs/STEP_BY_STEP.md` — Implementation plan (8 steps + 6 milestones)
- `docs/GODOT_CONSTRAINTS.md` — Engine quirks and workarounds
- `docs/REFERENCE.md` — Math, bone mapping, weapon profile specs

## License

MIT
