## Defines how a weapon affects ragdoll hit reactions. Create .tres resources
## with different presets (bullet, shotgun, explosion, melee, arrow).
class_name WeaponProfile
extends Resource

@export var weapon_name: StringName = &""

@export_group("Impulse")
## Base impulse force applied to the hit body.
@export_range(0.0, 100.0) var base_impulse: float = 8.0
## Fraction of base_impulse actually transferred (0 = no push, 1 = full).
@export_range(0.0, 1.0) var impulse_transfer_ratio: float = 0.3
## Extra upward force (0 = none, 0.4 = explosion-style launch).
@export_range(0.0, 1.0) var upward_bias: float = 0.0

@export_group("Ragdoll")
## Chance of triggering full ragdoll on hit (0 = never, 1 = always).
@export_range(0.0, 1.0) var ragdoll_probability: float = 0.0
## How much spring strength is reduced on the hit bone (0 = none, 1 = full).
@export_range(0.0, 1.0) var strength_reduction: float = 0.4
## How many neighbor bones also lose strength (0 = hit bone only).
@export_range(0, 10) var strength_spread: int = 1

@export_group("Recovery")
## How fast spring strength recovers per second after a hit.
@export_range(0.0, 5.0) var recovery_rate: float = 1.0
