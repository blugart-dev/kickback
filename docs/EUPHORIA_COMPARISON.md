# Kickback vs Euphoria — Feature Gap Analysis

Comparison of the Kickback plugin against NaturalMotion's Euphoria system
(GTA IV/V, Red Dead Redemption 2, Max Payne 3). Documents missing behaviors
and systems with difficulty ratings and implementation notes for Godot 4.6+.

## Status Legend
- [x] Implemented in Kickback
- [ ] Not yet implemented

## Implemented Features
- [x] Per-bone spring-based pose matching (velocity springs)
- [x] Per-bone strength reduction with adjacency spreading
- [x] 5-state machine (NORMAL/STAGGER/RAGDOLL/GETTING_UP/PERSISTENT)
- [x] Impact profiles per weapon type (5 presets)
- [x] Protected bones (selective immunity)
- [x] Signal-driven architecture (animation-agnostic)
- [x] Recovery with face-up/face-down orientation detection
- [x] Budget system for concurrent ragdolls
- [x] Stagger state with auto-recovery
- [x] Momentum transfer on ragdoll entry (v0.6)
- [x] Center of mass balance tracking (v0.6)

## Missing Features — Summary

| # | Feature | Difficulty | Impact | Lines Est. |
|---|---------|-----------|--------|------------|
| 1 | ~~Center of Mass Balance~~ | ~~Easy-Medium~~ | ~~Very High~~ | ~~100-150~~ |
| 2 | ~~Momentum Transfer~~ | ~~Easy~~ | ~~High~~ | ~~10-20~~ |
| 3 | Cumulative Damage/Pain | Easy-Medium | High | 100-150 |
| 4 | Regional Impairment | Medium | High | ~200 |
| 5 | Active Resistance (Bracing) | Easy-Medium | High | 80-120 |
| 6 | Procedural Stumble Steps | Medium | High | 150-200 |
| 7 | Arm Bracing / Wind-milling | Medium-Hard | Very High | 200-300 |
| 8 | Proportional Reactions | Easy | Medium | 50-80 |
| 9 | Movement-State-Aware Hits | Easy-Medium | Medium-High | 80-120 |
| 10 | Ground Crawling | Medium-Hard | Medium | 250-350 |
| 11 | Compensatory Stepping + IK | Hard | Very High | 400-600 |
| 12 | Environmental Grabbing | Hard-Very Hard | High | 400-500+ |
| 13 | Procedural Pose Generation | Very Hard | Very High | 600-800+ |
| 14 | Micro Hit Reactions | Medium | Medium-High | 150-200 |
| 15 | Fatigue / Exhaustion | Easy | Medium | 60-80 |
| 16 | Wall/Surface Bracing | Medium | Medium | 150-200 |
| 17 | Multi-Hit Stacking | Easy | Medium-High | 60-100 |
| 18 | Threat Anticipation | Easy | Medium | 60-80 |

## Difficulty Scale
- **Easy** — 1-2 files, < 200 lines, builds directly on existing systems
- **Medium** — 2-4 files, 200-500 lines, new subsystem but integrates cleanly
- **Hard** — New architecture, 500+ lines, may need engine workarounds
- **Very Hard** — Requires IK solvers, raycasting infrastructure, or systems Godot doesn't natively support well

## Suggested Build Order
1. ~~Momentum Transfer (#2)~~ — done
2. ~~Center of Mass Balance (#1)~~ — done
3. Fatigue (#15)
4. Multi-Hit Stacking (#17)
5. Proportional Reactions (#8)
6. Active Resistance (#5)
7. Cumulative Damage (#3)
8. Movement-State-Aware Hits (#9)
9. Threat Anticipation (#18)
10. Micro Hit Reactions (#14)
11. Regional Impairment (#4)
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
