## Base class of the behavior layer (docs/PLAN.md 0.6.0). A behavior reads the shared
## [BalanceState] every physics tick and answers with what it WANTS: pose targets for
## some bones and/or stiffness (strength multipliers) for some bones. It never writes to
## the rig itself — the controller applies the answers (a fixed ordered list in 0.6.0,
## the arbiter in 0.7.0), so two behaviors asking for the same bone resolve in one place.
##
## Return shape of [method tick]:
## [codeblock]
## {
##   "stiffness": { rig_name: multiplier },   # of the bone's effective base strength
##   "targets":   { rig_name: Transform3D },  # world-space pose target overrides
## }
## [/codeblock]
## Either key may be absent; an empty dictionary means "nothing this tick".
@icon("res://addons/kickback/icons/active_ragdoll_controller.svg")
class_name KickbackBehavior
extends RefCounted

## Higher wins when two behaviors ask for the same bone (used by the 0.7.0 arbiter; the
## 0.6.0 controller applies behaviors in list order and takes the max stiffness).
var priority: int = 0
## A disabled behavior is skipped without being removed from the list.
var enabled: bool = true


## Called once per physics tick while the controller is in a state the behavior runs in.
func tick(_ctx: BehaviorContext, _balance: BalanceState, _delta: float) -> Dictionary:
	return {}


## Called when the controller's state changes (the new [enum ActiveRagdollController.State]).
func on_state_changed(_new_state: int, _ctx: BehaviorContext) -> void:
	pass


## Drops any in-flight action (called on ragdoll / recovery).
func reset(_ctx: BehaviorContext) -> void:
	pass
