## Unit tests for resource factory methods and validation.
## Run this scene to verify ImpactProfile, RagdollProfile, and RagdollTuning.
extends Node


func _ready() -> void:
	print("=== test_resources.gd ===")
	var passed := 0
	var failed := 0

	# -- ImpactProfile factory methods --
	for method in ["create_bullet", "create_shotgun", "create_explosion", "create_melee", "create_arrow"]:
		var profile: ImpactProfile = ImpactProfile.call(method)
		if _assert(profile != null, "ImpactProfile.%s() returns non-null" % method):
			passed += 1
		else:
			failed += 1
		if _assert(profile.base_impulse > 0.0, "ImpactProfile.%s() has positive impulse" % method):
			passed += 1
		else:
			failed += 1
		if _assert(profile.strength_reduction > 0.0, "ImpactProfile.%s() has positive reduction" % method):
			passed += 1
		else:
			failed += 1

	# -- ImpactProfile preset values --
	var bullet := ImpactProfile.create_bullet()
	if _assert(bullet.base_impulse == 8.0, "Bullet impulse is 8.0"):
		passed += 1
	else:
		failed += 1
	if _assert(bullet.ragdoll_probability == 0.05, "Bullet ragdoll_probability is 0.05"):
		passed += 1
	else:
		failed += 1

	var explosion := ImpactProfile.create_explosion()
	if _assert(explosion.ragdoll_probability == 0.95, "Explosion ragdoll_probability is 0.95"):
		passed += 1
	else:
		failed += 1
	if _assert(explosion.strength_spread == 99, "Explosion spread is 99 (all bones)"):
		passed += 1
	else:
		failed += 1

	# -- RagdollProfile factory --
	var profile := RagdollProfile.create_mixamo_default()
	if _assert(profile != null, "RagdollProfile.create_mixamo_default() returns non-null"):
		passed += 1
	else:
		failed += 1
	if _assert(profile.bones.size() == 16, "Mixamo profile has 16 bones (got %d)" % profile.bones.size()):
		passed += 1
	else:
		failed += 1
	if _assert(profile.joints.size() == 15, "Mixamo profile has 15 joints (got %d)" % profile.joints.size()):
		passed += 1
	else:
		failed += 1

	# Verify bone names
	var bone_names := []
	for bone_def: BoneDefinition in profile.bones:
		bone_names.append(bone_def.rig_name)
	if _assert("Hips" in bone_names, "Profile contains Hips bone"):
		passed += 1
	else:
		failed += 1
	if _assert("Head" in bone_names, "Profile contains Head bone"):
		passed += 1
	else:
		failed += 1
	if _assert("Foot_L" in bone_names, "Profile contains Foot_L bone"):
		passed += 1
	else:
		failed += 1

	# -- RagdollTuning factory --
	var tuning := RagdollTuning.create_default()
	if _assert(tuning != null, "RagdollTuning.create_default() returns non-null"):
		passed += 1
	else:
		failed += 1
	if _assert(tuning.stagger_threshold == 0.70, "Default stagger_threshold is 0.70"):
		passed += 1
	else:
		failed += 1
	if _assert(tuning.stagger_duration == 1.8, "Default stagger_duration is 1.8"):
		passed += 1
	else:
		failed += 1
	if _assert(tuning.stagger_sway_strength == 300.0, "Default sway_strength is 300.0"):
		passed += 1
	else:
		failed += 1
	if _assert(tuning.resistance_counter_strength == 0.40, "Default resistance_counter_strength is 0.40"):
		passed += 1
	else:
		failed += 1

	# -- RagdollTuning validation --
	var warnings := tuning.validate_against_profile(profile)
	if _assert(warnings.size() == 0, "Default tuning validates against Mixamo profile (got %d warnings)" % warnings.size()):
		passed += 1
	else:
		failed += 1

	# Add a bad key and re-validate
	tuning.strength_map["FakeBone"] = 0.5
	var bad_warnings := tuning.validate_against_profile(profile)
	if _assert(bad_warnings.size() > 0, "Tuning with bad key produces validation warnings"):
		passed += 1
	else:
		failed += 1
	tuning.strength_map.erase("FakeBone")

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
