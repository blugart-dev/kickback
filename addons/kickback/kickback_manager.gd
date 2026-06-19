## Global budget manager for Kickback. Caps how many active ragdolls simulate at
## once. Add as an autoload or place in the scene root — controllers discover it
## via the [constant GROUP] group, so no wiring is needed.
##
## The cap is HARD for spontaneous reactions: when [method request_active_ragdoll]
## denies a slot, a hit- or balance-driven full ragdoll is downgraded to a stagger
## (the character still reacts, but skips the expensive limp/settle/get-up cycle).
## Explicit [method ActiveRagdollController.trigger_ragdoll] and
## [method ActiveRagdollController.set_persistent] bypass the cap — a deliberate or
## death ragdoll must always proceed. If no manager is present, ragdolls are
## unbounded.
@icon("res://addons/kickback/icons/kickback_manager.svg")
class_name KickbackManager
extends Node

@export_group("Budget")
## Maximum simultaneous active ragdolls allowed.
@export var max_active_ragdolls: int = 5

## Group name controllers use to discover this manager (works whether it is an
## autoload or placed in the scene tree).
const GROUP := "kickback_manager"

var _active_ragdoll_count: int = 0


func _enter_tree() -> void:
	add_to_group(GROUP)


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
