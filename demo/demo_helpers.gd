## Shared wiring helpers for the Kickback DEMO scenes. NOT part of the plugin —
## it lives under demo/ and is preloaded by the demo scripts to collapse the
## active-rig assembly, skeleton lookup, orbit-camera math, and debug-HUD setup
## that every demo otherwise hand-duplicates.
##
## This intentionally mirrors the DEMOS' wiring: it sets NodePaths and relies on
## each controller's defaults (it does NOT call .configure() up front, and does
## NOT set the controller's rig_sync_path). That differs from
## test/helpers/rig_harness.gd, which configures every node explicitly for the
## headless tests — keep the two separate.
##
## Usage:
##   const DemoHelpers := preload("res://demo/demo_helpers.gd")
##   var kc := DemoHelpers.build_active_rig(char_root)
extends RefCounted


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

	var skel_path := NodePath("../%s/Skeleton3D" % owner_name)
	var builder_path := NodePath("../PhysicsRigBuilder")
	var spring_path := NodePath("../SpringResolver")
	var root_path := NodePath("..")

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

	var kc := KickbackCharacter.new()
	kc.name = "KickbackCharacter"
	kc.skeleton_path = skel_path
	kc.character_root_path = root_path
	kc.ragdoll_profile = profile if profile else RagdollProfile.create_mixamo_default()
	kc.ragdoll_tuning = tuning if tuning else RagdollTuning.create_default()

	char_root.add_child(rig_builder)
	char_root.add_child(rig_sync)
	char_root.add_child(spring)
	char_root.add_child(active_ctrl)
	char_root.add_child(kc)
	return kc


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


## Positions an orbit camera at the given yaw/pitch (degrees) and distance around
## [param pivot], then looks at the pivot. The spherical-coords math shared by
## every orbiting demo; input capture and clamps stay per-demo.
static func orbit_camera(cam: Camera3D, yaw_deg: float, pitch_deg: float,
		distance: float, pivot: Vector3 = Vector3(0.0, 1.0, 0.0)) -> void:
	var yaw_rad := deg_to_rad(yaw_deg)
	var pitch_rad := deg_to_rad(pitch_deg)
	var offset := Vector3(
		sin(yaw_rad) * cos(pitch_rad),
		-sin(pitch_rad),
		cos(yaw_rad) * cos(pitch_rad),
	) * distance
	cam.global_position = pivot + offset
	cam.look_at(pivot)


## Instantiates the F3 StrengthDebugHUD overlay and adds it under [param parent].
static func add_debug_hud(parent: Node) -> StrengthDebugHUD:
	var hud := StrengthDebugHUD.new()
	hud.name = "StrengthDebugHUD"
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(hud)
	return hud
