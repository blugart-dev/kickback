extends Node3D

const DemoHelpers := preload("res://demo/demo_helpers.gd")
const OrbitCamera := preload("res://demo/orbit_camera.gd")

const GRID_COLS := 5
const GRID_ROWS := 4
const SPACING := 2.5

var _profile: ImpactProfile
var _explosion: ImpactProfile
var _kickbacks: Array[KickbackCharacter] = []

# Camera orbit
var _cam: Camera3D
var _orbit: OrbitCamera

var _fps_label: Label
var _budget_label: Label
var _budget_slider: HSlider
var _manager: Node

var YBOT_SCENE: PackedScene


func _ready() -> void:
	_cam = $Camera3D
	_orbit = OrbitCamera.new(_cam, 12.0, -35.0, 1.0, 3.0, 30.0, -80.0, 10.0)
	_fps_label = $HUD/FPSLabel
	YBOT_SCENE = load("res://assets/characters/ybot/ybot.tscn")

	_profile = ImpactProfile.create_shotgun()
	_profile.impulse_transfer_ratio = 0.60

	_explosion = ImpactProfile.create_explosion()
	_explosion.base_impulse = 50.0

	# Budget manager
	_manager = load("res://addons/kickback/kickback_manager.gd").new()
	_manager.name = "KickbackManager"
	_manager.max_active_ragdolls = 5
	add_child(_manager)

	# Create grid of characters
	var grid := $Grid
	for row in GRID_ROWS:
		for col in GRID_COLS:
			var char_root := Node3D.new()
			char_root.name = "Char_%d_%d" % [row, col]
			var x := (col - (GRID_COLS - 1) / 2.0) * SPACING
			var z := (row - (GRID_ROWS - 1) / 2.0) * SPACING
			char_root.position = Vector3(x, 0, z)
			grid.add_child(char_root)

			var ybot := YBOT_SCENE.instantiate()
			char_root.add_child(ybot)

			var kc := _setup_active(char_root, ybot.name)
			if kc:
				_kickbacks.append(kc)

	# Budget slider
	_build_budget_slider()

	# Debug gizmos
	DemoHelpers.add_debug_hud(self)


func _setup_active(char_root: Node3D, ybot_name: String) -> KickbackCharacter:
	return DemoHelpers.build_active_rig(char_root, ybot_name)


func _build_budget_slider() -> void:
	var hbox := HBoxContainer.new()

	var label := Label.new()
	label.text = "Max Ragdolls:"
	label.add_theme_font_size_override("font_size", 13)
	hbox.add_child(label)

	_budget_slider = HSlider.new()
	_budget_slider.min_value = 1
	_budget_slider.max_value = 20
	_budget_slider.step = 1
	_budget_slider.value = 5
	_budget_slider.custom_minimum_size.x = 120
	hbox.add_child(_budget_slider)

	_budget_label = Label.new()
	_budget_label.text = "5"
	_budget_label.add_theme_font_size_override("font_size", 13)
	_budget_label.custom_minimum_size.x = 30
	hbox.add_child(_budget_label)

	_budget_slider.value_changed.connect(func(val: float):
		_manager.max_active_ragdolls = int(val)
		_budget_label.text = str(int(val))
	)

	hbox.position = Vector2(10, 40)
	$HUD.add_child(hbox)


func _explode_all() -> void:
	for kc: KickbackCharacter in _kickbacks:
		kc.trigger_ragdoll()


func _unhandled_input(event: InputEvent) -> void:
	if _orbit.handle_input(event):
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			KickbackRaycast.shoot_from_camera(
				get_viewport(), mb.position, _profile)

	elif event is InputEventKey and event.pressed:
		match (event as InputEventKey).keycode:
			KEY_E:
				_explode_all()


func _physics_process(_delta: float) -> void:
	_orbit.update()

	# Update FPS
	if _fps_label:
		_fps_label.text = "FPS: %d | Active: %d/%d" % [
			Engine.get_frames_per_second(),
			_manager.get_active_ragdoll_count() if _manager else 0,
			_manager.max_active_ragdolls if _manager else 0]
