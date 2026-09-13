# Self-Preservation — the behavior layer (0.6.0)

> Rewritten 2026-09-13. The 0.4.0 "directed stumble" this document used to describe —
> a scripted displacement of the character root along the hit direction, steps paced by
> distance travelled, a phase-circle arm windmill — was deleted in 0.6.0 (see
> [AUDIT_2026-09-12.md](AUDIT_2026-09-12.md) §3.2 for why). Nothing in the plugin
> writes the character root's position any more; `grep "global_position +=" addons/kickback/`
> is empty.

## What a behavior is

A **behavior** (`addons/kickback/behaviors/behavior.gd`, `KickbackBehavior`) reads the
shared [`BalanceState`](REFERENCE.md#balance-state-060) every physics tick and answers
with what it *wants*:

```
{ "stiffness": { rig_name: multiplier },   # of the bone's effective base strength
  "targets":   { rig_name: Transform3D } } # world-space pose targets
```

It never writes to the rig. `ActiveRagdollController._tick_behaviors` runs a fixed
ordered list in NORMAL and STAGGER (after the balance update, before the IK solvers),
applies each stiffness as a **floor** on the bone's current strength and merges the pose
targets into the resolver's override channel after the IK solvers (a behavior wins on a
shared bone). The 0.7.0 arbiter replaces the fixed order with per-bone priority. A
behavior gets a `BehaviorContext` (resolver, rig, profile, tuning, root, the foot / arm
IK solvers, the state) and lifecycle calls (`on_state_changed`, `reset` on ragdoll).

## StepBehavior

`addons/kickback/behaviors/step_behavior.gd`. Two reasons to step, both read from
`BalanceState`:

| Trigger | Condition | Swing foot | Landing spot |
|---|---|---|---|
| **Balance step** | `ratio ≥ step_trigger_ratio` (0.9) for `STEP_TRIGGER_TICKS` (4) consecutive ticks — the capture point has reached the edge of the feet and stays there | the foot on the fall side (largest offset from the support centre along the imbalance direction) | the XCoM + 5 cm in the fall direction, kept ≥ `step_min_stance` from the stance foot, ≤ `step_max_length` from where the foot stands |
| **Re-plant** | `ratio ≤ step_calm_ratio` (0.85) and a foot in contact stands more than `step_replant_distance` (0.10 m) from its animation spot | the less loaded of the mis-placed feet | its animation spot |

A step (`FootIKSolver.begin_step`) is a lifted arc the foot IK solver animates as the
foot's target over `step_duration` (0.22 s) with `step_lift` (0.08 m); the joint motors
execute it. The foot then **hovers** at the goal with a little lift until the physical
foot has arrived within 5 cm (or 2.5 durations pass), because the motors lag the target
by ~10 ticks and a foot that touches down short is loaded and friction-pinned where it
lands. On landing the lock is set to where the foot actually is. While a foot is in
flight the behavior asks for the leg chains and the pelvis at full base strength (a
stagger's 10 % floor cannot step). Signals `step_started(foot_rig, target)`.

**Foot locks.** A load-bearing foot cannot be dragged by the animation — friction wins
over the leg motors. So a foot in contact whose animation spot has drifted more than
5 cm is *locked* to the ground where it stands (`FootIKSolver.set_foot_lock`: its IK
target becomes its own position, so the leg stops fighting friction) and released when
the spot comes back within 5 cm or the foot leaves the ground (the animation lifted it:
let it swing). The stagger's anti-slide pin is the same lock on both feet. Locks and
steps run in `JOINT_MOTOR` mode only; the legacy velocity-overwrite resolver drags
feet with unbounded force and never needs them.

**Measured** (ybot, 60 Hz, `tools/bench/step_probe.gd`):

- Root moved 0.25 m forward with the feet planted: right foot re-planted at 0.33 s,
  left at 0.83 s, legs within 1.5° by 1 s.
- After the `react_front` clip (feet friction-planted up to 0.4 m from their spots):
  5 steps over ~1.7 s, legs within 3° by 2.8 s. Bench SETTLE (idle error over the
  second after the clip) 10.4°, second 2: 6.2° — was 9.9° flat before the steps.
- 150 N·s shove at the chest **with the anchor's sideways hold** (`muscle_root_hold` 1,
  the default): 2–4 steps, pelvis moves 1–2 cm, ratio back to 0.6 within 2 s. These
  steps re-arrange the feet under a pelvis the anchor never let move.
- **Without the sideways hold** (`muscle_root_hold` 0) and no upright behavior: the
  standing idle is unstable — 7.2° idle error, constant steps, a 150 N·s shove walks
  the character off. The legs' soft, torque-limited motors (ankle 60 N·m against a
  720 N·m/rad inverted pendulum) with a ~10-tick lag cannot hold quiet standing by
  tracking a fixed pose; an ankle / hip strategy on the XCoM is required. That is the
  **UprightBehavior**, next; the hold goes to 0 with it.

## Fall reach (arm bracing on a committed fall)

Unchanged from 0.4.0 in mechanism, moved to the fall direction of the *hit*: when a hit
commits to a ragdoll (`_full_ragdoll`), the arm on the fall side keeps its muscles alive
(`arm_fall_reach_strength`) and reaches through the arm IK solver toward a ground point
`arm_fall_reach_distance` ahead, releases on ground contact or after
`arm_fall_reach_duration`, then goes limp with the rest. Skipped when the fall runs
against the character's facing (a backward fall cannot be broken by a forward plant).
Becomes `FallReachBehavior` when the arbiter lands.

## What is gone, and its replacement

| 0.4.0 | 0.6.0 |
|---|---|
| root teleport along the hit direction (`_update_directed_stumble`) | the body moves because the legs push and a foot lands under the CoM — or, with the hold on, does not move at all |
| steps paced by distance travelled | steps decided by the capture point and by foot mis-placement |
| stumble brace (lower body stiffened while stumbling) | leg stiffness asked for by the behavior only while a foot is in flight |
| arm windmill (phase circle scaled by drift) | deleted; `ArmBalanceBehavior` (arm target opposing the XCoM error) is next |
| `stumble_*`, `arm_windmill_*`, `arm_brace_weight` knobs | `steps_enabled`, `step_trigger_ratio`, `step_calm_ratio`, `step_replant_distance`, `step_duration`, `step_lift`, `step_max_length`, `step_min_stance` |
| `stumble_step_started` signal | `step_started(foot_rig, target)` |

## Testing

`test/test_step_behavior.gd` (6): the default list holds a StepBehavior; a quiet stance
never steps; the whole animation moved 0.2 m forward re-plants both feet with lifted
steps and the root never moves; `steps_enabled = false`; a sideways shove with the hold
released fires a balance step with the fall-side foot, landing further out; a stagger
recovers without moving the root. `test/test_balance_state.gd` covers the sensor.
