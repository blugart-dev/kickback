extends Node3D

@onready var _state_label: Label = %StateLabel
@onready var _hit_label: Label = %HitLabel

var _characters: Array[KickbackCharacter] = []
var _profiles: Array[WeaponProfile] = []
var _current_weapon: int = 0
var _frame_time_usec: float = 0.0
var _last_tick: int = 0


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

	# Find which character owns the hit body
	var char_root := _find_character_owner(collider)
	if char_root:
		var kc: KickbackCharacter = char_root.get_node_or_null("KickbackCharacter")
		if kc:
			kc.receive_hit(collider, direction.normalized(), hit_pos, profile)
			_hit_label.text = "Hit: %s on %s with %s" % [collider.name, char_root.name, profile.weapon_name]
			return

	_hit_label.text = "Hit: %s (no owner)" % collider.name


func _find_character_owner(body: Node) -> Node:
	# Walk up the tree to find a node that has a KickbackCharacter child
	var node := body.get_parent()
	while node and node != get_tree().root:
		if node.has_node("KickbackCharacter"):
			return node
		node = node.get_parent()
	return null


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_tick > 0:
		_frame_time_usec = lerp(_frame_time_usec, float(now - _last_tick), 0.1)
	_last_tick = now

	var camera := get_viewport().get_camera_3d()
	var profile: WeaponProfile = _profiles[_current_weapon]

	var active_count := 0
	for kc: KickbackCharacter in _characters:
		if kc.get_current_tier() == KickbackCharacter.Tier.ACTIVE_RAGDOLL:
			active_count += 1

	var info := "[%d] %s  |  FPS: %d  |  Frame: %.1fms  |  Active ragdolls: %d  |  RMB+WASD = fly  |  1-5 = weapon\n" % [
		_current_weapon + 1, profile.weapon_name, Engine.get_frames_per_second(),
		_frame_time_usec / 1000.0, active_count]

	if camera:
		for i in _characters.size():
			var kc: KickbackCharacter = _characters[i]
			var root: Node3D = kc.get_parent() as Node3D
			var dist := camera.global_position.distance_to(root.global_position) if root else 0.0
			info += "C%d: %s (%.0fm)  " % [i + 1, kc.get_tier_name(), dist]

	_state_label.text = info
