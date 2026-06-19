# Kickback vs Euphoria — Feature Gap Analysis

Comparison of the Kickback plugin against NaturalMotion's Euphoria system
(GTA IV/V, Red Dead Redemption 2, Max Payne 3). Documents missing behaviors
and systems with difficulty ratings and implementation notes for Godot 4.7+.

## Status Legend
- ✅ **Real** — a genuine behavior, robust
- 🟡 **Partial** — works narrowly, or a tunable knob doing a fraction of the behavior
- ⚪ **Nominal** — exists in name/API only; not a meaningful behavior yet
- ❌ **Missing** — not implemented

> ⚠️ **Honest accounting.** Counting features equally suggests Kickback is ~67% of the
> way to Euphoria. That overstates it: several "implemented" items are scalar knobs, not
> behaviors, and every *active self-preservation* behavior is absent. Difficulty-weighted,
> real parity is **~30%** (see the [ROADMAP.md](ROADMAP.md) scorecard).

## What's actually built

### Foundation — real and robust
- ✅ Per-bone spring-based pose matching (velocity springs) — the technical core
- ✅ Per-bone strength reduction with adjacency spreading
- ✅ 5-state machine (NORMAL/STAGGER/RAGDOLL/GETTING_UP/PERSISTENT)
- ✅ Stagger state with balance-driven auto-recovery
- ✅ Impact profiles per weapon type (5 presets)
- ✅ Protected bones (selective immunity)
- ✅ Signal-driven, animation-agnostic architecture
- ✅ Momentum transfer on ragdoll entry
- ✅ Center of mass **sensing** vs foot-support polygon
- ✅ Micro hit reactions (torso bend / head whip / spin torque)
- ✅ Terrain foot IK (two-bone solver + pelvis drop) — *planting only, not balance-stepping*

### Reactive modulators — partial / nominal
- 🟡 Recovery with face-up/down detection — single canned animation blend, no get-up variety
- 🟡 Active Resistance ("bracing") — biases spring *stiffness* toward balance; **no** bracing/limb motion
- 🟡 Cumulative pain / fatigue — decaying scalars that scale existing strength reductions
- ⚪ Regional impairment — a per-bone injury scalar feeding a multiplier; no limb-specific behavior
- ⚪ Threat anticipation — one strength pulse + a signal (a flinch knob, not anticipatory posture)
- ⚪ Budget system for concurrent ragdolls — `KickbackManager` counter is **not wired** into controllers

### The objective — absent (this is what 1.0 means)
Every behavior that makes Euphoria *Euphoria* — active balance recovery, stumble steps,
arm/wall bracing, environmental grabbing, ground crawling, and procedural pose
generation — is **not yet built**. See the table below.

## Missing Features — Summary

> Note: ~~struck-through~~ items are addressed in code — see *What's actually built*
> above for how deeply (several are partial or nominal, not full behaviors).

| # | Feature | Difficulty | Impact | Lines Est. |
|---|---------|-----------|--------|------------|
| 1 | ~~Center of Mass Balance~~ | ~~Easy-Medium~~ | ~~Very High~~ | ~~100-150~~ |
| 2 | ~~Momentum Transfer~~ | ~~Easy~~ | ~~High~~ | ~~10-20~~ |
| 3 | ~~Cumulative Damage/Pain~~ | ~~Easy-Medium~~ | ~~High~~ | ~~100-150~~ |
| 4 | ~~Regional Impairment~~ | ~~Medium~~ | ~~High~~ | ~~~200~~ |
| 5 | ~~Active Resistance (Bracing)~~ | ~~Easy-Medium~~ | ~~High~~ | ~~80-120~~ |
| 6 | Procedural Stumble Steps | Medium | High | 150-200 |
| 7 | Arm Bracing / Wind-milling | Medium-Hard | Very High | 200-300 |
| 8 | ~~Proportional Reactions~~ | ~~Easy~~ | ~~Medium~~ | ~~50-80~~ |
| 9 | ~~Movement-State-Aware Hits~~ | ~~Easy-Medium~~ | ~~Medium-High~~ | ~~80-120~~ |
| 10 | Ground Crawling | Medium-Hard | Medium | 250-350 |
| 11 | Compensatory Stepping + IK | Hard | Very High | 400-600 |
| 12 | Environmental Grabbing | Hard-Very Hard | High | 400-500+ |
| 13 | Procedural Pose Generation | Very Hard | Very High | 600-800+ |
| 14 | ~~Micro Hit Reactions~~ | ~~Medium~~ | ~~Medium-High~~ | ~~150-200~~ |
| 15 | ~~Fatigue / Exhaustion~~ | ~~Easy~~ | ~~Medium~~ | ~~60-80~~ |
| 16 | Wall/Surface Bracing | Medium | Medium | 150-200 |
| 17 | ~~Multi-Hit Stacking~~ | ~~Easy~~ | ~~Medium-High~~ | ~~60-100~~ |
| 18 | ~~Threat Anticipation~~ | ~~Easy~~ | ~~Medium~~ | ~~60-80~~ |

## Difficulty Scale
- **Easy** — 1-2 files, < 200 lines, builds directly on existing systems
- **Medium** — 2-4 files, 200-500 lines, new subsystem but integrates cleanly
- **Hard** — New architecture, 500+ lines, may need engine workarounds
- **Very Hard** — Requires IK solvers, raycasting infrastructure, or systems Godot doesn't natively support well

## Suggested Build Order
1. ~~Momentum Transfer (#2)~~ — done
2. ~~Center of Mass Balance (#1)~~ — done
3. ~~Fatigue (#15)~~ — done
4. ~~Multi-Hit Stacking (#17)~~ — done
5. ~~Proportional Reactions (#8)~~ — done
6. ~~Active Resistance (#5)~~ — done
7. ~~Cumulative Damage (#3)~~ — done
8. ~~Movement-State-Aware Hits (#9)~~ — done
9. ~~Threat Anticipation (#18)~~ — done
10. ~~Micro Hit Reactions (#14)~~ — done
11. ~~Regional Impairment (#4)~~ — done
12. Stumble Steps (#6)
13. Arm Bracing (#7)
14. Wall Bracing (#16)
15. Compensatory Stepping + IK (#11)
16. Ground Crawling (#10)
17. Environmental Grabbing (#12)
18. Procedural Pose Generation (#13)

## Core Insight

> Euphoria characters are active agents trying to survive.
> Kickback characters are passive spring systems that get pushed around.

Kickback nails the "ragdoll with springs" foundation. What's missing is the
**intelligence layer on top**: balance awareness, self-preservation behaviors,
environmental interaction, and cumulative damage. The springs are the muscles;
what's missing is the brain telling those muscles what to do.

## Detailed Feature Descriptions

See the full plan file for per-feature breakdowns including:
- What Euphoria does
- What Kickback currently does
- Concrete implementation approach
- Why it matters
- Difficulty assessment
