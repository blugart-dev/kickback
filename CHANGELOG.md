# Changelog

## [0.2.0] - 2026-03-18

### Added
- **Active ragdoll** — 16-bone physics rig with velocity-based spring resolver
- **Partial ragdoll** — PhysicalBoneSimulator3D for mid-range selective bone simulation
- **Flinch animations** — directional hit animations for far-range reactions
- **LOD system** — automatic tier selection based on camera distance with active ragdoll cap
- **Locomotion support** — spring resolver works with walk/run animations
- **Get-up recovery** — face-up/face-down detection, pose interpolation, staggered spring ramp
- **Weapon profiles** — resource-based presets (bullet, shotgun, explosion, melee, arrow)
- **Editor plugin** — "Add Kickback to Selected" one-click setup tool
- **Strength debug HUD** — F3-toggleable overlay showing per-bone spring strength
- **GUT test suite** — 27 automated tests across 7 files
- **KickbackManager** — global active ragdoll count cap and LOD distance thresholds

### Performance
- Cached bone indices in PhysicsRigSync (eliminated per-frame find_bone calls)
- Single-pass spring resolver loop (merged strength recovery + spring computation)
- Skip redundant property writes when physics values unchanged
- length_squared() for velocity clamping and settle detection

### Known Limitations
- Only supports Mixamo-compatible humanoid skeletons
- Requires Jolt Physics (GodotPhysics not supported)
- No inverse kinematics or foot planting
- Recovery repositioning assumes flat ground (raycast-based, but no slope adaptation)

## [0.1.0] - 2026-03-16

### Added
- Initial implementation (Steps 0-8)
- Basic passive ragdoll, partial ragdoll, and active ragdoll controllers
- Spring resolver with per-bone strength
- Physics rig builder for Mixamo humanoids
