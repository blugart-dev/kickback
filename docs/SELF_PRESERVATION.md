# Self-Preservation (0.4.0)

The first milestone where the character *actively reacts* to a hit instead of only
absorbing it or falling. Two behaviors:

1. **Directed stumble** *(shipped)* — a staggering hit visibly **shoves the character**:
   it lurches in the hit direction, the legs step to follow and keep it upright, and
   the upper body reacts loosely. It ends up somewhere new, then recovers to idle.
2. **Arm bracing** *(next)* — arms swing out to windmill for balance during a stumble,
   and reach for the ground when a fall is committed.

This is the start of the active self-preservation layer in the [scorecard](ROADMAP.md) —
the hard, heavily-weighted part of Euphoria parity. The springs are the muscles; this
milestone is the first piece of the *brain* telling them what to do.

## Design note: directed, not emergent

The first attempt drove stumbling **emergently** — wait for the centre-of-mass to drift
into a balance band, then make a small foot reposition to "catch" it. In practice it was
**invisible and unreliable**: most hits either never reached the band (recovered on
their own) or blew straight past it to a ragdoll, and even when it fired, a foot
reposition on an otherwise-rigid body didn't read as anything.

The behavior was reworked to be **directed**, which is closer to how Euphoria actually
works (a library of *triggered* physical behaviors, not pure emergent physics):

- The hit **triggers** the stumble directly and reliably (not a rare emergent window).
- The reaction is **big and legible** — it *displaces* the character, so you see it.
- It is **art-directable** via tuning (distance, speed, step count, stiffness).

The active-ragdoll springs (hardened separately — see the foot-IK orientation fix and
the spring settle deadband) are still the body; the directed stumble drives a bold,
reliable reaction on top of them.

## Directed stumble — how it works

On a staggering hit (`_start_stagger`), if the hit has a horizontal component, a stumble
begins, driven entirely by the hit direction:

**1. Knockback displacement.** The character root drifts along the hit direction at
`stumble_push_speed`, decaying at `stumble_push_decel` (momentum absorbed). Total travel
≈ `speed² / (2·decel)`. The springs pull the body along, so the whole character
*displaces* — you stumble where you're shoved. (Root motion happens in
`_physics_process`, per the locomotion rule in CLAUDE.md.)

**2. Stepping feet.** Every `stumble_step_length` of travel, the **trailing foot** (the
one furthest back along the drift) steps, up to `stumble_max_steps`. Each step, through
`FootIKSolver.begin_stumble()`:
- swings to a target placed *ahead of the hips* in the drift direction, **preserving the
  foot's lateral offset** so the feet stay in their own lanes and don't cross;
- **lifts** along a sine arc (`stumble_step_lift`) so it steps *over* the ground instead
  of sliding across it.

**3. Differential stiffness.** While stumbling, only the **lower body** (leg chains +
pelvis) stiffens toward base (`stumble_brace_strength`) to step and stay upright. The
**upper body is left loose** (at the stagger floor) so the torso, arms, and head react to
the hit and the momentum. That contrast — purposeful legs, reactive upper body — is what
reads as a live body caught off guard rather than a rigid mannequin.

**4. Commit + end.** While stumbling (`_stumbling`) the tip-over→ragdoll transition is
suspended, so the reaction plays out instead of collapsing mid-step. The stumble ends
when the drift is spent and the last step has planted; the stagger then recovers to NORMAL
on its own (the character stays at its new, displaced position).

A strong enough hit still ragdolls (you can't catch everything); a light hit just wobbles.
The stumble is the middle band — the visible "shoved and recovered" reaction.

### New surface

- `RagdollTuning` "Self-Preservation: Stumble Steps" group: `stumble_enabled`,
  `stumble_step_length`, `stumble_step_reach_max`, `stumble_step_duration`,
  `stumble_max_steps`, `stumble_brace_strength`, `stumble_push_speed`,
  `stumble_push_decel`, `stumble_step_lift` (+ `stumble_step_threshold` retained for
  future balance-driven use).
- `FootIKSolver`: `begin_stumble(foot_rig, target, duration)` + `is_stepping()` — the foot
  step animation (lerp + lift arc), reusing the existing stagger pin/IK/override plumbing.
- Signal: `stumble_step_started(foot_rig, target)`.

## Arm bracing

The upper-body active layer, so the whole reaction reads together (before this, the arms
only reacted passively because they're loose):

- **Windmill** — during a directed stumble the arms swing wide to fight for balance. Each
  hand sweeps a wide vertical circle out to its own side, the two arms in opposite phase.
  The arc is **coupled to the stumble's momentum** (full at impact, winding down as the
  drift spends) and **aligned to the fall direction** (sweeps in the plane of the shove and
  leans into it), so it reads as a reaction to *this* hit, not a canned loop. It's layered
  at **partial weight** over the loose flail — a balancing tendency, not a rigid takeover.
- **Reach for the ground** — when a hit commits to a fall, the **leading arm** (the shoulder
  furthest along the fall direction) reaches toward the ground to break it. Because a limp
  ragdoll has left its animation pose, this can't be solved from animation: a brief braced
  window keeps that arm's springs alive and runs the IK **anchored to the physical arm**,
  driving the hand toward a ground point within reach while the rest of the body goes limp,
  then releases into the full ragdoll (on contact or when the window expires). It's gated to
  **forward/side falls** — a backward fall can't be broken by a hands-forward plant, and
  forcing it just contorts the arm.

**How it's built.** `RagdollProfile` arm-chain roles (`get_arm_chain`, mirroring the leg
chains) + the `ArmIKSolver`, which mirrors `FootIKSolver`: it drives an arm to a world-space
target and blends its IK weight in/out (`begin_reach`/`update_reach`/`end_reach`), with an
animation-anchored mode (windmill) and a physics-anchored mode (fall reach). The two-bone
math (law of cosines + swing-of-animation basis) is factored out of `FootIKSolver` into a
shared, stateless `TwoBoneIK` util both solvers use — no duplication; the foot IK refactor is
behavior-preserving (idle foot buzz unchanged within physics noise). Foot IK and arm IK share
the spring's override channel by **merging** into a per-frame-cleared set (foot first, arm
last), so both can write the same frame without clobbering. The controller triggers the
windmill from the stumble update and the reach from the ragdoll commit; tuning lives in the
`RagdollTuning` "Self-Preservation: Arm Bracing" group, with live sliders in the Tuning Lab
and a fall-reach target gizmo in the F3 debug HUD.

## State-machine integration

No new states. The directed stumble lives inside `STAGGER` (`_update_directed_stumble`,
called from `_update_stagger`) and commits across the tip-over check. Arm bracing spans the
`STAGGER`→`RAGDOLL` transition: the windmill runs in `STAGGER` (driven from the stumble
update), and the fall reach runs at the `RAGDOLL` commit (set up in `_full_ragdoll`, advanced
in `_update_ragdoll`) — keeping the bracing arm's springs alive into the otherwise-limp fall.

## Testing

Following the project pattern (drive the *real* classes via `test/helpers/rig_harness.gd`):

- **Directed stumble** (`test/test_stumble_step.gd`) — on a live rig, a staggering hit
  displaces the character along the hit direction, fires steps, and recovers; disabling
  the behavior suppresses both. The synthetic rig's emergent fall is too nonlinear to
  assert a *physical* catch outcome, so motion *quality* is validated visually on the
  real ybot, not asserted.
- **Arm roles** (`test/test_ragdoll_profile_roles.gd`) — pure-data accessor tests, as for
  the leg chains.
- **`TwoBoneIK`** (`test/test_two_bone_ik.gd`) — pure math: swing degeneracies, segment-
  length invariants, identity when no adjustment is needed.
- **`ArmIKSolver`** (`test/test_arm_ik.gd`) — the real solver on a live rig: reach drives the
  hand to target, unreachable targets no-op, weight blends out on release, and the
  physics-anchored mode reaches from the body pose.
- **Fall reach** (`test/test_fall_brace.gd`) — drives the real controller: a forward fall
  keeps the leading arm alive while the rest goes limp, a backward fall skips the reach (the
  `min_facing` gate, which is configurable), and the brace releases after its window. The
  reach *motion* is validated visually; the tests assert the state-machine wiring.
