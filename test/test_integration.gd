extends Node3D

@onready var _state_label: Label = %StateLabel
@onready var _hit_label: Label = %HitLabel

var _characters: Array[KickbackCharacter] = []
var _profiles: Array[WeaponProfile] = []
var _current_weapon: int = 0


func _ready() -> void:
	_profiles = [
		load("res://addons/kickback/resources/bullet.tres"),
		load("res://addons/kickback/resources/shotgun.tres"),
		load("res://addons/kickback/resources/explosion.tres"),
		load("res://addons/kickback/resources/melee.tres"),
		load("res://addons/kickback/resources/arrow.tres"),
	]
	_find_characters(self)


func _find_characters(node: Node) -> void:
	for child in node.get_children():
		if child is KickbackCharacter:
			_characters.append(child)
		_find_characters(child)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1: _current_weapon = 0
			KEY_2: _current_weapon = 1
			KEY_3: _current_weapon = 2
			KEY_4: _current_weapon = 3
			KEY_5: _current_weapon = 4

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_shoot(event.position)


func _shoot(screen_pos: Vector2) -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	var from := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	var to := from + direction * 200.0

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = (1 << 3) | (1 << 4)
	query.collide_with_bodies = true

	var result := space_state.intersect_ray(query)
	if result.is_empty():
		_hit_label.text = "Miss"
		return

	var collider: CollisionObject3D = result["collider"]
	var hit_pos: Vector3 = result["position"]
	var profile: WeaponProfile = _profiles[_current_weapon]

	for kc: KickbackCharacter in _characters:
		kc.receive_hit(collider, direction.normalized(), hit_pos, profile)

	_hit_label.text = "Hit: %s with %s" % [collider.name, profile.weapon_name]


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	var profile: WeaponProfile = _profiles[_current_weapon]
	var info := "[%d] %s  |  FPS: %d  |  RMB+WASD = fly  |  1-5 = weapon  |  LMB = shoot\n" % [
		_current_weapon + 1, profile.weapon_name, Engine.get_frames_per_second()]

	if camera:
		for i in _characters.size():
			var kc: KickbackCharacter = _characters[i]
			var root: Node3D = kc.get_parent() as Node3D
			var dist := camera.global_position.distance_to(root.global_position) if root else 0.0
			info += "C%d: %s (%.0fm)  " % [i + 1, kc.get_tier_name(), dist]

	_state_label.text = info
