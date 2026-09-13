## Records what every Kickback character does, per physics tick, to a JSON-lines
## file — the bridge between "I saw it wobble in the editor" and a number that can
## be analysed offline (tools/bench/trace_report.py). Add it anywhere in the scene
## (the demos add it next to the debug HUD) and press [member toggle_key] (F5) to
## start / stop; or call [method start] / [method stop] from code.
##
## Per tick, per character: state, balance ratio, pelvis position / velocity, the
## worst body orientation error (deg) and which body, the lowest body point, the
## root motor command / force limit, the foot-IK pelvis offset, plus the engine's
## frame pacing (process fps, physics steps that frame). Files land in
## `user://kickback_traces/` as `trace_<unix time>.jsonl`; the path is printed.
@icon("res://addons/kickback/icons/kickback_manager.svg")
class_name KickbackTraceRecorder
extends Node

## Key that toggles recording (unhandled input).
@export var toggle_key: Key = KEY_F5
## Record every Nth physics tick (1 = every tick).
@export_range(1, 60) var every_n_ticks: int = 1
## Also record every joint's motor command magnitude and force limit (bigger files).
@export var record_joints: bool = false

var _file: FileAccess = null
var _path: String = ""
var _tick: int = 0
var _start_usec: int = 0
var _last_process_usec: int = 0
var _physics_steps_this_frame: int = 0

signal recording_started(path: String)
signal recording_stopped(path: String, ticks: int)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == toggle_key:
		if is_recording():
			stop()
		else:
			start()


func is_recording() -> bool:
	return _file != null


## Starts a new trace file. Returns the file path ("" on failure).
func start(path: String = "") -> String:
	if _file:
		stop()
	if path.is_empty():
		path = "user://kickback_traces/trace_%d.jsonl" % int(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	_file = FileAccess.open(path, FileAccess.WRITE)
	if not _file:
		push_error("KickbackTraceRecorder: cannot open '%s' (%s)" % [path, error_string(FileAccess.get_open_error())])
		return ""
	_path = ProjectSettings.globalize_path(path)
	_tick = 0
	_start_usec = Time.get_ticks_usec()
	_file.store_line(JSON.stringify({
		"header": true, "godot": Engine.get_version_info().string,
		"physics_hz": Engine.physics_ticks_per_second, "physics_engine": ProjectSettings.get_setting("physics/3d/physics_engine"),
		"scene": get_tree().current_scene.scene_file_path if get_tree().current_scene else "",
	}))
	print("KickbackTraceRecorder: recording to %s (press %s to stop)" % [_path, OS.get_keycode_string(toggle_key)])
	recording_started.emit(_path)
	return _path


## Stops and closes the trace. Returns the file path.
func stop() -> String:
	if not _file:
		return ""
	_file.close()
	_file = null
	print("KickbackTraceRecorder: stopped after %d ticks -> %s" % [_tick, _path])
	recording_stopped.emit(_path, _tick)
	return _path


func _process(_delta: float) -> void:
	_physics_steps_this_frame = 0


func _physics_process(delta: float) -> void:
	_physics_steps_this_frame += 1
	if not _file:
		return
	_tick += 1
	if _tick % every_n_ticks != 0:
		return
	var row := {
		"t": float(Time.get_ticks_usec() - _start_usec) / 1e6,
		"tick": _tick,
		"dt": delta,
		"fps": Engine.get_frames_per_second(),
		"steps_this_frame": _physics_steps_this_frame,
		"chars": [],
	}
	for kc: KickbackCharacter in get_tree().get_nodes_in_group("kickback_characters") if get_tree().has_group("kickback_characters") else _find_characters():
		var entry := _sample(kc)
		if not entry.is_empty():
			(row.chars as Array).append(entry)
	_file.store_line(JSON.stringify(row))


func _find_characters() -> Array:
	return get_tree().root.find_children("*", "KickbackCharacter", true, false)


func _sample(kc: KickbackCharacter) -> Dictionary:
	if not is_instance_valid(kc) or not kc.is_setup_complete():
		return {}
	var ctrl := kc.get_active_controller()
	var parent := kc.get_parent()
	var builder: PhysicsRigBuilder = parent.find_child("PhysicsRigBuilder", false, false)
	var spring: SpringResolver = parent.find_child("SpringResolver", false, false)
	var skel: Skeleton3D = KickbackSetup.find_skeleton(parent)
	if not ctrl or not builder or not spring or not skel:
		return {}
	var bodies: Dictionary = builder.get_bodies()
	var root_rig := ctrl.get_root_rig()
	var hips: RigidBody3D = bodies.get(root_rig)
	if not hips:
		return {}
	var sg := skel.global_transform
	var worst := 0.0
	var worst_name := ""
	var low := INF
	var low_name := ""
	var joints: Dictionary = {}
	for rig: String in bodies:
		var b: RigidBody3D = bodies[rig]
		var idx: int = skel.find_bone(builder.get_bone_name_for_body(rig))
		var target: Basis = (sg * spring.get_animation_bone_global(idx)).basis.orthonormalized()
		var q := (target * b.global_basis.orthonormalized().inverse()).get_rotation_quaternion()
		if q.w < 0.0:
			q = -q
		var e := rad_to_deg(2.0 * acos(clampf(q.w, -1.0, 1.0)))
		if e > worst:
			worst = e
			worst_name = rig
		if b.global_position.y < low:
			low = b.global_position.y
			low_name = rig
		if record_joints:
			var cmd: Dictionary = spring.get_motor_command(rig)
			if not cmd.is_empty():
				joints[rig] = [snappedf((cmd.target as Vector3).length(), 0.001), snappedf(float(cmd.limit), 0.1), snappedf(e, 0.1)]
	var root_cmd: Dictionary = spring.get_motor_command(root_rig)
	var st: Dictionary = spring._bones.get(root_rig, {})
	var entry := {
		"name": parent.name,
		"state": ctrl.get_state_name(),
		"balance": snappedf(ctrl.get_balance_ratio(), 0.001),
		"hips": [snappedf(hips.global_position.x, 0.001), snappedf(hips.global_position.y, 0.0001), snappedf(hips.global_position.z, 0.001)],
		"hips_v": [snappedf(hips.linear_velocity.x, 0.001), snappedf(hips.linear_velocity.y, 0.001), snappedf(hips.linear_velocity.z, 0.001)],
		"hips_target_y": snappedf((st.get("target_xform", Transform3D.IDENTITY) as Transform3D).origin.y, 0.0001) if not st.is_empty() else null,
		"worst_err": snappedf(worst, 0.1), "worst_body": worst_name,
		"lowest_y": snappedf(low, 0.001), "lowest_body": low_name,
		"root_cmd": snappedf((root_cmd.get("target", Vector3.ZERO) as Vector3).length(), 0.001) if not root_cmd.is_empty() else null,
		"root_limit": snappedf(float(root_cmd.get("limit", 0.0)), 0.1) if not root_cmd.is_empty() else null,
		"motor_mode": spring.is_motor_mode(),
		"pelvis_offset": snappedf(ctrl._foot_ik._pelvis_offset, 0.0001) if ctrl._foot_ik else null,
		"fatigue": snappedf(ctrl.get_fatigue(), 0.01),
		"pain": snappedf(ctrl.get_pain(), 0.01),
	}
	if record_joints:
		entry["joints"] = joints
	return entry
