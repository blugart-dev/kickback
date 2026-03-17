extends Node3D

@onready var _state_label: Label = %StateLabel
@onready var _hit_label: Label = %HitLabel
@onready var _ragdoll_ctrl: PartialRagdollController = %RagdollController
@onready var _flinch_ctrl: FlinchController = %FlinchController
@onready var _weapon: RaycastWeapon = %Weapon


func _ready() -> void:
	_weapon.hit_reported.connect(_on_hit_reported)
	_weapon.hit_fired.connect(_on_hit_fired)
	_flinch_ctrl.flinch_triggered.connect(_on_flinch_triggered)


func _on_hit_fired(event: HitEvent) -> void:
	# Flinch first (instant animation play), then ragdoll (async physics)
	# Flinch skips if ragdoll is already active from a previous hit
	_flinch_ctrl.on_hit(event)
	_ragdoll_ctrl.apply_hit(event)


func _process(_delta: float) -> void:
	var ragdoll := "REACTING" if _ragdoll_ctrl.is_reacting() else "idle"
	_state_label.text = "FPS: %d  |  Ragdoll: %s  |  LMB = shoot  |  RMB = orbit  |  Scroll = zoom" % [Engine.get_frames_per_second(), ragdoll]


func _on_hit_reported(bone_name: String) -> void:
	_hit_label.text = "Hit: %s" % bone_name


func _on_flinch_triggered(direction_name: String) -> void:
	_hit_label.text = _hit_label.text + "  →  " + direction_name
