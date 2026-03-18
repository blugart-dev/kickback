extends GutTest

var _manager: KickbackManager


func before_each():
	_manager = KickbackManager.new()
	_manager.max_active_ragdolls = 3
	_manager.lod_distances = [10.0, 25.0, 50.0]
	add_child_autofree(_manager)


func test_request_grants_when_available():
	assert_true(_manager.request_active_ragdoll())
	assert_eq(_manager.get_active_ragdoll_count(), 1)


func test_request_denies_at_capacity():
	for i in 3:
		_manager.request_active_ragdoll()
	assert_false(_manager.request_active_ragdoll())
	assert_eq(_manager.get_active_ragdoll_count(), 3)


func test_release_frees_slot():
	_manager.request_active_ragdoll()
	_manager.request_active_ragdoll()
	_manager.release_active_ragdoll()
	assert_eq(_manager.get_active_ragdoll_count(), 1)
	assert_true(_manager.request_active_ragdoll())


func test_release_cannot_go_negative():
	_manager.release_active_ragdoll()
	_manager.release_active_ragdoll()
	assert_eq(_manager.get_active_ragdoll_count(), 0)


func test_get_tier_returns_correct_values():
	assert_eq(_manager.get_tier(5.0), 0, "5m should be active ragdoll")
	assert_eq(_manager.get_tier(15.0), 1, "15m should be partial ragdoll")
	assert_eq(_manager.get_tier(30.0), 2, "30m should be flinch")
	assert_eq(_manager.get_tier(100.0), 3, "100m should be none")


func test_get_tier_boundary_values():
	assert_eq(_manager.get_tier(9.99), 0, "Just under 10m = active")
	assert_eq(_manager.get_tier(10.0), 1, "Exactly 10m = partial")
	assert_eq(_manager.get_tier(25.0), 2, "Exactly 25m = flinch")
	assert_eq(_manager.get_tier(50.0), 3, "Exactly 50m = none")
