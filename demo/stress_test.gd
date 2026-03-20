extends Node3D

const GRID_COLS := 5
const GRID_ROWS := 4
const SPACING := 2.5

var _profile: ImpactProfile
var _explosion: ImpactProfile
var _kickbacks: Array[KickbackCharacter] = []

# Camera orbit
var _cam: Camera3D
var _cam_distance: float = 12.0
var _cam_yaw: float = 0.0
var _cam_pitch: float = -35.0
var _dragging: bool = false

var _fps_label: Label
var _budget_label: Label
var _budget_slider: HSlider
var _manager: KickbackManager

var YBOT_SCENE: PackedScene


func _ready() -> void:
	_cam = $Camera3D
	_fps_label = $HUD/FPSLabel
	YBOT_SCENE = load("res://assets/characters/ybot/ybot.tscn")

	_profile = ImpactProfile.create_shotgun()
	_profile.impulse_transfer_ratio = 0.60

	_explosion = ImpactProfile.create_explosion()
	_explosion.base_impulse = 50.0

	# Budget manager
	_manager = KickbackManager.new()
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
	var debug_hud := StrengthDebugHUD.new()
	debug_hud.name = "StrengthDebugHUD"
	debug_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(debug_hud)


func _setup_active(char_root: Node3D, ybot_name: String) -> KickbackCharacter:
	var skel_path := NodePath("../%s/Skeleton3D" % ybot_name)
	var root_path := NodePath("..")
	var builder_path := NodePath("../PhysicsRigBuilder")
	var spring_path := NodePath("../SpringResolver")

	var rb := PhysicsRigBuilder.new()
	rb.name = "PhysicsRigBuilder"
	rb.skeleton_path = skel_path
	var rs := PhysicsRigSync.new()
	rs.name = "PhysicsRigSync"
	rs.skeleton_path = skel_path
	rs.rig_builder_path = builder_path
	var sp := SpringResolver.new()
	sp.name = "SpringResolver"
	sp.skeleton_path = skel_path
	sp.rig_builder_path = builder_path
	var ac := ActiveRagdollController.new()
	ac.name = "ActiveRagdollController"
	ac.spring_resolver_path = spring_path
	ac.rig_builder_path = builder_path
	ac.character_root_path = root_path

	var tuning := RagdollTuning.create_default()
	tuning.stagger_strength_floor = 0.20

	var kc := KickbackCharacter.new()
	kc.name = "KickbackCharacter"
	kc.skeleton_path = skel_path
	kc.character_root_path = root_path
	kc.ragdoll_profile = RagdollProfile.create_mixamo_default()
	kc.ragdoll_tuning = tuning

	char_root.add_child(rb)
	char_root.add_child(rs)
	char_root.add_child(sp)
	char_root.add_child(ac)
	char_root.add_child(kc)
	return kc


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
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					KickbackRaycast.shoot_from_camera(
						get_viewport(), mb.position, _profile)
			MOUSE_BUTTON_RIGHT:
				_dragging = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_cam_distance = maxf(_cam_distance - 1.0, 3.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_cam_distance = minf(_cam_distance + 1.0, 30.0)

	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_cam_yaw -= mm.relative.x * 0.3
		_cam_pitch = clampf(_cam_pitch - mm.relative.y * 0.3, -80.0, 10.0)

	elif event is InputEventKey and event.pressed:
		match (event as InputEventKey).keycode:
			KEY_E:
				_explode_all()


func _physics_process(_delta: float) -> void:
	if not _cam:
		return
	var pivot := Vector3(0, 1.0, 0)
	var yaw_rad := deg_to_rad(_cam_yaw)
	var pitch_rad := deg_to_rad(_cam_pitch)
	var offset := Vector3(
		sin(yaw_rad) * cos(pitch_rad),
		-sin(pitch_rad),
		cos(yaw_rad) * cos(pitch_rad),
	) * _cam_distance
	_cam.global_position = pivot + offset
	_cam.look_at(pivot)

	# Update FPS
	if _fps_label:
		_fps_label.text = "FPS: %d | Active: %d/%d" % [
			Engine.get_frames_per_second(),
			_manager.get_active_ragdoll_count() if _manager else 0,
			_manager.max_active_ragdolls if _manager else 0]
