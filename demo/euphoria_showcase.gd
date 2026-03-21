## Euphoria Showcase — demonstrates all v0.6+ features in one scene.
## Left: Sustained fire (pain, fatigue, hit stacking, reaction pulses, bracing)
## Center: Moving target (momentum transfer, movement-aware hits)
## Right: Injuries (regional impairment, micro reactions, threat anticipation)
extends Node3D

const WALK_SPEED := 1.8
const WAYPOINT_A := Vector3(0, 0, -2.5)
const WAYPOINT_B := Vector3(0, 0, 2.5)

var _profiles: Array[ImpactProfile] = []
var _weapon_names := PackedStringArray(["Bullet", "Melee", "Arrow", "Shotgun", "Explosion"])
var _weapon_idx: int = 0

var _kickbacks: Array[KickbackCharacter] = []
var _controllers: Array[ActiveRagdollController] = []
var _char_roots: Array[Node3D] = []

# Moving target
var _walk_target := WAYPOINT_A
var _moving_anim: AnimationPlayer

# Camera orbit
var _cam: Camera3D
var _cam_distance: float = 6.0
var _cam_yaw: float = 0.0
var _cam_pitch: float = -15.0
var _dragging: bool = false

var _weapon_label: Label


func _ready() -> void:
	_cam = $Camera3D
	_weapon_label = $HUD/WeaponLabel

	_profiles = [
		ImpactProfile.create_bullet(),
		ImpactProfile.create_melee(),
		ImpactProfile.create_arrow(),
		ImpactProfile.create_shotgun(),
		ImpactProfile.create_explosion(),
	]
	# Boost bullet so reactions are visible
	_profiles[0].base_impulse = 12.0
	_profiles[0].impulse_transfer_ratio = 0.45
	_profiles[0].strength_spread = 2

	# Setup all 3 characters
	var char_names := ["SustainedFire", "MovingTarget", "Injuries"]
	for i in range(3):
		var char_root: Node3D = get_node(char_names[i])
		_char_roots.append(char_root)
		var kc := _setup_active(char_root, i)
		_kickbacks.append(kc)

	# Find moving target's AnimationPlayer
	_moving_anim = _find_child_of_type(_char_roots[1], "AnimationPlayer")
	if _moving_anim:
		_moving_anim.call_deferred("play", "walk")

	# Debug gizmos
	var debug_hud := StrengthDebugHUD.new()
	debug_hud.name = "StrengthDebugHUD"
	debug_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(debug_hud)


func _setup_active(char_root: Node3D, idx: int) -> KickbackCharacter:
	var ybot_name := ""
	for child in char_root.get_children():
		if _find_child_of_type(child, "Skeleton3D"):
			ybot_name = child.name
			break
	if ybot_name.is_empty():
		return null

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
	_controllers.append(ac)

	var tuning := RagdollTuning.create_default()
	tuning.stagger_strength_floor = 0.20
	tuning.stagger_duration = 1.0

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


func _find_child_of_type(node: Node, type_name: String) -> Node:
	for child in node.get_children():
		if child.get_class() == type_name:
			return child
		var found := _find_child_of_type(child, type_name)
		if found:
			return found
	return null


func _physics_process(delta: float) -> void:
	# Moving target patrol
	if _char_roots.size() > 1:
		var mover := _char_roots[1]
		var pos := mover.global_position
		var dir := _walk_target - pos
		dir.y = 0
		if dir.length() < 0.3:
			_walk_target = WAYPOINT_B if _walk_target == WAYPOINT_A else WAYPOINT_A
		var move_dir := dir.normalized()
		mover.global_position += move_dir * WALK_SPEED * delta
		if move_dir.length_squared() > 0.01:
			mover.global_rotation.y = atan2(move_dir.x, move_dir.z)

	_update_camera()


func _update_camera() -> void:
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


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					# Threat anticipation on the injuries character (right)
					if _kickbacks.size() > 2 and _kickbacks[2]:
						var threat_dir := -_cam.global_basis.z
						_kickbacks[2].anticipate_threat(threat_dir, 0.5)
					KickbackRaycast.shoot_from_camera(
						get_viewport(), mb.position, _profiles[_weapon_idx])
			MOUSE_BUTTON_RIGHT:
				_dragging = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_cam_distance = maxf(_cam_distance - 0.5, 2.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_cam_distance = minf(_cam_distance + 0.5, 15.0)

	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_cam_yaw -= mm.relative.x * 0.3
		_cam_pitch = clampf(_cam_pitch - mm.relative.y * 0.3, -80.0, 80.0)

	elif event is InputEventKey and event.pressed:
		var key := (event as InputEventKey).keycode
		match key:
			KEY_1: _set_weapon(0)
			KEY_2: _set_weapon(1)
			KEY_3: _set_weapon(2)
			KEY_4: _set_weapon(3)
			KEY_5: _set_weapon(4)
			KEY_R:
				for kc: KickbackCharacter in _kickbacks:
					if kc: kc.trigger_ragdoll()
			KEY_T:
				for kc: KickbackCharacter in _kickbacks:
					if kc: kc.trigger_stagger(-_cam.global_basis.z)
			KEY_P:
				# Reset all — clear fatigue, pain, injuries
				for ctrl: ActiveRagdollController in _controllers:
					if ctrl:
						ctrl.reset_fatigue()
						ctrl.reset_pain()
						ctrl.reset_injuries()


func _set_weapon(idx: int) -> void:
	_weapon_idx = clampi(idx, 0, _profiles.size() - 1)
	if _weapon_label:
		_weapon_label.text = "Weapon: %s  [1-5]" % _weapon_names[_weapon_idx]
