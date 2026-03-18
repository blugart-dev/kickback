## Utility to verify Jolt Physics is active. Kickback requires Jolt — GodotPhysics
## cannot handle ragdoll joint motors or the required body count.
class_name JoltCheck


## Returns true if the project is configured to use Jolt Physics.
static func is_jolt_active() -> bool:
	var engine_name := ProjectSettings.get_setting("physics/3d/physics_engine", "") as String
	return engine_name == "Jolt Physics" or engine_name == "JoltPhysics3D"


## Prints a warning and returns false if Jolt is not active.
static func warn_if_not_jolt() -> bool:
	if not is_jolt_active():
		push_warning("Kickback: Jolt Physics is not active. Ragdoll will not work correctly.")
		return false
	return true
