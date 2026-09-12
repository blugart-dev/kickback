extends GutTest

# ── SpringResolver: gravity semantics + root-motion stripping ───────────────
# Drives the REAL resolver on a live rig (res://test/helpers/rig_harness.gd).
# Regressions from docs/AUDIT_2026-09-12.md §4 items 1 and 7.

const RigHarness := preload("res://test/helpers/rig_harness.gd")


func _tuning() -> RagdollTuning:
	var t := RagdollTuning.create_default()
	t.foot_ik_enabled = false
	t.stagger_sway_strength = 0.0
	return t


func _spawn(tuning: RagdollTuning):
	var h = RigHarness.new()
	add_child_autoqfree(h)
	h.setup(tuning, null, true)
	var ok: bool = await h.await_ready(40)
	assert_true(ok, "Kickback setup completed within frame budget")
	return h


# A bone at full strength has its gravity scaled to zero (the springs hold the
# pose); a limp bone falls at the tuning's gravity_scale — not half of it.
func test_limp_bone_falls_at_tuning_gravity_scale():
	var t := _tuning()
	t.gravity_scale = 1.0
	var h = await _spawn(t)
	await wait_physics_frames(2)
	var hips: RigidBody3D = h.get_body("Hips")
	assert_almost_eq(hips.gravity_scale, 0.0, 0.02, "full strength: no gravity")

	h.controller.trigger_ragdoll()
	await wait_physics_frames(2)
	assert_almost_eq(hips.gravity_scale, 1.0, 0.02,
		"strength 0: gravity_scale equals RagdollTuning.gravity_scale (was 0.5)")


func test_gravity_scale_knob_is_honoured():
	var t := _tuning()
	t.gravity_scale = 1.4
	var h = await _spawn(t)
	h.controller.trigger_ragdoll()
	await wait_physics_frames(2)
	for rig_name: String in RigHarness.RIG_NAMES:
		var body: RigidBody3D = h.get_body(rig_name)
		assert_almost_eq(body.gravity_scale, 1.4, 0.02, "%s limp gravity" % rig_name)


# Root-motion stripping removes the root bone's XZ from the root AND its
# descendants (a stripped root with displaced children leans the rig).
func test_root_motion_stripping_applies_to_descendants():
	var t := _tuning()
	t.strip_root_motion = true
	var h = await _spawn(t)
	var hips_idx: int = h.bone_idx("mixamorig_Hips")
	var spine_idx: int = h.bone_idx("mixamorig_Spine")
	var foot_idx: int = h.bone_idx("mixamorig_LeftFoot")
	var rest_spine: Transform3D = h.spring.get_animation_bone_global(spine_idx)
	var rest_foot: Transform3D = h.spring.get_animation_bone_global(foot_idx)

	# Author 1.5 m of horizontal root motion (and 0.1 m vertical, which is kept).
	h.skeleton.set_bone_pose_position(hips_idx, Vector3(1.5, 1.0, -1.5))
	var hips: Transform3D = h.spring.get_animation_bone_global(hips_idx)
	var spine: Transform3D = h.spring.get_animation_bone_global(spine_idx)
	var foot: Transform3D = h.spring.get_animation_bone_global(foot_idx)

	assert_almost_eq(hips.origin.x, 0.0, 0.0001, "root XZ stripped")
	assert_almost_eq(hips.origin.z, 0.0, 0.0001, "root XZ stripped")
	assert_almost_eq(hips.origin.y, 1.0, 0.0001, "root Y kept")
	assert_almost_eq(spine.origin.x, rest_spine.origin.x, 0.0001, "child X follows stripped root")
	assert_almost_eq(spine.origin.z, rest_spine.origin.z, 0.0001, "child Z follows stripped root")
	assert_almost_eq(foot.origin.x, rest_foot.origin.x, 0.0001, "deep descendant X stripped")
	assert_almost_eq(foot.origin.z, rest_foot.origin.z, 0.0001, "deep descendant Z stripped")


func test_root_motion_kept_when_stripping_disabled():
	var t := _tuning()
	t.strip_root_motion = false
	var h = await _spawn(t)
	var hips_idx: int = h.bone_idx("mixamorig_Hips")
	var foot_idx: int = h.bone_idx("mixamorig_LeftFoot")
	var rest_foot: Transform3D = h.spring.get_animation_bone_global(foot_idx)
	h.skeleton.set_bone_pose_position(hips_idx, Vector3(1.5, 0.9, -1.5))
	var hips: Transform3D = h.spring.get_animation_bone_global(hips_idx)
	var foot: Transform3D = h.spring.get_animation_bone_global(foot_idx)
	assert_almost_eq(hips.origin.x, 1.5, 0.0001)
	assert_almost_eq(foot.origin.x, rest_foot.origin.x + 1.5, 0.0001)
	assert_almost_eq(foot.origin.z, rest_foot.origin.z - 1.5, 0.0001)
