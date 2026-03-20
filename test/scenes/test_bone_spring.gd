## Experiment: Can PhysicalBoneSimulator3D support velocity-based spring pose matching?
## This is a standalone test — no plugin code used.
##
## Controls:
##   E = toggle ragdoll (zero/restore all strengths)
##   LMB = shoot (apply impulse to hit bone)
##   RMB = orbit camera
##   F = toggle freeze (pause/resume simulation)
extends Node3D

@onready var _label: Label = %StateLabel
@onready var _character: Node3D = get_node_or_null("%Character")


var _skeleton: Skeleton3D
var _simulator: PhysicalBoneSimulator3D
var _bones: Dictionary = {}  # bone_name → {pb: PhysicalBone3D, bone_idx: int, strength: float, base: float}
var _ragdolled: bool = false
var _active: bool = false

## Per-bone default strengths (same values as RagdollTuning)
const STRENGTHS := {
	"mixamorig_Hips": 0.65, "mixamorig_Spine": 0.60, "mixamorig_Spine1": 0.60,
	"mixamorig_Spine2": 0.60, "mixamorig_Neck": 0.40, "mixamorig_Head": 0.35,
	"mixamorig_LeftArm": 0.45, "mixamorig_LeftForeArm": 0.40, "mixamorig_LeftHand": 0.25,
	"mixamorig_RightArm": 0.45, "mixamorig_RightForeArm": 0.40, "mixamorig_RightHand": 0.25,
	"mixamorig_LeftUpLeg": 0.55, "mixamorig_LeftLeg": 0.45, "mixamorig_LeftFoot": 0.30,
	"mixamorig_RightUpLeg": 0.55, "mixamorig_RightLeg": 0.45, "mixamorig_RightFoot": 0.30,
}

const PIN_STRENGTH := {
	"mixamorig_Hips": 0.85,
	"mixamorig_LeftFoot": 0.4, "mixamorig_RightFoot": 0.4,
}
const DEFAULT_PIN := 0.1
const DEFAULT_STRENGTH := 0.25
const RECOVERY_RATE := 0.3
const MAX_ANG_VEL := 20.0
const MAX_LIN_VEL := 10.0


func _ready() -> void:
	_skeleton = _character.get_node("Skeleton3D")
	_simulator = _skeleton.get_node("PhysicalBoneSimulator3D")

	# Build bone map from all PhysicalBone3D children
	for child in _simulator.get_children():
		if child is PhysicalBone3D:
			var pb: PhysicalBone3D = child
			var bone_idx := _skeleton.find_bone(pb.bone_name)
			if bone_idx >= 0:
				var base: float = STRENGTHS.get(pb.bone_name, DEFAULT_STRENGTH)
				_bones[pb.bone_name] = {
					"pb": pb,
					"bone_idx": bone_idx,
					"strength": base,
					"base": base,
				}

	print("BoneSpring: Found %d physical bones" % _bones.size())

	# Start full simulation
	await get_tree().process_frame
	await get_tree().process_frame
	_simulator.physical_bones_start_simulation()
	_active = true
	print("BoneSpring: Simulation started")


func _physics_process(delta: float) -> void:
	if not _active:
		return

	var skel_global := _skeleton.global_transform

	for bone_name: String in _bones:
		var state: Dictionary = _bones[bone_name]
		var pb: PhysicalBone3D = state.pb
		var bone_idx: int = state.bone_idx

		# Strength recovery
		if not _ragdolled:
			state.strength = move_toward(state.strength, state.base, RECOVERY_RATE * delta)

		var strength: float = state.strength
		if strength < 0.001:
			continue

		# Get animation target (walk parent chain, same as SpringResolver)
		var anim_pose := _get_anim_bone_global(bone_idx)
		# Strip root motion XZ on hips
		if bone_name == "mixamorig_Hips":
			anim_pose.origin.x = 0.0
			anim_pose.origin.z = 0.0
		# Account for PhysicalBone3D body_offset — the physics body is offset
		# from the bone transform by this amount
		var target := skel_global * anim_pose * pb.body_offset
		var current := pb.global_transform

		# Angular spring (same math as SpringResolver)
		var error_basis := target.basis.orthonormalized() * current.basis.orthonormalized().inverse()
		var det := error_basis.determinant()
		if det > 0.001 or det < -0.001:
			var q := error_basis.get_rotation_quaternion()
			if q.w < 0:
				q = -q
			var angle := 2.0 * acos(clampf(q.w, -1.0, 1.0))
			var axis_raw := Vector3(q.x, q.y, q.z)
			if axis_raw.length_squared() > 0.0001 and angle > 0.001:
				var target_vel := (axis_raw.normalized() * angle) / delta
				pb.angular_velocity = pb.angular_velocity.lerp(target_vel, strength)

		# Linear spring (pin)
		var pin: float = PIN_STRENGTH.get(bone_name, DEFAULT_PIN) * (strength / state.base if state.base > 0.001 else 1.0)
		var pos_error := target.origin - current.origin
		pb.linear_velocity = pb.linear_velocity.lerp(pos_error / delta, pin)

		# Clamp velocities
		if pb.angular_velocity.length_squared() > MAX_ANG_VEL * MAX_ANG_VEL:
			pb.angular_velocity = pb.angular_velocity.normalized() * MAX_ANG_VEL
		if pb.linear_velocity.length_squared() > MAX_LIN_VEL * MAX_LIN_VEL:
			pb.linear_velocity = pb.linear_velocity.normalized() * MAX_LIN_VEL


func _get_anim_bone_global(bone_idx: int) -> Transform3D:
	var xform := _skeleton.get_bone_pose(bone_idx)
	var parent_idx := _skeleton.get_bone_parent(bone_idx)
	while parent_idx >= 0:
		xform = _skeleton.get_bone_pose(parent_idx) * xform
		parent_idx = _skeleton.get_bone_parent(parent_idx)
	return xform


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_E:
				_ragdolled = not _ragdolled
				if _ragdolled:
					for state: Dictionary in _bones.values():
						state.strength = 0.0
				else:
					for state: Dictionary in _bones.values():
						state.strength = state.base
			KEY_F:
				_active = not _active
				if _active:
					_simulator.physical_bones_start_simulation()
				else:
					_simulator.physical_bones_stop_simulation()

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_shoot(event.position)


func _shoot(screen_pos: Vector2) -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	var from := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	var to := from + direction * 100.0

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0xFFFFFFFF  # Hit everything
	query.collide_with_bodies = true
	query.exclude = []

	var result := space.intersect_ray(query)
	if result.is_empty():
		print("BoneSpring: miss")
		return

	var collider: Object = result["collider"]
	print("BoneSpring: hit %s (%s)" % [collider.name, collider.get_class()])

	if collider is PhysicalBone3D:
		var pb: PhysicalBone3D = collider
		var hit_pos: Vector3 = result["position"]
		var local_offset := pb.to_local(hit_pos)
		pb.apply_impulse(direction.normalized() * 12.0, local_offset)

		# Reduce strength on hit bone
		if pb.bone_name in _bones:
			_bones[pb.bone_name].strength *= 0.1
			print("  → %s strength: %.3f" % [pb.bone_name, _bones[pb.bone_name].strength])


func _process(_delta: float) -> void:
	var state_text := "RAGDOLL" if _ragdolled else "SPRING"
	if not _active:
		state_text = "PAUSED"
	_label.text = "BoneSpring: %s | Bones: %d | E=ragdoll F=pause LMB=shoot" % [state_text, _bones.size()]
