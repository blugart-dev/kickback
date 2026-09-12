# Muscle spike (2026-09-12) — can joint motors replace the velocity resolver?

The [audit](AUDIT_2026-09-12.md) §8 proposed replacing `SpringResolver`'s velocity
overwrite with a torque-bounded muscle layer, and asked for a spike before committing.
This is that spike. Script: `tools/spike/motor_spike.gd` (standalone, headless, touches no
plugin file):

```
godot --headless --path . -s tools/spike/motor_spike.gd            # velocity motors + script PD
SPIKE_SET=pos godot --headless --path . -s tools/spike/motor_spike.gd   # position-mode springs
SPIKE_SET=vel godot --headless --path . -s tools/spike/motor_spike.gd   # velocity-motor gain sweep
```

Godot 4.7.2 + Jolt, the synthetic 16-body harness rig (`test/helpers/rig_harness.gd`),
pelvis frozen so only joint tracking is measured, **no ground** (the harness foot box sits
inside the ground plane and corrupts the foot number). Error = angle between each body's
basis and its animation bone's basis. Nine bodies measured (torso, head, left arm, left leg).

Scenarios per configuration: **HOLD** (static pose, 1 s settle, 1.5 s measured),
**TRACK** (chest ±20° at 1 Hz, straight left arm ±40° at 1.5 Hz), **HIT** (8 N·s impulse
on the left hand; peak hand error and ticks until back under 5°).

## Three candidate muscle layers

| Layer | Mechanism | Torque limit | Gravity |
|---|---|---|---|
| `spring` (shipped resolver) | writes body angular/linear velocity every tick | none (blend fraction) | off at full strength |
| `motor` | Jolt 6DOF **velocity** motor per joint axis: target = `kp·err + feed-forward` in the joint frame, `PARAM_ANGULAR_MOTOR_FORCE_LIMIT` = muscle torque | yes | on (1.0) |
| `posmotor` | Jolt 6DOF **position** motor via Godot's angular-spring params (implicit); equilibrium point re-aimed every tick | only with `FLAG_ENABLE_MOTOR` also set | on |
| `pd` | script PD torque (`apply_torque`), gains from the body inertia tensor, subtree gravity compensation, clamp | yes | on |

Two engine facts the spike established empirically (both are now in
[GODOT_CONSTRAINTS.md](GODOT_CONSTRAINTS.md)):

- **Motor target velocity axes are mirrored**: a +1 rad/s target on X/Y/Z yields −1 rad/s
  of child-relative-to-parent rotation about the joint frame's X/Y/Z. Consistent with the
  limit-sign mirroring `JointDefinition.apply_to` already compensates for.
- **The angular-spring equilibrium point is the *inverse* relative rotation
  (parent-relative-to-child) decomposed with Godot's `EULER_ORDER_XYZ`**, sign +1
  (residual 0.0° on a composite target). The spring honours the motor force limit only
  when `FLAG_ENABLE_MOTOR` is enabled alongside `FLAG_ENABLE_ANGULAR_SPRING`.

## Results (mean error in degrees; arm = UpperArm / LowerArm / Hand)

| Config | Hz | HOLD mean | HOLD arm | TRACK mean | TRACK arm | HIT peak / recover |
|---|---:|---:|---|---:|---|---|
| spring (resolver) | 60 | 0.0 | 0/0/0 | 3.1 | 4/14/4 | 1.2° / 3 ticks |
| motor kp10 | 60 | 0.6 | 0.9/1.3/1.2 | 13.1 | 28/37/37 | 39° / 7 |
| motor kp20 | 60 | 1.8 | 3.0/3.9/3.6 | 11.1 | 22/28/27 | 34° / 73 |
| motor kp20, arm torque ×0.25 | 60 | 6.4 | **19/19/19** (sags: 15 N·m < the 19 N·m a horizontal arm needs) | 17.3 | 49/49/49 | 58° / never |
| motor kp20, arm torque ×4 | 60 | 3.8 | 7/11/10 (oscillates) | 26.0 | 48/62/68 | 179° / never |
| posmotor f=6 Hz ζ=1 | 60 | 2.4 | 1.5/4.3/4.3 | 16.4 | 27/40/43 | 124° / never |
| posmotor f=10 Hz | 60 | 0.9 | 0.5/1.6/1.6 | 30.4 | 54/71/82 | 177° / never |
| pd f=4 Hz | 60 | 19.5 | 37/40/40 | 53 | — | never |
| pd f=6 Hz | 60 | 59 | unstable | — | — | never |
| spring | 30 | 2.4 | 4/4/0 | 5.4 | 4/15/8 | 1.3° / 3 |
| motor kp20 | 30 | 9.5 | 13/17/17 | 37 | 55/67/70 | 162° / never |
| posmotor f=6 | 30 | 2.6 | 1.6/4.4/4.4 | 42 | 87/95/100 | 167° / never |
| spring | 120 | 0.0 | 0/0/0 | 3.8 | 8/12/3 | 1.4° / 3 |
| motor kp20 | 120 | 8.5* | 3/6/5 | 9.9 | 6/9/8 | 26° / 23 |
| posmotor f=6 | 120 | 2.4 | 1.5/4.3/4.3 | 9.6 | 15/20/21 | 19° / 17 |
| pd f=8 | 120 | 5.2 | 8/14/14 | 28 | 47/61/63 | never |

\* run with ground (foot artifact inflates the mean); arm numbers are comparable.
Raising Jolt's velocity iterations from 8 to 24 (via `override.cfg`) changed nothing.

## What the numbers say

1. **The resolver's "perfect" tracking is the cheat, quantified.** Gravity is off and
   velocities are overwritten, so HOLD is exactly 0 and a hit is erased in 3 ticks. Nothing
   physical can match that, and it should not: a muscle cannot teleport a limb.
2. **Velocity-mode motors are a working, physically honest muscle.** Under real gravity
   they hold a T-pose within ~1° (kp 10), the torque limit does what a muscle limit should
   (a 15 N·m shoulder cannot hold a horizontal arm; 60 N·m can), and a hit produces a real
   reaction (hand flung ~35–40°, back in 0.1–1 s) instead of being erased. Costs: fast
   motion tracks worse (the ±40° @ 1.5 Hz arm needs ~70 N·m, above the 60 N·m budget, so
   part of this deficit is *correct*), a small limit cycle on light bodies grows with gain
   and with motor torque, and the gain must be re-tuned per tick rate (kp 20 is unstable
   at 30 Hz).
3. **Position-mode springs are not usable as the primary muscle in 4.7's binding.** They
   hold well and are implicit, but tracking degrades sharply with tick rate (a property an
   implicit spring should not have — something in the per-tick equilibrium re-aim costs
   it), the torque limit needs the motor flag, and a hard hit can leave the joint stuck on
   the far side of Jolt's swing-twist decomposition (the 124–177° "never" rows).
4. **Script PD torque is rejected.** Explicit per-body PD at 60 Hz is unstable above ~4 Hz
   natural frequency on this rig's light limb chains, and 4 Hz is already too soft to hold
   an arm. Substepping would be needed; not worth it when Jolt's motors exist.

## Decision (revises audit §8)

Do **not** rip the resolver out. **Evolve it into a motor-driven muscle layer**:

- Keep the resolver's command formulation (error × gain + feed-forward, chain-aware,
  per-bone strength) — it is right, and it already carries the IK/override plumbing.
- Execute the command through each joint's **velocity motor** with the mirrored axis map,
  in the joint frame, with `force limit = muscle torque × strength` instead of writing
  body velocities. Strength becomes a torque; hits stop being erased.
- Gravity on for every jointed body. The pelvis (no parent joint) keeps a weakened
  position pin plus an upright torque, so the character still stands before the balance
  layer exists.
- Gains normalised per tick (`kp·dt` constant, ≈ 0.17–0.33 at 60 Hz), the same
  `_fr_weight` idea the resolver already has.
- Ship it behind a `muscle_mode` switch (`VELOCITY_OVERWRITE` legacy / `JOINT_MOTOR`),
  A/B on the ybot, and accept a tracking-error regression on fast clips in exchange for
  physical honesty. The acceptance bar for 0.5.0 is HOLD ≤ 2°, idle tracking ≤ 5°, and
  hit response visibly physical, at 60 Hz, on the demo character.

Open items the muscle layer must address (all reproducible with the spike script):
the light-body limit cycle (candidates: lower kp on low-inertia joints, command the
parent's motion into the child's target like the resolver's chain-consistency term),
30 Hz stability (kp scaling alone was not enough; verify with `_fr_weight`-style
normalisation), and the swing-twist wrap after violent hits (velocity mode recovered in
every 60/120 Hz run; verify on the ybot with joint limits at their authored values).

## Addendum — what the implementation found (0.5.0, 2026-09-13)

- **The spike commanded the motor in the wrong frame for two of its three axes.** Jolt
  solves the 6DOF angular motor on swing-twist axes: twist about the *parent* frame's X,
  swing about the *child* frame's Y/Z. The spike (and the first implementation) used the
  parent frame for all three; on the harness T-pose that is invisible (single-axis
  rotations), on the ybot idle it left every joint 2–4° short. With the split, the ybot
  idle went from 5.4° to 0.96° mean. Part of the spike's "TRACK deficit" was this, not
  the torque budget.
- **The root must be a motor too.** A velocity-overwritten pelvis under bounded child
  motors sat 8° off on the real idle (the reaction torques of the spine and hip motors
  rock it); a limit-free world joint with a 400 N·m motor fixed it (pelvis 0.6°).
- **Gain 0.10 per tick, not 0.15–0.25.** Once the pelvis is a bounded motor the arm chain
  rings at 0.15 on a 60° elbow step; 0.10 settles without ringing and still tracks a
  ±40° 1.5 Hz swing within 5°.
- Final ybot numbers and the 30 Hz caveat are in REFERENCE.md "Muscle layer".
