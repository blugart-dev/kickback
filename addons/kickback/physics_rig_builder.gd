class_name PhysicsRigBuilder
extends Node3D

const COLLISION_LAYER := 8   # Godot layer 4 (1<<3)
const COLLISION_MASK := 14   # Layers 2+3+4 (environment+props+self)

@export var skeleton_path: NodePath

var _skeleton: Skeleton3D
var _bodies: Dictionary = {}         # rig_name → RigidBody3D
var _rig_to_bone: Dictionary = {}    # rig_name → mixamo bone name
var _built: bool = false

const BONE_MAP: Array[Dictionary] = [
	{name = "Hips",       bone = "mixamorig_Hips",         mass = 15.0, shape = "box",     size = Vector3(0.35, 0.20, 0.25)},
	{name = "Spine",      bone = "mixamorig_Spine",        mass = 10.0, shape = "box",     size = Vector3(0.30, 0.18, 0.18)},
	{name = "Chest",      bone = "mixamorig_Spine2",       mass = 12.0, shape = "box",     size = Vector3(0.35, 0.22, 0.22)},
	{name = "Head",       bone = "mixamorig_Head",         mass = 5.0,  shape = "sphere",  radius = 0.12},
	{name = "UpperArm_L", bone = "mixamorig_LeftArm",      mass = 3.0,  shape = "capsule", radius = 0.055, height = 0.28},
	{name = "LowerArm_L", bone = "mixamorig_LeftForeArm",  mass = 2.0,  shape = "capsule", radius = 0.05, height = 0.25},
	{name = "Hand_L",     bone = "mixamorig_LeftHand",     mass = 1.0,  shape = "box",     size = Vector3(0.10, 0.04, 0.12)},
	{name = "UpperArm_R", bone = "mixamorig_RightArm",     mass = 3.0,  shape = "capsule", radius = 0.055, height = 0.28},
	{name = "LowerArm_R", bone = "mixamorig_RightForeArm", mass = 2.0,  shape = "capsule", radius = 0.05, height = 0.25},
	{name = "Hand_R",     bone = "mixamorig_RightHand",    mass = 1.0,  shape = "box",     size = Vector3(0.10, 0.04, 0.12)},
	{name = "UpperLeg_L", bone = "mixamorig_LeftUpLeg",    mass = 8.0,  shape = "capsule", radius = 0.08, height = 0.40},
	{name = "LowerLeg_L", bone = "mixamorig_LeftLeg",      mass = 4.0,  shape = "capsule", radius = 0.065, height = 0.38},
	{name = "Foot_L",     bone = "mixamorig_LeftFoot",     mass = 2.0,  shape = "box",     size = Vector3(0.12, 0.07, 0.25)},
	{name = "UpperLeg_R", bone = "mixamorig_RightUpLeg",   mass = 8.0,  shape = "capsule", radius = 0.08, height = 0.40},
	{name = "LowerLeg_R", bone = "mixamorig_RightLeg",     mass = 4.0,  shape = "capsule", radius = 0.065, height = 0.38},
	{name = "Foot_R",     bone = "mixamorig_RightFoot",    mass = 2.0,  shape = "box",     size = Vector3(0.12, 0.07, 0.25)},
]

# Maps rig body → child bone (for computing shape offset along bone direction)
const CHILD_BONE_MAP: Dictionary = {
	"Hips": "mixamorig_Spine",         "Spine": "mixamorig_Spine2",
	"Chest": "mixamorig_Neck",         "Head": "",
	"UpperArm_L": "mixamorig_LeftForeArm",  "LowerArm_L": "mixamorig_LeftHand",   "Hand_L": "",
	"UpperArm_R": "mixamorig_RightForeArm", "LowerArm_R": "mixamorig_RightHand",  "Hand_R": "",
	"UpperLeg_L": "mixamorig_LeftLeg",      "LowerLeg_L": "mixamorig_LeftFoot",   "Foot_L": "",
	"UpperLeg_R": "mixamorig_RightLeg",     "LowerLeg_R": "mixamorig_RightFoot",  "Foot_R": "",
}

const JOINT_MAP: Array[Dictionary] = [
	{parent = "Hips",       child = "Spine",      xl = -15, xh = 15,  yl = -15, yh = 15,  zl = -10, zh = 10},
	{parent = "Spine",      child = "Chest",      xl = -15, xh = 15,  yl = -15, yh = 15,  zl = -10, zh = 10},
	{parent = "Chest",      child = "Head",       xl = -40, xh = 40,  yl = -50, yh = 50,  zl = -30, zh = 30},
	{parent = "Chest",      child = "UpperArm_L", xl = -70, xh = 70,  yl = -70, yh = 70,  zl = -70, zh = 70},
	{parent = "UpperArm_L", child = "LowerArm_L", xl = -65, xh = 65,  yl = -5,  yh = 5,   zl = -5,  zh = 5},
	{parent = "LowerArm_L", child = "Hand_L",     xl = -40, xh = 40,  yl = -20, yh = 20,  zl = -50, zh = 50},
	{parent = "Chest",      child = "UpperArm_R", xl = -70, xh = 70,  yl = -70, yh = 70,  zl = -70, zh = 70},
	{parent = "UpperArm_R", child = "LowerArm_R", xl = -65, xh = 65,  yl = -5,  yh = 5,   zl = -5,  zh = 5},
	{parent = "LowerArm_R", child = "Hand_R",     xl = -40, xh = 40,  yl = -20, yh = 20,  zl = -50, zh = 50},
	{parent = "Hips",       child = "UpperLeg_L", xl = -60, xh = 60,  yl = -20, yh = 20,  zl = -30, zh = 30},
	{parent = "UpperLeg_L", child = "LowerLeg_L", xl = -60, xh = 60,  yl = -5,  yh = 5,   zl = -5,  zh = 5},
	{parent = "LowerLeg_L", child = "Foot_L",     xl = -30, xh = 30,  yl = -10, yh = 10,  zl = -20, zh = 20},
	{parent = "Hips",       child = "UpperLeg_R", xl = -60, xh = 60,  yl = -20, yh = 20,  zl = -30, zh = 30},
	{parent = "UpperLeg_R", child = "LowerLeg_R", xl = -60, xh = 60,  yl = -5,  yh = 5,   zl = -5,  zh = 5},
	{parent = "LowerLeg_R", child = "Foot_R",     xl = -30, xh = 30,  yl = -10, yh = 10,  zl = -20, zh = 20},
]


func _ready() -> void:
	JoltCheck.warn_if_not_jolt()
	_skeleton = get_node(skeleton_path) as Skeleton3D
	await get_tree().process_frame
	await get_tree().process_frame
	_build_rig()
	set_enabled(false)


func _build_rig() -> void:
	for config in BONE_MAP:
		var bone_idx := _skeleton.find_bone(config.bone)
		if bone_idx < 0:
			push_warning("PhysicsRigBuilder: bone '%s' not found" % config.bone)
			continue

		var bone_global := _get_bone_global(config.bone)
		var body := _create_body(config, bone_global)
		add_child(body)
		body.global_transform = bone_global
		_bodies[config.name] = body
		_rig_to_bone[config.name] = config.bone

	for config in JOINT_MAP:
		_create_joint(config)

	_built = true


func _get_bone_global(bone_name: String) -> Transform3D:
	var idx := _skeleton.find_bone(bone_name)
	if idx < 0:
		return Transform3D.IDENTITY
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(idx)


func _create_body(config: Dictionary, bone_global: Transform3D) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = config.name
	body.mass = config.mass
	body.collision_layer = COLLISION_LAYER
	body.collision_mask = COLLISION_MASK
	body.can_sleep = false
	body.gravity_scale = 0.8
	body.angular_damp = 8.0
	body.linear_damp = 2.0

	# Shape is offset locally along the bone direction (toward child bone)
	var col_shape := _create_collision_shape(config)
	var child_bone: String = CHILD_BONE_MAP.get(config.name, "")
	if child_bone != "":
		var child_global := _get_bone_global(child_bone)
		var bone_to_child_local := bone_global.affine_inverse() * child_global
		col_shape.position = bone_to_child_local.origin * 0.5
	body.add_child(col_shape)

	return body


func _create_collision_shape(config: Dictionary) -> CollisionShape3D:
	var col := CollisionShape3D.new()
	match config.shape:
		"box":
			var box := BoxShape3D.new()
			box.size = config.size
			col.shape = box
		"capsule":
			var capsule := CapsuleShape3D.new()
			capsule.radius = config.radius
			capsule.height = config.height
			col.shape = capsule
		"sphere":
			var sphere := SphereShape3D.new()
			sphere.radius = config.radius
			col.shape = sphere
	return col


func _create_joint(config: Dictionary) -> void:
	var parent_body: RigidBody3D = _bodies[config.parent]
	var child_body: RigidBody3D = _bodies[config.child]
	var child_bone: String = _rig_to_bone[config.child]
	var joint_global := _get_bone_global(child_bone)

	var joint := Generic6DOFJoint3D.new()
	joint.name = "%s_to_%s" % [config.parent, config.child]
	add_child(joint)

	joint.global_transform = joint_global
	joint.node_a = joint.get_path_to(parent_body)
	joint.node_b = joint.get_path_to(child_body)

	# Lock linear axes
	for axis in ["x", "y", "z"]:
		joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
		joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
		joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)

	# Angular limits
	for axis in ["x", "y", "z"]:
		joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(config.xl))
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(config.xh))
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(config.yl))
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(config.yh))
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(config.zl))
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(config.zh))


func set_enabled(value: bool) -> void:
	if value and _built:
		snap_to_skeleton()
	for body: RigidBody3D in _bodies.values():
		body.freeze = not value


func snap_to_skeleton() -> void:
	for rig_name: String in _bodies:
		var body: RigidBody3D = _bodies[rig_name]
		var bone_name: String = _rig_to_bone[rig_name]
		var bone_global := _get_bone_global(bone_name)
		body.global_transform = bone_global
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO


func get_bodies() -> Dictionary:
	return _bodies


func get_bone_name_for_body(rig_name: String) -> String:
	return _rig_to_bone.get(rig_name, "")
