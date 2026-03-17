# Godot 4.6 Constraints and Workarounds

Read this BEFORE writing any physics code. These are confirmed issues and
workarounds specific to Godot 4.6.x with Jolt physics.

## Why we use RigidBody3D instead of PhysicalBone3D for active ragdoll

PhysicalBone3D is missing critical RigidBody3D functionality (proposal #8008):
- No `apply_force(force, position)` — only `apply_impulse()` is exposed
- No `apply_torque(torque)` — the method doesn't exist
- No `body_entered` / `body_exited` signals — can't detect collisions
- No `contact_monitor` property
- No `center_of_mass` property
- No `get_colliding_bodies()`

RigidBody3D has ALL of these. The active ragdoll layer uses RigidBody3D exclusively.

PhysicalBone3D + PhysicalBoneSimulator3D is used ONLY for the mid-range partial
ragdoll tier (Step 1), where apply_impulse() and influence blending are sufficient.

## PhysicalBoneSimulator3D (used in Step 1 only)

### influence is global, not per-bone
`PhysicalBoneSimulator3D.influence` (0.0-1.0) blends ALL bones between
physics and animation. You cannot set per-bone influence. This means when
blending back from partial ragdoll, ALL bones get slightly softened.
For brief hit reactions (0.3-0.4s blend), this is acceptable.

### Partial simulation works
`simulator.physical_bones_start_simulation(["UpperArm_L", "LowerArm_L", "Hand_L"])`
correctly simulates only the named bones. This is the core of Step 1.

### Keep AnimationTree active
```gdscript
# WRONG — stops target poses, ragdoll looks worse
animation_tree.active = false

# RIGHT — animation keeps playing, physics overrides selectively
animation_tree.active = true
```

### Deferred simulation start
Don't start simulation in _ready(). Wait one frame:
```gdscript
func start_ragdoll():
    await get_tree().physics_frame
    simulator.physical_bones_start_simulation()
```

## Jolt physics specifics

### Verify Jolt is active
Project Settings → Physics → 3D → Physics Engine must be "JoltPhysics3D".
If it says "GodotPhysics3D", change it. GodotPhysics has:
- Generic6DOFJoint3D motors/springs NOT IMPLEMENTED (despite UI existing)
- ~50 body limit vs Jolt's ~800
- No angular motor support

### Joint springs are unreliable
Generic6DOFJoint3D angular springs are poorly documented with Jolt.
Spring equilibrium point has coordinate space issues and flipped axes.
**DO NOT USE built-in joint springs.** Use the velocity-based spring
resolver in script instead (Step 4). This is what V-Sekai and Jolt's
creator recommend.

### Angular motors DO work
If you need joint-level motors (we don't for the spring resolver approach):
```gdscript
joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, 0.0)
joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, 100.0)
joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_MOTOR, true)
```

### Solver tuning for ragdolls
```
Project Settings → Physics → Jolt 3D → Solver:
  Velocity Iterations: 8   (default 4 — increase for joint stability)
  Position Iterations: 2   (default 1)
```

### Disable sleeping on active ragdoll bodies
The spring resolver constantly modifies velocities, which conflicts with sleep:
```gdscript
rigid_body.can_sleep = false  # For all active ragdoll bodies
```
Re-enable sleeping for dead/settled ragdolls to save CPU.

## Skeleton3D.get_bone_global_pose() timing

In Godot 4.3+, `get_bone_global_pose()` may return stale data during physics.
Two safe alternatives:

```gdscript
# Option A: Read directly from the RigidBody3D (always current)
var bone_global = physics_body.global_transform

# Option B: Connect to PhysicalBoneSimulator3D signal (Step 1 only)
simulator.modification_processed.connect(_on_poses_updated)
```

For the dual-skeleton approach (Steps 3+), always read from the RigidBody3D
transforms directly — never from skeleton bone poses.

## Scaling

PhysicalBoneSimulator3D has scaling bugs (#95679). Keep character root at
scale (1,1,1). Scale the mesh at import time or on the MeshInstance3D.
Never apply non-uniform scale to any node in a ragdoll hierarchy.

## PhysicalBone3D joint types (learned in Step 0-1)

### Auto-generated joints use PIN — switch to CONE
Godot's "Create Physical Skeleton" generates all joints as `joint_type = 1`
(PIN). PIN joints are simple ball-and-socket with **no angular limits** — bones
can rotate freely in any direction. This causes unnatural bending.

Change all joints to `joint_type = 2` (CONE/ConeTwist) which provides:
- `swing_span`: max angle bone can deviate from rest direction (degrees)
- `twist_span`: max twist rotation around bone's own axis (degrees)
- `bias`, `softness`, `relaxation`: constraint stiffness tuning

Recommended values for Mixamo Y Bot:
- Spine: swing 30°, twist 25°
- Head: swing 60°, twist 55°
- Arms (shoulder): swing 80°, twist 60°
- ForeArms (elbow): swing 80°, twist 10°
- UpLegs (hip): swing 70°, twist 30°
- Legs (knee): swing 80°, twist 10°
- Feet (ankle): swing 35°, twist 20°

### Self-collision
Set PhysicalBone3D `collision_mask` to include its own layer (layer 5) for
inter-bone collision. Without this, limbs pass through each other.
Mask = 18 (layer 2 environment + layer 5 self).

### Damping
Auto-generated bones have zero damping — ragdoll feels liquid. Add:
- `angular_damp = 5.0` (prevents spinning)
- `linear_damp = 0.5` (prevents excessive bouncing)

## Dual-skeleton physics rig (learned in Step 3)

### Body positioning: use bone transforms, not midpoints
Place each RigidBody3D at the bone's `global_transform` directly. Offset the
collision shape locally within the body (`col.position = offset`). Do NOT place
bodies at midpoints between bones — the offset math accumulates errors and
causes visible snapping when toggling physics on/off.

### PhysicalBoneSimulator3D conflicts with set_bone_global_pose_override
When the sync script writes `set_bone_global_pose_override()` on the Skeleton3D,
any PhysicalBone3D nodes still in the scene receive the overridden transforms.
This can produce degenerate bases that Jolt rejects. Fix: `queue_free()` the
PhysicalBoneSimulator3D entirely, not just `process_mode = DISABLED`.

### Symmetric joint limits without spring resolver
Without a spring resolver to enforce pose direction, asymmetric 6DOF angular
limits (e.g., knee -120/0) cause backwards bending because the joint frame
orientation is unpredictable. Use symmetric limits (e.g., ±60) until the spring
resolver is in place.

### Degenerate basis guard for set_bone_global_pose_override
Always check `basis.determinant()` before passing a transform to
`set_bone_global_pose_override()`. Skip if determinant is near zero.

## Signal ordering with async controllers (learned in polish pass)

When multiple controllers react to the same hit event, call order matters.
A controller that uses `_set_reacting(true)` synchronously will block any
subsequent controller that checks `is_reacting()`. Solution: call instant
handlers (AnimationPlayer.play) before async handlers (ragdoll with await).

```gdscript
# WRONG — ragdoll sets is_reacting=true, flinch always skips
_ragdoll_ctrl.apply_hit(event)
_flinch_ctrl.on_hit(event)

# RIGHT — flinch plays instantly, ragdoll starts async after
_flinch_ctrl.on_hit(event)
_ragdoll_ctrl.apply_hit(event)
```

## AnimationTree (learned in Step 2)

### Don't hand-write AnimationTree in .tscn
AnimationTree sub_resources (BlendSpace2D, BlendTree, etc.) have complex internal
types. Writing them by hand in .tscn causes "Type mismatch between initial and
final value" errors spamming every frame. Always set up AnimationTree through
the Godot editor.

### Simple flinch approach: skip AnimationTree entirely
For directional flinch animations, `AnimationPlayer.play()` + `queue("idle")` is
simpler and more reliable than AnimationTree Add2 blending. The AnimationPlayer
handles the blend transition natively via the `custom_blend` parameter.

### Mixamo animation naming convention
Mixamo "React From Front" means "I was hit from the front" (the animation shows
a backward recoil). Map hit direction directly to animation name — don't invert.

## GDScript export gotchas (learned in Step 0-1)

### Typed node exports don't resolve from hand-written .tscn
`@export var camera: Camera3D` stored as `camera = NodePath(...)` in a .tscn
file does not reliably resolve the NodePath into a node reference.
Workaround: use `get_viewport().get_camera_3d()` or `@export var path: NodePath`
with `get_node(path)` instead.

### node_paths attribute in .tscn
The `node_paths=PackedStringArray(...)` attribute on `[node]` entries is ONLY
for typed node reference exports (`@export var x: Node3D`). Do NOT use it for
`@export var path: NodePath` — it will resolve the path as empty string.

## Collision layers

Use this layout:
- Layer 1: Character controllers (CharacterBody3D)
- Layer 2: Environment (StaticBody3D, terrain)
- Layer 3: Props, dynamic objects
- Layer 4: Ragdoll physics bodies (RigidBody3D from dual-skeleton)
- Layer 5: PhysicalBone3D (partial ragdoll)

Ragdoll bodies (layer 4) should:
- Collide with: layer 2 (environment), layer 3 (props), layer 4 (self — inter-bone collision)
- NOT collide with: layer 1 (would conflict with CharacterBody3D)

## Performance budget

- Each ragdoll rig: ~16 RigidBody3D + ~15 Generic6DOFJoint3D = ~31 physics objects
- Spring resolver: 16 velocity calculations per physics frame per character
- With Jolt at 60Hz: 30-50 simultaneous passive ragdolls, 5-8 active ragdolls before physics > 4ms
- Main bottleneck: `PhysicsServer::flush_queries()`, not GDScript
- Profile with: Debugger → Monitors → Physics Process time
