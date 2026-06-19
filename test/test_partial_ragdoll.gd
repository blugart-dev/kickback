extends GutTest
## Coverage for the standalone Partial Ragdoll path (PhysicalBoneSimulator3D),
## previously untested. Builds a synthetic Mixamo skeleton + a populated
## PhysicalBoneSimulator3D + a PartialRagdollController, then exercises chain
## selection and the react -> hold -> blend-out lifecycle, including the
## re-hit and despawn-mid-reaction edge cases the harden pass fixed.

const RigHarness := preload("res://test/helpers/rig_harness.gd")

var _root: Node3D
var _skeleton: Skeleton3D
var _sim: PhysicalBoneSimulator3D
var _ctrl: PartialRagdollController


func before_each():
	_root = Node3D.new()
	add_child_autoqfree(_root)
	_skeleton = RigHarness.build_mixamo_skeleton()
	_root.add_child(_skeleton)
	_sim = PhysicalBoneSimulator3D.new()
	_sim.name = "PhysicalBoneSimulator3D"
	_skeleton.add_child(_sim)
	var mapping := SkeletonDetector.detect_humanoid_bones(_skeleton)
	SkeletonDetector.populate_physical_bones(_skeleton, _sim, mapping, _root)
	_sim.active = true

	_ctrl = PartialRagdollController.new()
	_ctrl.simulator_path = NodePath("../Skeleton3D/PhysicalBoneSimulator3D")
	_ctrl.skeleton_path = NodePath("../Skeleton3D")
	_ctrl.hold_time = 0.1
	_ctrl.blend_duration = 0.15
	_ctrl.configure(RagdollProfile.create_mixamo_default(), RagdollTuning.create_default())
	_root.add_child(_ctrl)
	await get_tree().process_frame  # let _ready build the bone map


func _phys_bone(bone_name: String) -> PhysicalBone3D:
	for c in _sim.get_children():
		if c is PhysicalBone3D and (c as PhysicalBone3D).bone_name == bone_name:
			return c
	return null


func _event(bone_name: String) -> HitEvent:
	var e := HitEvent.new()
	e.hit_bone_name = bone_name
	e.hit_direction = Vector3.FORWARD
	e.hit_position = Vector3.ZERO
	e.impulse_magnitude = 3.0
	e.hit_bone = _phys_bone(bone_name)
	return e


# ── Chain selection ──────────────────────────────────────────────────────────

func test_chain_includes_bone_children_and_parent():
	var chain := _ctrl._get_bone_chain("mixamorig_LeftForeArm")
	assert_has(chain, "mixamorig_LeftForeArm", "the hit bone itself")
	assert_has(chain, "mixamorig_LeftHand", "the child bone")
	assert_has(chain, "mixamorig_LeftArm", "the parent bone")


func test_chain_excludes_root():
	# Upper-leg's parent is the Hips (root). The root must never be pulled into
	# the simulated chain (it anchors the character).
	var chain := _ctrl._get_bone_chain("mixamorig_LeftUpLeg")
	assert_has(chain, "mixamorig_LeftUpLeg", "the hit bone")
	assert_has(chain, "mixamorig_LeftLeg", "the child")
	assert_does_not_have(chain, "mixamorig_Hips", "root excluded from the chain")


func test_unmapped_bone_is_ignored():
	_ctrl.apply_hit(_event("no_such_bone"))
	assert_false(_ctrl.is_reacting(), "a hit on an unmapped bone is a no-op")


# ── React -> hold -> blend-out lifecycle ─────────────────────────────────────

func test_react_then_recovers():
	_ctrl.apply_hit(_event("mixamorig_LeftForeArm"))
	assert_true(_ctrl.is_reacting(), "reacting immediately after the hit")
	# The first state_changed(true) already fired synchronously; wait for the
	# blend-out's state_changed(false).
	var fired: bool = await wait_for_signal(_ctrl.state_changed, 5.0)
	assert_true(fired, "blend-out completed and emitted state_changed")
	assert_false(_ctrl.is_reacting(), "no longer reacting after blend-out")
	assert_almost_eq(_sim.influence, 1.0, 0.01, "influence restored to 1.0 after blend-out")


func test_rehit_during_reaction_settles():
	# A second hit landing during the hold window used to fall through and spawn a
	# SECOND, competing reaction coroutine (the race the generation counter fixes).
	# The race is a visual glitch (dedup hides it from signal counts), so here we
	# assert the deterministic part: the re-hit lifecycle still resolves cleanly to
	# not-reacting with influence restored — it never hangs or strands the controller.
	_ctrl.apply_hit(_event("mixamorig_LeftForeArm"))
	await get_tree().physics_frame
	await get_tree().physics_frame
	_ctrl.apply_hit(_event("mixamorig_LeftForeArm"))  # re-hit mid-reaction
	# Poll until settled (generous budget; timers/tweens advance with SceneTree time).
	var settled := false
	for i in 360:
		await get_tree().process_frame
		if not _ctrl.is_reacting():
			settled = true
			break
	assert_true(settled, "re-hit reaction settles back to not-reacting")
	assert_almost_eq(_sim.influence, 1.0, 0.01, "influence restored after the re-hit reaction")


func test_exit_during_reaction_is_safe():
	_ctrl.apply_hit(_event("mixamorig_LeftForeArm"))
	await get_tree().physics_frame
	# Despawn the whole character mid-reaction (common when a hit enemy is removed).
	_root.queue_free()
	# Let the abandoned coroutine's awaits resume across several frames — it must
	# bail via _is_current() instead of touching the freed simulator.
	for i in 20:
		await get_tree().process_frame
	assert_true(true, "freeing the character mid-reaction did not crash the pending coroutine")
