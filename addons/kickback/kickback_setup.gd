## Runtime-safe assembly of the Kickback active-ragdoll node set. The editor
## "Add Kickback to Selected" tool and the demos both build a character through
## these static helpers, so a game that spawns characters at runtime can too
## (this file has no editor dependency; exported builds can load it).
##
## Node set created under the character root, in this order:
## PhysicsRigBuilder, PhysicsRigSync, SpringResolver, ActiveRagdollController,
## KickbackCharacter (last, so its sibling scan finds the others).
class_name KickbackSetup
extends RefCounted


## Assembles the Kickback active-ragdoll node set — PhysicsRigBuilder,
## PhysicsRigSync, SpringResolver, ActiveRagdollController and, last so its
## sibling scan in _ready sees the other four, KickbackCharacter — as direct
## children of [param root] (the gameplay root: [code]character_root_path[/code]
## points at it). Every NodePath is derived with [method Node.get_path_to] from
## [param root] (see [method child_path_to]), so [param skeleton] may sit at any
## depth below it (the project's own [code]Root/Model/Skeleton3D[/code] layout
## included). Paths are set BEFORE each node is parented: at runtime add_child
## runs _ready at once, and PhysicsRigBuilder resolves skeleton_path there.
## [param profile] / [param tuning] null = the KickbackCharacter's auto-detected
## defaults. [param scene_owner] (editor use) makes the nodes persist in that
## scene; leave null when spawning at runtime. Returns the five nodes in tree
## order. Static and editor-free, so runtime spawners can reuse it.
static func add_active_rig(root: Node, skeleton: Skeleton3D, profile: RagdollProfile = null,
		tuning: RagdollTuning = null, scene_owner: Node = null) -> Array[Node]:
	var skeleton_path := child_path_to(root, skeleton)
	var root_path := child_path_to(root, root)

	var builder := PhysicsRigBuilder.new()
	builder.name = "PhysicsRigBuilder"
	builder.skeleton_path = skeleton_path
	root.add_child(builder)
	var builder_path := child_path_to(root, builder)

	# SkeletonModifier3D-based: PhysicsRigSync promotes itself under the Skeleton3D at
	# runtime, so it can be created here alongside the other Kickback nodes.
	var sync := PhysicsRigSync.new()
	sync.name = "PhysicsRigSync"
	sync.skeleton_path = skeleton_path
	sync.rig_builder_path = builder_path
	root.add_child(sync)

	var spring := SpringResolver.new()
	spring.name = "SpringResolver"
	spring.skeleton_path = skeleton_path
	spring.rig_builder_path = builder_path
	root.add_child(spring)

	var active := ActiveRagdollController.new()
	active.name = "ActiveRagdollController"
	active.spring_resolver_path = child_path_to(root, spring)
	active.rig_builder_path = builder_path
	active.rig_sync_path = child_path_to(root, sync)
	active.character_root_path = root_path
	root.add_child(active)

	var kc := KickbackCharacter.new()
	kc.name = "KickbackCharacter"
	kc.ragdoll_profile = profile
	kc.ragdoll_tuning = tuning
	kc.skeleton_path = skeleton_path
	kc.character_root_path = root_path
	root.add_child(kc)

	var nodes: Array[Node] = [builder, sync, spring, active, kc]
	if scene_owner:
		for node: Node in nodes:
			node.owner = scene_owner
	return nodes


## The NodePath a DIRECT CHILD of [param root] uses to reach [param target]
## ([code]..[/code] for [param root] itself, [code]../<get_path_to>[/code]
## otherwise). [param target] must be [param root] or one of its descendants;
## neither needs to be inside a SceneTree.
static func child_path_to(root: Node, target: Node) -> NodePath:
	if target == root:
		return NodePath("..")
	return NodePath("../" + String(root.get_path_to(target)))


## Depth-first search of [param root]'s descendants for the first Skeleton3D
## (any depth — characters usually nest it under an imported model scene).
## Returns null if none.
static func find_skeleton(root: Node) -> Skeleton3D:
	for child in root.get_children():
		if child is Skeleton3D:
			return child
		var found := find_skeleton(child)
		if found:
			return found
	return null
