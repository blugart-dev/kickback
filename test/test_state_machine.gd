extends GutTest


func _effective_base(base: float, fatigue: float, injury: float, tuning: RagdollTuning) -> float:
	return base * (1.0 - fatigue * tuning.fatigue_impact) * (1.0 - injury * tuning.injury_impact)


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


# ── Effective base strength formula ───────────────────────────────────────────

func test_effective_base_no_debuffs():
	var t := RagdollTuning.create_default()
	assert_almost_eq(_effective_base(0.65, 0.0, 0.0, t), 0.65, 0.001)


func test_effective_base_max_fatigue():
	var t := RagdollTuning.create_default()
	assert_almost_eq(_effective_base(0.65, 1.0, 0.0, t), 0.325, 0.001)


func test_effective_base_max_injury():
	var t := RagdollTuning.create_default()
	assert_almost_eq(_effective_base(0.65, 0.0, 1.0, t), 0.39, 0.001)


func test_effective_base_both_max():
	var t := RagdollTuning.create_default()
	assert_almost_eq(_effective_base(0.65, 1.0, 1.0, t), 0.195, 0.001)


# ── Hit streak multiplier ────────────────────────────────────────────────────

func test_streak_zero():
	var t := RagdollTuning.create_default()
	assert_almost_eq(_streak_multiplier(0, t), 1.0, 0.001)


func test_streak_one():
	var t := RagdollTuning.create_default()
	assert_almost_eq(_streak_multiplier(1, t), 1.3, 0.001)


func test_streak_five():
	var t := RagdollTuning.create_default()
	assert_almost_eq(_streak_multiplier(5, t), 2.5, 0.001)


# ── Movement instability ─────────────────────────────────────────────────────

func test_instability_below_min_speed():
	var t := RagdollTuning.create_default()
	assert_almost_eq(_movement_instability(0.5, t), 1.0, 0.001)


func test_instability_mid_speed():
	var t := RagdollTuning.create_default()
	assert_almost_eq(_movement_instability(3.0, t), 1.15, 0.001)


func test_instability_max_speed():
	var t := RagdollTuning.create_default()
	assert_almost_eq(_movement_instability(5.0, t), 1.3, 0.001)


func test_instability_over_max_clamped():
	var t := RagdollTuning.create_default()
	assert_almost_eq(_movement_instability(10.0, t), 1.3, 0.001)


# ── Pain thresholds ──────────────────────────────────────────────────────────

func test_pain_thresholds_ordered():
	var t := RagdollTuning.create_default()
	assert_eq(t.pain_stagger_threshold, 0.5)
	assert_eq(t.pain_ragdoll_threshold, 0.9)
	assert_true(t.pain_stagger_threshold < t.pain_ragdoll_threshold)


# ── Balance thresholds ────────────────────────────────────────────────────────

func test_balance_thresholds_ordered():
	var t := RagdollTuning.create_default()
	assert_true(t.balance_recovery_threshold < t.balance_stagger_threshold)
	assert_true(t.balance_stagger_threshold < t.balance_ragdoll_threshold)


# ── Fatigue accumulation ──────────────────────────────────────────────────────

func test_single_hit_fatigue():
	var t := RagdollTuning.create_default()
	var fatigue := clampf(0.0 + 0.85 * t.fatigue_gain, 0.0, 1.0)
	assert_almost_eq(fatigue, 0.1275, 0.001)


func test_fatigue_clamped_after_many_hits():
	var t := RagdollTuning.create_default()
	var fatigue := 0.0
	for i in 10:
		fatigue = clampf(fatigue + 0.85 * t.fatigue_gain, 0.0, 1.0)
	assert_true(fatigue <= 1.0)


# ── Stagger floor ────────────────────────────────────────────────────────────

func test_hips_floor_value():
	var t := RagdollTuning.create_default()
	assert_almost_eq(0.65 * t.stagger_strength_floor, 0.065, 0.001)


func test_fatigued_floor():
	var t := RagdollTuning.create_default()
	var eff := 0.65 * (1.0 - 1.0 * t.fatigue_impact)
	assert_almost_eq(eff * t.stagger_strength_floor, 0.0325, 0.001)


# ── Injury pin impact ────────────────────────────────────────────────────────

func test_injured_pin():
	var t := RagdollTuning.create_default()
	var pin := 0.85 * (1.0 - 0.5 * t.injury_pin_impact)
	assert_almost_eq(pin, 0.5525, 0.001)


func test_injury_threshold():
	var t := RagdollTuning.create_default()
	assert_eq(t.injury_threshold, 0.3)


# ── State enum values ─────────────────────────────────────────────────────────

func test_state_enum():
	assert_eq(ActiveRagdollController.State.NORMAL, 0)
	assert_eq(ActiveRagdollController.State.STAGGER, 1)
	assert_eq(ActiveRagdollController.State.RAGDOLL, 2)
	assert_eq(ActiveRagdollController.State.GETTING_UP, 3)
	assert_eq(ActiveRagdollController.State.PERSISTENT, 4)
