extends Node3D

const DemoHelpers := preload("res://demo/demo_helpers.gd")
const OrbitCamera := preload("res://demo/orbit_camera.gd")

const MAX_LOG := 15

var _profiles: Array[ImpactProfile] = []
var _weapon_names := PackedStringArray(["Bullet", "Melee", "Arrow", "Shotgun", "Explosion"])
var _weapon_idx: int = 0

var _kickback: KickbackCharacter
var _char_root: Node3D
var _hud_log: DemoHelpers.LogPanel

# Camera orbit
var _cam: Camera3D
var _orbit: OrbitCamera

var _weapon_label: Label


func _ready() -> void:
	_cam = $Camera3D
	_orbit = OrbitCamera.new(_cam, 4.0, -15.0, 0.5, 1.5, 10.0)
	_weapon_label = $HUD/WeaponLabel
	_hud_log = DemoHelpers.LogPanel.new($HUD/LogLabel, MAX_LOG)

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
		var active_ctrl := _kickback.get_active_controller()
		if active_ctrl:
			active_ctrl.hit_absorbed.connect(_on_hit_absorbed)
			active_ctrl.stagger_started.connect(_on_stagger_started)
			active_ctrl.stagger_finished.connect(_on_stagger_finished)
			active_ctrl.ragdoll_started.connect(_on_ragdoll_started)
			active_ctrl.recovery_started.connect(_on_recovery_started)
			active_ctrl.recovery_finished.connect(_on_recovery_finished)
			active_ctrl.state_changed.connect(_on_state_changed)
			active_ctrl.balance_changed.connect(_on_balance_changed)
			active_ctrl.fatigue_changed.connect(_on_fatigue_changed)
			active_ctrl.pain_changed.connect(_on_pain_changed)
			active_ctrl.recovery_interrupted.connect(_on_recovery_interrupted)
			active_ctrl.region_injured.connect(_on_region_injured)
			active_ctrl.threat_anticipated.connect(_on_threat_anticipated)

	# Debug gizmos
	DemoHelpers.add_debug_hud(self)

	_weapon_idx = DemoHelpers.select_weapon(_weapon_idx, _weapon_names, _weapon_label)


func _setup_active(char_root: Node3D) -> KickbackCharacter:
	return DemoHelpers.build_active_rig(char_root)


# --- Signal handlers ---

func _on_hit_absorbed(rig_name: String, new_strength: float) -> void:
	_spawn_popup("hit_absorbed: %s (%.2f)" % [rig_name, new_strength], Color(0.3, 0.9, 0.3))
	_hud_log.add("hit_absorbed(%s, %.2f)" % [rig_name, new_strength])

func _on_stagger_started(hit_dir: Vector3) -> void:
	_spawn_popup("stagger_started", Color(1.0, 0.6, 0.2))
	_hud_log.add("stagger_started(dir: %.1f, %.1f, %.1f)" % [hit_dir.x, hit_dir.y, hit_dir.z])

func _on_stagger_finished() -> void:
	_spawn_popup("stagger_finished", Color(1.0, 0.6, 0.2))
	_hud_log.add("stagger_finished()")

func _on_ragdoll_started() -> void:
	_spawn_popup("ragdoll_started", Color(0.9, 0.2, 0.2))
	_hud_log.add("ragdoll_started()")

func _on_recovery_started(face_up: bool) -> void:
	_spawn_popup("recovery_started (face_%s)" % ("up" if face_up else "down"), Color(0.9, 0.8, 0.2))
	_hud_log.add("recovery_started(face_up=%s)" % face_up)

func _on_recovery_finished() -> void:
	_spawn_popup("recovery_finished", Color(0.3, 0.9, 0.3))
	_hud_log.add("recovery_finished()")

func _on_state_changed(new_state: int) -> void:
	var state_names := ["NORMAL", "STAGGER", "RAGDOLL", "GETTING_UP", "PERSISTENT"]
	var state_label: String = state_names[new_state] if new_state < state_names.size() else "?"
	_hud_log.add("state_changed → %s" % state_label)

func _on_balance_changed(ratio: float) -> void:
	if ratio > 0.4:  # Only show when notably off-balance
		_hud_log.add("balance_changed(%.2f)" % ratio)

func _on_fatigue_changed(level: float) -> void:
	_spawn_popup("fatigue: %.0f%%" % (level * 100), Color(0.7, 0.4, 0.9))
	_hud_log.add("fatigue_changed(%.2f)" % level)

func _on_pain_changed(level: float) -> void:
	if level > 0.1:  # Skip tiny pain
		_hud_log.add("pain_changed(%.2f)" % level)

func _on_recovery_interrupted() -> void:
	_spawn_popup("RECOVERY INTERRUPTED!", Color(1.0, 0.2, 0.2))
	_hud_log.add("recovery_interrupted()")

func _on_region_injured(rig_name: String, severity: float) -> void:
	_spawn_popup("injured: %s (%.0f%%)" % [rig_name, severity * 100], Color(0.9, 0.4, 0.2))
	_hud_log.add("region_injured(%s, %.2f)" % [rig_name, severity])

func _on_threat_anticipated(direction: Vector3, urgency: float) -> void:
	_spawn_popup("threat! (%.1f)" % urgency, Color(1.0, 1.0, 0.3))
	_hud_log.add("threat_anticipated(urgency=%.1f)" % urgency)


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


# --- Input ---

func _unhandled_input(event: InputEvent) -> void:
	if _orbit.handle_input(event):
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			KickbackRaycast.shoot_from_camera(
				get_viewport(), mb.position, _profiles[_weapon_idx])

	elif event is InputEventKey and event.pressed:
		var key := (event as InputEventKey).keycode
		_weapon_idx = DemoHelpers.select_weapon_by_key(key, _weapon_idx, _weapon_names, _weapon_label)
		match key:
			KEY_R:
				if _kickback: _kickback.trigger_ragdoll()
			KEY_T:
				if _kickback: _kickback.trigger_stagger(-_cam.global_basis.z)


func _physics_process(_delta: float) -> void:
	var pivot := _char_root.global_position + Vector3(0, 1.0, 0) if _char_root else Vector3(0, 1, 0)
	_orbit.update(pivot)
