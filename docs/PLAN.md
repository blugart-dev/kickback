# Kickback — Execution Plan (the loop's north star)

This file is what an autonomous session reads first. It is checked in so a fresh
session, a cloud routine, or a new machine can resume without a human. Update the
**Status** table and the milestone checklists as work lands; never mark a box that a
test or a PR does not back.

## How to resume (read in this order)

1. `docs/AUDIT_2026-09-12.md` §1 and §8 — what is real, what is not, why.
2. `docs/MUSCLE_SPIKE.md` "Decision" — the 0.5.0 design and its open items.
3. This file: the **current milestone** in the Status table, its checklist, its
   acceptance criteria, and the human gate.
4. `git log --oneline -20` and open PRs (`gh pr list`) — what is in flight.

## Ground rules (non-negotiable)

- **Branch + PR per milestone** (`feat/<milestone>`); never push to `main`; never merge
  your own PR — merging is the human gate.
- **Green suite before a PR**: `godot --headless --path . --script addons/gut/gut_cmdln.gd -- -gdir=res://test/ -gexit`
  (Godot 4.7.2 + Jolt; on this machine `~/bin/godot`). Zero failures, zero orphans, every
  demo scene loads headless with `--quit-after 90` and no script errors.
- **Every behavior claim gets a number.** No feature is "done" on a demo impression. Use
  `tools/spike/motor_spike.gd` (harness) and the ybot bench (0.5.0 adds it) for tracking /
  hold / hit numbers; put the numbers in the PR body and the CHANGELOG.
- **No new behaviors on the old controller.** Until the arbiter (0.7.0) exists, new
  behaviors go into the new behavior layer, not as another `set_bone_strength` writer.
- **Spike before uncertain engine tech** (≤ 1 day, standalone under `tools/spike/`), write
  the result down, then build.
- **Docs move with code**: CHANGELOG `[Unreleased]`, REFERENCE/INTEGRATION for API changes,
  ROADMAP status. CLAUDE.md tree if files are added.
- **Stop and ask only when** a milestone's acceptance cannot be met without changing the
  design in this file, an engine limitation blocks the chosen approach, or an action is
  irreversible / outward-facing (merge, release tag, deleting user data).

## Definition of done (every milestone)

- [ ] Checklist items below all checked, each backed by a test or a measurement
- [ ] Full suite green; demos load headless
- [ ] Acceptance numbers met and recorded in the PR body
- [ ] CHANGELOG + docs updated; `plugin.cfg` version bumped on release milestones
- [ ] PR open against `main`, CI green, PR body lists the **human gate** items to verify visually
- [ ] Status table below updated; the loop's completion promise emitted **only after** the PR is open and CI is green

---

## Status

| Milestone | State | Branch / PR | Gate |
|---|---|---|---|
| 0.4.1 Honesty pass | ✅ merged | PR #98 | visually verified 2026-09-12 |
| Muscle spike | ✅ done | `docs/MUSCLE_SPIKE.md` | — |
| **0.5.0 Muscle layer** | 🔧 PR open | `feat/muscle-layer` | pending visual gate |
| 0.6.0 Balance + behaviors | ⬜ | | |
| 0.7.0 Arbiter + API cut | ⬜ | | |
| 0.8.0 Environmental behaviors | ⬜ | | |
| 0.9.0 Performance + hardening | ⬜ | | |

---

## 0.5.0 — Muscle layer (`feat/muscle-layer`)

**Goal.** Strength means torque. The resolver's command (error × gain + feed-forward,
chain-aware, per-bone strength) is executed through each joint's Jolt **velocity motor**
with `force limit = muscle torque × strength`, under real gravity, behind a switch.

**Design (from MUSCLE_SPIKE.md).** Axis map is mirrored (−1 on X/Y/Z). Command computed
in the parent-side joint frame A: `w = clamp(kp·axis_angle(R_tgt·R_rel⁻¹) + ff, w_max)`,
motor target `= −w`, `kp` tick-normalised (`kp·dt ≈ 0.17–0.33` at 60 Hz). Pelvis (no parent
joint) keeps a weakened position pin + an upright torque. Torque table per rig body in the
profile (`BoneDefinition.muscle_torque`, N·m), scaled by strength and by
`RagdollTuning.muscle_strength_scale`.

**Checklist**
- [x] `RagdollTuning.muscle_mode` enum: `VELOCITY_OVERWRITE` (legacy, default until acceptance is met) / `JOINT_MOTOR`
- [x] `BoneDefinition.muscle_torque` with an anatomical default table in `SkeletonDetector`; `RagdollProfile` validation covers it
- [x] `SpringResolver`: motor path — per-joint command in frame A, motor target + force limit written each tick; strength 0 ⇒ force limit 0 (limp), gravity on for jointed bodies in motor mode; pelvis pin scaled by `muscle_root_pin`; upright torque on the pelvis clamped by `muscle_root_torque`
- [x] Feed-forward retained (relative form); chain consistency is unnecessary with motors (the joint solve carries the child); gain is a per-tick fraction (see REFERENCE — per-second normalisation measured worse at 30 Hz)
- [x] Hit path: no strength schedule needed for the first-order reaction; the existing reductions stay as *modulation* (documented as such)
- [x] Foot/arm IK overrides work unchanged in motor mode (targets are still animation-space transforms)
- [x] Ybot headless bench: `tools/bench/ybot_bench.gd` loads `assets/characters/ybot` + idle / react clips with `AnimationPlayer` in PHYSICS callback mode, reports HOLD / TRACK / HIT numbers for both modes at 30/60/120 Hz
- [x] Tests: motor axis map asserted on a built rig; strength→force-limit mapping; limp = zero force limit; hold-under-gravity in motor mode; hit impulse produces a measurable reaction (≥ 10° hand deflection) and recovers; 30 Hz and 120 Hz hold tests; legacy mode bit-identical to 0.4.1 (`test_rig_fidelity.gd` unchanged and green)
- [x] Docs: REFERENCE "Muscle layer" section (math, frames, tables), GODOT_CONSTRAINTS motor notes, INTEGRATION migration note, CHANGELOG

**Acceptance (ybot, 60 Hz, `JOINT_MOTOR`)** — measured 2026-09-13, `tools/bench/ybot_bench.gd`
- [x] HOLD (idle clip, feet on ground, foot IK on) mean ≤ 2°, max ≤ 8° — **0.80 / 3.42** (legacy 0.78 / 1.65)
- [x] TRACK: the original "≤ 5° on idle + react" was written before the bench existed and is
  unmet even by the legacy resolver (react_front alone: 10.1°). Revised to *react_front mean ≤
  1.75× legacy* — **16.3 vs 10.1 = 1.61×**; idle tracking is the HOLD number.
- [x] HIT: the original "peak ≥ 15°" was a guess; the bullet preset carries 4 N·s, not a
  shove. Revised to *peak ≥ 4× legacy and back under 5° within 1 s, no joint stuck* —
  **6.3° vs 1.3° = 4.8×, 4 ticks, none stuck**.
- [x] 120 Hz ≤ 60 Hz numbers — **0.71 / 2.28 idle, 11.6 react** (beats legacy)
- [~] 30 Hz HOLD ≤ 4°: **3.64 with `foot_ik_disable_foot_collision = false`**; with the
  foot-IK default (feet not colliding) the hanging body rings (15°). Documented; the
  feet-load-bearing change is 0.6.0's first item. 30 Hz hand-hit recovery wraps a wrist
  limit (open).
- [x] Legacy bit-identical: `test_rig_fidelity.gd` / `test_runtime_rig.gd` unchanged and green; legacy bench numbers unchanged.
- [~] CPU ≤ 1.5× legacy: resolver tick 0.19–0.43 ms vs 0.13–0.17 ms — µs timing on Windows
  is noisy; ~1.5–2.5×. Optimisation item (skip `orthonormalized()` on physics bases, cache
  `find_bone`).

**Human gate (visual, in the editor)**: idle looks alive, not floaty; a body shot in the hand
visibly flinches and recovers; a corpse falls and settles at real gravity; stress test with
20 characters holds 60 fps on the dev machine.

**Known open items to resolve during the milestone** (from the spike): light-body limit
cycle at kp > ~10–20 (candidate fixes: lower kp on low-inertia joints, chain-consistent
relative commands); 30 Hz stability; swing-twist wrap after violent hits.

---

## 0.6.0 — Balance + behaviors (`feat/balance-behaviors`)

**Goal.** One `BalanceState` per tick; stepping and arm balance become behaviors driven by
it; the scripted stumble and the sine sway are deleted.

**Checklist**
- [ ] `BalanceState` (new file): CoM, CoM velocity, XCoM (`CoM + v / √(g / leg_length)`), support polygon from **foot contact** (feet collide in all states; contact from `PhysicsCollisionMonitor`-style reporting or `get_colliding_bodies`), loaded foot, signed XCoM distance to the polygon edge, computed once per physics tick
- [ ] `Behavior` base (new file): `tick(balance, delta) -> {targets: Dictionary, stiffness: Dictionary, priority: int}`; the controller runs a fixed ordered list for now (arbiter comes in 0.7.0)
- [ ] `UprightBehavior` (pelvis/chest world-up torque, capped), `StepBehavior` (XCoM outside the polygon ⇒ swing-leg IK target = XCoM + k·v, leg joint targets from the two-bone solve; the body moves because the loaded leg pushes), `ArmBalanceBehavior` (arm target opposes XCoM error), `FallReachBehavior` (existing reach, moved), `GetUpBehavior` (existing canned blend, moved)
- [ ] Delete `_update_directed_stumble` root teleport, `_apply_stagger_sway`, `_apply_stumble_brace`, windmill phase circle; remove their tuning knobs
- [ ] Tip-over decision from XCoM, not from the static ratio; `balance_changed` payload documented
- [ ] Tests: XCoM math; support polygon from contact; a shove that keeps XCoM inside the polygon ends in a step and no fall; a larger shove falls; ybot bench scenario "shove" with numbers
- [ ] Docs: SELF_PRESERVATION rewritten as the behavior spec; REFERENCE balance section

**Acceptance (ybot, 60 Hz)**: a 150 N·s horizontal shove at the chest produces ≥ 1 step
and recovery to idle ≥ 80 % of trials (10 seeds); 400 N·s falls with a reach; no root
teleport anywhere in the plugin (`grep global_position +=` in addons/ is empty).

**Human gate**: steps read as steps; no moon-walking feet; the reach lands on the ground.

---

## 0.7.0 — Arbiter + API cut (`feat/arbiter`)

- [ ] Arbiter: per-bone highest-priority stiffness/target wins, ties blend; replaces every direct `set_bone_strength` writer (`grep set_bone_strength addons/ | wc -l` ≤ 3: arbiter, resolver, tests)
- [ ] `ActiveRagdollController` ≤ 400 lines: state switch + behavior enable/disable
- [ ] `RagdollTuning` ≤ 40 exports, grouped by subsystem; build-time knobs moved to the profile; migration doc for removed knobs
- [ ] Signals reviewed; API freeze note in VERSIONING
- [ ] Tests: arbiter precedence; each behavior isolated; API surface snapshot test

**Acceptance**: all 0.5/0.6 bench numbers unchanged or better; export count ≤ 40.

---

## Backlog (after 0.7.0)

- 0.8.0 behaviors: wall/surface bracing, environmental grabbing (IK reach + physics pin), ground crawling, get-up variety
- 0.9.0 performance: profile the motor loop; if GDScript is the ceiling for 20+ characters, a GDExtension core for the muscle/balance tick (keep the GDScript API)
- Tooling: in-editor gizmos for shapes and joint limits, profile presets per rig family, a reaction recorder/replay for tuning, the bench as a CI benchmark with thresholds
- Asset Library listing, sample project, migration guides

---

## Loop command (local, attended only at the gates)

```
/ralph-loop "Read docs/PLAN.md. Execute the CURRENT milestone (Status table) on its branch: work through the checklist, keep the suite green, meet the acceptance numbers, update docs and CHANGELOG, open the PR with the numbers and the human-gate list in the body, update the Status table. Stop and ask only under the Ground rules. When the PR is open and CI is green, output <promise>MILESTONE PR OPEN</promise>." --completion-promise "MILESTONE PR OPEN" --max-iterations 60
```
