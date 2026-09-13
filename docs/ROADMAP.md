# Roadmap

`1.0.0` = full [Euphoria parity](EUPHORIA_COMPARISON.md). See [VERSIONING.md](VERSIONING.md)
for what the numbers mean. The minor version tracks difficulty-weighted progress toward
that goal.

## Euphoria Parity Scorecard

Progress is weighted by **difficulty**, not feature count — the unbuilt behaviors are
the hard ones. (Counting features equally gives a misleading ~67%; weighted, the honest
figure is **~20–25%**, per the 2026-09 [audit](AUDIT_2026-09-12.md).)

| Layer | Status | Weight | Earned |
|-------|--------|-------:|-------:|
| **Passive substrate** — rig / joints / sync / terrain foot IK, velocity springs, 5-state machine, CoM *sensing* | 🟡 Rig, joint frames, sync and foot IK are real and kept; the "muscle" is a velocity-overwrite tracker (mass/inertia ignored, hit impulses erased in 2–3 ticks, gravity scaled by strength) and the balance model is a static CoM offset — audit §3.1, §3.3 | 13 | 8 |
| **Reactive basics** — strength spread, micro-reactions, momentum transfer, impact profiles, protected bones | ✅ Done | 5 | 5 |
| **"Soft" modulators** — pain / fatigue / injury, regional impairment, threat anticipation, active-resistance | ⚪ Nominal (scalar multipliers on strength, not behaviors) | 8 | 1 |
| **Active self-preservation** — stumble-stepping, arm/wall bracing, environmental grabbing, ground crawling, get-up variety, balance *recovery* | ❌ Absent — the 0.4.0 directed stumble is a scripted root displacement and the windmill a canned circle (audit §3.2); the fall reach is real but a half-behavior | 29 | 0 |
| **Procedural pose "brain"** — target-seeking generated poses | ❌ Absent | 6 | 0 |
| **Total** | | **61** | **~14 ≈ 23%** |

> Weights are a difficulty/effort judgment, not exact science. By the strictest
> *behavioral* lens (only active survival behaviors count) parity is ~15%; by raw
> engineering effort it's ~30%. The audit's **~20–25%** is the band the minor version
> tracks. The important finding is not the number but that the current muscle substrate
> caps what is reachable: balance recovery, bracing and grabbing are *defined* by bounded
> torques interacting with contacts and gravity, and a layer that overwrites velocities
> cannot carry them (audit §1, §8). Hence the plan below replaces the muscle layer before
> adding behaviors.

## Milestones

| Version | Theme | Delivers |
|---------|-------|----------|
| **0.3.x** | Re-baseline + hardening | Honest docs & scorecard, plus the hardening batch: fixed silent multi-rig degradation, wired the budget manager (hard cap), added runtime smoke tests, generalized beyond Mixamo, and migrated `PhysicsRigSync` to a `SkeletonModifier3D`. See *Known hardening items* for what's resolved vs still open. |
| **0.4.0** ✅ | Scripted stumble + arm bracing | Directed stumble (a scripted root displacement with foot-IK step targets), windmill (phase circle), reach-for-ground on a fall (real physics-anchored IK). **Shipped**, see [SELF_PRESERVATION.md](SELF_PRESERVATION.md) — **not counted as active self-preservation** on the scorecard. |
| **0.4.1** 🔧 | Honesty pass | Audit §8 step 1: docs and scorecard corrected (this document, SELF_PRESERVATION, README), dead knobs deleted, audit §4 defects 1–5, 12–15, 19–22 fixed (half-gravity corpse, phantom RAGDOLL signal, wall-clock timers, forward-sign face-up, recovery_rate precedence documented, dead tuning hookup, runtime skeleton validation, recursive setup tool, demos wire `rig_sync_path`, HUD guards, physics-time cooldowns). Branch `audit/honesty-pass`. |
| **spike** ✅ | Muscle spike | Done — [MUSCLE_SPIKE.md](MUSCLE_SPIKE.md). Velocity-mode 6DOF motors are a working, torque-honest muscle (hold ≈ 1° under real gravity, hits produce real reactions); position-mode springs and script PD torque are rejected on data. Decision: evolve the resolver into a motor-driven muscle layer rather than rip it out. |
| **0.5.0** 🔧 | Muscle layer (PR open) | The resolver's command (error × gain + feed-forward, chain-aware, per-bone strength) executed through each joint's velocity motor with `force limit = muscle torque × strength`; gravity on for jointed bodies; pelvis keeps a weakened pin + upright torque; gains tick-normalised; behind a `muscle_mode` switch. Acceptance on the ybot at 60 Hz: HOLD ≤ 2°, idle tracking ≤ 5°, visibly physical hit response (a tracking regression on fast clips is accepted by design). |
| **0.6.0** | Balance + behaviors | `BalanceState` (CoM, CoM velocity, XCoM, support polygon from foot *contact*, loaded foot, signed distance to the polygon edge) computed once per tick; `Step` and `ArmBalance` as behaviors driven by it; **the scripted stumble and the sine sway are removed**. |
| **0.7.0** | Arbiter + API | Behaviors return per-bone stiffness + priority; an arbiter replaces the ~20 direct `set_bone_strength` writers; the controller slims to a ~200-line behavior switch; `RagdollTuning` cut to ≤ 40 physical/behavioral knobs; API freeze. |
| **0.8.0+** | Environmental behaviors | Wall/surface bracing, environmental grabbing, ground crawling, get-up variety — as behaviors on a substrate that can carry them. |
| **0.9.0** | Production hardening | Multi-rig guarantees, runtime test coverage, beta/RC. |
| **1.0.0** | **Full Euphoria parity** | Committed stable API; the self-preservation layer complete. |

Intermediate minor numbers are recomputed from the scorecard as milestones land. The
order of work is the audit's §8; the reason for doing the muscle layer first is that every
behavior milestone after 0.4.0 on the previous roadmap would have been another scripted
layer on a substrate that cannot carry it.

## Known hardening items

Robustness gaps surfaced by the 2026-06-19 audit. Most of the 0.3.x batch has since landed;
the remainder is tracked here.

**Resolved in 0.3.x:**

- ✅ **Silent multi-rig degradation** (PR #62) — bones resolve through `RagdollProfile`
  semantic roles and `_compute_balance_state` reports `has_support`, so non-Mixamo rigs no
  longer read zeroed balance as "perfectly balanced."
- ✅ **Budget manager wired + hard cap** (PR #65) — controllers request/release slots and
  over-budget *spontaneous* ragdolls downgrade to a stagger (explicit/death ragdolls bypass).
- ✅ **Partial-ragdoll collision shapes scale** (PR #62) — the partial path reuses the active
  shape pipeline.
- ✅ **Runtime/physics tests** (PR #64) — the rig is built and stepped in a headless SceneTree
  in CI (spring tracking, ragdoll, recovery, sync, foot IK, budget).
- ✅ **`PhysicsRigSync` is a `SkeletonModifier3D`** — retired the deprecated
  `set_bone_global_pose_override`. The modifier's per-frame pose roll-back keeps the spring's
  `get_bone_pose()` read clean (no feedback loop), and the node self-promotes under the
  skeleton at runtime. See [SKELETON_MODIFIER_MIGRATION.md](SKELETON_MODIFIER_MIGRATION.md).
- ✅ **Spring math is frame-rate independent** — the velocity targets and per-tick blend
  weights are normalized to a 60 Hz reference (`SpringResolver._fr_weight`), so reaction feel
  no longer drifts with the physics tick rate. Bit-identical at 60 Hz; stable at 30/120.

**Still open (from the 2026-09 [audit](AUDIT_2026-09-12.md)):**

- **Muscle layer is a kinematic tracker** (§3.1) — velocities overwritten every tick;
  mass and inertia ignored; fights the constraint solver and contacts. Replaced in 0.5.0.
- **Directed stumble is a root teleport** (§3.2) — removed in 0.6.0 once `Step` exists.
- **Static balance model** (§3.3) — no XCoM, no contact support polygon, no loaded foot.
  0.6.0.
- **Controller is a god object with no arbitration** (§3.5) — 20 `set_bone_strength`
  writers, last-writer-wins. 0.7.0.
- **Initialisation by await-counting** (§3.6) — 2 / 3 / 5 process-frame awaits that happen
  to be ordered; `_build_adjacency` not re-run by `configure()`.
- **Feet have collision off in NORMAL/STAGGER** (§4 #6) — the legs never bear load; needed
  by every balance behavior. 0.5.0.
- **Tests that pass while the feature is broken** (§6) — `test_state_machine` timing,
  `test_arm_ik` unconditional assert, `test_stumble_step` asserting a teleport,
  `test_fall_brace` timer-vs-contact; untested: two rigs at once, non-60 Hz, non-identity
  rest bases, editor tooling, `.tres` presets, Jolt presence.
- **`RagdollTuning` has 139 exports in 15 groups** (§5) — cut to ≤ 40 in 0.7.0.
