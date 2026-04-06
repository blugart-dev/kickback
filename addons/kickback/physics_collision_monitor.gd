## Monitors physics contacts on ragdoll bodies and emits impact events.
## Optional component — add as a sibling to KickbackCharacter. Does NOT
## trigger hit reactions; emits its own signal for scoring, VFX, and sound.
##
## This is completely separate from [method KickbackCharacter.receive_hit].
## Routing [signal body_impact] back through receive_hit() will cause a
## feedback loop — use it only for passive observation (damage numbers,
## particle spawning, audio cues, score tracking).
@icon("res://addons/kickback/icons/physics_rig_builder.svg")
class_name PhysicsCollisionMonitor
extends Node

@export_group("References")
## Path to the KickbackCharacter sibling. If empty, auto-discovers from siblings.
@export var kickback_character_path: NodePath

@export_group("Filtering")
## Minimum impact velocity (m/s) to emit a signal. Contacts below this
## are silently discarded. Prevents spam from gentle resting contacts.
@export_range(0.0, 20.0) var velocity_threshold: float = 2.0
## Per-bone cooldown in seconds. After emitting for a bone, that bone
## is silenced for this duration.
@export_range(0.0, 5.0) var cooldown: float = 0.3
## Which bones to monitor. Empty array = monitor ALL bones.
@export var monitored_bones: PackedStringArray = []
## Filter out contacts between bones of the same ragdoll rig.
@export var filter_self_collisions: bool = true

## Emitted when a monitored ragdoll body impacts the environment.
## [param bone_name] is the rig name (e.g., "Head", "Foot_L").
## [param velocity] is the impact speed in m/s at the moment of contact.
## [param contact_body] is the Node3D that was contacted (e.g., a StaticBody3D).
signal body_impact(bone_name: String, velocity: float, contact_body: Node3D)

var _kickback_char: KickbackCharacter
var _rig_builder: PhysicsRigBuilder
var _connected: bool = false
var _body_to_rig_name: Dictionary = {}       # RigidBody3D → rig_name
var _cooldown_timestamps: Dictionary = {}    # rig_name → last emit time (msec)
var _ragdoll_layer_mask: int = 0


func _ready() -> void:
	if not kickback_character_path.is_empty():
		_kickback_char = get_node_or_null(kickback_character_path) as KickbackCharacter
	else:
		for sibling in get_parent().get_children():
			if sibling is KickbackCharacter:
				_kickback_char = sibling
				break

	if not _kickback_char:
		push_warning("PhysicsCollisionMonitor: no KickbackCharacter found — monitor disabled")
		return

	if _kickback_char.is_setup_complete():
		_connect_to_bodies()
	else:
		_kickback_char.setup_complete.connect(_connect_to_bodies, CONNECT_ONE_SHOT)


func _connect_to_bodies() -> void:
	for sibling in get_parent().get_children():
		if sibling is PhysicsRigBuilder:
			_rig_builder = sibling
			break

	if not _rig_builder:
		push_warning("PhysicsCollisionMonitor: no PhysicsRigBuilder found — monitor disabled")
		return

	var bodies: Dictionary = _rig_builder.get_bodies()
	if bodies.is_empty():
		push_warning("PhysicsCollisionMonitor: PhysicsRigBuilder has no bodies — monitor disabled")
		return

	_ragdoll_layer_mask = _rig_builder.get_tuning().collision_layer

	var monitor_set: Dictionary = {}
	for bone_name: String in monitored_bones:
		monitor_set[bone_name] = true

	for rig_name: String in bodies:
		if not monitor_set.is_empty() and rig_name not in monitor_set:
			continue

		var body: RigidBody3D = bodies[rig_name]
		body.contact_monitor = true
		body.max_contacts_reported = maxf(body.max_contacts_reported, 1)
		_body_to_rig_name[body] = rig_name
		body.body_entered.connect(_on_body_entered.bind(body))

	_connected = true


func _on_body_entered(other_body: Node3D, this_body: RigidBody3D) -> void:
	var rig_name: String = _body_to_rig_name.get(this_body, "")
	if rig_name.is_empty():
		return

	# Filter self-collisions (bone-on-bone from the same rig)
	if filter_self_collisions and other_body is RigidBody3D:
		if other_body.collision_layer & _ragdoll_layer_mask:
			if other_body in _body_to_rig_name:
				return

	# Filter by velocity threshold
	var speed: float = this_body.linear_velocity.length()
	if speed < velocity_threshold:
		return

	# Filter by cooldown
	var now: float = Time.get_ticks_msec()
	var last_time: float = _cooldown_timestamps.get(rig_name, 0.0)
	if (now - last_time) < cooldown * 1000.0:
		return
	_cooldown_timestamps[rig_name] = now

	body_impact.emit(rig_name, speed, other_body)


func _exit_tree() -> void:
	if not _connected:
		return
	for body: RigidBody3D in _body_to_rig_name.keys():
		if is_instance_valid(body):
			body.contact_monitor = false
			body.max_contacts_reported = 0
