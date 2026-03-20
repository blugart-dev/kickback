extends GutTest

var _character: Node3D
var _flinch: FlinchController


func before_each():
	_character = preload("res://assets/characters/ybot/ybot.tscn").instantiate()
	add_child_autofree(_character)

	_flinch = FlinchController.new()
	_flinch.name = "FlinchController"
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


func test_hit_from_left_emits_flinch_left():
	watch_signals(_flinch)
	var event := HitEvent.new()
	event.hit_direction = -_character.global_basis.x
	event.hit_bone_region = "torso"
	_flinch.on_hit(event)
	assert_signal_emitted_with_parameters(_flinch, "flinch_triggered", [FlinchController.Direction.LEFT])


func test_hit_from_right_emits_flinch_right():
	watch_signals(_flinch)
	var event := HitEvent.new()
	event.hit_direction = _character.global_basis.x
	event.hit_bone_region = "torso"
	_flinch.on_hit(event)
	assert_signal_emitted_with_parameters(_flinch, "flinch_triggered", [FlinchController.Direction.RIGHT])


func test_headshot_emits_flinch_head():
	watch_signals(_flinch)
	var event := HitEvent.new()
	event.hit_direction = -_character.global_basis.z
	event.hit_bone_region = "head"
	_flinch.on_hit(event)
	assert_signal_emitted_with_parameters(_flinch, "flinch_triggered", [FlinchController.Direction.HEAD])


func test_flinch_front_signal_carries_correct_value():
	watch_signals(_flinch)
	var event := HitEvent.new()
	event.hit_direction = -_character.global_basis.z
	event.hit_bone_region = "torso"
	_flinch.on_hit(event)
	assert_signal_emitted_with_parameters(_flinch, "flinch_triggered", [FlinchController.Direction.FRONT])


func test_near_zero_direction_defaults_to_front():
	watch_signals(_flinch)
	var event := HitEvent.new()
	event.hit_direction = Vector3.UP  # Pure vertical — horizontal component is zero
	event.hit_bone_region = "torso"
	_flinch.on_hit(event)
	assert_signal_emitted_with_parameters(_flinch, "flinch_triggered", [FlinchController.Direction.FRONT])
