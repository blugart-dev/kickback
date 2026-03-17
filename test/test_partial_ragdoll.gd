extends Node3D

@onready var _state_label: Label = %StateLabel
@onready var _hit_label: Label = %HitLabel
@onready var _ragdoll_ctrl: PartialRagdollController = %RagdollController
@onready var _weapon: RaycastWeapon = %Weapon


func _ready() -> void:
	_weapon.hit_reported.connect(_on_hit_reported)
	_weapon.hit_fired.connect(_ragdoll_ctrl.apply_hit)


func _process(_delta: float) -> void:
	var state := "REACTING" if _ragdoll_ctrl.is_reacting() else "IDLE"
	_state_label.text = "State: %s  |  FPS: %d  |  Click = shoot" % [state, Engine.get_frames_per_second()]


func _on_hit_reported(bone_name: String) -> void:
	_hit_label.text = "Hit: %s" % bone_name
