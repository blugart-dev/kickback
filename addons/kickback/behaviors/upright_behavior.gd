## Standing balance (docs/PLAN.md 0.6.0): the ankle / hip strategy in IK form. Every
## tick it compares where the body's extrapolated centre of mass is with where the
## ANIMATION's centre of mass is (both over the feet) and shifts the whole-body pose
## target the other way: the legs, solved by the foot IK to the planted feet, then pull
## the body back — leaning the shins (ankle strategy) and the pelvis (hip strategy) as
## one. Nothing external pushes the pelvis; the joint motors do it within their torques.
##
## Why: with the root anchor's sideways hold released the standing rig is a soft table —
## measured on the ybot 4° idle error and a 150 N·s shove displaces the pelvis 0.47 m
## without any correction. Tracking a fixed pose cannot hold an inverted pendulum through
## torque-limited motors with a ~10-tick lag; a feedback shift on the XCoM error can.
##
## The error is measured against the animation's own CoM, not the support centre, so a
## weight-shifted idle (CoM 9 cm toward one foot on the ybot) is not "corrected" away.
@icon("res://addons/kickback/icons/active_ragdoll_controller.svg")
class_name UprightBehavior
extends KickbackBehavior

## Diagnostics.
var last_error: Vector2 = Vector2.ZERO
var last_shift: Vector2 = Vector2.ZERO

var _shift: Vector2 = Vector2.ZERO


func tick(ctx: BehaviorContext, balance: BalanceState, delta: float) -> Dictionary:
	var ik := ctx.foot_ik
	if not enabled or ik == null or not ik.is_initialized() or not ctx.tuning.upright_enabled:
		return {}
	if not ctx.spring.is_motor_mode() or not balance.has_support:
		_relax(ik, delta)
		return {}
	var t := ctx.tuning
	# Animation CoM over the ground, from the animation targets and the body masses.
	var anim_com := Vector2.ZERO
	var total := 0.0
	for rig_name: String in ctx.rig_builder.get_bodies():
		var body: RigidBody3D = ctx.rig_builder.get_bodies()[rig_name]
		var a := ctx.animation_global(rig_name).origin
		anim_com += Vector2(a.x, a.z) * body.mass
		total += body.mass
	if total <= 0.001:
		return {}
	anim_com /= total
	# Error: where the body is heading (XCoM) minus where the animation stands.
	var xcom := Vector2(balance.xcom.x, balance.xcom.z)
	last_error = xcom - anim_com
	var target := -last_error * t.upright_gain
	if target.length() > t.upright_max_shift:
		target = target.normalized() * t.upright_max_shift
	# Smooth the shift so the target does not jump with the XCoM's velocity term.
	var blend := 1.0 - exp(-t.upright_response * delta)
	_shift = _shift.lerp(target, blend)
	last_shift = _shift
	ik.set_body_shift(Vector3(_shift.x, 0.0, _shift.y))
	return {}


func _relax(ik: FootIKSolver, delta: float) -> void:
	_shift = _shift.lerp(Vector2.ZERO, 1.0 - exp(-8.0 * delta))
	last_shift = _shift
	ik.set_body_shift(Vector3(_shift.x, 0.0, _shift.y))


func reset(ctx: BehaviorContext) -> void:
	_shift = Vector2.ZERO
	last_shift = Vector2.ZERO
	if ctx.foot_ik:
		ctx.foot_ik.set_body_shift(Vector3.ZERO)
