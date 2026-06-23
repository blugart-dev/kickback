# Roadmap

`1.0.0` = full [Euphoria parity](EUPHORIA_COMPARISON.md). See [VERSIONING.md](VERSIONING.md)
for what the numbers mean. The minor version tracks difficulty-weighted progress toward
that goal.

## Euphoria Parity Scorecard

Progress is weighted by **difficulty**, not feature count — the unbuilt behaviors are
the hard ones. (Counting features equally gives a misleading ~67%; weighted, the honest
figure is **~30%**.)

| Layer | Status | Weight | Earned |
|-------|--------|-------:|-------:|
| **Passive substrate** — velocity springs, 5-state machine, CoM *sensing*, terrain foot IK | ✅ Done & robust | 13 | 13 |
| **Reactive basics** — strength spread, micro-reactions, momentum transfer, impact profiles, protected bones | ✅ Done | 5 | 5 |
| **"Soft" modulators** — pain / fatigue / injury, regional impairment, threat anticipation, active-resistance | 🟡 Partial (knobs, not behaviors) | 8 | 2 |
| **Active self-preservation** — stumble-stepping, arm/wall bracing, environmental grabbing, ground crawling, get-up variety, balance *recovery* | ❌ Absent | 29 | 0 |
| **Procedural pose "brain"** — target-seeking generated poses | ❌ Absent | 6 | 0 |
| **Total** | | **61** | **~20 ≈ 30%** |

> Weights are a difficulty/effort judgment, not exact science. By the strictest
> *behavioral* lens (only active survival behaviors count) parity is ~20%; by raw
> engineering effort it's ~35%. `0.3.x` anchors the ~30% midpoint. The springs are the
> muscles — what's missing is the brain telling them what to do.

## Milestones

| Version | Theme | Delivers |
|---------|-------|----------|
| **0.3.x** | Re-baseline + hardening | Honest docs & scorecard, plus the hardening batch: fixed silent multi-rig degradation, wired the budget manager (hard cap), added runtime smoke tests, generalized beyond Mixamo, and migrated `PhysicsRigSync` to a `SkeletonModifier3D`. See *Known hardening items* for what's resolved vs still open. |
| **0.4.0** 🚧 | Self-Preservation | Directed stumble (shipped) + arm bracing (next) — the first *active* survival behaviors. **In progress** — see [SELF_PRESERVATION.md](SELF_PRESERVATION.md). |
| **0.5.0** | Environmental Awareness | Wall/surface bracing + ground crawling. |
| **0.6.0** | World Interaction | Environmental grabbing (IK reach + physics pins to grab points). |
| **0.7.0** | Procedural Poses (core) | Replace canned recovery blends with target-seeking generated poses. |
| **0.8.0** | Balance Recovery | Active balance recovery + get-up variety driven by procedural poses. |
| **0.9.0** | Production hardening | Multi-rig guarantees, runtime test coverage, API freeze, beta/RC. |
| **1.0.0** | **Full Euphoria parity** | Committed stable API; the self-preservation layer complete. |

Intermediate minor numbers are recomputed from the scorecard as milestones land.

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

**Still open:**

- None currently tracked — the `0.3.x` hardening items are resolved. The next substantive
  work is the `0.4.0` Self-Preservation layer (procedural stumble steps + arm bracing).
