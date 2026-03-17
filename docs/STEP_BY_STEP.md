# Step-by-Step Implementation Plan

Do these in order. Each step builds on the previous. Each has a test scene and
concrete pass/fail criteria. Do NOT proceed to the next step until the current
one passes.

---

## Step 0 — Project setup + passive ragdoll ✅ COMPLETE

**Goal**: A character with working passive ragdoll. This validates skeleton,
collision shapes, and joint limits before adding any complexity.

**Status**: Complete. Key learnings:
- Auto-generated PhysicalBone3D joints use PIN type (no limits) — must change to CONE
- Collision shapes from auto-generation are too small — need manual sizing
- Self-collision (mask includes own layer) and damping are essential
- Typed node exports (`@export var x: Camera3D`) don't resolve from hand-written .tscn

**Tasks**:
- Initialize Godot project with Jolt physics enabled
- Create `addons/kickback/` plugin structure with `plugin.cfg`
- Import a humanoid character (Mixamo Y-Bot or similar) with idle + walk animations
- Set up Skeleton3D → PhysicalBoneSimulator3D → auto-generate PhysicalBone3D nodes
- Add a simple floor (StaticBody3D + plane)
- Write a test controller: press R to toggle ragdoll on/off
- Raycast weapon: click to cast ray, on hit apply impulse to the nearest PhysicalBone3D

**Test scene**: `test/test_passive_ragdoll.tscn`

**Pass criteria**:
- Character plays idle animation
- Press R → character goes fully limp, falls naturally
- Press R again → character snaps back to animation (this will look bad — that's fine)
- Click on character → impulse pushes the hit bone, body reacts
- Joints don't explode, limbs don't stretch, bones don't clip through floor
- Performance: steady 60fps with 1 character

**Tuning notes**:
- If joints explode: reduce mass differences between connected bones
- If limbs stretch: tighten joint angular limits
- If bones clip floor: check collision shapes extend beyond mesh, increase solver iterations (Project Settings → Jolt → Solver → Velocity Iterations: 8)
- If ragdoll feels too floppy: increase joint damping, add angular limits

---

## Step 1 — Partial ragdoll hit reactions ✅ COMPLETE

**Goal**: On hit, only the struck limb (and neighbors) go ragdoll briefly, then
blend back to animation. This is the highest value-to-effort feature.

**Status**: Complete. Key learnings:
- Weapon emits HitEvent, controller handles impulse AFTER simulation starts
- Bone chain: hit bone + recursive children + 1 parent (stop at Hips)
- Deferred start needs two physics frames: one to start sim, one before impulse
- CONE joints with per-bone swing/twist limits prevent unnatural bending
- Overlapping hits: kill active tween, stop sim, restart fresh

**Tasks**:
- Create `HitEvent` class: hit_position, hit_direction, hit_bone_name, impulse_magnitude
- On raycast hit: identify which PhysicalBone3D was struck
- Collect bone chain: hit bone + children + 1 parent (stop at hips)
- Call `simulator.physical_bones_start_simulation(bone_array)`
- Apply impulse at hit point: `bone.apply_impulse(direction * magnitude, local_offset)`
- Hold for 0.1-0.15s (let physics play out)
- Tween `simulator.influence` from 1.0 → 0.0 over 0.3-0.4s
- On complete: `stop_simulation()`, reset influence to 1.0
- Handle overlapping hits (cancel existing tween, restart)

**Test scene**: `test/test_partial_ragdoll.tscn`

**Pass criteria**:
- Shoot arm → arm swings back → smoothly returns to animation
- Shoot leg → leg buckles briefly → recovers
- Shoot torso → upper body lurches → recovers
- Character keeps walking/idling through the reaction (lower body unaffected when shooting arm)
- Two rapid hits on different limbs both react
- No visual pop or snap on blend-back

**Tuning notes**:
- If blend-back pops: increase blend duration (0.4 → 0.6s) or add ease-out curve
- If reaction is too subtle: increase impulse magnitude
- If whole body goes soft during blend-back (because `influence` is global): shorten blend duration to minimize the window, or accept it as a whole-body flinch

---

## Step 2 — Additive flinch animations

**Goal**: Directional flinch animations that layer on top of any current animation.
Used standalone for far targets, combined with partial ragdoll for mid-range.

**Tasks**:
- Import or create 4 directional flinch animations (front/back/left/right)
  - Mixamo "Hit Reaction" variants work as placeholders
  - Duration: 0.2-0.3s, upper body only
- Set up AnimationTree with locomotion state machine + additive flinch layer:
  - AnimationNodeAdd2 for flinch blending
  - AnimationNodeOneShot to trigger flinch
  - AnimationNodeBlendSpace1D or TransitionNode to select direction
- On hit: compute hit direction in character local space → map to quadrant → fire OneShot
- Flinch blend: set add_amount to 1.0 instantly, tween to 0.0 over 0.2s
- Use zero crossfade on OneShot (instant onset sells the hit)
- Optional: 1-2 frame hitstop (pause AnimationTree playback, not Engine.time_scale)

**Test scene**: `test/test_flinch.tscn`

**Pass criteria**:
- Shoot from front → character recoils backward
- Shoot from behind → character lurches forward
- Shoot from sides → appropriate lateral flinch
- Flinch layers on top of walk/idle without interrupting it
- Rapid multiple hits produce stacking flinches (second doesn't cancel first)
- Combined with Step 1: partial ragdoll + flinch fire together for close hits

**Tuning notes**:
- If flinch looks weak: increase add_amount above 1.0 (1.2-1.5), or add hitstop
- If flinch interrupts locomotion: verify it's additive, not replacing the base layer
- Four anims is minimum. Eight (add head, gut, shoulder_l, shoulder_r) is better.

---

## Step 3 — Dual-skeleton physics rig

**Goal**: Build the RigidBody3D skeleton that will become the active ragdoll.
No spring resolver yet — just verify the physics rig works as a passive ragdoll.

**Tasks**:
- Create the physics rig hierarchy (see REFERENCE.md for bone list):
  - One RigidBody3D per major bone (~16 bodies)
  - Connected by Generic6DOFJoint3D with angular limits
  - CapsuleShape3D for limbs, BoxShape3D for torso, SphereShape3D for head
- Place on collision layer 4 (not layer 1 where CharacterBody3D lives)
- Make all RigidBody3Ds invisible (no mesh attached)
- Write sync script: each _process, read RigidBody3D global transforms → write to
  the visible Skeleton3D via `set_bone_global_pose_override(bone_idx, transform, 1.0, true)`
- The visible mesh reads from the visible Skeleton3D, so it follows the physics rig
- Add enable/disable toggle to switch between animation-driven and physics-driven

**Test scene**: `test/test_physics_rig.tscn`

**Pass criteria**:
- With physics disabled: character plays animation normally (sync script off)
- With physics enabled, no springs: bodies fall, ragdoll naturally, mesh follows
- Joint limits prevent impossible poses (no backwards knees, no 360° shoulders)
- Push a physics ball into the ragdoll → limbs react, joints hold
- No joint explosions, no NaN positions, no bodies drifting apart
- Rig matches the visual skeleton proportions (no obvious mismatch)

**Tuning notes**:
- If joints explode on enable: defer `start_simulation` by one frame, or zero out velocities first
- If bodies drift apart: increase solver iterations or check joint anchor positions
- If proportions look wrong: debug-draw the collision shapes (enable Debug → Visible Collision Shapes)
- Mass distribution: hips 15kg, chest 12kg, head 5kg, upper arm 3kg, lower arm 2kg, hand 1kg, upper leg 8kg, lower leg 4kg, foot 2kg. Adjust to taste.

---

## Step 4 — Spring resolver

**Goal**: The physics rig actively tracks the animation skeleton. This is the
core active ragdoll system.

**Tasks**:
- Write `SpringResolver` script (see REFERENCE.md for the math)
- For each RigidBody3D body, every _physics_process:
  1. Read target rotation from animation skeleton bone pose
  2. Compute rotation error (quaternion difference → axis-angle)
  3. Compute target angular velocity to close the gap in one frame
  4. Lerp current angular_velocity toward target at `strength` rate
- Per-bone strength values: core 0.4, upper limbs 0.25, head 0.15, hands 0.1, legs 0.35
- Position pinning on hips only: lerp linear_velocity toward position error
- Hip pin strength: 0.3 (enough to prevent drift, not enough to float)

**Test scene**: `test/test_active_ragdoll.tscn`

**Pass criteria**:
- Character plays idle with physics rig active — body roughly holds pose
- Character walks — physics rig follows, slight natural wobble is expected and desired
- Push a ball into the character → body deforms → recovers to animation pose
- Gravity works: character doesn't float (if it does, reduce hip pin strength)
- Character doesn't collapse (if it does, increase core strength)
- Switching between pure animation and active ragdoll is smooth

**Tuning notes**:
- Strength 0.3 is the magic starting point (V-Sekai, Jolt creator recommendation)
- If character oscillates: reduce strength or add more damping (lower lerp factor)
- If character is too stiff (ignores physics): reduce strength
- If character is too floppy (collapses): increase strength on core/legs
- Start with idle only. Walk introduces foot-ground interaction that may need separate tuning.

---

## Step 5 — Hit reactions on the active ragdoll

**Goal**: Hits apply impulse + reduce spring strength = physics wins temporarily = Euphoria moment.

**Tasks**:
- On raycast hit: identify which RigidBody3D was struck
- Apply impulse directly: `body.apply_impulse(direction * magnitude, local_hit_offset)`
- Reduce `strength` on hit body and neighbors:
  - Hit bone: multiply strength by (1.0 - weapon_profile.strength_reduction)
  - Neighbors (parent + children, 1-2 levels): apply with distance falloff
- Recover strength: in _physics_process, `strength = move_toward(strength, base_strength, recovery_rate * delta)`
- Recovery rate: ~1.0/second (full recovery in ~0.5-1.0s for a bullet)
- For lethal hits: set all strengths to 0.0 (pure ragdoll)
- Combine with additive flinch from Step 2 for extra visual punch

**Test scene**: `test/test_hit_reactions.tscn`

**Pass criteria**:
- Bullet to arm: arm swings, body compensates slightly, arm recovers
- Bullet to leg: leg buckles, character stumbles, recovers
- Bullet to head: head snaps, dramatic visible reaction
- Shotgun: wider spread, more of the body reacts
- Multiple rapid hits accumulate (strength drops further before recovery)
- Lethal hit: full ragdoll, no recovery
- Reactions look different depending on hit location and direction
- Reactions look different from the passive ragdoll (there's active resistance/compensation)

---

## Step 6 — Weapon profiles

**Goal**: Different weapons produce distinctly different reactions.

**Tasks**:
- Create `WeaponProfile` Resource class with exported properties
- Create .tres files for each weapon type (see REFERENCE.md for values)
- Wire weapon selection into test scene (number keys to switch)
- Implement bone spread (impulse applied to neighbors with falloff)
- Implement sustained force for melee (apply_force over N frames instead of single impulse)
- Implement upward bias for explosions
- Implement ragdoll probability (random chance of full ragdoll per hit)

**Test scene**: `test/test_weapons.tscn`

**Pass criteria**:
- Bullet: sharp, localized, fast recovery
- Shotgun: wider impact zone, character staggers
- Explosion: launches character, strong upward component, almost always full ragdoll
- Melee: sustained push, character gets shoved
- Arrow: similar to bullet but slightly more impulse, very localized
- Each weapon feels distinctly different from the others

---

## Step 7 — Recovery / get-up system

**Goal**: Characters that go full ragdoll can get back up.

**Tasks**:
- Detect settling: all RigidBody3D angular + linear velocities below threshold for 0.8s
- On settle:
  1. Capture all body transforms
  2. Detect orientation: chest body's Y axis dot world UP → face up or face down
  3. Select get-up animation (face_up or face_down)
  4. Match character root position to ragdoll hip position (raycast to ground)
  5. Match Y rotation to head-to-feet direction
- Ramp all spring strengths from 0.0 → base values over 0.5-1.0s
  while the get-up animation plays as the spring target
- The bodies physically drive themselves into the get-up pose (active recovery)
- When max bone rotation error < 0.1 rad and strength > 0.8: transfer authority back to animation skeleton
- Safety timeout: force recovery after 5s regardless of settling

**Test scene**: `test/test_recovery.tscn`

**Pass criteria**:
- Full ragdoll → character settles → physically gets up → returns to idle
- Face-up and face-down orientations produce different get-up sequences
- No visual pop or snap during transition
- Works on slopes and uneven ground (raycast handles this)
- Interrupted recovery (hit during get-up) sends character back to ragdoll

---

## Step 8 — LOD system + integration

**Goal**: Wire everything together with distance-based fidelity.

**Tasks**:
- Create LOD manager: distance to camera → tier selection
  - < 10m: active ragdoll (Steps 4-5)
  - 10-25m: partial ragdoll (Step 1)
  - 25-50m: additive flinch (Step 2)
  - > 50m: canned animation only
- Cap simultaneous active ragdolls at 3-5 (configurable)
- Create main `KickbackCharacter` coordinator node that wires everything:
  - Receives hit events from game combat system
  - Routes to appropriate tier handler
  - Manages state transitions (normal → reacting → ragdoll → recovering → normal)
- Create `KickbackManager` autoload for global tracking (active ragdoll count, LOD distances)
- Write final integration test with multiple characters

**Test scene**: `test/test_integration.tscn` (20+ characters at various distances)

**Pass criteria**:
- Close characters: full active ragdoll reactions
- Mid characters: partial ragdoll reactions
- Far characters: flinch animation only
- Very far: canned animation only
- Shooting rapidly across many characters: no performance drop below 55fps
- Tier transitions are invisible (character crossing distance threshold doesn't pop)
- Active ragdoll count cap is enforced (6th character falls back to partial ragdoll)
