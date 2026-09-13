## Joint-limit envelope (docs/PLAN.md 0.6.0 "ragdoll look"): plays every clip of the
## ybot's AnimationPlayer, samples the animation pose at 30 Hz, and reports per joint the
## min / max angle reached on each limit axis (in the joint limit frame the rig uses)
## next to the authored limits from the profile — how much slack the anatomical ranges
## leave beyond what the character's animations ever use. Standalone; not part of the
## plugin or the suite.
##
##   godot --headless --path . -s tools/bench/limit_envelope.gd
extends SceneTree

const YBOT := "res://assets/characters/ybot/ybot.tscn"


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	await process_frame
	var world := Node3D.new()
	root.add_child(world)
	var char_root := Node3D.new()
	world.add_child(char_root)
	var model: Node = (load(YBOT) as PackedScene).instantiate()
	char_root.add_child(model)
	var sim := model.find_child("PhysicalBoneSimulator3D", true, false)
	if sim:
		sim.get_parent().remove_child(sim)
		sim.queue_free()
	var skeleton := KickbackSetup.find_skeleton(char_root)
	var anim: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	var tuning := RagdollTuning.create_default()
	var nodes := KickbackSetup.add_active_rig(char_root, skeleton, null, tuning)
	var kc: KickbackCharacter = nodes[nodes.size() - 1]
	var builder: PhysicsRigBuilder = nodes[0]
	var spring: SpringResolver = nodes[2]
	if not kc.is_setup_complete():
		await kc.setup_complete
	spring.set_active(false)  # pose sampling only; the rig just supplies the joint frames

	var profile := builder.get_profile()
	var lo: Dictionary = {}   # child rig → Vector3 min angles (deg)
	var hi: Dictionary = {}
	var worst_clip: Dictionary = {}  # child rig → {axis: clip}
	for jd: JointDefinition in profile.joints:
		lo[jd.child_rig] = Vector3(INF, INF, INF)
		hi[jd.child_rig] = Vector3(-INF, -INF, -INF)
		worst_clip[jd.child_rig] = {}
	var sg := skeleton.global_transform
	var clips := anim.get_animation_list()
	print("=== limit envelope over %d clips ===" % clips.size())
	for clip: String in clips:
		if clip == "RESET":
			continue
		anim.play(clip)
		var length := anim.current_animation_length
		var t := 0.0
		while t <= length:
			anim.seek(t, true)
			skeleton.force_update_all_bone_transforms()
			for jd: JointDefinition in profile.joints:
				var pi: int = skeleton.find_bone(builder.get_bone_name_for_body(jd.parent_rig))
				var ci: int = skeleton.find_bone(builder.get_bone_name_for_body(jd.child_rig))
				if pi < 0 or ci < 0:
					continue
				var ang: Vector3 = builder.get_joint_angles(jd.child_rig, sg * spring.get_animation_bone_global(pi), sg * spring.get_animation_bone_global(ci))
				if not ang.is_finite():
					continue
				for k in 3:
					if ang[k] < lo[jd.child_rig][k]:
						lo[jd.child_rig][k] = ang[k]
						worst_clip[jd.child_rig]["lo%d" % k] = clip
					if ang[k] > hi[jd.child_rig][k]:
						hi[jd.child_rig][k] = ang[k]
						worst_clip[jd.child_rig]["hi%d" % k] = clip
			t += 1.0 / 30.0
	print("%-12s | %-24s | %-24s | %-24s" % ["joint", "X used  [limit]", "Y used  [limit]", "Z used  [limit]"])
	for jd: JointDefinition in profile.joints:
		var c := jd.child_rig
		var lims := [jd.limit_x, jd.limit_y, jd.limit_z]
		var cols := PackedStringArray()
		for k in 3:
			var lim: Vector2 = lims[k]
			var flag := ""
			if lo[c][k] < lim.x - 1.0 or hi[c][k] > lim.y + 1.0:
				flag = " !"
			cols.append("%5.0f..%4.0f [%4.0f..%4.0f]%s" % [lo[c][k], hi[c][k], lim.x, lim.y, flag])
		print("%-12s | %-24s | %-24s | %-24s" % [c, cols[0], cols[1], cols[2]])
	print("(! = a clip exceeds the authored limit by more than 1 deg; clips: %s)" % ", ".join(clips))
	quit()
