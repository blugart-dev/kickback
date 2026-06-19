# Changelog

> **Versioning recalibrated 2026-06-19.** `1.0.0` now means full Euphoria parity
> (see [VERSIONING.md](docs/VERSIONING.md)). The project was re-baselined from `0.8.5`
> to `0.3.0` to honestly reflect difficulty-weighted progress (~30%). Entries under
> **Legacy history** below use the old, inconsistent numbering and are **not comparable**
> to current versions.

## [0.3.0] - 2026-06-19

### Changed
- **Versioning recalibrated** — re-baselined `0.8.5` → `0.3.0`; `1.0.0` is now full
  Euphoria parity. Deleted the old `v0.7.0` / `v0.8.0` / `v0.8.5` releases and tags.
  Added [VERSIONING.md](docs/VERSIONING.md) and [ROADMAP.md](docs/ROADMAP.md) (with a
  difficulty-weighted parity scorecard) and re-scored
  [EUPHORIA_COMPARISON.md](docs/EUPHORIA_COMPARISON.md) with honest real/partial/nominal
  classifications.
- **Upgraded to Godot 4.7** — `project.godot` features, all documentation version
  references, and CI (both the `tests` and `release` workflows) bumped from 4.6.1 to 4.7.
  Validated: clean headless import + GUT suite passing.

### Added
- **Semantic role accessors on `RagdollProfile`** — `get_root_rig`, `get_chest_rig`,
  `get_head_rig`, `get_torso_rigs`, `get_foot_rigs`, `get_leg_chain`, `get_all_leg_rigs`,
  `is_leg_rig`, `get_leg_side`, and `get_root_skeleton_bone`, backed by overridable
  `root_rig`/`chest_rig`/`head_rig`/`torso_rigs`/`foot_rigs`/`left_leg_chain`/`right_leg_chain`
  export fields (defaulting to the Mixamo convention). The controller, `FootIKSolver`, and
  debug HUD query these instead of hardcoding `"Hips"`/`"Foot_L"`/…, so non-Mixamo rigs work
  by overriding the role fields. List accessors filter out names that don't map to a defined
  bone, so a missing body degrades gracefully. `validate_against_skeleton` now flags role
  names that don't reference a defined rig bone.
- **`KickbackLayers`** — named collision-layer constants (active ragdoll = UI layer 4,
  partial ragdoll = UI layer 5) replacing magic numbers in `KickbackRaycast` and
  `SkeletonDetector`.
- **Runtime / physics smoke tests** — the first automated coverage of the physics runtime
  (previously 0 %). The GUT suite now builds a real rig in a headless `SceneTree` — a
  synthetic Mixamo-named skeleton wired to `PhysicsRigBuilder` + `SpringResolver` +
  `PhysicsRigSync` + `ActiveRagdollController` via `KickbackCharacter` — steps Jolt physics,
  and asserts rig construction (16 bodies / 15 joints, bodies snapped to bone globals),
  spring tracking against gravity, `apply_hit` strength reduction, full ragdoll → recovery,
  stagger and persistent transitions, physics→skeleton sync, and the real `FootIKSolver`
  planting feet over ground. `test_state_machine.gd` and `test_foot_ik.gd` were refactored
  to drive the real controller/solver rather than re-implement their formulas. Shared
  builder: `test/helpers/rig_harness.gd`. Also covers the budget hard cap (downgrade vs
  bypass, slot accounting). Suite is now 89 tests.
- **`SkeletonModifier3D` migration — docs + Godot 4.7 investigation** —
  [docs/SKELETON_MODIFIER_MIGRATION.md](docs/SKELETON_MODIFIER_MIGRATION.md) records the
  rationale and as-built notes, grounded in a 4.7 investigation (4.7 leaves the
  skeleton/modifier subsystem unchanged; the modifier's per-frame roll-back is what preserves
  the spring's clean `get_bone_pose()` read target). The migration itself shipped — see
  *Changed* below. Cross-linked from `GODOT_CONSTRAINTS.md` and `ROADMAP.md`.

### Fixed
- **Multi-rig safety** — balance-driven stagger/ragdoll no longer silently disables on
  skeletons that don't expose `Foot_L`/`Foot_R` bodies. `_compute_balance_state` now
  reports `has_support`; callers skip balance logic when it's unavailable instead of
  reading `0.0` as "perfectly balanced".
- **PhysicsCollisionMonitor** disconnects its `body_entered` signals on `_exit_tree`
  (was leaking connections to bodies that outlive the monitor); `max_contacts_reported`
  now uses `maxi` (was `maxf` assigned into an int property).
- **Multi-rig balance/IK completed** — the controller, `FootIKSolver`, and debug HUD now
  resolve root/torso/feet/leg-side bones through `RagdollProfile`'s semantic roles instead
  of hardcoded Mixamo names, and `_compute_balance_state` supports any number of feet.
  Non-Mixamo rigs gain working balance/IK/sway by setting the role fields (previously they
  silently lost them). Completes the PR #60 `has_support` guard.
- **`RagdollProfile.root_bone`** no longer defaults to the Mixamo-specific `"mixamorig_Hips"`.
  It defaults to empty and derives from `root_rig` via `get_root_skeleton_bone()`, so the
  partial-ragdoll recursion guard is correct on any rig.

### Changed
- **Budget hard cap** — `KickbackManager` (default 5 slots, discovered via the
  `kickback_manager` group) now actually bounds simultaneous ragdolls. When a slot is
  denied, a *spontaneous* hit- or balance-driven full ragdoll is downgraded to a stagger
  (the character still reacts but skips the expensive limp/settle/get-up cycle), and a
  tipping-over character retries on later frames so it ragdolls as soon as a slot frees up.
  Explicit `trigger_ragdoll()` and `set_persistent()` (death/knockdown) bypass the cap — a
  deliberate or death ragdoll must always proceed. Slots are released on recovery/removal.
  With no manager present, ragdolls stay unbounded. (Supersedes the earlier soft cap.)
- Moved `strip_root_motion.gd` from `demo/` to `addons/kickback/editor/`.
- **Demos consolidated** (11 → 8). `ball_throw` folded into `shooting_range` as a
  right-click ball-throw alt-fire (velocity-scaled impact, mouse-wheel throw strength).
  `tuning_presets` and `protected_bones` folded into `tuning_playground`, now a "Tuning
  Lab" with the five presets (Tank/Standard/Loose/Fragile/Protected) side-by-side plus a
  Custom character driven by the live, now-scrollable slider panel. Preset tunings reuse
  the `RagdollTuning.create_*` factory methods where available. The patrol/recover/resume
  loop `ball_throw` demonstrated already lives in `animated_npc`.
- **Partial-ragdoll collision shapes scale to the character** —
  `SkeletonDetector.populate_physical_bones` reuses the active-rig shape pipeline
  (`create_profile_from_skeleton` + `create_collision_shape`) instead of fixed 0.15 m
  boxes / 0.05 m capsules.
- **Editor deprecation** — `EditorPlugin.get_editor_interface()` → the `EditorInterface`
  singleton (4 sites in `kickback_plugin.gd`).
- **Typed joint setup** — extracted the `Generic6DOFJoint3D` configuration into
  `JointDefinition.apply_to()`, shared by the runtime `PhysicsRigBuilder` and the editor
  `RigBaker`. Replaces the `joint.call("set_flag_" + axis, …)` / `set_param_` dynamic
  dispatch with typed per-axis calls (and de-duplicates the two copies).
- **`PhysicsRigSync` is now a `SkeletonModifier3D`** — retires the deprecated
  `set_bone_global_pose_override`. It writes the physics rig onto the skeleton inside
  `_process_modification_with_delta` via `set_bone_global_pose()` in parent-first bone order;
  the engine applies the result to the skin and rolls it back each frame, so `get_bone_pose()`
  (the spring's animation target) stays uncontaminated — no feedback loop. The node
  self-promotes under the `Skeleton3D` at runtime (deferred reparent), so `KickbackCharacter`,
  `ActiveRagdollController`, all 8 demos, and the test harness were untouched; only the setup
  tool's node type changed (`Node` → `SkeletonModifier3D`). Validated headlessly (89 GUT tests
  incl. a signal-time multi-bone sync assertion that exercises the write ordering + clean
  scene-smoke on all 8 demos); mesh-tracking polish verified in-editor.

### Removed
- Dead passive-tracking path in `SpringResolver` (springs are always active) and its 5
  unused tuning parameters (`spring_active_gravity`, `spring_active_angular_damp`,
  `spring_active_linear_damp`, `spring_passive_angular_damp_offset`,
  `spring_passive_linear_damp_offset`).
- `demo/ik_research` research spike (superseded by the shipped `FootIKSolver`).
- Demo scenes `ball_throw`, `tuning_presets`, and `protected_bones` (merged into
  `shooting_range` and `tuning_playground` — see Changed above).
- Stray debug `print()` output across setup/baking/HUD paths (meaningful notices kept as
  `push_warning`).
- The vestigial `RagdollAnimator` hook — the write-only `_anim_player` field, the
  `animation_player_path` export, and the setup tool's `AnimationPlayer` detection that fed
  it. Nothing consumed it (the controllers are animation-agnostic by design). Also removed
  the unused `JoltCheck.warn_if_not_jolt()` and `KickbackCharacter.get_mode_name()`.

---

## Legacy history (deprecated numbering — pre-recalibration)

These releases used a scheme where the version did **not** track Euphoria parity; the
numbers below are preserved for reference only and are not comparable to current ones.

## [0.8.5] - 2026-03-26

### Added
- **Bake Physics Rig** — "Bake Rig" button in inspector generates persistent RigidBody3D + Joint nodes editable in the scene tree. Runtime auto-detects baked nodes via metadata.
- **Per-bone shape proportions** — feet/hands use `depth_is_length` mode with leaf extent walking (foot→toeBase→toeEnd) for accurate collision shapes.
- **Scale-independent shapes** — all minimum sizes are ratios of Hips→Head distance, works for any character size automatically.
- **Per-bone `shape_offset`** on BoneDefinition — replaces hardcoded 0.65/0.5 offset ratio.
- **Edit-time validation** — RagdollProfile bones checked against skeleton, RagdollTuning keys checked against profile. Warnings shown in inspector.
- **Enhanced status panel** — bone/joint counts, foot IK status, validation section.
- **Tuning preset dropdown** — Default, Game, Tank, Agile, Fragile presets with undo/redo. New factory methods: `create_tank()`, `create_agile()`, `create_fragile()`.
- **Joint compliance** — `angular_softness`, `angular_damping`, `angular_restitution` on JointDefinition for stiff knees vs floppy arms.
- **Per-state collision control** — `normal_state_disabled_collision` on RagdollTuning disables bone colliders during NORMAL state, restored on STAGGER/RAGDOLL.
- **Live tuning** — RagdollTuning changes propagate instantly during play mode via `changed` signal.
- **Spring strength heatmap** — larger pulsing dots at WIREFRAME+, strength % labels at FULL detail level.
- **Balance visualization** — filled support polygon, CoM diamond colored by balance ratio, numeric BAL display, imbalance direction arrow with arrowhead.
- Shared `create_collision_shape()` on SkeletonDetector (single source of truth).
- Head sphere centered via HeadTop_End child bone.

### Changed
- Collision shape estimation rewritten with `BONE_PROPORTIONS` table and `_estimate_leaf_extent()`.
- `_measure_skeleton_height()` for scale-independent shape sizing.
- Gizmo issues (#27, #28) closed — resolved by bake feature using Godot's built-in gizmos.

## [0.8.0] - 2026-03-25

### Added
- **Foot IK** — direct two-bone math solver integrated with spring resolver via target overrides. Ground raycasts, pelvis adjustment, swing detection.
- **Anti-foot-slide** — feet pinned at stagger start position during STAGGER state.
- **Foot IK tuning** — 11 new parameters on RagdollTuning (ankle_height, blend speeds, swing thresholds, etc.).
- **Foot IK demo** — side-by-side IK ON vs OFF over varied terrain.
- **Tuning playground sliders** — foot IK parameter sliders added.
- **Unit tests** — foot IK solver tests (initialization, stagger lifecycle, tuning defaults).
- **Architecture docs** — FOOT_IK.md documenting the IK pipeline and tuning guide.

### Changed
- Skeleton modifier callback mode set to PHYSICS during setup for IK + spring sync.

## [0.7.0] - 2026-03-21

### Added
- **Active Resistance** — during stagger, per-bone spring strengths dynamically adjust every physics frame based on center-of-mass position and velocity. Counter-side bones stiffen to pull balance back, core engages progressively as balance worsens, load-bearing leg braces as a pillar. Characters visibly fight to stay upright. New tuning: `resistance_counter_strength`, `resistance_core_ramp`, `resistance_leg_brace`, `resistance_velocity_spike`, `resistance_velocity_scale`.
- **Stagger sway force** — continuous oscillating force applied to core bones (Hips/Spine/Chest) during stagger. Springs fight this force, producing visible back-and-forth wobble. Quadratic decay over stagger duration. New tuning: `stagger_sway_strength` (300N default), `stagger_sway_frequency` (1.5Hz).
- **Organic sway** — layered oscillation at irrational frequency ratios (never repeats), perpendicular drift for figure-8 wobble, independent upper body twist torque, per-stagger random phase. Fully configurable: `stagger_sway_drift`, `stagger_sway_twist`, `stagger_sway_secondary_ratio`, `stagger_sway_twist_ratio`, `stagger_sway_spine_falloff`, `stagger_sway_chest_falloff`.
- **Stagger recovery rate** — separate spring recovery rate during stagger, suppressing natural recovery so Active Resistance becomes the primary driver. New tuning: `stagger_recovery_rate` (0.03/s default, vs 0.3/s normal).
- **Tuning playground sliders** — 14 new sliders covering sway (8), stagger recovery, and active resistance (3+2).

### Changed
- **Stagger defaults retuned** — `stagger_threshold` 0.55 → 0.70 (triggers more easily), `stagger_duration` 0.6 → 1.8s (longer wobble), `stagger_strength_floor` 0.35 → 0.10 (deeper sway, more contrast with resistance).
- **`_compute_balance_ratio()` refactored** into `_compute_balance_state()` returning CoM position, support center, balance ratio, and imbalance direction. Public API unchanged.
- **Demo scenes updated** — removed stale stagger overrides from 5 demos so new defaults take effect.
- Plugin version bumped to 0.7.0.

## [0.5.0] - 2026-03-20

### Added
- **Stagger state** — new state between hit absorption and full ragdoll. Character visibly wobbles but stays on feet. Configurable via `RagdollTuning`: `stagger_threshold`, `stagger_duration`, `stagger_strength_floor`, `stagger_ragdoll_bonus`. Signals: `stagger_started(hit_direction)`, `stagger_finished()`.
- **`trigger_stagger(hit_dir)`** — force stagger from code via KickbackCharacter or ActiveRagdollController.
- **`is_staggering()`** — query whether character is in stagger state.
- **Protected bones** — `RagdollTuning.protected_bones` array marks bones that never weaken from hits. Legs stay animated while upper body reacts. During full ragdoll, all bones still go limp.
- **Debug gizmos rewrite** — self-contained, auto-discovers all KickbackCharacter nodes. Color-coded bone dots for active ragdoll (red/yellow/green by strength), cyan/yellow for partial ragdoll. Scales with distance. No configuration needed.
- **`StrengthDebugHUD.set_target()`** — optional API for dynamically switching which character the HUD displays.
- **8 demo scenes** in `demo/`:
  - `demo.tscn` — Active vs Partial side-by-side comparison
  - `shooting_range.tscn` — FPS controller with 5 targets and juicy weapon profiles
  - `signal_showcase.tscn` — floating 3D popups + signal log showing every signal
  - `tuning_playground.tscn` — live sliders for runtime parameter tuning
  - `stress_test.tscn` — 20 characters, mass ragdoll, budget slider
  - `animated_npc.tscn` — signal-driven NPC: walk → flinch → stagger → ragdoll → get-up → injured → walk
  - `ball_throw.tscn` — throw physics balls at NPCs, velocity-scaled impact, loose springs
  - `tuning_presets.tscn` — 5 characters (Tank/Standard/Loose/Fragile/Protected) hit simultaneously
  - `protected_bones.tscn` — protected vs unprotected legs side-by-side comparison

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
