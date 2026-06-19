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
| **0.3.x** | Re-baseline + hardening | Honest docs & scorecard (this release). Then: fix silent multi-rig degradation, wire-or-remove the budget manager, add runtime smoke tests, generalize beyond Mixamo. |
| **0.4.0** | Self-Preservation | Procedural stumble steps + arm bracing — the first *active* survival behaviors. |
| **0.5.0** | Environmental Awareness | Wall/surface bracing + ground crawling. |
| **0.6.0** | World Interaction | Environmental grabbing (IK reach + physics pins to grab points). |
| **0.7.0** | Procedural Poses (core) | Replace canned recovery blends with target-seeking generated poses. |
| **0.8.0** | Balance Recovery | Active balance recovery + get-up variety driven by procedural poses. |
| **0.9.0** | Production hardening | Multi-rig guarantees, runtime test coverage, API freeze, beta/RC. |
| **1.0.0** | **Full Euphoria parity** | Committed stable API; the self-preservation layer complete. |

Intermediate minor numbers are recomputed from the scorecard as milestones land.

## Known hardening items (targeted for 0.3.x)

Robustness gaps surfaced by the 2026-06-19 audit — not blockers for using the plugin on
Mixamo-style rigs, but prerequisites for "general-purpose":

- **Silent multi-rig degradation** — non-Mixamo skeletons that map fine can still lose
  balance/IK/sway because rig bone names (`Hips`/`Chest`/`Foot_L`…) are hardcoded;
  `_compute_balance_state` returns zeroed data read as "perfectly balanced," silently
  disabling the balance→ragdoll path. Should warn or fail loudly.
- **Budget manager is unwired** — `KickbackManager.request/release_active_ragdoll` is
  never called by controllers; only the stress-test demo reads the counter.
- **Spring math is implicitly 60 Hz-bound** — corrections are divided by `delta` with no
  substepping awareness.
- **Partial-ragdoll collision shapes don't scale** to character size (the active path does).
- **No runtime/physics automated tests** — the rig is never built or stepped in CI; all
  physics behavior is currently eyeballed in demos only.
