## Global manager for Kickback. Tracks active ragdoll count and LOD distance
## thresholds. Add as an autoload or place in the scene root.
class_name KickbackManager
extends Node

@export_group("LOD")
## Maximum simultaneous active ragdolls before fallback to partial ragdoll.
@export var max_active_ragdolls: int = 5
## Distance thresholds: [active_ragdoll, partial_ragdoll, flinch]. Beyond last = no reaction.
@export var lod_distances: Array[float] = [10.0, 25.0, 50.0]

var _active_ragdoll_count: int = 0


## Requests an active ragdoll slot. Returns true if granted, false if at capacity.
func request_active_ragdoll() -> bool:
	if _active_ragdoll_count >= max_active_ragdolls:
		return false
	_active_ragdoll_count += 1
	return true


## Releases an active ragdoll slot.
func release_active_ragdoll() -> void:
	_active_ragdoll_count = maxi(_active_ragdoll_count - 1, 0)


## Returns how many active ragdolls are currently in use.
func get_active_ragdoll_count() -> int:
	return _active_ragdoll_count


## Returns the LOD tier index for a given camera distance.
## 0 = active ragdoll, 1 = partial ragdoll, 2 = flinch, 3 = none.
func get_tier(distance: float) -> int:
	for i in lod_distances.size():
		if distance < lod_distances[i]:
			return i
	return lod_distances.size()
