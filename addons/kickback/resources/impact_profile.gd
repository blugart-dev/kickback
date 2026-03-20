## Defines how an impact affects ragdoll hit reactions. Create .tres resources
## with different presets for various impact types.
class_name ImpactProfile
extends Resource

## Human-readable name for this impact preset (e.g. "Pistol", "Explosion").
@export var profile_name: StringName = &""

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


static func _make(pname: StringName, impulse: float, transfer: float, upward: float,
		ragdoll_prob: float, reduction: float, spread: int, recovery: float) -> ImpactProfile:
	var p := ImpactProfile.new()
	p.profile_name = pname
	p.base_impulse = impulse
	p.impulse_transfer_ratio = transfer
	p.upward_bias = upward
	p.ragdoll_probability = ragdoll_prob
	p.strength_reduction = reduction
	p.strength_spread = spread
	p.recovery_rate = recovery
	return p


## Creates a bullet impact profile — low impulse, high strength reduction, fast recovery.
static func create_bullet() -> ImpactProfile:
	return _make(&"Bullet", 8.0, 0.15, 0.0, 0.05, 0.85, 1, 0.4)


## Creates a shotgun impact profile — high impulse, wide spread, chance of full ragdoll.
static func create_shotgun() -> ImpactProfile:
	return _make(&"Shotgun", 20.0, 0.40, 0.05, 0.40, 0.92, 3, 0.25)


## Creates an explosion impact profile — massive impulse with upward bias, near-certain ragdoll.
static func create_explosion() -> ImpactProfile:
	return _make(&"Explosion", 40.0, 1.00, 0.40, 0.95, 1.0, 99, 0.15)


## Creates a melee impact profile — strong transfer, moderate ragdoll chance.
static func create_melee() -> ImpactProfile:
	return _make(&"Melee", 15.0, 0.60, 0.0, 0.15, 0.88, 2, 0.3)


## Creates an arrow impact profile — moderate impulse, localized effect.
static func create_arrow() -> ImpactProfile:
	return _make(&"Arrow", 12.0, 0.30, 0.0, 0.10, 0.88, 1, 0.3)
