# Self-Preservation (0.4.0)

The first milestone where the character *actively tries to survive* a loss of balance
instead of only reacting and falling. Two behaviors:

1. **Stumble stepping** — when balance tips during `STAGGER`, the character takes a
   procedural recovery step in the fall direction to catch itself.
2. **Arm bracing** — when a fall becomes unavoidable, the character reaches an arm
   toward the ground to break the fall.

This is the start of the "active self-preservation" layer in the
[scorecard](ROADMAP.md) — the hard, heavily-weighted part of Euphoria parity. The
springs are the muscles; this milestone is the first piece of the *brain* telling them
what to do.

## Design principles (unchanged)

- **No new physics paradigm.** Both behaviors are *target generation*: they compute
  world-space goal transforms and feed them to `SpringResolver.set_target_overrides()`,
  exactly like `FootIKSolver` already does. The springs do the smoothing and the
  physics does the rest. We are not adding torque controllers or new joint types.
- **Animation-agnostic and signal-driven.** New signals announce what happened
  (`stumble_step_started`, `brace_started`); no animation is played from the
  controller.
- **Role-driven, multi-rig safe.** Arms resolve through new `RagdollProfile` semantic
  roles (mirroring the existing leg-chain roles), so non-Mixamo rigs degrade gracefully
  instead of hardcoding bone names.
- **Behaviors are opt-out via tuning.** Each behavior has an `_enabled` flag and a
  full tuning group, defaulting on with conservative values. A rig with no arms simply
  never braces; a profile with no leg chain never stumbles.

## What already exists that we build on

These are the hooks the milestone plugs into — none of them are new:

| Existing piece | What it gives us | File |
|---|---|---|
| `_compute_balance_state()` | `com`, `support_center`, `balance_ratio`, `imbalance_dir`, `has_support` — the full balance signal, every stagger frame | `active_ragdoll_controller.gd` |
| `STAGGER` state + `_update_stagger()` | The window where a character is off-balance but still on its feet — exactly when a stumble step should fire | `active_ragdoll_controller.gd` |
| `FootIKSolver` | A complete two-bone IK solver that already **moves a foot to a world target** (`_pin_pos_l/r`) and writes the result through spring overrides during `STAGGER` | `foot_ik_solver.gd` |
| `RagdollProfile` semantic roles | `get_leg_chain("L"/"R")`, `get_foot_rigs()`, `get_leg_side()` — the pattern we mirror for arms | `resources/ragdoll_profile.gd` |
| `balance_ragdoll_threshold` / `balance_recovery_threshold` | The existing tip-over / recovered thresholds the step decision slots between | `ragdoll_tuning.gd` |

The key insight: **stumble stepping is "move the foot pin in the fall direction"**, and
`FootIKSolver` already pins and moves feet to world targets during `STAGGER`. We are
extending an engine, not writing one.

---

## Behavior 1 — Stumble stepping

### Trigger window

Inside `_update_stagger()`, balance is already classified each frame:

- `balance_ratio < balance_recovery_threshold` → regaining balance (early recovery)
- `balance_ratio > balance_ragdoll_threshold` → tipping over (→ full ragdoll)
- in between → staggering in place (sway + active resistance)

A stumble step fires in a **new band just below the ragdoll threshold**: the character
is past "wobbling" and heading toward a fall, but a well-placed step could still save
it. Concretely: `balance_ratio > stumble_step_threshold` (a new tunable that sits
between `balance_recovery_threshold` and `balance_ragdoll_threshold`), gated by a
per-step cooldown so we take discrete steps rather than sliding a foot continuously.

If a step lands and balance drops back under `balance_recovery_threshold`, the existing
early-recovery path ends the stagger — the catch *worked*. If `balance_ratio` keeps
climbing past `balance_ragdoll_threshold` despite stepping (up to
`stumble_max_steps`), the existing tip-over path takes over and the character ragdolls —
the catch *failed*. Both outcomes already exist; stumble stepping just inserts an
attempt to avoid the second.

### Which foot steps

The **trailing foot** — the one on the side the CoM is falling *away* from — swings to
catch the fall. `imbalance_dir` (XZ unit vector toward the fall) plus each foot's
position relative to `support_center` already tell us this; `_apply_active_resistance()`
computes nearly the identical "load-bearing leg" calculation today. The load-bearing
foot stays planted; the other steps.

### Where it steps

A ground target offset from the stepping foot's current position, in the
`imbalance_dir`, by `stumble_step_length` (scaled by `balance_ratio` so a harder tip
takes a bigger step), clamped to a reachable distance, then snapped to the ground via
the existing foot-IK ground raycast. This becomes the foot's IK target for the duration
of the step, blended in/out by the existing `foot_ik_foot_blend_speed`.

### Execution

`FootIKSolver` gains a stumble mode alongside its current pin mode: instead of holding
`_pin_pos` static, the pin target lerps to the step goal over `stumble_step_duration`,
plants, and holds. The two-bone IK, weight blending, and override plumbing are all
reused as-is. The controller owns the *decision* (when/which/where); the solver owns the
*motion*.

### New surface

- `RagdollTuning`: `stumble_enabled`, `stumble_step_threshold`, `stumble_step_length`,
  `stumble_step_duration`, `stumble_step_cooldown`, `stumble_max_steps`,
  `stumble_step_reach_max` (+ validation).
- Signal: `stumble_step_started(foot_rig: String, target: Vector3)`.
- `FootIKSolver`: `begin_stumble(foot_rig, target)`, step-target lerp in the solve.

---

## Behavior 2 — Arm bracing

### Trigger

A brace fires when a fall is committed — i.e. the controller is entering/!in `RAGDOLL`
with the CoM descending toward ground within `brace_anticipation_time`, OR a stumble
catch failed. A short downward raycast from each shoulder/hand finds whether there is
ground within reach; if so, that arm braces.

### Which arm

The arm on the side the body is falling toward (leading side, via `imbalance_dir`),
preferring whichever shoulder is closer to the detected ground. Both arms may brace for
a face-down fall.

### Execution

A new `ArmIKSolver` mirrors `FootIKSolver`: same law-of-cosines two-bone solve, same
spring-override output, operating on the arm chain (`shoulder→elbow→hand`) with the hand
as the end effector reaching the braced ground point. Because the two solvers share the
same math, PR5 factors the reusable core (`_solve_two_bone_ik`, the basis helpers) so it
is not copy-pasted.

The brace holds while the hand is loaded, then blends out as springs recover (entering
`GETTING_UP`), reusing the existing blend-out logic shape.

### New surface

- `RagdollProfile`: `left_arm_chain` / `right_arm_chain` roles +
  `get_arm_chain("L"/"R")`, `get_all_arm_rigs()`, `get_arm_side()`, `get_hand_rigs()`,
  mirroring the leg accessors. Mixamo defaults:
  `["UpperArm_L","LowerArm_L","Hand_L"]` / `..._R`.
- `RagdollTuning`: `brace_enabled`, `brace_anticipation_time`, `brace_reach`,
  `brace_ground_mask`, `brace_strength`, `brace_blend_speed` (+ validation).
- Signal: `brace_started(arm_rig: String, target: Vector3)`.
- New file: `arm_ik_solver.gd`, owned by `ActiveRagdollController`, lazily initialized
  like `_foot_ik`.

---

## State-machine integration

No new states. Behaviors hang off the existing machine:

```
NORMAL ──hit──▶ STAGGER ──(balance tips into stumble band)──▶ [stumble step attempt]
                  │                                                    │
                  │ catch works (balance < recovery)                  │ catch fails
                  ▼                                                    ▼
                NORMAL  ◀──────────────                          RAGDOLL ──(CoM descending)──▶ [arm brace]
                                                                     │
                                                                     ▼
                                                                 GETTING_UP (brace blends out)
```

- Stumble lives entirely inside `STAGGER` (`_update_stagger`), driven through the foot IK
  that already runs there.
- Brace spans the `STAGGER→RAGDOLL` transition and the early part of `RAGDOLL`, blending
  out into `GETTING_UP`.

## Testing strategy

Following the 0.3.x pattern (drive the *real* classes via `test/helpers/rig_harness.gd`,
no re-implemented formulas):

- **Decision logic** (PR2): synthetic off-balance state → assert correct stepping foot
  and a target offset in `imbalance_dir`; assert no step inside cooldown / above
  `stumble_max_steps`.
- **Arm roles** (PR4): pure-data accessor tests, incl. a non-convention rig and a
  missing-arm rig (graceful empty).
- **`ArmIKSolver`** (PR5): on the harness rig over ground — initializes, reaches a
  target within arm length, blends out on reset.
- **Visual** (PR3/PR6): in-editor validation, as with the 0.3.x foot-IK/spring work.

## Open design questions (for review)

1. **Stumble step count** — cap at 1 (single catch step) or allow `stumble_max_steps`
   chained steps (more Euphoria-like, more failure modes)? *Leaning: configurable, default 2.*
2. **Root translation during a step** — does a step move the character root (real
   locomotion) or only place the foot while the root stays put (catch-in-place)?
   *Leaning: foot-placement only for 0.4.0; root-following recovery is 0.8.0 Balance
   Recovery territory.*
3. **Brace as RAGDOLL override vs. pre-ragdoll STAGGER extension** — brace during the
   committed fall (simpler, reads as "throwing hands out") or try to brace *before*
   committing (harder, can look like flailing)? *Leaning: during the committed fall for
   0.4.0.*

These don't block PR2; they're flagged so the feel decisions are explicit before the
visual PRs.
