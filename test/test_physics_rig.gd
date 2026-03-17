extends Node3D

@onready var _state_label: Label = %StateLabel
@onready var _hit_label: Label = %HitLabel
@onready var _rig_builder: PhysicsRigBuilder = %PhysicsRigBuilder
@onready var _rig_sync: PhysicsRigSync = %PhysicsRigSync

var _physics_enabled: bool = false


func _ready() -> void:
	# Remove Step 0's PhysicalBoneSimulator3D — its PhysicalBone3D nodes conflict
	# with set_bone_global_pose_override (degenerate transforms passed to Jolt)
	var simulator := %Character.get_node_or_null("Skeleton3D/PhysicalBoneSimulator3D")
	if simulator:
		simulator.queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_T:
		_physics_enabled = not _physics_enabled
		_rig_builder.set_enabled(_physics_enabled)
		_rig_sync.set_active(_physics_enabled)


func _process(_delta: float) -> void:
	var mode := "PHYSICS" if _physics_enabled else "ANIMATION"
	_state_label.text = "Mode: %s  |  FPS: %d  |  T = toggle  |  RMB = orbit  |  Scroll = zoom" % [mode, Engine.get_frames_per_second()]
	_hit_label.text = "Bodies: %d" % _rig_builder.get_bodies().size()
