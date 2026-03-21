## Unit tests for resource factory methods, sub-classes, and validation.
## Run this scene to verify ImpactProfile, RagdollProfile, RagdollTuning,
## BoneDefinition, JointDefinition, and IntermediateBoneEntry.
extends Node


func _ready() -> void:
	print("=== test_resources.gd ===")
	var passed := 0
	var failed := 0

	# ── ImpactProfile factory methods ─────────────────────────────────────────
	var profiles: Array[ImpactProfile] = [
		ImpactProfile.create_bullet(),
		ImpactProfile.create_shotgun(),
		ImpactProfile.create_explosion(),
		ImpactProfile.create_melee(),
		ImpactProfile.create_arrow(),
	]
	var profile_names := ["bullet", "shotgun", "explosion", "melee", "arrow"]
	for i in profiles.size():
		var p := profiles[i]
		var n := profile_names[i]
		if _assert(p != null, "ImpactProfile.create_%s() non-null" % n):
			passed += 1
		else:
			failed += 1
		if _assert(p.base_impulse > 0.0, "ImpactProfile.create_%s() positive impulse" % n):
			passed += 1
		else:
			failed += 1
		if _assert(p.strength_reduction > 0.0, "ImpactProfile.create_%s() positive reduction" % n):
			passed += 1
		else:
			failed += 1
		if _assert(p.recovery_rate > 0.0, "ImpactProfile.create_%s() positive recovery" % n):
			passed += 1
		else:
			failed += 1

	# ── ImpactProfile preset values ───────────────────────────────────────────
	var bullet := ImpactProfile.create_bullet()
	if _assert(bullet.base_impulse == 8.0, "Bullet impulse = 8.0"):
		passed += 1
	else:
		failed += 1
	if _assert(bullet.ragdoll_probability == 0.05, "Bullet ragdoll_prob = 0.05"):
		passed += 1
	else:
		failed += 1
	if _assert(bullet.strength_spread == 1, "Bullet spread = 1"):
		passed += 1
	else:
		failed += 1

	var shotgun := ImpactProfile.create_shotgun()
	if _assert(shotgun.ragdoll_probability == 0.40, "Shotgun ragdoll_prob = 0.40"):
		passed += 1
	else:
		failed += 1
	if _assert(shotgun.strength_spread == 3, "Shotgun spread = 3"):
		passed += 1
	else:
		failed += 1

	var explosion := ImpactProfile.create_explosion()
	if _assert(explosion.ragdoll_probability == 0.95, "Explosion ragdoll_prob = 0.95"):
		passed += 1
	else:
		failed += 1
	if _assert(explosion.strength_spread == 99, "Explosion spread = 99"):
		passed += 1
	else:
		failed += 1
	if _assert(explosion.upward_bias > 0.0, "Explosion has upward bias"):
		passed += 1
	else:
		failed += 1

	var melee := ImpactProfile.create_melee()
	if _assert(melee.impulse_transfer_ratio == 0.60, "Melee transfer = 0.60"):
		passed += 1
	else:
		failed += 1

	var arrow := ImpactProfile.create_arrow()
	if _assert(arrow.base_impulse == 12.0, "Arrow impulse = 12.0"):
		passed += 1
	else:
		failed += 1

	# ── RagdollProfile factory ────────────────────────────────────────────────
	var profile := RagdollProfile.create_mixamo_default()
	if _assert(profile != null, "RagdollProfile.create_mixamo_default() non-null"):
		passed += 1
	else:
		failed += 1
	if _assert(profile.bones.size() == 16, "Mixamo: 16 bones (got %d)" % profile.bones.size()):
		passed += 1
	else:
		failed += 1
	if _assert(profile.joints.size() == 15, "Mixamo: 15 joints (got %d)" % profile.joints.size()):
		passed += 1
	else:
		failed += 1
	if _assert(profile.root_bone == "Hips", "Mixamo: root_bone = 'Hips'"):
		passed += 1
	else:
		failed += 1
	if _assert(profile.intermediate_bones.size() > 0, "Mixamo: has intermediate bones"):
		passed += 1
	else:
		failed += 1

	# ── BoneDefinition ────────────────────────────────────────────────────────
	var bone_names := []
	for bone_def: BoneDefinition in profile.bones:
		bone_names.append(bone_def.rig_name)
		if bone_def.rig_name == "Hips":
			if _assert(bone_def.mass == 15.0, "Hips mass = 15.0 (got %.1f)" % bone_def.mass):
				passed += 1
			else:
				failed += 1
			if _assert(bone_def.skeleton_bone_name != "", "Hips has skeleton_bone_name"):
				passed += 1
			else:
				failed += 1
		elif bone_def.rig_name == "Head":
			if _assert(bone_def.mass == 5.0, "Head mass = 5.0"):
				passed += 1
			else:
				failed += 1
	if _assert("Hips" in bone_names, "BoneDefinition: Hips present"):
		passed += 1
	else:
		failed += 1
	if _assert("Foot_L" in bone_names, "BoneDefinition: Foot_L present"):
		passed += 1
	else:
		failed += 1
	if _assert("Hand_R" in bone_names, "BoneDefinition: Hand_R present"):
		passed += 1
	else:
		failed += 1

	# ── JointDefinition ───────────────────────────────────────────────────────
	var joint_pairs := []
	for joint_def: JointDefinition in profile.joints:
		joint_pairs.append("%s→%s" % [joint_def.parent_rig_name, joint_def.child_rig_name])
	if _assert("Hips→Spine" in joint_pairs, "JointDefinition: Hips→Spine exists"):
		passed += 1
	else:
		failed += 1
	if _assert("Chest→Head" in joint_pairs, "JointDefinition: Chest→Head exists"):
		passed += 1
	else:
		failed += 1
	if _assert("Chest→UpperArm_L" in joint_pairs, "JointDefinition: Chest→UpperArm_L exists"):
		passed += 1
	else:
		failed += 1

	# Verify angular limits are non-zero
	for joint_def: JointDefinition in profile.joints:
		if joint_def.parent_rig_name == "Hips" and joint_def.child_rig_name == "Spine":
			if _assert(joint_def.angular_limit_x > 0.0, "Hips→Spine: X limit > 0"):
				passed += 1
			else:
				failed += 1
			break

	# ── IntermediateBoneEntry ─────────────────────────────────────────────────
	var inter := profile.intermediate_bones[0]
	if _assert(inter is IntermediateBoneEntry, "First intermediate is IntermediateBoneEntry"):
		passed += 1
	else:
		failed += 1
	if _assert(inter.skeleton_bone_name != "", "Intermediate has skeleton_bone_name"):
		passed += 1
	else:
		failed += 1
	if _assert(inter.body_a != "", "Intermediate has body_a"):
		passed += 1
	else:
		failed += 1
	if _assert(inter.body_b != "", "Intermediate has body_b"):
		passed += 1
	else:
		failed += 1

	# ── RagdollTuning factory & defaults ──────────────────────────────────────
	var tuning := RagdollTuning.create_default()
	if _assert(tuning != null, "RagdollTuning.create_default() non-null"):
		passed += 1
	else:
		failed += 1
	if _assert(tuning.stagger_threshold == 0.70, "stagger_threshold = 0.70"):
		passed += 1
	else:
		failed += 1
	if _assert(tuning.stagger_duration == 1.8, "stagger_duration = 1.8"):
		passed += 1
	else:
		failed += 1
	if _assert(tuning.stagger_strength_floor == 0.10, "stagger_strength_floor = 0.10"):
		passed += 1
	else:
		failed += 1
	if _assert(tuning.stagger_sway_strength == 300.0, "stagger_sway_strength = 300.0"):
		passed += 1
	else:
		failed += 1
	if _assert(tuning.resistance_counter_strength == 0.40, "resistance_counter_strength = 0.40"):
		passed += 1
	else:
		failed += 1
	if _assert(tuning.resistance_leg_brace == 0.35, "resistance_leg_brace = 0.35"):
		passed += 1
	else:
		failed += 1
	if _assert(tuning.stagger_recovery_rate == 0.03, "stagger_recovery_rate = 0.03"):
		passed += 1
	else:
		failed += 1
	if _assert(tuning.stagger_sway_drift == 0.4, "stagger_sway_drift = 0.4"):
		passed += 1
	else:
		failed += 1
	if _assert(tuning.stagger_sway_twist == 0.15, "stagger_sway_twist = 0.15"):
		passed += 1
	else:
		failed += 1

	# ── RagdollTuning validation ──────────────────────────────────────────────
	var warnings := tuning.validate_against_profile(profile)
	if _assert(warnings.size() == 0, "Default tuning validates clean (%d warnings)" % warnings.size()):
		passed += 1
	else:
		failed += 1
		for w: String in warnings:
			print("    warning: %s" % w)

	# Bad key in strength_map
	tuning.strength_map["FakeBone"] = 0.5
	var w1 := tuning.validate_against_profile(profile)
	if _assert(w1.size() > 0, "Bad strength_map key caught"):
		passed += 1
	else:
		failed += 1
	tuning.strength_map.erase("FakeBone")

	# Bad key in pin_strength_overrides
	tuning.pin_strength_overrides["Ghost"] = 0.5
	var w2 := tuning.validate_against_profile(profile)
	if _assert(w2.size() > 0, "Bad pin_strength key caught"):
		passed += 1
	else:
		failed += 1
	tuning.pin_strength_overrides.erase("Ghost")

	# Bad key in ramp_delay
	tuning.ramp_delay["Phantom"] = 0.1
	var w3 := tuning.validate_against_profile(profile)
	if _assert(w3.size() > 0, "Bad ramp_delay key caught"):
		passed += 1
	else:
		failed += 1
	tuning.ramp_delay.erase("Phantom")

	# Bad key in min_strength
	tuning.min_strength["Bogus"] = 0.05
	var w4 := tuning.validate_against_profile(profile)
	if _assert(w4.size() > 0, "Bad min_strength key caught"):
		passed += 1
	else:
		failed += 1
	tuning.min_strength.erase("Bogus")

	# Bad protected_bones
	tuning.protected_bones = PackedStringArray(["Invisible"])
	var w5 := tuning.validate_against_profile(profile)
	if _assert(w5.size() > 0, "Bad protected_bones caught"):
		passed += 1
	else:
		failed += 1
	tuning.protected_bones = PackedStringArray()

	# Bad core_bracing_bones
	tuning.core_bracing_bones = PackedStringArray(["Nonexistent"])
	var w6 := tuning.validate_against_profile(profile)
	if _assert(w6.size() > 0, "Bad core_bracing_bones caught"):
		passed += 1
	else:
		failed += 1
	tuning.core_bracing_bones = PackedStringArray(["Hips", "Spine", "Chest"])

	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	if failed > 0:
		print("FAIL")
	else:
		print("ALL TESTS PASSED")


func _assert(condition: bool, message: String) -> bool:
	if condition:
		print("  PASS: %s" % message)
	else:
		print("  FAIL: %s" % message)
	return condition
