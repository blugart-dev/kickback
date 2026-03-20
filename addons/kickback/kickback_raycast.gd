## Static utility for raycasting against Kickback-enabled characters.
## Handles the common pattern of shooting from camera, detecting hit bodies,
## finding the owning KickbackCharacter, and routing the hit automatically.
##
## Quick start — one line to shoot from mouse position:
## [codeblock]
## KickbackRaycast.shoot_from_camera(get_viewport(), event.position, profile)
## [/codeblock]
class_name KickbackRaycast

## Collision layer bit for active ragdoll RigidBody3D nodes (layer 4 in UI).
const ACTIVE_RAGDOLL_BIT := 3
## Collision layer bit for partial ragdoll PhysicalBone3D nodes (layer 5 in UI).
const PARTIAL_RAGDOLL_BIT := 4
## Default collision mask targeting both ragdoll layers.
const DEFAULT_MASK := (1 << ACTIVE_RAGDOLL_BIT) | (1 << PARTIAL_RAGDOLL_BIT)


## Performs a raycast from the viewport camera through [param screen_pos] and
## routes any hit to the appropriate KickbackCharacter. Returns true if a hit
## was detected and routed, false otherwise.
static func shoot_from_camera(
	viewport: Viewport,
	screen_pos: Vector2,
	profile: ImpactProfile,
	ray_length: float = 100.0,
	collision_mask: int = DEFAULT_MASK
) -> bool:
	var camera := viewport.get_camera_3d()
	if not camera:
		return false

	var from := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	var to := from + direction * ray_length

	var space := viewport.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = collision_mask
	query.collide_with_bodies = true

	var result := space.intersect_ray(query)
	if result.is_empty():
		return false

	var collider: CollisionObject3D = result["collider"]
	var hit_pos: Vector3 = result["position"]

	var character := find_character_owner(collider)
	if not character:
		return false

	character.receive_hit(collider, direction.normalized(), hit_pos, profile)
	return true


## Walks up the scene tree from a hit body to find the KickbackCharacter
## that owns it. Returns null if no KickbackCharacter is found.
static func find_character_owner(body: Node) -> KickbackCharacter:
	var node := body.get_parent()
	while node:
		for child in node.get_children():
			if child is KickbackCharacter:
				return child
		node = node.get_parent()
	return null
