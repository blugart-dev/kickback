extends Node3D

var _profiles: Array[ImpactProfile] = []
var _weapon_names := PackedStringArray(["Bullet", "Melee", "Arrow", "Shotgun", "Explosion"])
var _weapon_idx: int = 0

var _kickback: KickbackCharacter
var _char_root: Node3D
var _log_label: Label
var _log_lines: PackedStringArray = []
const MAX_LOG := 15

# Camera orbit
var _cam: Camera3D
var _cam_distance: float = 4.0
var _cam_yaw: float = 0.0
var _cam_pitch: float = -15.0
var _dragging: bool = false

var _weapon_label: Label


func _ready() -> void:
	_cam = $Camera3D
	_weapon_label = $HUD/WeaponLabel
	_log_label = $HUD/LogLabel

	_profiles = [
		ImpactProfile.create_bullet(),
		ImpactProfile.create_melee(),
		ImpactProfile.create_arrow(),
		ImpactProfile.create_shotgun(),
		ImpactProfile.create_explosion(),
	]
	# Boost bullet for visible reactions
	_profiles[0].base_impulse = 15.0
	_profiles[0].impulse_transfer_ratio = 0.55
	_profiles[0].strength_spread = 3

	_char_root = $Character
	_kickback = _setup_active(_char_root)

	# Connect all signals for visualization
	if _kickback:
		var active_ctrl: ActiveRagdollController = null
		for sibling in _char_root.get_children():
			if sibling is ActiveRagdollController:
				active_ctrl = sibling
				break

		if active_ctrl:
			active_ctrl.hit_absorbed.connect(_on_hit_absorbed)
			active_ctrl.stagger_started.connect(_on_stagger_started)
			active_ctrl.stagger_finished.connect(_on_stagger_finished)
			active_ctrl.ragdoll_started.connect(_on_ragdoll_started)
			active_ctrl.recovery_started.connect(_on_recovery_started)
			active_ctrl.recovery_finished.connect(_on_recovery_finished)
			active_ctrl.state_changed.connect(_on_state_changed)

	# Debug gizmos
	var debug_hud := StrengthDebugHUD.new()
	debug_hud.name = "StrengthDebugHUD"
	debug_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(debug_hud)

	_update_weapon_label()


func _setup_active(char_root: Node3D) -> KickbackCharacter:
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

	var tuning := RagdollTuning.create_default()
	tuning.stagger_strength_floor = 0.20
	tuning.stagger_duration = 0.9

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


# --- Signal handlers ---

func _on_hit_absorbed(rig_name: String, new_strength: float) -> void:
	_spawn_popup("hit_absorbed: %s (%.2f)" % [rig_name, new_strength], Color(0.3, 0.9, 0.3))
	_log("hit_absorbed(%s, %.2f)" % [rig_name, new_strength])

func _on_stagger_started(hit_dir: Vector3) -> void:
	_spawn_popup("stagger_started", Color(1.0, 0.6, 0.2))
	_log("stagger_started(dir: %.1f, %.1f, %.1f)" % [hit_dir.x, hit_dir.y, hit_dir.z])

func _on_stagger_finished() -> void:
	_spawn_popup("stagger_finished", Color(1.0, 0.6, 0.2))
	_log("stagger_finished()")

func _on_ragdoll_started() -> void:
	_spawn_popup("ragdoll_started", Color(0.9, 0.2, 0.2))
	_log("ragdoll_started()")

func _on_recovery_started(face_up: bool) -> void:
	_spawn_popup("recovery_started (face_%s)" % ("up" if face_up else "down"), Color(0.9, 0.8, 0.2))
	_log("recovery_started(face_up=%s)" % face_up)

func _on_recovery_finished() -> void:
	_spawn_popup("recovery_finished", Color(0.3, 0.9, 0.3))
	_log("recovery_finished()")

func _on_state_changed(new_state: int) -> void:
	var state_names := ["NORMAL", "STAGGER", "RAGDOLL", "GETTING_UP", "PERSISTENT"]
	var state_label: String = state_names[new_state] if new_state < state_names.size() else "?"
	_log("state_changed → %s" % state_label)


func _spawn_popup(text: String, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 24
	label.outline_size = 6
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	add_child(label)
	var start_pos := _char_root.global_position + Vector3(0, 2.5, 0)
	label.global_position = start_pos

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position", start_pos + Vector3(0, 1.5, 0), 2.0)
	tween.tween_property(label, "modulate:a", 0.0, 2.0).set_delay(0.5)
	tween.chain().tween_callback(label.queue_free)


func _log(msg: String) -> void:
	_log_lines.append(msg)
	if _log_lines.size() > MAX_LOG:
		_log_lines = _log_lines.slice(_log_lines.size() - MAX_LOG)
	if _log_label:
		_log_label.text = "\n".join(_log_lines)


# --- Input ---

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					KickbackRaycast.shoot_from_camera(
						get_viewport(), mb.position, _profiles[_weapon_idx])
			MOUSE_BUTTON_RIGHT:
				_dragging = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_cam_distance = maxf(_cam_distance - 0.5, 1.5)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_cam_distance = minf(_cam_distance + 0.5, 10.0)

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
				if _kickback: _kickback.trigger_ragdoll()
			KEY_T:
				if _kickback: _kickback.trigger_stagger(-_cam.global_basis.z)


func _physics_process(_delta: float) -> void:
	if not _cam:
		return
	var pivot := _char_root.global_position + Vector3(0, 1.0, 0) if _char_root else Vector3(0, 1, 0)
	var yaw_rad := deg_to_rad(_cam_yaw)
	var pitch_rad := deg_to_rad(_cam_pitch)
	var offset := Vector3(
		sin(yaw_rad) * cos(pitch_rad),
		-sin(pitch_rad),
		cos(yaw_rad) * cos(pitch_rad),
	) * _cam_distance
	_cam.global_position = pivot + offset
	_cam.look_at(pivot)


func _set_weapon(idx: int) -> void:
	_weapon_idx = clampi(idx, 0, _profiles.size() - 1)
	_update_weapon_label()

func _update_weapon_label() -> void:
	if _weapon_label:
		_weapon_label.text = "Weapon: %s  [1-5]" % _weapon_names[_weapon_idx]
