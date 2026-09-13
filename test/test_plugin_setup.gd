extends GutTest

# ── "Add Kickback to Selected" node assembly ────────────────────────────────
# KickbackSetup.add_active_rig is the editor-free half of the setup tool (the
# EditorPlugin only wraps it in an undo action). It must wire every NodePath
# so the nodes resolve when the Skeleton3D is NESTED below the character root
# — the project's own Root/Model/Skeleton3D layout — and the resulting graph
# must actually initialize into active-ragdoll mode. Also covers the status
# panel's preset discovery (derived from RagdollTuning's create_* factories).

const RigHarness := preload("res://test/helpers/rig_harness.gd")
const StatusPanel := preload("res://addons/kickback/editor/kickback_status_panel.gd")


## Root (Node3D) -> Model (Node3D) -> Skeleton3D, as an imported model scene
## instanced under a gameplay root lays it out. Returns [root, skeleton].
func _nested_character(in_tree: bool = true) -> Array:
	var root := Node3D.new()
	root.name = "Root"
	var model := Node3D.new()
	model.name = "Model"
	root.add_child(model)
	var skel := RigHarness.build_mixamo_skeleton()
	model.add_child(skel)
	if in_tree:
		add_child_autoqfree(root)
	else:
		autofree(root)
	return [root, skel]


func _quiet_tuning() -> RagdollTuning:
	var t := RagdollTuning.create_default()
	t.foot_ik_enabled = false
	return t


# ── Skeleton discovery ──────────────────────────────────────────────────────

func test_find_skeleton_searches_nested_descendants():
	var pair := _nested_character(false)
	var found := KickbackSetup.find_skeleton(pair[0])
	assert_eq(found, pair[1], "Skeleton3D found two levels below the selected root")


func test_find_skeleton_returns_null_without_skeleton():
	var root := Node3D.new()
	autofree(root)
	root.add_child(MeshInstance3D.new())
	assert_null(KickbackSetup.find_skeleton(root))


func test_child_path_to():
	var pair := _nested_character(false)
	assert_eq(KickbackSetup.child_path_to(pair[0], pair[1]), NodePath("../Model/Skeleton3D"))
	assert_eq(KickbackSetup.child_path_to(pair[0], pair[0]), NodePath(".."))


# ── Assembly ────────────────────────────────────────────────────────────────

func test_add_active_rig_wires_every_path_for_nested_skeleton():
	var pair := _nested_character()
	var root: Node3D = pair[0]
	var skel: Skeleton3D = pair[1]
	var nodes := KickbackSetup.add_active_rig(root, skel, RagdollProfile.create_mixamo_default(), _quiet_tuning())

	assert_eq(nodes.size(), 5)
	var names := PackedStringArray()
	for n: Node in nodes:
		names.append(n.name)
		assert_eq(n.get_parent(), root, "%s is a direct child of the character root" % n.name)
	assert_eq(names, PackedStringArray(["PhysicsRigBuilder", "PhysicsRigSync", "SpringResolver", "ActiveRagdollController", "KickbackCharacter"]))

	var builder := nodes[0] as PhysicsRigBuilder
	var sync := nodes[1] as PhysicsRigSync
	var spring := nodes[2] as SpringResolver
	var active := nodes[3] as ActiveRagdollController
	var kc := nodes[4] as KickbackCharacter

	assert_eq(kc.skeleton_path, NodePath("../Model/Skeleton3D"), "skeleton path goes through the model node, not '../Skeleton3D'")
	assert_eq(kc.get_node_or_null(kc.skeleton_path), skel, "KickbackCharacter.skeleton_path resolves")
	assert_eq(kc.get_node_or_null(kc.character_root_path), root, "KickbackCharacter.character_root_path resolves to the gameplay root")
	assert_eq(builder.get_node_or_null(builder.skeleton_path), skel, "PhysicsRigBuilder.skeleton_path resolves")
	assert_eq(sync.get_node_or_null(sync.skeleton_path), skel, "PhysicsRigSync.skeleton_path resolves")
	assert_eq(sync.get_node_or_null(sync.rig_builder_path), builder, "PhysicsRigSync.rig_builder_path resolves")
	assert_eq(spring.get_node_or_null(spring.skeleton_path), skel, "SpringResolver.skeleton_path resolves")
	assert_eq(spring.get_node_or_null(spring.rig_builder_path), builder, "SpringResolver.rig_builder_path resolves")
	assert_eq(active.get_node_or_null(active.spring_resolver_path), spring, "controller.spring_resolver_path resolves")
	assert_eq(active.get_node_or_null(active.rig_builder_path), builder, "controller.rig_builder_path resolves")
	assert_eq(active.get_node_or_null(active.rig_sync_path), sync, "controller.rig_sync_path resolves")
	assert_eq(active.get_node_or_null(active.character_root_path), root, "controller.character_root_path resolves")
	assert_null(kc.owner, "no scene_owner requested -> nodes not owned (runtime spawn)")


func test_add_active_rig_sets_scene_owner():
	var pair := _nested_character()
	var nodes := KickbackSetup.add_active_rig(pair[0], pair[1], null, null, pair[0])
	for n: Node in nodes:
		assert_eq(n.owner, pair[0], "%s owned by the scene root so it persists on save" % n.name)


func test_add_active_rig_works_on_detached_root():
	# get_path_to needs a common ancestor, not a SceneTree — assembling a
	# character before it is added to the scene must produce the same paths.
	var pair := _nested_character(false)
	var nodes := KickbackSetup.add_active_rig(pair[0], pair[1])
	var kc := nodes[4] as KickbackCharacter
	assert_eq(kc.skeleton_path, NodePath("../Model/Skeleton3D"))
	assert_eq((nodes[0] as PhysicsRigBuilder).skeleton_path, NodePath("../Model/Skeleton3D"))
	assert_eq((nodes[3] as ActiveRagdollController).rig_sync_path, NodePath("../PhysicsRigSync"))


func test_assembled_nested_character_initializes_active_mode():
	# End to end: the graph the setup tool creates on Root/Model/Skeleton3D must
	# come up in ACTIVE mode with the full rig, in a live tree.
	var pair := _nested_character()
	var nodes := KickbackSetup.add_active_rig(pair[0], pair[1], RagdollProfile.create_mixamo_default(), _quiet_tuning())
	var kc := nodes[4] as KickbackCharacter
	var frames := 0
	while not kc.is_setup_complete() and frames < 40:
		await get_tree().process_frame
		frames += 1
	assert_true(kc.is_setup_complete(), "Kickback setup completed within frame budget")
	assert_eq(kc.get_mode(), KickbackCharacter.Mode.ACTIVE, "active ragdoll mode detected")
	assert_eq((nodes[0] as PhysicsRigBuilder).get_bodies().size(), 16, "rig built from the nested skeleton")
	assert_eq(pair[1].modifier_callback_mode_process, Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS)


# ── Status panel preset discovery ───────────────────────────────────────────

func test_status_panel_presets_cover_every_tuning_factory():
	var factories := StatusPanel._tuning_preset_factories()
	assert_eq(factories[0], "create_default", "Default listed first")
	for expected: String in ["create_default", "create_game_default", "create_tank", "create_agile",
			"create_fragile", "create_responsive", "create_heavy"]:
		assert_true(expected in factories, "%s discovered" % expected)
	var tuning_script: Script = RagdollTuning
	for factory: String in factories:
		var tuning = tuning_script.call(factory)  # how the panel's Apply dispatches
		assert_true(tuning is RagdollTuning, "%s() callable by name and returns a RagdollTuning" % factory)


func test_null_profile_and_tuning_resolve_to_defaults_and_ik_initialises():
	# add_active_rig(root, skeleton) with no profile / tuning: KickbackCharacter must
	# resolve the defaults itself and hand concrete resources to the controllers —
	# a null passed through configure() used to strip the controller's roles and
	# disable foot / arm IK with a warning.
	var pair := _nested_character()
	var root: Node3D = pair[0]
	var skel: Skeleton3D = pair[1]
	var ground := StaticBody3D.new()
	var gs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 1, 10)
	gs.shape = box
	ground.add_child(gs)
	ground.position.y = -0.5
	root.add_child(ground)
	var nodes := KickbackSetup.add_active_rig(root, skel)
	var kc: KickbackCharacter = nodes[nodes.size() - 1]
	var frames := 0
	while not kc.is_setup_complete() and frames < 60:
		await get_tree().process_frame
		frames += 1
	assert_true(kc.is_setup_complete())
	assert_not_null(kc.ragdoll_profile, "profile resolved to a concrete resource")
	assert_not_null(kc.ragdoll_tuning, "tuning resolved to a concrete resource")
	await wait_physics_frames(3)
	var ctrl: ActiveRagdollController = nodes[3]
	assert_eq(ctrl.get_root_rig(), "Hips", "controller roles resolved from the default profile")
	assert_eq(ctrl.get_foot_rigs().size(), 2, "foot roles resolved (foot IK can initialise)")
