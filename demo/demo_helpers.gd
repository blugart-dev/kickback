## Shared wiring helpers for the Kickback DEMO scenes. NOT part of the plugin —
## it lives under demo/ and is preloaded by the demo scripts to collapse the
## active-rig assembly, skeleton lookup, weapon-picker / HUD-log plumbing and
## debug-HUD setup that every demo otherwise hand-duplicates. (The orbit camera
## lives in demo/orbit_camera.gd.)
##
## build_active_rig() wires the same node set and NodePaths as the editor setup
## tool and test/helpers/rig_harness.gd — including the controller's
## rig_sync_path, which the get-up teleport needs (see INTEGRATION.md). Unlike
## the harness it does not call .configure() up front: KickbackCharacter
## configures its sibling controllers from the assigned RagdollProfile /
## RagdollTuning in its own _ready(), exactly as a setup-tool scene does.
##
## Usage:
##   const DemoHelpers := preload("res://demo/demo_helpers.gd")
##   var kc := DemoHelpers.build_active_rig(char_root)
extends RefCounted


## Scrolling text log for a HUD Label: keeps the newest [member max_lines] messages.
class LogPanel extends RefCounted:
	var label: Label
	var max_lines: int
	var _lines: PackedStringArray = []

	func _init(target: Label, limit: int) -> void:
		label = target
		max_lines = limit

	## Appends [param msg], drops the oldest lines past the limit and redraws the label.
	func add(msg: String) -> void:
		_lines.append(msg)
		if _lines.size() > max_lines:
			_lines = _lines.slice(_lines.size() - max_lines)
		if label:
			label.text = "\n".join(_lines)


## Builds the full Kickback active-ragdoll node graph (PhysicsRigBuilder +
## PhysicsRigSync + SpringResolver + ActiveRagdollController + KickbackCharacter)
## as children of [param char_root] and returns the KickbackCharacter (or null if
## no Skeleton3D is found). [param skeleton_owner] is the char_root child that owns
## the Skeleton3D (auto-detected when ""). [param tuning] / [param profile] override
## the Mixamo/default config.
static func build_active_rig(char_root: Node3D, skeleton_owner: String = "",
		tuning: RagdollTuning = null, profile: RagdollProfile = null) -> KickbackCharacter:
	var owner_name := skeleton_owner if skeleton_owner != "" else find_skeleton_owner(char_root)
	if owner_name == "":
		return null
	var skeleton := char_root.get_node_or_null(NodePath("%s/Skeleton3D" % owner_name)) as Skeleton3D
	if not skeleton:
		return null
	var nodes := KickbackSetup.add_active_rig(char_root, skeleton,
		profile if profile else RagdollProfile.create_mixamo_default(),
		tuning if tuning else RagdollTuning.create_default())
	return nodes[nodes.size() - 1] as KickbackCharacter


## Returns the name of the [param char_root] child whose subtree contains a
## Skeleton3D, or "" (with an error) when none is present.
static func find_skeleton_owner(char_root: Node3D, error_prefix: String = "DemoHelpers") -> String:
	for child in char_root.get_children():
		if find_descendant_of_type(child, "Skeleton3D"):
			return child.name
	push_error("%s: No Skeleton3D found in %s" % [error_prefix, char_root.name])
	return ""


## Depth-first search of [param node]'s descendants for the first node whose class
## is [param type_name] (e.g. "Skeleton3D", "AnimationPlayer"). Returns null if none.
static func find_descendant_of_type(node: Node, type_name: String) -> Node:
	for child in node.get_children():
		if child.get_class() == type_name:
			return child
		var found := find_descendant_of_type(child, type_name)
		if found:
			return found
	return null


## Returns the PhysicsRigBuilder that [param kc]'s facade drives (its sibling
## under the character root), or null. The plugin does not expose rig bodies
## through the facade, so a demo that needs a specific RigidBody3D (e.g. to hit
## every character in the chest) goes through the builder's get_bodies().
static func find_rig_builder(kc: KickbackCharacter) -> PhysicsRigBuilder:
	var parent := kc.get_parent()
	if not parent:
		return null
	for sibling in parent.get_children():
		if sibling is PhysicsRigBuilder:
			return sibling
	return null


## Builds an ImpactProfile from the fields the demos tune.
static func make_profile(pname: StringName, impulse: float, transfer: float, upward: float,
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


## The five "cranked" weapon profiles the interactive demos share — deliberately
## hotter than the addons/kickback/presets so reactions read on screen.
static func create_cranked_profiles() -> Array[ImpactProfile]:
	return [
		make_profile(&"Bullet",    15.0, 0.55, 0.0,  0.05, 0.90, 3, 0.35),
		make_profile(&"Melee",     22.0, 0.80, 0.05, 0.15, 0.92, 4, 0.25),
		make_profile(&"Arrow",     18.0, 0.60, 0.0,  0.10, 0.90, 2, 0.3),
		make_profile(&"Shotgun",   30.0, 0.65, 0.10, 0.40, 0.95, 5, 0.20),
		make_profile(&"Explosion", 50.0, 1.00, 0.50, 0.95, 1.0, 99, 0.12),
	]


## Weapon picker shared by the demos: clamps [param idx] into [param names] and
## writes "Weapon: <name>  [1-5]" to [param label] (null-safe). Returns the index.
static func select_weapon(idx: int, names: PackedStringArray, label: Label) -> int:
	var clamped := clampi(idx, 0, names.size() - 1)
	if label:
		label.text = "Weapon: %s  [1-5]" % names[clamped]
	return clamped


## Keyboard side of the picker: KEY_1..KEY_5 select weapons 0..4; keys past the
## end of [param names] are ignored. Returns the new index, or [param current]
## when [param key] is not a weapon key.
static func select_weapon_by_key(key: Key, current: int, names: PackedStringArray, label: Label) -> int:
	if key < KEY_1 or key > KEY_5:
		return current
	var idx := int(key - KEY_1)
	if idx >= names.size():
		return current
	return select_weapon(idx, names, label)


## Instantiates the F3 StrengthDebugHUD overlay and adds it under [param parent].
static func add_debug_hud(parent: Node) -> StrengthDebugHUD:
	var hud := StrengthDebugHUD.new()
	hud.name = "StrengthDebugHUD"
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(hud)
	return hud
