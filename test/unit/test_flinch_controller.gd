extends GutTest

var _character: Node3D
var _flinch: FlinchController


func before_each():
	_character = preload("res://assets/characters/ybot/ybot.tscn").instantiate()
	add_child_autofree(_character)

	_flinch = FlinchController.new()
	_flinch.name = "FlinchController"
	_flinch.animation_player_path = NodePath("../AnimationPlayer")
	_flinch.character_path = NodePath("..")
	_character.add_child(_flinch)

	await get_tree().process_frame


func test_hit_from_front_emits_flinch_front():
	watch_signals(_flinch)
	var event := HitEvent.new()
	event.hit_direction = -_character.global_basis.z  # Toward character = from front
	event.hit_bone_region = "torso"
	_flinch.on_hit(event)
	assert_signal_emitted(_flinch, "flinch_triggered")


func test_hit_from_back_emits_flinch_back():
	watch_signals(_flinch)
	var event := HitEvent.new()
	event.hit_direction = _character.global_basis.z  # Away from character = from back
	event.hit_bone_region = "torso"
	_flinch.on_hit(event)
	assert_signal_emitted(_flinch, "flinch_triggered")
