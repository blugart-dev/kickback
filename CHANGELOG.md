# Changelog

## [0.5.0] - 2026-03-20

### Added
- **Stagger state** — new state between hit absorption and full ragdoll. Character visibly wobbles but stays on feet. Configurable via `RagdollTuning`: `stagger_threshold`, `stagger_duration`, `stagger_strength_floor`, `stagger_ragdoll_bonus`. Signals: `stagger_started(hit_direction)`, `stagger_finished()`.
- **`trigger_stagger(hit_dir)`** — force stagger from code via KickbackCharacter or ActiveRagdollController.
- **`is_staggering()`** — query whether character is in stagger state.
- **Debug gizmos rewrite** — self-contained, auto-discovers all KickbackCharacter nodes. Color-coded bone dots for active ragdoll (red/yellow/green by strength), cyan/yellow for partial ragdoll. Scales with distance. No configuration needed.
- **`StrengthDebugHUD.set_target()`** — optional API for dynamically switching which character the HUD displays.
- **5 demo scenes** in `demo/`:
  - `demo.tscn` — Active vs Partial side-by-side comparison
  - `shooting_range.tscn` — FPS controller with 5 targets and juicy weapon profiles
  - `signal_showcase.tscn` — floating 3D popups + signal log showing every signal
  - `tuning_playground.tscn` — live sliders for runtime parameter tuning
  - `stress_test.tscn` — 20 characters, mass ragdoll, budget slider

### Changed
- **No more LOD switching** — Active Ragdoll and Partial Ragdoll are independent modes. Pick one per character. `KickbackCharacter` uses `Mode` enum (ACTIVE/PARTIAL/NONE) set once at startup, replacing the `Tier` enum and runtime distance-based switching.
- **Setup tool presets** — "Active Ragdoll" and "Partial Ragdoll" replace "Full (Active + Partial)" and "Active Ragdoll Only".
- **Inspector status panel** — shows only controllers relevant to the detected mode.
- **KickbackManager** — now purely a budget manager. Removed `lod_distances` and `get_tier()`.
- Plugin version bumped to 0.5.0.

### Removed
- `Tier` enum, `tier_changed` signal, `force_tier()`, `clear_forced_tier()`, `get_current_tier()`, `get_tier_name()`
- `_process()` LOD distance logic in KickbackCharacter
- `_set_tier()` state machine (collision layer toggling, rig sync toggling)
- LOD zone visualization (Shift+F3)
- Per-bone strength table and legend from debug HUD (dots show it visually)

### Fixed
- PhysicalBoneSimulator3D colliders blocking active ragdoll raycasts
- `draw_polyline` crash with fewer than 2 points in debug HUD
- Debug HUD blocking mouse input (mouse_filter set to IGNORE)
- Camera snap during ragdoll recovery (smooth pivot lerp)

## [0.3.0] - 2026-03-20

### Added
- **Configurable architecture** — `RagdollProfile` (skeleton mapping) and `RagdollTuning` (physics feel) Resources replace all hardcoded constants. Factory methods provide zero-config defaults.
- **Composable animation** — `RagdollAnimator` handles animation playback via signals. Controllers emit intent (ragdoll_started, recovery_started, recovery_finished, flinch_triggered) instead of playing animations directly. Remove or extend the animator for custom behavior.
- **Skeleton auto-detection** — `SkeletonDetector` identifies humanoid bones in Mixamo, Rigify, Unreal Mannequin, and custom naming conventions. Auto-generates `RagdollProfile` and `PhysicalBone3D` nodes during setup.
- **Impact profile presets** — shipped in `addons/kickback/presets/` (bullet, shotgun, explosion, melee, arrow). Factory methods: `ImpactProfile.create_bullet()` etc.
- **KickbackRaycast** — static utility for one-line hit detection from camera: `KickbackRaycast.shoot_from_camera(viewport, pos, profile)`.
- **Editor inspector plugin** — custom status panel on KickbackCharacter showing setup validation, animation checklist, controller presence, and tips.
- **Scene tree icons** — custom SVG icons for all 9 node types via `@icon()` annotations.
- **Debug HUD refactor** — semi-transparent panel with organized sections (status, per-bone strength, color legend, FPS). Shift+F3 toggles LOD zone visualization (ground circles at tier distances).
- **Convenience API** — `KickbackCharacter.trigger_ragdoll()`, `force_tier()`, `clear_forced_tier()`, `get_expected_animations()`.
- **Setup report dialog** — shows bone detection results, animation status, collision layer guide, and quick-start code.
- **Doc comments** — `##` tooltips on all `@export` properties for Godot inspector.
- **Consolidated startup validation** — single message checks Jolt, animations, simulator, dictionary key typos.
- **Persistent ragdoll** — `set_persistent(true)` keeps character ragdolled indefinitely (death/knockdown). Reversible with `set_persistent(false)` which triggers normal recovery.
- **Slope-adapted recovery** — opt-in `RagdollTuning.align_to_slope` aligns character root to ground normal during get-up. Default off (upright recovery).
- **Ragdoll-to-ragdoll collision** — same-tier collision between characters (active↔active on layer 4, partial↔partial on layer 5). PhysicalBone3D nodes auto-configured with correct collision layers.
- **Demo scene** — `test_demo.tscn` with 5 patrolling AI agents, weapon switching (1-5), kill/revive (K/R), full Kickback integration. Demonstrates locomotion with active ragdoll.
- **PatrolAgent** — reusable test helper that walks between waypoints, handles Kickback signals (ragdoll, recovery, flinch), and owns all animation. Reference implementation for locomotion with active ragdoll.
- **`KickbackCharacter.setup_complete` signal** — emitted when initialization finishes. Game code should wait for this before starting gameplay.
- **`KickbackCharacter.is_setup_complete()`** — public getter for initialization status.

### Changed
- `WeaponProfile` renamed to `ImpactProfile` (weapon_name → profile_name)
- `FlinchController` now emits `Direction` enum (int) instead of animation name (String)
- Animation playback removed from `ActiveRagdollController`, `FlinchController`, `PartialRagdollController`
- Animation names moved from `RagdollTuning` to `RagdollAnimator`
- Test scenes consolidated from 12 to 7, reorganized into `test/scenes/`, `test/helpers/`, `test/unit/`
- Plugin version bumped to 0.3.0

### Fixed
- Jolt check deduplication (one warning instead of 7)
- Encapsulation violation: `_spring._skeleton` replaced with `get_skeleton()` getter
- Null safety in `PhysicsRigSync.set_active()`
- Signal type mismatch in test_combined.gd
- Removed references to deleted `animation_player_path` exports in unit tests

### Removed
- 5 redundant test scenes (passive_ragdoll, partial_ragdoll, flinch, physics_rig, active_ragdoll)
- `passive_ragdoll_controller.gd` (test utility, only used by deleted scene)
- `free_camera.gd` usage reduced (kept but only used by integration test)

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
- Humanoid skeletons only (auto-detected; non-humanoid not supported)
- Requires Jolt Physics (GodotPhysics not supported)
- No inverse kinematics or foot planting
- Recovery repositioning assumes flat ground (raycast-based, but no slope adaptation)

## [0.1.0] - 2026-03-16

### Added
- Initial implementation (Steps 0-8)
- Basic passive ragdoll, partial ragdoll, and active ragdoll controllers
- Spring resolver with per-bone strength
- Physics rig builder for Mixamo humanoids
