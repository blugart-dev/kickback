## Global budget manager for Kickback. Tracks how many active ragdolls are
## currently simulating. Add as an autoload or place in the scene root.
@icon("res://addons/kickback/icons/kickback_manager.svg")
class_name KickbackManager
extends Node

@export_group("Budget")
## Maximum simultaneous active ragdolls allowed.
@export var max_active_ragdolls: int = 5

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
