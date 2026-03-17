extends Node3D

@onready var _state_label: Label = %StateLabel
@onready var _hit_label: Label = %HitLabel
@onready var _rig_builder: PhysicsRigBuilder = %PhysicsRigBuilder
@onready var _rig_sync: PhysicsRigSync = %PhysicsRigSync
@onready var _spring: SpringResolver = %SpringResolver
@onready var _weapon: RaycastWeapon = %Weapon

var _physics_enabled: bool = false


func _ready() -> void:
	var simulator := %Character.get_node_or_null("Skeleton3D/PhysicalBoneSimulator3D")
	if simulator:
		simulator.queue_free()
	_weapon.hit_reported.connect(_on_hit_reported)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_T:
		_physics_enabled = not _physics_enabled
		_rig_builder.set_enabled(_physics_enabled)
		_rig_sync.set_active(_physics_enabled)
		_spring.set_active(_physics_enabled)


func _process(_delta: float) -> void:
	var mode := "ACTIVE RAGDOLL" if _physics_enabled else "ANIMATION"
	_state_label.text = "Mode: %s  |  FPS: %d  |  T = toggle  |  LMB = shoot  |  RMB = orbit" % [mode, Engine.get_frames_per_second()]


func _on_hit_reported(bone_name: String) -> void:
	_hit_label.text = "Hit: %s" % bone_name
