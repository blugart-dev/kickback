class_name JoltCheck


static func is_jolt_active() -> bool:
	var engine_name := ProjectSettings.get_setting("physics/3d/physics_engine", "") as String
	return engine_name == "Jolt Physics" or engine_name == "JoltPhysics3D"


static func warn_if_not_jolt() -> bool:
	if not is_jolt_active():
		push_warning("Kickback: Jolt Physics is not active. Ragdoll will not work correctly.")
		return false
	return true
