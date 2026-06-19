## Utility to verify Jolt Physics is active. Kickback requires Jolt — GodotPhysics
## cannot handle ragdoll joint motors or the required body count.
class_name JoltCheck


## Returns true if the project is configured to use Jolt Physics.
static func is_jolt_active() -> bool:
	var engine_name := ProjectSettings.get_setting("physics/3d/physics_engine", "") as String
	return engine_name == "Jolt Physics" or engine_name == "JoltPhysics3D"
