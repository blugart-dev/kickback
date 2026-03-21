## Unit tests for RagdollTuning validation against RagdollProfile.
## Tests all dictionary key validation paths and threshold interactions.
extends Node


func _ready() -> void:
	print("=== test_tuning_validation.gd ===")
	var passed := 0
	var failed := 0

	var profile := RagdollProfile.create_mixamo_default()

	# ── Clean tuning validates with 0 warnings ───────────────────────────────
	var clean := RagdollTuning.create_default()
	var w := clean.validate_against_profile(profile)
	if _assert(w.size() == 0, "Clean default: 0 warnings"):
		passed += 1
	else:
		failed += 1
		for warning: String in w:
			print("    unexpected: %s" % warning)

	# ── Each dictionary catches bad keys ──────────────────────────────────────
	var dicts_to_test := [
		["strength_map", "strength_map"],
		["pin_strength_overrides", "pin_strength_overrides"],
		["ramp_delay", "ramp_delay"],
		["min_strength", "min_strength"],
	]
	for entry: Array in dicts_to_test:
		var prop_name: String = entry[0]
		var expected_prefix: String = entry[1]
		var t := RagdollTuning.create_default()
		t.get(prop_name)["FAKE_BONE_XYZ"] = 0.5
		var warnings := t.validate_against_profile(profile)
		if _assert(warnings.size() > 0, "%s: bad key caught" % prop_name):
			passed += 1
		else:
			failed += 1
		var found_prefix := false
		for warning_text: String in warnings:
			if expected_prefix in warning_text:
				found_prefix = true
		if _assert(found_prefix, "%s: warning mentions '%s'" % [prop_name, expected_prefix]):
			passed += 1
		else:
			failed += 1

	# ── protected_bones catches bad names ─────────────────────────────────────
	var t1 := RagdollTuning.create_default()
	t1.protected_bones = PackedStringArray(["Hips", "BadBone123"])
	var w1 := t1.validate_against_profile(profile)
	if _assert(w1.size() == 1, "protected_bones: 1 warning for 'BadBone123'"):
		passed += 1
	else:
		failed += 1

	# Valid protected bones pass
	var t2 := RagdollTuning.create_default()
	t2.protected_bones = PackedStringArray(["UpperLeg_L", "LowerLeg_L", "Foot_L"])
	var w2 := t2.validate_against_profile(profile)
	if _assert(w2.size() == 0, "protected_bones: valid names pass"):
		passed += 1
	else:
		failed += 1

	# ── core_bracing_bones catches bad names ──────────────────────────────────
	var t3 := RagdollTuning.create_default()
	t3.core_bracing_bones = PackedStringArray(["Hips", "Spine", "GhostBone"])
	var w3 := t3.validate_against_profile(profile)
	if _assert(w3.size() == 1, "core_bracing_bones: 1 warning for 'GhostBone'"):
		passed += 1
	else:
		failed += 1

	# ── Multiple errors accumulate ────────────────────────────────────────────
	var t4 := RagdollTuning.create_default()
	t4.strength_map["Bad1"] = 0.5
	t4.pin_strength_overrides["Bad2"] = 0.5
	t4.ramp_delay["Bad3"] = 0.1
	t4.protected_bones = PackedStringArray(["Bad4"])
	var w4 := t4.validate_against_profile(profile)
	if _assert(w4.size() == 4, "Multiple errors: 4 warnings (got %d)" % w4.size()):
		passed += 1
	else:
		failed += 1

	# ── Empty dictionaries are valid ──────────────────────────────────────────
	var t5 := RagdollTuning.create_default()
	t5.strength_map = {}
	t5.pin_strength_overrides = {}
	t5.ramp_delay = {}
	t5.min_strength = {}
	var w5 := t5.validate_against_profile(profile)
	if _assert(w5.size() == 0, "Empty dicts: 0 warnings"):
		passed += 1
	else:
		failed += 1

	# ── All default bone names are valid ──────────────────────────────────────
	var t6 := RagdollTuning.create_default()
	var valid_rig_names := []
	for bone_def: BoneDefinition in profile.bones:
		valid_rig_names.append(bone_def.rig_name)
	for key: String in t6.strength_map:
		if _assert(key in valid_rig_names, "strength_map key '%s' is valid" % key):
			passed += 1
		else:
			failed += 1

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
