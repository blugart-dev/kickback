extends GutTest


func test_default_values():
	var ip := ImpactProfile.new()
	assert_eq(ip.base_impulse, 8.0)
	assert_eq(ip.impulse_transfer_ratio, 0.3)
	assert_eq(ip.upward_bias, 0.0)
	assert_eq(ip.ragdoll_probability, 0.0)
	assert_eq(ip.strength_reduction, 0.4)
	assert_eq(ip.strength_spread, 1)
	assert_eq(ip.recovery_rate, 1.0)


func test_bullet_profile_loads():
	var bullet: ImpactProfile = load("res://test/resources/bullet.tres")
	assert_not_null(bullet)
	assert_eq(bullet.profile_name, &"Bullet")


func test_explosion_profile_loads():
	var explosion: ImpactProfile = load("res://test/resources/explosion.tres")
	assert_not_null(explosion)
	assert_gt(explosion.ragdoll_probability, 0.5, "Explosions should have high ragdoll chance")
	assert_gt(explosion.upward_bias, 0.0, "Explosions should have upward bias")


func test_all_profiles_load():
	var profile_paths := [
		"res://test/resources/bullet.tres",
		"res://test/resources/shotgun.tres",
		"res://test/resources/explosion.tres",
		"res://test/resources/melee.tres",
		"res://test/resources/arrow.tres",
	]
	for path: String in profile_paths:
		var profile: ImpactProfile = load(path)
		assert_not_null(profile, "Profile should load: %s" % path)
		assert_gt(profile.base_impulse, 0.0, "Impulse should be positive: %s" % path)
		assert_gt(profile.recovery_rate, 0.0, "Recovery should be positive: %s" % path)
