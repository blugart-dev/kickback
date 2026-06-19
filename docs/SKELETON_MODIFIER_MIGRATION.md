# PhysicsRigSync → SkeletonModifier3D migration plan

**Status: deferred** (planned for the `0.9.0` production-hardening milestone). This is a
written plan, not yet implemented. It exists so the work can be picked up against a clear,
code-grounded scope and so no future audit naively "fixes" the deprecated call (see
[GODOT_CONSTRAINTS.md](GODOT_CONSTRAINTS.md)).

## Why this exists

`PhysicsRigSync` pushes the physics ragdoll back onto the visible mesh with
`Skeleton3D.set_bone_global_pose_override()` (`physics_rig_sync.gd:127`). That method has
been **deprecated since Godot 4.3** ("may be changed or removed in future versions"). It
still works in 4.7 with no runtime warning, so there's no pressure today — but it will be
removed in a future major (Godot 5 is the likely point), at which time the ragdoll mesh
would stop following physics. Retiring it is the one piece of engine-API debt that will
hard-break on an upgrade.

The override is **load-bearing for a reason**, and that reason is why the obvious fix is
wrong:

- The override is a **separate layer**. It changes what the skin renders but does **not**
  change `get_bone_pose()`.
- `SpringResolver` reads `get_bone_pose()` (walked up the parent chain in
  `get_animation_bone_global`, `spring_resolver.gd:196-202`) as its **animation target** —
  the pose it drives the physics bodies *toward*.
- Swapping to the non-deprecated `set_bone_global_pose()` writes the real local pose, which
  contaminates `get_bone_pose()`, feeding the spring its own physics output → a feedback
  loop. The pose collapses.

So there is no small fix. The only correct path is to make `PhysicsRigSync` a
**`SkeletonModifier3D`**.

## Godot 4.7 landscape (investigated 2026-06-19)

**4.7 changed nothing in this subsystem.** It's a polish release (HDR, AreaLight3D,
VirtualJoystick, UI transform offsets); the official 4.7 dev snapshot lists no
Skeleton3D / SkeletonModifier3D / IK / ragdoll changes, only generic animation-*resource*
performance work. The `SkeletonModifier3D` class API is byte-for-byte the same between the
4.6 and 4.7 docs. Practical consequence: **the migration target is a stable API, not a
moving one** — it can be specced and built whenever, with no 4.7 churn to wait out.

Timeline of the relevant ground (all earlier than 4.7, all stable):

| Version | Landed |
|---------|--------|
| 4.3 | `SkeletonModifier3D` introduced; pose-override methods deprecated |
| 4.6 | IK framework returns: `IKModifier3D` + `TwoBoneIK3D` + `ChainIK3D` |
| 4.7 | *(no changes in this area)* |

Current modifier API (4.6+, unchanged in 4.7):
- Override `_process_modification_with_delta(delta)` — the old `_process_modification()` is
  itself deprecated.
- The modifier must be a **child of `Skeleton3D`**; processing order = child order.
- Apply **100%** of the result; the engine blends the `influence` property for you.
- Read modified poses only at the `modification_processed` / `Skeleton3D.skeleton_updated`
  signals — **not** in `_process()`.
- `Skeleton3D.modifier_callback_mode_process` (we already set this to `PHYSICS` in
  `kickback_character.gd:63` and `kickback_plugin.gd:254`).

## Why the migration is viable — the roll-back mechanic

This is the linchpin. Per Godot's *Design of the Skeleton Modifier 3D* article, a modifier's
output is applied to the skin and then **rolled back every frame**:

> "At the beginning of the update process, it stores the pose before the modification
> process temporarily. When the modification process is complete and applied to the skin,
> the pose is rolled back to the temporarily stored pose."
>
> "The modification by SkeletonModifier3D is immediately discarded after it is applied to
> the skin, so it is not reflected in the bone pose of Skeleton3D during `_process()`."

That is *exactly* the separation the override layer gives us today, but on a supported API:
the modifier writes the physics pose to the skin, then the base pose rolls back to the
animation result — so `get_bone_pose()` outside the modifier callback stays the clean
animation target the spring reads. **The feedback loop that blocks the naive swap does not
occur.**

## Code inventory — what actually touches skeleton poses

The reason this migration is *localized*: nothing in script reads the override **back**.
Every consumer of the physics pose reads the `RigidBody3D` transform directly (the rule in
[GODOT_CONSTRAINTS.md](GODOT_CONSTRAINTS.md): "always read from the RigidBody3D transforms
directly — never from skeleton bone poses"). Only the **skin** consumes the override.

| Site | What it does | Migration impact |
|------|--------------|------------------|
| `physics_rig_sync.gd:127` | `set_bone_global_pose_override(idx, xform, 1, true)` — the per-frame write | **MIGRATE** → `set_bone_global_pose()` inside `_process_modification_with_delta` |
| `physics_rig_sync.gd:45` | clears overrides on `set_active(false)` | **MIGRATE** → toggle modifier `active`; the engine rolls back |
| `physics_rig_sync.gd:90-119` | `_process()` + intermediate-bone interpolation | **MIGRATE** → move the body into the modifier callback |
| `spring_resolver.gd:196-202` | `get_bone_pose()` chain = animation target | **UNCHANGED** — roll-back keeps this clean |
| `physics_rig_builder.gd:108` | `get_bone_global_pose()` at build/snap time | **UNCHANGED** — override is inactive at build time |
| `foot_ik_solver.gd` | reads via `spring.get_animation_bone_global()` + `get_bone_global_rest()` | **UNCHANGED** — already reads the clean path |
| `active_ragdoll_controller.gd` (recovery, balance, sync) | reads `RigidBody3D` transforms directly | **UNCHANGED** |
| `kickback_character.gd:63`, `kickback_plugin.gd:254` | set `modifier_callback_mode_process = PHYSICS` | **KEEP** — now actually drives the modifier stack |

## The migration, concretely

1. **`PhysicsRigSync extends SkeletonModifier3D`** and the node becomes a **child of
   `Skeleton3D`** (today it's a sibling of the controllers). This is the one structural
   change and it ripples to node placement in: the setup tool (`kickback_plugin.gd`), the
   editor `RigBaker`, **all 8 demo scenes**, and `test/helpers/rig_harness.gd`.
2. **Move the per-bone write into `_process_modification_with_delta(delta)`**, using
   `set_bone_global_pose()` instead of the override. Apply 100% (let `influence` blend).
   Keep the degenerate-basis (`determinant`) guard from `_safe_set_bone_override`.
3. **Intermediate bones** (`_intermediate_cache`) get the same interpolation, written inside
   the callback.
4. **`set_active(bool)`** maps to the modifier's `active` property; the explicit
   override-clearing loop goes away (the engine's roll-back handles it).
5. **`sync_now()`** (the forced immediate sync that hides the 1-frame pop after a recovery
   teleport) has no direct equivalent — replace with `Skeleton3D.advance(delta)` to step the
   modifier stack on demand, or accept the next-frame modifier pass and re-verify there's no
   visible pop.

## Open design questions (resolve during implementation)

- **`set_bone_global_pose()` vs `set_bone_pose()` inside one pass** — does the global setter
  compose correctly per bone when parents and children are both written in the same
  modification pass (order sensitivity)? The current override sets global per bone and is
  order-independent; confirm the modifier equivalent matches.
- **Spring/modifier ordering** — the spring drives bodies in `_physics_process`; the modifier
  runs in the skeleton update (physics callback, after `AnimationMixer`). Confirm the spring's
  `get_bone_pose()` read still returns the *animation* pose given the `AnimationPlayer`/
  `AnimationTree` update timing.
- **`PhysicalBoneSimulator3D` coexistence** — the active path `queue_free`s it; the partial
  path uses it. Verify a `SkeletonModifier3D` doesn't reintroduce the
  override↔PhysicalBone leak documented in GODOT_CONSTRAINTS.md.
- **Foot IK as a downstream modifier (stretch)** — once the sync is a proper modifier, the
  hand-rolled `FootIKSolver` could potentially become a downstream modifier reading the
  physics pose at the stack signal, and even use the engine-native `TwoBoneIK3D` /
  `ChainIK3D` (4.6). Out of scope for the migration itself; noted as a follow-on.

## Validation (must be in-editor + visual — headless can't cover it)

The headless harness asserts the sync **math** but cannot confirm the mesh *renders*
correctly. Required per-scene visual checks across all 8 demos: ragdoll mesh tracks physics
with no jitter; recovery teleport shows no pop; foot IK plants on terrain; stagger sway is
visible; partial-ragdoll demos are unaffected.

**Test impact to plan for:** `test/test_runtime_rig.gd::test_skeleton_sync_follows_physics_during_ragdoll`
currently reads `get_bone_global_pose()` from the test's own timing and expects the *physics*
pose (the override). After migration, that read outside the modifier callback returns the
*rolled-back animation* pose, so the assertion must move to the `Skeleton3D.skeleton_updated`
/ `modification_processed` signal (or read the `RigidBody3D` directly). This is a known,
expected change — not a regression.

## Effort / risk summary

The code change is **localized** (essentially `physics_rig_sync.gd` plus node-placement
wiring) but it is **structural** (node moves under the skeleton) and **visually sensitive**
(it's the core render path of the ragdoll). It cannot be fully validated by automated tests.
That combination is why it's a dedicated `0.9.0` milestone rather than a cleanup PR.
