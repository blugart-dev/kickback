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


func test_factory_bullet_matches_preset():
	var factory := ImpactProfile.create_bullet()
	var preset: ImpactProfile = load("res://test/resources/bullet.tres")
	assert_eq(factory.base_impulse, preset.base_impulse, "Bullet impulse should match")
	assert_eq(factory.impulse_transfer_ratio, preset.impulse_transfer_ratio, "Bullet transfer should match")
	assert_eq(factory.strength_reduction, preset.strength_reduction, "Bullet reduction should match")
	assert_eq(factory.strength_spread, preset.strength_spread, "Bullet spread should match")
	assert_eq(factory.recovery_rate, preset.recovery_rate, "Bullet recovery should match")


func test_factory_shotgun_values():
	var p := ImpactProfile.create_shotgun()
	assert_eq(p.profile_name, &"Shotgun")
	assert_eq(p.base_impulse, 20.0)
	assert_eq(p.impulse_transfer_ratio, 0.40)
	assert_eq(p.strength_spread, 3)
	assert_almost_eq(p.ragdoll_probability, 0.40, 0.001)


func test_factory_explosion_values():
	var p := ImpactProfile.create_explosion()
	assert_eq(p.profile_name, &"Explosion")
	assert_eq(p.base_impulse, 40.0)
	assert_eq(p.impulse_transfer_ratio, 1.0)
	assert_eq(p.strength_spread, 99)
	assert_almost_eq(p.ragdoll_probability, 0.95, 0.001)
	assert_almost_eq(p.upward_bias, 0.40, 0.001)


func test_factory_melee_values():
	var p := ImpactProfile.create_melee()
	assert_eq(p.profile_name, &"Melee")
	assert_eq(p.base_impulse, 15.0)
	assert_eq(p.impulse_transfer_ratio, 0.60)
	assert_eq(p.strength_spread, 2)


func test_factory_arrow_values():
	var p := ImpactProfile.create_arrow()
	assert_eq(p.profile_name, &"Arrow")
	assert_eq(p.base_impulse, 12.0)
	assert_eq(p.impulse_transfer_ratio, 0.30)
	assert_eq(p.strength_spread, 1)
