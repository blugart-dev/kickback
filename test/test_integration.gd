extends Node3D

@onready var _state_label: Label = %StateLabel
@onready var _hit_label: Label = %HitLabel

var _characters: Array[KickbackCharacter] = []
var _bullet_profile: WeaponProfile


func _ready() -> void:
	_bullet_profile = load("res://addons/kickback/resources/bullet.tres")

	# Find all KickbackCharacter nodes
	for child in get_tree().get_nodes_in_group("kickback_characters"):
		if child is KickbackCharacter:
			_characters.append(child)

	# Also search by class
	if _characters.is_empty():
		_find_characters(self)


func _find_characters(node: Node) -> void:
	for child in node.get_children():
		if child is KickbackCharacter:
			_characters.append(child)
		_find_characters(child)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_shoot(event.position)


func _shoot(screen_pos: Vector2) -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	var from := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	var to := from + direction * 100.0

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = (1 << 3) | (1 << 4)  # Layers 4 + 5
	query.collide_with_bodies = true

	var result := space_state.intersect_ray(query)
	if result.is_empty():
		_hit_label.text = "Miss"
		return

	var collider: CollisionObject3D = result["collider"]
	var hit_pos: Vector3 = result["position"]

	# Find which KickbackCharacter owns this body
	for kc: KickbackCharacter in _characters:
		kc.receive_hit(collider, direction.normalized(), hit_pos, _bullet_profile)

	_hit_label.text = "Hit: %s" % collider.name


func _process(_delta: float) -> void:
	var info := "FPS: %d  |  LMB = shoot  |  RMB = orbit  |  " % Engine.get_frames_per_second()
	for i in _characters.size():
		var kc: KickbackCharacter = _characters[i]
		info += "C%d: %s  " % [i + 1, kc.get_tier_name()]
	_state_label.text = info
