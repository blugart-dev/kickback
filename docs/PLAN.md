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

- **`main` is release-only and frozen until the maintainer says it *feels amazing*
  (decision 2026-09-13).** Integration happens on **`develop`**: every milestone is a
  `feat/<milestone>` branch off `develop` with a PR **into `develop`**; when its CI is green
  and its numbers are in the body, fast-forward `develop` to it (`git push origin
  feat/x:develop`, never a force push) and start the next branch. `main` receives one
  release PR from `develop` when the maintainer's feel gate passes; that merge, and any
  tag, is the human's. Never push to `main`.
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
| **0.5.0 Muscle layer** | ✅ code complete, on `develop` (PR #100 to `main` kept open as the record; not merged) | `feat/muscle-layer` → `develop` | feel gate deferred: maintainer says "not there yet, comes later" |
| **0.6.0 Balance + behaviors** | 🔧 in progress | `feat/balance-behaviors` → `develop` | steps read as steps |
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
- [x] HOLD (idle clip, feet on ground, foot IK on) mean ≤ 2°, max ≤ 8° — **0.94 / 3.54** (legacy 0.78 / 1.57); pelvis within 1 mm of target, no bounce (the first build stood 3.5 cm low and bounced at 3 Hz: user-visible wobble, fixed by the anchor-body root)
- [x] GET-UP: after a ragdoll on the ground every shooting-range character stands back up upright, worst body error ~2° (the first build got up upside down)
- [ ] TRACK: the original "≤ 5° on idle + react" was written before the bench existed and is
  unmet even by the legacy resolver (react_front alone: 10.1°). Revised to *react_front mean ≤
  1.75× legacy*; measured **24.5 vs 10.1 = 2.4×** with the anchor root and the per-axis
  (swing-twist angle space) limb command — 18.8 with the earlier rotation-vector command,
  which tracked fast clips better but stalled joints after a ragdoll. Robustness won;
  recorded as a MISS, carried to 0.6.0 (candidate: rotation-vector command when the joint
  is within ~30° of its target, angle-space otherwise).
- [ ] HIT: the original "peak ≥ 15°" was a guess; the bullet preset carries 4 N·s, not a
  shove. Revised to *peak ≥ 3× legacy and back under 5° within 1 s, no joint stuck* —
  measured **2.4° vs 1.3° = 1.8×, 4 ticks, none stuck** with the anchor root (4.5° before).
  A MISS on deflection; the user also reports hits read less vividly than legacy. The
  vividness levers are now sliders in the Tuning Lab (`muscle_strength_curve`,
  `muscle_strength_scale`, `muscle_gain`, root torque/force); carried to 0.6.0.
- [x] 120 Hz ≤ 60 Hz numbers — **0.73 / 2.43 idle, 10.6 react** (beats legacy)
- [~] 30 Hz HOLD ≤ 4°: **4.85** with the defaults (was a 15° ring before the force-driven
  root); 3.6 with `foot_ik_disable_foot_collision = false`. Feet-load-bearing is 0.6.0's
  first item. 30 Hz hand-hit recovery wraps a wrist limit (open).
- [x] Legacy bit-identical: `test_rig_fidelity.gd` / `test_runtime_rig.gd` unchanged and green; legacy bench numbers unchanged.
- [x] CPU ≤ 1.5× legacy: resolver tick 0.17–0.21 ms vs 0.13–0.15 ms on quiet runs (≈1.2–1.4×);
  µs timing on Windows is noisy under load.

**Human gate (visual, in the editor)**: idle looks alive, not floaty; a body shot in the hand
visibly flinches and recovers; a corpse falls and settles at real gravity; stress test with
20 characters holds 60 fps on the dev machine.

**Resolved during the milestone**: the light-body limit cycle (gain 0.10 per tick, root as a
bounded motor); the frame of the motor command (swing-twist: twist in the parent frame,
swing in the child frame — the spike's remaining TRACK deficit was partly this); the
stagger floor as a raw torque fraction collapsed the character → `muscle_strength_curve`
0.5 (√ratio); a strength-scaled root pin/motor let a stagger topple → the root holds at
full authority until limp (`_root_hold_factor`), the stand-in for balance.
**Found by the user in the editor (2026-09-13)**: (1) the pelvis stood 3.5 cm low and
bounced at 3 Hz (whole-body wobble, feet clipping the floor) — the velocity pin on the
pelvis was diluted by the joint solve; (2) characters got up **upside down** after a
ragdoll on the ground — a fixed world joint's swing-twist motor axes degenerate once the
pelvis lies 90°+ from its frame, and re-anchoring by rebuilding the constraint left every
limb joint inert. Both fixed by the kinematic **root anchor** design (REFERENCE.md "Muscle
layer"): a static body teleported to the target each tick, joined to the pelvis by a
limit-free joint with bounded angular/linear motors, clamped to lead by ≤ 1 rad / 0.5 m.
Limb motors are now commanded in Jolt's swing-twist angle space (the limits' space) so
joints thrown to their limits come back. The balance tip-over is off in motor mode (a
held pelvis cannot topple; the ratio spikes were false falls). Verified: after a ragdoll
every shooting-range character gets up upright with ~2° error. Tooling from that
investigation: `tools/bench/scene_probe.gd` (`PROBE_ACTION=ragdoll`), `KickbackTraceRecorder`
(F5) + `tools/bench/trace_report.py`.
**Still open** (carried to 0.6.0): 30 Hz with non-colliding feet; 30 Hz hand-hit wrist
wrap; resolver CPU (≈1.4× on a quiet run, noisy); the visual gate (user), then
`plugin.cfg` 0.5.0 + tag.

---

## 0.6.0 — Balance + behaviors (`feat/balance-behaviors`)

**Goal.** One `BalanceState` per tick; stepping and arm balance become behaviors driven by
it; the scripted stumble and the sine sway are deleted.

**Checklist**
- [x] **Feet load-bearing** (2026-09-13, `test_feet_load_bearing.gd`, 9 tests): sole-aligned
  foot collider (`BoneDefinition.sole_aligned`, bottom face on the foot IK sole, heel added —
  the old bone-aligned box sat 7 cm under the floor, which is why the feet were masked out);
  feet collide in every state (`foot_ik_disable_foot_collision` default false) and report
  contacts; `muscle_root_support` (default 0) removes the anchor's vertical authority via a
  second, world-aligned position anchor. Measured (ybot): feet carry the body (were ~2 %);
  pelvis sag on the legs 6 mm @60 Hz / 0.8 mm @120 / 9 mm @30; idle 1.10/3.57 @60
  (0.94 before), 0.73/1.87 @120; get-up on the shooting range ≤ 8° at `recovery_finished`
  and 1–4° after 3 s (anchor lifts + frictionless feet during the canned blend, support
  faded back over 0.75 s). **Exposed**: SETTLE after react_front 10.2° @60 Hz (legacy
  0.96) — loaded feet stay where friction planted them; the step behavior must move them.
  30 Hz idle regressed 4.85 → 5.45 (open).
- [x] **Self-collision on** (2026-09-13, maintainer asked for the ragdoll look first; `test_self_collision.gd`,
  6 tests): `self_collision` default true; jointed pairs excluded by the joint, build-pose
  overlaps excluded by a safety net (`get_self_collision_exclusions`), everything else
  collides. Measured: ybot has no non-adjacent overlaps in idle / react / 4 s ragdoll, bench
  bit-identical on/off, get-up 2–5°. **Limits not tightened**: `tools/bench/limit_envelope.gd`
  shows 17 axes already exceeded by the 21 clips (elbow lateral ±58 vs ±20, spine X −75 vs
  ±35, knee 149 vs 140). Open: the elbow-lateral reading looks like a frame/twist-bone
  question; a stagger/ragdoll with a leg swinging through the other is now blocked.
- [ ] `BalanceState` (new file): CoM, CoM velocity, XCoM (`CoM + v / √(g / leg_length)`), support polygon from **foot contact** (feet collide in all states ✅; contact from the foot bodies' `contact_monitor` ✅ — the polygon itself is still to build), loaded foot, signed XCoM distance to the polygon edge, computed once per physics tick
- [ ] `Behavior` base (new file): `tick(balance, delta) -> {targets: Dictionary, stiffness: Dictionary, priority: int}`; the controller runs a fixed ordered list for now (arbiter comes in 0.7.0)
- [ ] `UprightBehavior` (pelvis/chest world-up torque, capped), `StepBehavior` (XCoM outside the polygon ⇒ swing-leg IK target = XCoM + k·v, leg joint targets from the two-bone solve; the body moves because the loaded leg pushes), `ArmBalanceBehavior` (arm target opposes XCoM error), `FallReachBehavior` (existing reach, moved), `GetUpBehavior` (existing canned blend, moved)
- [ ] Delete `_update_directed_stumble` root teleport, `_apply_stagger_sway`, `_apply_stumble_brace`, windmill phase circle; remove their tuning knobs
- [ ] **Removal list from the 2026-09-13 feature inventory** (each item was compensation for
  the velocity-overwrite substrate or a stand-in for balance, and is now either redundant
  or fake on top of real muscles):
  - [ ] `_apply_micro_reaction` (head-whip / torso-bend / spin torque impulses): added because
    the old resolver erased the real impulse in 3 ticks; with motors the impulse *is* the whip.
    Delete; re-check hit vividness on the bench without it before touching gains.
  - [ ] Velocity clamps (`max_angular_velocity` / `max_linear_velocity` hard writes) in motor
    mode: they overwrite what the motor just did. Motor mode uses `muscle_max_angular_velocity`
    on the command only.
  - [ ] Unjointed / root bodies in motor mode still run the legacy velocity spring
    (`_drive_root_body`); every body in motor mode is force-driven or free.
  - [ ] Reaction pulses, strength reduction + spread, threat pulse: keep as *modulation*
    (a torque-cap dip) but re-tune their defaults on the bench with real impulses; threat
    anticipation becomes a pose behavior (head turn / arm raise) or is removed from the API.
  - [ ] Stagger exit by regained balance (XCoM inside the polygon for `hold_time`), the timer
    only as a safety net.
  - [ ] Hit-streak / movement-instability multipliers and the `ragdoll_probability` dice
    roll: move out of the physics decision path into an explicit gameplay hook (a knockdown
    is either physics or an explicit call).
- [ ] **Tip-over owned by `BalanceState`, not dice.** Today in motor mode the CoM ratio check
  is off and *nothing physical decides a fall*: a standing character only goes down by
  `ragdoll_probability`, pain, or an explicit trigger. 0.6.0 acceptance requires the fall in
  the 400 N·s shove case to be *decided by XCoM leaving the polygon with no recoverable
  step*, and the root anchor to release when it does. `balance_changed` payload documented
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
- [ ] `RagdollTuning` ≤ 40 exports (161 on 2026-09-13), grouped by subsystem; build-time knobs moved to the profile; migration doc for removed knobs
- [ ] **Retire `VELOCITY_OVERWRITE`** (decision 2026-09-13): it stays through 0.6.0 as the A/B
  reference on the bench, then the legacy path, `spring_chain_consistency`, strength-scaled
  gravity, the settle deadbands and `test_rig_fidelity.gd`'s legacy pins go with the API cut.
  One muscle model, one code path.
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
