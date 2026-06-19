## Demo: FPS shooting range. Walk around with WASD + mouse. Left-click fires the
## selected hitscan weapon (5 profiles); right-click throws a velocity-scaled
## physics ball (alt-fire). Characters stagger, ragdoll, and recover from hits.
extends CharacterBody3D

const SPEED := 5.0
const MOUSE_SENSITIVITY := 0.002

# Ball alt-fire
const BALL_RADIUS := 0.12
const BALL_MASS := 2.0
const BALL_LIFETIME := 6.0
const THROW_MIN := 5.0
const THROW_MAX := 30.0

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
	_profiles = [
		_make_profile(&"Bullet",    15.0, 0.55, 0.0,  0.05, 0.90, 3, 0.35),
		_make_profile(&"Melee",     22.0, 0.80, 0.05, 0.15, 0.92, 4, 0.25),
		_make_profile(&"Arrow",     18.0, 0.60, 0.0,  0.10, 0.90, 2, 0.3),
		_make_profile(&"Shotgun",   30.0, 0.65, 0.10, 0.40, 0.95, 5, 0.20),
		_make_profile(&"Explosion", 50.0, 1.00, 0.50, 0.95, 1.0, 99, 0.12),
	]

	# Set up each character with Active Ragdoll
	var targets := get_node("../Targets")
	for i in targets.get_child_count():
		var char_root: Node3D = targets.get_child(i)
		_setup_active(char_root)

	# Debug gizmos
	var debug_hud := StrengthDebugHUD.new()
	debug_hud.name = "StrengthDebugHUD"
	debug_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_node("../HUD").add_child(debug_hud)

	_capture_mouse()
	_update_weapon_label()
	_update_throw_label()


func _setup_active(char_root: Node3D) -> void:
	var ybot_name := _get_ybot_name(char_root)
	if ybot_name.is_empty():
		return

	var skel_path := NodePath("../%s/Skeleton3D" % ybot_name)
	var root_path := NodePath("..")
	var builder_path := NodePath("../PhysicsRigBuilder")
	var spring_path := NodePath("../SpringResolver")

	var rig_builder := PhysicsRigBuilder.new()
	rig_builder.name = "PhysicsRigBuilder"
	rig_builder.skeleton_path = skel_path

	var rig_sync := PhysicsRigSync.new()
	rig_sync.name = "PhysicsRigSync"
	rig_sync.skeleton_path = skel_path
	rig_sync.rig_builder_path = builder_path

	var spring := SpringResolver.new()
	spring.name = "SpringResolver"
	spring.skeleton_path = skel_path
	spring.rig_builder_path = builder_path

	var active_ctrl := ActiveRagdollController.new()
	active_ctrl.name = "ActiveRagdollController"
	active_ctrl.spring_resolver_path = spring_path
	active_ctrl.rig_builder_path = builder_path
	active_ctrl.character_root_path = root_path

	var tuning := RagdollTuning.create_default()

	var kc := KickbackCharacter.new()
	kc.name = "KickbackCharacter"
	kc.skeleton_path = skel_path
	kc.character_root_path = root_path
	kc.ragdoll_profile = RagdollProfile.create_mixamo_default()
	kc.ragdoll_tuning = tuning

	char_root.add_child(rig_builder)
	char_root.add_child(rig_sync)
	char_root.add_child(spring)
	char_root.add_child(active_ctrl)
	char_root.add_child(kc)


func _get_ybot_name(char_root: Node3D) -> String:
	for child in char_root.get_children():
		if _find_child_of_type(child, "Skeleton3D"):
			return child.name
	push_error("ShootingRange: No Skeleton3D found in %s" % char_root.name)
	return ""


func _find_child_of_type(node: Node, type_name: String) -> Node:
	for child in node.get_children():
		if child.get_class() == type_name:
			return child
		var found := _find_child_of_type(child, type_name)
		if found:
			return found
	return null


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
		match key:
			KEY_1: _set_weapon(0)
			KEY_2: _set_weapon(1)
			KEY_3: _set_weapon(2)
			KEY_4: _set_weapon(3)
			KEY_5: _set_weapon(4)
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
	ball.collision_layer = 2
	ball.collision_mask = 10  # ground (layer 2) + active ragdoll (layer 4)
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


func _make_profile(pname: StringName, impulse: float, transfer: float, upward: float,
		ragdoll_prob: float, reduction: float, spread: int, recovery: float) -> ImpactProfile:
	var p := ImpactProfile.new()
	p.profile_name = pname
	p.base_impulse = impulse
	p.impulse_transfer_ratio = transfer
	p.upward_bias = upward
	p.ragdoll_probability = ragdoll_prob
	p.strength_reduction = reduction
	p.strength_spread = spread
	p.recovery_rate = recovery
	return p


func _set_weapon(idx: int) -> void:
	_weapon_idx = clampi(idx, 0, _profiles.size() - 1)
	_update_weapon_label()


func _update_weapon_label() -> void:
	if _weapon_label:
		_weapon_label.text = "Weapon: %s  [1-5]" % _weapon_names[_weapon_idx]


func _update_throw_label() -> void:
	if _throw_label:
		_throw_label.text = "Throw: %.0f  [scroll]" % _throw_strength
