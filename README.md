# Kickback

Physics-based reactive characters for Godot 4.6+. Inspired by NaturalMotion's Euphoria engine (GTA IV/V, Red Dead Redemption).

Characters react dynamically to gunshots, explosions, melee hits, and arrows using active ragdoll physics, partial ragdoll simulation, and additive animation blending — layered by distance for performance.

## Status

🚧 **Work in progress** — being built incrementally, step by step.

## What it does

- **Close range**: Full active ragdoll — physics skeleton tracks animation via spring resolver, hits reduce spring strength so physics temporarily wins, producing unique reactions every time
- **Mid range**: Partial ragdoll — only the hit limb goes physics, blends back to animation
- **Far range**: Additive flinch animations — lightweight directional reactions
- **LOD system**: Automatically selects fidelity tier based on camera distance

## Requirements

- Godot 4.6.1+
- Jolt physics (built-in default)
- Humanoid skeleton with standard bone naming (Mixamo-compatible)

## Architecture

The active ragdoll uses **RigidBody3D + Generic6DOFJoint3D**, not PhysicalBone3D. This is a deliberate choice — PhysicalBone3D lacks `apply_force()`, `apply_torque()`, collision signals, and has broken joint springs with Jolt. Every successful Godot active ragdoll project bypasses it.

See `CLAUDE.md` for technical details and `docs/` for implementation docs.

## License

MIT
