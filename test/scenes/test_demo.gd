## Interactive demo: multiple patrolling agents with weapon switching.
## Uses DemoAgent (professional-grade patrol AI with smooth animation transitions).
## Controls:
##   LMB = shoot, RMB + WASD = fly camera, Scroll = zoom
##   1-5 = switch weapon, K = kill nearest, R = revive all
##   F3 = debug overlay, Shift+F3 = LOD zones
extends Node3D

@onready var _state_label: Label = %StateLabel
@onready var _hit_label: Label = %HitLabel

var _characters: Array[KickbackCharacter] = []
var _profiles: Array[ImpactProfile] = []
var _profile_names: PackedStringArray = ["Bullet", "Shotgun", "Explosion", "Melee", "Arrow"]
var _current_weapon: int = 0


func _ready() -> void:
	_profiles = [
		load("res://test/resources/bullet.tres"),
		load("res://test/resources/shotgun.tres"),
		load("res://test/resources/explosion.tres"),
		load("res://test/resources/melee.tres"),
		load("res://test/resources/arrow.tres"),
	]
	_characters = KickbackCharacter.find_all(self)
	_hit_label.text = "LMB = shoot | 1-5 = weapon | K = kill nearest | R = revive all"



func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1: _current_weapon = 0
			KEY_2: _current_weapon = 1
			KEY_3: _current_weapon = 2
			KEY_4: _current_weapon = 3
			KEY_5: _current_weapon = 4
			KEY_K: _kill_nearest()
			KEY_R: _revive_all()

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_shoot(event.position)


func _shoot(screen_pos: Vector2) -> void:
	var profile := _profiles[_current_weapon]
	var hit := KickbackRaycast.shoot_from_camera(get_viewport(), screen_pos, profile)
	if hit:
		_hit_label.text = "Hit with %s!" % _profile_names[_current_weapon]
	else:
		_hit_label.text = "Miss"


func _kill_nearest() -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return

	var nearest: KickbackCharacter = null
	var nearest_dist := INF

	for kc: KickbackCharacter in _characters:
		var root := kc.get_character_root()
		if not root:
			continue
		# Skip already persistent characters
		if kc.get_active_state_name() == "PERSISTENT":
			continue
		var dist := camera.global_position.distance_to(root.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = kc

	if nearest:
		nearest.set_persistent(true)
		_hit_label.text = "Killed nearest agent!"


func _revive_all() -> void:
	for kc: KickbackCharacter in _characters:
		if kc.get_active_state_name() == "PERSISTENT":
			kc.set_persistent(false)
	_hit_label.text = "Revived all agents!"


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return

	var active_count := 0
	var info_parts := PackedStringArray()

	for i in _characters.size():
		var kc: KickbackCharacter = _characters[i]
		var root := kc.get_character_root()
		var dist := camera.global_position.distance_to(root.global_position) if root else 0.0

		if kc.get_current_tier() == KickbackCharacter.Tier.ACTIVE_RAGDOLL:
			active_count += 1

		# Show DemoAgent anim state if available
		var agent_info := ""
		if root:
			var agent := root.get_node_or_null("PatrolAgent") as DemoAgent
			if agent:
				agent_info = "/%s" % agent.get_anim_state_name()

		info_parts.append("A%d:%s(%s%s,%.0fm)" % [
			i + 1, kc.get_tier_name(), kc.get_active_state_name(), agent_info, dist])

	_state_label.text = "[%d] %s | FPS: %d | Active: %d | %s" % [
		_current_weapon + 1, _profile_names[_current_weapon],
		Engine.get_frames_per_second(), active_count,
		" | ".join(info_parts)]
