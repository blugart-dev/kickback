class_name KickbackManager
extends Node

## Maximum simultaneous active ragdolls before fallback to partial ragdoll.
@export var max_active_ragdolls: int = 5
## Distance thresholds: [active_ragdoll, partial_ragdoll, flinch]. Beyond last = no reaction.
@export var lod_distances: Array[float] = [10.0, 25.0, 50.0]

var _active_ragdoll_count: int = 0


func request_active_ragdoll() -> bool:
	if _active_ragdoll_count >= max_active_ragdolls:
		return false
	_active_ragdoll_count += 1
	return true


func release_active_ragdoll() -> void:
	_active_ragdoll_count = maxi(_active_ragdoll_count - 1, 0)


func get_active_ragdoll_count() -> int:
	return _active_ragdoll_count


func get_tier(distance: float) -> int:
	## Returns 0=active_ragdoll, 1=partial_ragdoll, 2=flinch, 3=none
	for i in lod_distances.size():
		if distance < lod_distances[i]:
			return i
	return lod_distances.size()
