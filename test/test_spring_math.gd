extends GutTest
## Unit coverage for SpringResolver's frame-rate-independence reparameterization
## (SpringResolver._fr_weight). The spring blends rigid-body velocities by a
## per-tick weight; these assert the weight is 60 Hz-anchored (unchanged at the
## reference rate) and that the resulting convergence is frame-rate independent.


func test_fr_weight_identity_at_60hz():
	# At the 60 Hz reference the weight is returned unchanged, so the existing
	# tuning (calibrated at 60 Hz) is preserved bit-for-bit.
	for w: float in [0.1, 0.25, 0.5, 0.65, 0.95]:
		assert_almost_eq(SpringResolver._fr_weight(w, 1.0 / 60.0), w, 0.0001,
			"weight %.2f is unchanged at 60 Hz" % w)


func test_fr_weight_framerate_independent_decay():
	# Over a fixed 1 s of wall-clock the fraction of error remaining must be the
	# same regardless of tick rate. remaining = (1 - weight)^ticks.
	var w := 0.5
	var rem_30 := pow(1.0 - SpringResolver._fr_weight(w, 1.0 / 30.0), 30.0)
	var rem_60 := pow(1.0 - SpringResolver._fr_weight(w, 1.0 / 60.0), 60.0)
	var rem_120 := pow(1.0 - SpringResolver._fr_weight(w, 1.0 / 120.0), 120.0)
	assert_almost_eq(rem_30, rem_60, 0.0001, "30 Hz converges like 60 Hz over 1 s")
	assert_almost_eq(rem_120, rem_60, 0.0001, "120 Hz converges like 60 Hz over 1 s")


func test_fr_weight_clamps_out_of_range():
	# Defensive: a weight >= 1 must not produce NaN (a negative base raised to a
	# fractional power). It clamps to a full snap.
	assert_almost_eq(SpringResolver._fr_weight(1.0, 1.0 / 120.0), 1.0, 0.0001,
		"weight 1.0 stays a full snap at any rate")
	assert_false(is_nan(SpringResolver._fr_weight(1.5, 1.0 / 120.0)),
		"out-of-range weight is clamped, not NaN")
