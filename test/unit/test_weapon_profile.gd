extends GutTest


func test_default_values():
	var wp := WeaponProfile.new()
	assert_eq(wp.base_impulse, 8.0)
	assert_eq(wp.impulse_transfer_ratio, 0.3)
	assert_eq(wp.upward_bias, 0.0)
	assert_eq(wp.ragdoll_probability, 0.0)
	assert_eq(wp.strength_reduction, 0.4)
	assert_eq(wp.strength_spread, 1)
	assert_eq(wp.recovery_rate, 1.0)


func test_bullet_profile_loads():
	var bullet: WeaponProfile = load("res://addons/kickback/resources/bullet.tres")
	assert_not_null(bullet)
	assert_eq(bullet.weapon_name, &"Bullet")


func test_explosion_profile_loads():
	var explosion: WeaponProfile = load("res://addons/kickback/resources/explosion.tres")
	assert_not_null(explosion)
	assert_gt(explosion.ragdoll_probability, 0.5, "Explosions should have high ragdoll chance")
	assert_gt(explosion.upward_bias, 0.0, "Explosions should have upward bias")


func test_all_profiles_load():
	var profile_paths := [
		"res://addons/kickback/resources/bullet.tres",
		"res://addons/kickback/resources/shotgun.tres",
		"res://addons/kickback/resources/explosion.tres",
		"res://addons/kickback/resources/melee.tres",
		"res://addons/kickback/resources/arrow.tres",
	]
	for path: String in profile_paths:
		var profile: WeaponProfile = load(path)
		assert_not_null(profile, "Profile should load: %s" % path)
		assert_gt(profile.base_impulse, 0.0, "Impulse should be positive: %s" % path)
		assert_gt(profile.recovery_rate, 0.0, "Recovery should be positive: %s" % path)
