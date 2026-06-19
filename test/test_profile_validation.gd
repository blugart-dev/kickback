extends GutTest
## Coverage for RagdollProfile.validate_against_skeleton — the inspector's
## edit-time correctness gate. Uses the shared synthetic Mixamo skeleton built
## by the runtime harness so the canonical profile round-trips cleanly.

const RigHarness = preload("res://test/helpers/rig_harness.gd")

var _skeleton: Skeleton3D


func before_all():
	_skeleton = RigHarness.build_mixamo_skeleton()


func after_all():
	if is_instance_valid(_skeleton):
		_skeleton.free()


func test_mixamo_default_validates_clean():
	var p := RagdollProfile.create_mixamo_default()
	var w := p.validate_against_skeleton(_skeleton)
	assert_eq(w.size(), 0, "Mixamo default should validate clean against a Mixamo skeleton; got %s" % str(w))


func test_missing_skeleton_bone_warns():
	var p := RagdollProfile.create_mixamo_default()
	for bd: BoneDefinition in p.bones:
		if bd.rig_name == "Head":
			bd.skeleton_bone = "no_such_bone"
			break
	var w := p.validate_against_skeleton(_skeleton)
	var found := false
	for warning: String in w:
		if "no_such_bone" in warning:
			found = true
	assert_true(found, "A bone mapped to a missing skeleton bone should warn")


func test_joint_referencing_undefined_rig_warns():
	var p := RagdollProfile.create_mixamo_default()
	var jd := JointDefinition.new()
	jd.parent_rig = "Hips"
	jd.child_rig = "GhostRig"
	p.joints.append(jd)
	var w := p.validate_against_skeleton(_skeleton)
	var found := false
	for warning: String in w:
		if "GhostRig" in warning:
			found = true
	assert_true(found, "A joint referencing an undefined rig should warn")


func test_role_referencing_undefined_rig_warns():
	var p := RagdollProfile.create_mixamo_default()
	p.head_rig = "NotABone"
	var w := p.validate_against_skeleton(_skeleton)
	var found := false
	for warning: String in w:
		if "NotABone" in warning:
			found = true
	assert_true(found, "A semantic role pointing at an undefined rig should warn")


func test_missing_feet_warns_foot_ik():
	var p := RagdollProfile.new()
	var bd := BoneDefinition.new()
	bd.rig_name = "Hips"
	bd.skeleton_bone = "mixamorig_Hips"
	p.bones.append(bd)
	p.root_rig = "Hips"
	p.foot_rigs = PackedStringArray()
	p.left_leg_chain = PackedStringArray()
	p.right_leg_chain = PackedStringArray()
	var w := p.validate_against_skeleton(_skeleton)
	var foot_warnings := 0
	for warning: String in w:
		if "Foot IK" in warning:
			foot_warnings += 1
	assert_true(foot_warnings >= 1, "Missing feet should produce foot-IK role warnings")


func test_missing_intermediate_bone_warns():
	var p := RagdollProfile.create_mixamo_default()
	var entry := IntermediateBoneEntry.new()
	entry.skeleton_bone = "ghost_intermediate"
	entry.rig_body_a = "Spine"
	entry.rig_body_b = "Chest"
	p.intermediate_bones.append(entry)
	var w := p.validate_against_skeleton(_skeleton)
	var found := false
	for warning: String in w:
		if "ghost_intermediate" in warning:
			found = true
	assert_true(found, "A missing intermediate skeleton bone should warn")
