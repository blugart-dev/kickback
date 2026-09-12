## Demo: FPS shooting range. Walk around with WASD + mouse. Left-click fires the
## selected hitscan weapon (5 profiles); right-click throws a velocity-scaled
## physics ball (alt-fire). Characters stagger, ragdoll, and recover from hits.
extends CharacterBody3D

const DemoHelpers := preload("res://demo/demo_helpers.gd")

const SPEED := 5.0
const MOUSE_SENSITIVITY := 0.002

# Ball alt-fire
const BALL_RADIUS := 0.12
const BALL_MASS := 2.0
const BALL_LIFETIME := 6.0
const THROW_MIN := 5.0
const THROW_MAX := 30.0
## Projectiles live on UI layer 2 (see KickbackLayers / GODOT_CONSTRAINTS.md
## "Collision layers"); the plugin only names the layers it owns.
const BALL_LAYER := 1 << 1

var _profiles: Array[ImpactProfile] = []
var _weapon_names := PackedStringArray(["Bullet", "Melee", "Arrow", "Shotgun", "Explosion"])
var _weapon_idx: int = 0
var _throw_strength: float = 15.0

var _cam: Camera3D
var _weapon_label: Label
var _throw_label: Label
var _mouse_captured: bool = false


func _ready() -> void:
	_cam = $Camera3D
	_weapon_label = $"../HUD/WeaponLabel"
	_throw_label = $"../HUD/ThrowLabel"

	# Cranked profiles for the demo — big visible physics reactions
	_profiles = DemoHelpers.create_cranked_profiles()

	# Set up each character with Active Ragdoll
	var targets := get_node("../Targets")
	for i in targets.get_child_count():
		var char_root: Node3D = targets.get_child(i)
		_setup_active(char_root)

	# Debug gizmos
	DemoHelpers.add_debug_hud(get_node("../HUD"))

	_capture_mouse()
	_weapon_idx = DemoHelpers.select_weapon(_weapon_idx, _weapon_names, _weapon_label)
	_update_throw_label()


func _setup_active(char_root: Node3D) -> void:
	DemoHelpers.build_active_rig(char_root)


func _capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_mouse_captured = true


func _release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_mouse_captured = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _mouse_captured:
		var mm := event as InputEventMouseMotion
		rotate_y(-mm.relative.x * MOUSE_SENSITIVITY)
		_cam.rotate_x(-mm.relative.y * MOUSE_SENSITIVITY)
		_cam.rotation.x = clampf(_cam.rotation.x, -1.4, 1.4)

	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if _mouse_captured:
					var screen_center := get_viewport().get_visible_rect().size / 2.0
					KickbackRaycast.shoot_from_camera(
						get_viewport(), screen_center, _profiles[_weapon_idx])
				else:
					_capture_mouse()
			MOUSE_BUTTON_RIGHT:
				if _mouse_captured:
					_throw_ball()
			MOUSE_BUTTON_WHEEL_UP:
				_throw_strength = minf(_throw_strength + 2.0, THROW_MAX)
				_update_throw_label()
			MOUSE_BUTTON_WHEEL_DOWN:
				_throw_strength = maxf(_throw_strength - 2.0, THROW_MIN)
				_update_throw_label()

	elif event is InputEventKey and event.pressed:
		var key := (event as InputEventKey).keycode
		_weapon_idx = DemoHelpers.select_weapon_by_key(key, _weapon_idx, _weapon_names, _weapon_label)
		match key:
			KEY_P:
				# Toggle persistent on nearest character
				var nearest := _get_nearest_kickback()
				if nearest:
					if nearest.is_ragdolled():
						nearest.set_persistent(false)
					else:
						nearest.set_persistent(true)
			KEY_ESCAPE:
				if _mouse_captured:
					_release_mouse()
				else:
					_capture_mouse()


func _physics_process(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity.y -= 9.8 * delta

	# Movement
	var input_dir := Vector2.ZERO
	if _mouse_captured:
		if Input.is_key_pressed(KEY_W): input_dir.y -= 1
		if Input.is_key_pressed(KEY_S): input_dir.y += 1
		if Input.is_key_pressed(KEY_A): input_dir.x -= 1
		if Input.is_key_pressed(KEY_D): input_dir.x += 1

	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()


# --- Ball alt-fire (velocity-scaled physics impact) ---

func _throw_ball() -> void:
	var ball := RigidBody3D.new()
	ball.mass = BALL_MASS
	ball.collision_layer = BALL_LAYER
	# Hits the ground (layer 1) and the active ragdoll bodies (layer 4)
	ball.collision_mask = KickbackLayers.ENVIRONMENT_LAYER | KickbackLayers.ACTIVE_RAGDOLL_LAYER
	ball.contact_monitor = true
	ball.max_contacts_reported = 4
	ball.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = BALL_RADIUS
	shape.shape = sphere
	ball.add_child(shape)

	var mesh := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = BALL_RADIUS
	sphere_mesh.height = BALL_RADIUS * 2.0
	mesh.mesh = sphere_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.4, 0.1)
	mesh.material_override = mat
	ball.add_child(mesh)

	# Add to tree FIRST, then set world position
	get_parent().add_child(ball)
	ball.global_position = _cam.global_position - _cam.global_basis.z * 0.5
	ball.linear_velocity = -_cam.global_basis.z * _throw_strength

	ball.body_entered.connect(_on_ball_hit.bind(ball))
	get_tree().create_timer(BALL_LIFETIME).timeout.connect(ball.queue_free)


func _on_ball_hit(hit_body: Node, ball: RigidBody3D) -> void:
	if not hit_body is RigidBody3D:
		return
	var character := KickbackRaycast.find_character_owner(hit_body)
	if not character or character.is_ragdolled():
		return

	# Scale impact by ball kinetic energy — harder throw = bigger reaction
	var speed := ball.linear_velocity.length()
	var energy := 0.5 * ball.mass * speed * speed
	var impact_scale := clampf(energy / 80.0, 0.3, 4.0)

	var profile := ImpactProfile.new()
	profile.profile_name = &"Ball"
	profile.base_impulse = 25.0 * impact_scale
	profile.impulse_transfer_ratio = clampf(0.6 * impact_scale, 0.3, 1.0)
	profile.upward_bias = 0.1
	profile.ragdoll_probability = clampf(0.05 * impact_scale, 0.0, 0.5)
	profile.strength_reduction = clampf(0.85 * impact_scale, 0.4, 1.0)
	profile.strength_spread = clampi(int(3 * impact_scale), 2, 10)
	profile.recovery_rate = 0.25

	var hit_dir := ball.linear_velocity.normalized()
	character.receive_hit(hit_body as RigidBody3D, hit_dir, hit_body.global_position, profile)


# --- Utility ---

func _get_nearest_kickback() -> KickbackCharacter:
	var characters := KickbackCharacter.find_all(get_node("../Targets"))
	if characters.is_empty():
		return null
	var my_pos := global_position
	var nearest: KickbackCharacter = null
	var nearest_dist := INF
	for kc: KickbackCharacter in characters:
		var root := kc.get_character_root()
		if not root:
			continue
		var dist := my_pos.distance_to(root.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = kc
	return nearest


func _update_throw_label() -> void:
	if _throw_label:
		_throw_label.text = "Throw: %.0f  [scroll]" % _throw_strength
