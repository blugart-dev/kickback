extends GutTest

# ── Budget hard cap ─────────────────────────────────────────────────────────
# Verifies KickbackManager's hard cap: spontaneous hit/balance ragdolls are
# downgraded to a stagger when no slot is free, while explicit trigger_ragdoll()
# and set_persistent() (death/knockdown) bypass the cap. Drives the real
# controller + manager on a live rig via res://test/helpers/rig_harness.gd.

const RigHarness := preload("res://test/helpers/rig_harness.gd")
const KickbackManager := preload("res://addons/kickback/kickback_manager.gd")


func _fast_tuning() -> RagdollTuning:
	var t := RagdollTuning.create_default()
	t.foot_ik_enabled = false
	t.ragdoll_force_recovery_time = 0.4
	t.recovery_duration = 0.4
	t.safety_timeout = 0.6
	t.settle_duration = 0.15
	return t


func _spawn(tuning: RagdollTuning):
	var h = RigHarness.new()
	add_child_autoqfree(h)
	h.setup(tuning, null, true)
	var ok: bool = await h.await_ready(40)
	assert_true(ok, "Kickback setup completed within frame budget")
	return h


# Adds a budget manager to the tree (it joins the "kickback_manager" group on
# enter, which is how the controller discovers it).
func _add_manager(max_slots: int):
	var m = KickbackManager.new()
	m.max_active_ragdolls = max_slots
	add_child_autoqfree(m)
	return m


# A hit that deterministically WANTS a full ragdoll (probability 1.0), so the
# only variable is whether the budget grants the slot.
func _ragdoll_impact() -> ImpactProfile:
	var p := ImpactProfile.new()
	p.base_impulse = 5.0
	p.impulse_transfer_ratio = 0.3
	p.ragdoll_probability = 1.0
	p.strength_reduction = 0.5
	p.strength_spread = 0
	p.recovery_rate = 1.0
	return p


func _hit(h) -> void:
	var chest: RigidBody3D = h.get_body("Chest")
	h.controller.apply_hit(chest, Vector3.FORWARD, chest.global_position, _ragdoll_impact())


# ── Hard cap on spontaneous hit ragdolls ────────────────────────────────────

func test_over_budget_hit_downgrades_to_stagger():
	var h = await _spawn(_fast_tuning())
	_add_manager(0)  # no slots available
	_hit(h)
	assert_eq(h.controller.get_state(), ActiveRagdollController.State.STAGGER,
		"hard cap downgrades a would-be ragdoll to a stagger")


func test_within_budget_hit_ragdolls_and_counts():
	var h = await _spawn(_fast_tuning())
	var mgr = _add_manager(5)
	_hit(h)
	assert_eq(h.controller.get_state(), ActiveRagdollController.State.RAGDOLL,
		"a granted slot allows the full ragdoll")
	assert_eq(mgr.get_active_ragdoll_count(), 1, "manager counts the active ragdoll")


func test_recovery_releases_budget_slot():
	var h = await _spawn(_fast_tuning())
	var mgr = _add_manager(5)
	_hit(h)
	assert_eq(mgr.get_active_ragdoll_count(), 1, "slot held during ragdoll")
	var recovered: bool = await wait_for_signal(h.controller.recovery_finished, 8.0)
	assert_true(recovered, "ragdoll recovered")
	assert_eq(mgr.get_active_ragdoll_count(), 0, "recovery released the slot")


# ── Explicit / death ragdolls bypass the cap ────────────────────────────────

func test_explicit_trigger_ragdoll_bypasses_cap():
	var h = await _spawn(_fast_tuning())
	_add_manager(0)  # no slots
	h.controller.trigger_ragdoll()
	assert_eq(h.controller.get_state(), ActiveRagdollController.State.RAGDOLL,
		"explicit trigger_ragdoll ignores the budget")


func test_persistent_bypasses_cap():
	var h = await _spawn(_fast_tuning())
	_add_manager(0)  # no slots
	h.controller.set_persistent(true)
	assert_eq(h.controller.get_state(), ActiveRagdollController.State.PERSISTENT,
		"set_persistent (death/knockdown) ignores the budget")
