extends Node3D

@onready var _state_label: Label = %StateLabel
@onready var _hit_label: Label = %HitLabel
@onready var _flinch_ctrl: FlinchController = %FlinchController
@onready var _weapon: RaycastWeapon = %Weapon


func _ready() -> void:
	_weapon.hit_reported.connect(_on_hit_reported)
	_weapon.hit_fired.connect(_flinch_ctrl.on_hit)
	_flinch_ctrl.flinch_triggered.connect(_on_flinch_triggered)


func _process(_delta: float) -> void:
	_state_label.text = "FPS: %d  |  LMB = shoot  |  RMB drag = orbit  |  Scroll = zoom" % Engine.get_frames_per_second()


func _on_hit_reported(bone_name: String) -> void:
	_hit_label.text = "Hit: %s" % bone_name


func _on_flinch_triggered(direction_name: String) -> void:
	_hit_label.text = _hit_label.text + "  →  " + direction_name
