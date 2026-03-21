## Unit tests for state machine logic, math formulas, and threshold behavior.
## Tests the resource-level math without requiring physics simulation.
extends Node


func _ready() -> void:
	print("=== test_state_machine.gd ===")
	var passed := 0
	var failed := 0

	# ── Effective base strength formula ───────────────────────────────────────
	# effective = base * (1.0 - fatigue * fatigue_impact) * (1.0 - injury * injury_impact)
	var tuning := RagdollTuning.create_default()

	# No fatigue, no injury → full base
	var eff := _effective_base(0.65, 0.0, 0.0, tuning)
	if _assert(absf(eff - 0.65) < 0.001, "No fatigue/injury: effective = base (%.3f)" % eff):
		passed += 1
	else:
		failed += 1

	# Max fatigue → 50% reduction (fatigue_impact = 0.5)
	eff = _effective_base(0.65, 1.0, 0.0, tuning)
	if _assert(absf(eff - 0.325) < 0.001, "Max fatigue: effective = 0.325 (%.3f)" % eff):
		passed += 1
	else:
		failed += 1

	# Max injury → 40% reduction (injury_impact = 0.4)
	eff = _effective_base(0.65, 0.0, 1.0, tuning)
	if _assert(absf(eff - 0.39) < 0.001, "Max injury: effective = 0.39 (%.3f)" % eff):
		passed += 1
	else:
		failed += 1

	# Both max → 50% * 60% = 30% of base
	eff = _effective_base(0.65, 1.0, 1.0, tuning)
	if _assert(absf(eff - 0.195) < 0.001, "Max both: effective = 0.195 (%.3f)" % eff):
		passed += 1
	else:
		failed += 1

	# ── Hit streak multiplier ─────────────────────────────────────────────────
	# multiplier = 1.0 + (streak * hit_streak_multiplier)
	var mult := _streak_multiplier(0, tuning)
	if _assert(absf(mult - 1.0) < 0.001, "Streak 0: multiplier = 1.0"):
		passed += 1
	else:
		failed += 1

	mult = _streak_multiplier(1, tuning)
	if _assert(absf(mult - 1.3) < 0.001, "Streak 1: multiplier = 1.3 (%.3f)" % mult):
		passed += 1
	else:
		failed += 1

	mult = _streak_multiplier(5, tuning)
	if _assert(absf(mult - 2.5) < 0.001, "Streak 5: multiplier = 2.5 (%.3f)" % mult):
		passed += 1
	else:
		failed += 1

	# ── Movement instability bonus ────────────────────────────────────────────
	# At min_speed (1.0): no bonus. At max_speed (5.0): full bonus (0.3)
	var inst := _movement_instability(0.5, tuning)
	if _assert(absf(inst - 1.0) < 0.001, "Below min speed: no instability"):
		passed += 1
	else:
		failed += 1

	inst = _movement_instability(3.0, tuning)
	var expected := 1.0 + (2.0 / 4.0) * 0.3  # 1.15
	if _assert(absf(inst - expected) < 0.001, "Mid speed: instability = %.3f (got %.3f)" % [expected, inst]):
		passed += 1
	else:
		failed += 1

	inst = _movement_instability(5.0, tuning)
	if _assert(absf(inst - 1.3) < 0.001, "Max speed: instability = 1.3 (got %.3f)" % inst):
		passed += 1
	else:
		failed += 1

	inst = _movement_instability(10.0, tuning)
	if _assert(absf(inst - 1.3) < 0.001, "Over max speed: clamped to 1.3"):
		passed += 1
	else:
		failed += 1

	# ── Pain thresholds ───────────────────────────────────────────────────────
	if _assert(tuning.pain_stagger_threshold == 0.5, "Pain stagger threshold = 0.5"):
		passed += 1
	else:
		failed += 1
	if _assert(tuning.pain_ragdoll_threshold == 0.9, "Pain ragdoll threshold = 0.9"):
		passed += 1
	else:
		failed += 1
	if _assert(tuning.pain_stagger_threshold < tuning.pain_ragdoll_threshold,
		"Stagger threshold < ragdoll threshold"):
		passed += 1
	else:
		failed += 1

	# ── Balance thresholds are ordered correctly ──────────────────────────────
	if _assert(tuning.balance_recovery_threshold < tuning.balance_stagger_threshold,
		"Recovery < stagger threshold"):
		passed += 1
	else:
		failed += 1
	if _assert(tuning.balance_stagger_threshold < tuning.balance_ragdoll_threshold,
		"Stagger < ragdoll threshold"):
		passed += 1
	else:
		failed += 1

	# ── Fatigue accumulation formula ──────────────────────────────────────────
	# fatigue += reduction * fatigue_gain
	var fatigue := 0.0
	var reduction := 0.85  # Bullet
	fatigue = clampf(fatigue + reduction * tuning.fatigue_gain, 0.0, 1.0)
	if _assert(absf(fatigue - 0.1275) < 0.001, "1 bullet hit: fatigue = 0.1275 (%.4f)" % fatigue):
		passed += 1
	else:
		failed += 1

	# 10 bullet hits
	fatigue = 0.0
	for i in 10:
		fatigue = clampf(fatigue + reduction * tuning.fatigue_gain, 0.0, 1.0)
	if _assert(fatigue <= 1.0, "10 hits: fatigue clamped <= 1.0 (%.3f)" % fatigue):
		passed += 1
	else:
		failed += 1

	# ── Stagger floor with effective base ─────────────────────────────────────
	var floor_ratio := tuning.stagger_strength_floor  # 0.10
	var hips_base := 0.65
	var floor_val := hips_base * floor_ratio
	if _assert(absf(floor_val - 0.065) < 0.001, "Hips floor = 0.065 (%.3f)" % floor_val):
		passed += 1
	else:
		failed += 1

	# With fatigue, floor uses effective base
	var eff_base := hips_base * (1.0 - 1.0 * tuning.fatigue_impact)  # 0.325
	var fatigued_floor := eff_base * floor_ratio
	if _assert(absf(fatigued_floor - 0.0325) < 0.001, "Fatigued hips floor = 0.0325 (%.4f)" % fatigued_floor):
		passed += 1
	else:
		failed += 1

	# ── Injury system ─────────────────────────────────────────────────────────
	# Only significant hits cause injury (above injury_threshold)
	if _assert(tuning.injury_threshold == 0.3, "Injury threshold = 0.3"):
		passed += 1
	else:
		failed += 1

	# Injury reduces pin strength
	var pin := 0.85
	var injury := 0.5
	var injured_pin := pin * (1.0 - injury * tuning.injury_pin_impact)
	if _assert(absf(injured_pin - 0.5525) < 0.001, "Injured pin = 0.5525 (%.4f)" % injured_pin):
		passed += 1
	else:
		failed += 1

	# ── State enum values ─────────────────────────────────────────────────────
	if _assert(ActiveRagdollController.State.NORMAL == 0, "NORMAL = 0"):
		passed += 1
	else:
		failed += 1
	if _assert(ActiveRagdollController.State.STAGGER == 1, "STAGGER = 1"):
		passed += 1
	else:
		failed += 1
	if _assert(ActiveRagdollController.State.RAGDOLL == 2, "RAGDOLL = 2"):
		passed += 1
	else:
		failed += 1
	if _assert(ActiveRagdollController.State.GETTING_UP == 3, "GETTING_UP = 3"):
		passed += 1
	else:
		failed += 1
	if _assert(ActiveRagdollController.State.PERSISTENT == 4, "PERSISTENT = 4"):
		passed += 1
	else:
		failed += 1

	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	if failed > 0:
		print("FAIL")
	else:
		print("ALL TESTS PASSED")


# ── Helper: replicate _effective_base_strength formula ────────────────────────

func _effective_base(base: float, fatigue: float, injury: float, tuning: RagdollTuning) -> float:
	var fatigue_factor := 1.0 - fatigue * tuning.fatigue_impact
	var injury_factor := 1.0 - injury * tuning.injury_impact
	return base * fatigue_factor * injury_factor


func _streak_multiplier(streak: int, tuning: RagdollTuning) -> float:
	return 1.0 + float(streak) * tuning.hit_streak_multiplier


func _movement_instability(speed: float, tuning: RagdollTuning) -> float:
	if speed < tuning.movement_instability_min_speed:
		return 1.0
	var ratio := clampf(
		(speed - tuning.movement_instability_min_speed) /
		(tuning.movement_instability_max_speed - tuning.movement_instability_min_speed),
		0.0, 1.0)
	return 1.0 + ratio * tuning.movement_instability_bonus


func _assert(condition: bool, message: String) -> bool:
	if condition:
		print("  PASS: %s" % message)
	else:
		print("  FAIL: %s" % message)
	return condition
