extends GutTest
## Coverage for the optional PhysicsCollisionMonitor — its connect/disconnect
## lifecycle, including the _exit_tree signal-leak fix (it must drop its
## body_entered connections and reset contact_monitor when removed, so it does
## not leak connections to rig bodies that outlive it).

const RigHarness := preload("res://test/helpers/rig_harness.gd")


func _spawn():
	var h = RigHarness.new()
	add_child_autoqfree(h)
	var t := RagdollTuning.create_default()
	t.foot_ik_enabled = false
	h.setup(t, null, true)
	var ok: bool = await h.await_ready(40)
	assert_true(ok, "Kickback setup completed")
	return h


func test_monitor_connects_and_disconnects_cleanly():
	var h = await _spawn()
	var foot: RigidBody3D = h.get_body("Foot_L")
	var base_conns := foot.body_entered.get_connections().size()

	var mon := PhysicsCollisionMonitor.new()
	h.add_child(mon)  # sibling of KickbackCharacter — it auto-discovers the rig
	await get_tree().process_frame  # let _ready + _connect_to_bodies run

	assert_true(foot.contact_monitor, "monitor enables contact_monitor on rig bodies")
	assert_gt(foot.body_entered.get_connections().size(), base_conns,
		"monitor added a body_entered connection to the rig bodies")

	mon.free()
	await get_tree().process_frame

	assert_false(foot.contact_monitor, "_exit_tree restores contact_monitor = false")
	assert_eq(foot.body_entered.get_connections().size(), base_conns,
		"_exit_tree disconnects body_entered (no leaked connection to the freed monitor)")
