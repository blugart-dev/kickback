## Demo: Throw physics balls at NPCs. Characters resist, stagger, and ragdoll
## from accumulated hits. NPCs patrol, react with animations, recover, resume.
extends CharacterBody3D

const SPEED := 5.0
const MOUSE_SENSITIVITY := 0.002
const BALL_RADIUS := 0.12
const BALL_MASS := 2.0
const BALL_LIFETIME := 6.0
const NPC_WALK_SPEED := 1.5

var _cam: Camera3D
var _throw_strength: float = 15.0
var _mouse_captured: bool = false
var _hit_profile: ImpactProfile
var _strength_label: Label
var _scene_root: Node3D

# NPC data: {root, kickback, anim, can_walk, injured_timer, waypoint_a, waypoint_b, walk_target}
var _npcs: Array[Dictionary] = []

var YBOT_SCENE: PackedScene


func _ready() -> void:
	_cam = $Camera3D
	_strength_label = $"../HUD/StrengthLabel"
	_scene_root = get_node("..")
	YBOT_SCENE = load("res://assets/characters/ybot/ybot.tscn")

	_hit_profile = ImpactProfile.new()
	_hit_profile.profile_name = &"Ball"
	_hit_profile.base_impulse = 18.0
	_hit_profile.impulse_transfer_ratio = 0.6
	_hit_profile.upward_bias = 0.05
	_hit_profile.ragdoll_probability = 0.2
	_hit_profile.strength_reduction = 0.75
	_hit_profile.strength_spread = 3
	_hit_profile.recovery_rate = 0.3

	# Set up NPCs with patrol routes
	var targets := get_node("../Targets")
	for i in targets.get_child_count():
		var char_root: Node3D = targets.get_child(i)
		_setup_npc(char_root, i)

	# Debug gizmos
	var debug_hud := StrengthDebugHUD.new()
	debug_hud.name = "StrengthDebugHUD"
	debug_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_node("../HUD").add_child(debug_hud)

	_capture_mouse()
	_update_strength_label()


func _setup_npc(char_root: Node3D, idx: int) -> void:
	var ybot_name := ""
	for child in char_root.get_children():
		if _find_child_of_type(child, "Skeleton3D"):
			ybot_name = child.name
			break
	if ybot_name.is_empty():
		return

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
	# Very reactive — bodies swing freely on hits, springs barely resist
	tuning.stagger_strength_floor = 0.08
	tuning.stagger_duration = 1.2
	tuning.stagger_threshold = 0.7  # Stagger triggers easily
	tuning.recovery_rate = 0.15  # Slow recovery — long wobble
	tuning.max_angular_velocity = 30.0  # Bodies can spin faster
	tuning.max_linear_velocity = 15.0  # Bodies can fly further
	tuning.strength_map = {
		"Hips": 0.25, "Spine": 0.20, "Chest": 0.20,
		"Head": 0.12,
		"UpperArm_L": 0.15, "LowerArm_L": 0.10, "Hand_L": 0.06,
		"UpperArm_R": 0.15, "LowerArm_R": 0.10, "Hand_R": 0.06,
		"UpperLeg_L": 0.22, "LowerLeg_L": 0.15, "Foot_L": 0.08,
		"UpperLeg_R": 0.22, "LowerLeg_R": 0.15, "Foot_R": 0.08,
	}
	tuning.pin_strength_overrides = {"Hips": 0.25, "Foot_L": 0.08, "Foot_R": 0.08}
	tuning.default_pin_strength = 0.02
	# Legs stay animated — upper body reacts, feet stay planted
	tuning.protected_bones = PackedStringArray([
		"UpperLeg_L", "UpperLeg_R", "LowerLeg_L", "LowerLeg_R", "Foot_L", "Foot_R"
	])

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

	var anim: AnimationPlayer = _find_child_of_type(char_root, "AnimationPlayer")

	# Connect signals for animation
	ac.ragdoll_started.connect(_on_ragdoll_started.bind(idx))
	ac.recovery_started.connect(_on_recovery_started.bind(idx))
	ac.recovery_finished.connect(_on_recovery_finished.bind(idx))

	# Each NPC patrols a short route near their start position
	var start_pos := char_root.global_position
	var wp_a := start_pos + Vector3(-2, 0, 0)
	var wp_b := start_pos + Vector3(2, 0, 0)

	# Defer walk start so it overrides ybot's autoplay idle
	if anim:
		anim.play.call_deferred("walk")

	_npcs.append({
		"root": char_root,
		"kickback": kc,
		"anim": anim,
		"can_walk": true,
		"injured_timer": 0.0,
		"waypoint_a": wp_a,
		"waypoint_b": wp_b,
		"walk_target": wp_b,
	})


# --- NPC Signal Handlers ---

func _on_ragdoll_started(idx: int) -> void:
	_npcs[idx].can_walk = false


func _on_recovery_started(face_up: bool, idx: int) -> void:
	var anim: AnimationPlayer = _npcs[idx].anim
	if anim:
		anim.play("get_up_face_up" if face_up else "get_up_face_down")


func _on_recovery_finished(idx: int) -> void:
	var npc: Dictionary = _npcs[idx]
	npc.can_walk = true
	npc.injured_timer = 3.0
	var anim: AnimationPlayer = npc.anim
	if anim:
		anim.play("injured_walk")


# --- Ball Throwing ---

func _throw_ball() -> void:
	var ball := RigidBody3D.new()
	ball.mass = BALL_MASS
	ball.collision_layer = 2
	ball.collision_mask = 10
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

	# Add to tree FIRST, then set position
	_scene_root.add_child(ball)
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

	# Scale impact by ball's kinetic energy — harder throw = bigger reaction
	var speed := ball.linear_velocity.length()
	var energy := 0.5 * ball.mass * speed * speed
	var impact_scale := clampf(energy / 80.0, 0.3, 4.0)

	var profile := ImpactProfile.new()
	profile.profile_name = &"Ball"
	profile.base_impulse = 25.0 * impact_scale
	profile.impulse_transfer_ratio = clampf(0.6 * impact_scale, 0.3, 1.0)
	profile.upward_bias = 0.1
	profile.ragdoll_probability = clampf(0.03 * impact_scale, 0.0, 0.5)  # Very low — resist first
	profile.strength_reduction = clampf(0.85 * impact_scale, 0.4, 1.0)
	profile.strength_spread = clampi(int(3 * impact_scale), 2, 10)
	profile.recovery_rate = 0.15  # Slow — stay wobbly longer

	var hit_dir := ball.linear_velocity.normalized()
	character.receive_hit(hit_body as RigidBody3D, hit_dir, hit_body.global_position, profile)


# --- Utility ---

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


# --- Input ---

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _mouse_captured:
		var mm := event as InputEventMouseMotion
		rotate_y(-mm.relative.x * MOUSE_SENSITIVITY)
		_cam.rotate_x(-mm.relative.y * MOUSE_SENSITIVITY)
		_cam.rotation.x = clampf(_cam.rotation.x, -1.4, 1.4)

	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			match mb.button_index:
				MOUSE_BUTTON_LEFT:
					if _mouse_captured:
						_throw_ball()
					else:
						_capture_mouse()
				MOUSE_BUTTON_WHEEL_UP:
					_throw_strength = minf(_throw_strength + 2.0, 30.0)
					_update_strength_label()
				MOUSE_BUTTON_WHEEL_DOWN:
					_throw_strength = maxf(_throw_strength - 2.0, 5.0)
					_update_strength_label()

	elif event is InputEventKey and event.pressed:
		match (event as InputEventKey).keycode:
			KEY_ESCAPE:
				if _mouse_captured:
					_release_mouse()
				else:
					_capture_mouse()


# --- Physics Process ---

func _physics_process(delta: float) -> void:
	# Player movement
	if not is_on_floor():
		velocity.y -= 9.8 * delta

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

	# NPC patrol + timers
	for npc: Dictionary in _npcs:
		var root: Node3D = npc.root

		# Injured timer
		if npc.injured_timer > 0.0:
			npc.injured_timer -= delta
			if npc.injured_timer <= 0.0 and npc.can_walk:
				var anim: AnimationPlayer = npc.anim
				if anim:
					anim.play("walk")

		# Walk toward waypoint
		if npc.can_walk:
			var target: Vector3 = npc.walk_target
			var dir := (target - root.global_position)
			dir.y = 0
			if dir.length() < 0.3:
				npc.walk_target = npc.waypoint_b if npc.walk_target == npc.waypoint_a else npc.waypoint_a

			var move_dir := dir.normalized()
			var spd := NPC_WALK_SPEED * (0.4 if npc.injured_timer > 0.0 else 1.0)
			root.global_position += move_dir * spd * delta

			if move_dir.length_squared() > 0.01:
				root.global_rotation.y = atan2(move_dir.x, move_dir.z)


func _update_strength_label() -> void:
	if _strength_label:
		_strength_label.text = "Throw: %.0f  [scroll]" % _throw_strength
