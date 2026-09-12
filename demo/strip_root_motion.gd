@tool
extends EditorScript
## Strips root motion from animation .res files.
##
## Finds the root bone's position track (typically mixamorig_Hips) and flattens
## it to frame 0's value, so the animation plays in-place. Rotation is preserved.
##
## Usage: Open this script in the Script Editor, then File → Run (Ctrl+Shift+X).
## Edit the ANIMATIONS array below to choose which files to process.

## Animations to strip root motion from. Add/remove paths as needed.
const ANIMATIONS := [
	"res://assets/animations/ybot/react_front.res",
	"res://assets/animations/ybot/react_back.res",
	"res://assets/animations/ybot/react_left.res",
	"res://assets/animations/ybot/react_right.res",
	"res://assets/animations/ybot/kip_up.res",
	"res://assets/animations/ybot/injured_walk.res",
	"res://assets/animations/ybot/injured_walk_back.res",
	"res://assets/animations/ybot/injured_walk_left.res",
	"res://assets/animations/ybot/injured_walk_right.res",
	"res://assets/animations/ybot/injured_back_left.res",
	"res://assets/animations/ybot/injured_back_right.res",
]

## The root bone whose position track will be flattened. Mixamo uses "mixamorig_Hips".
const ROOT_BONE := "mixamorig_Hips"


func _run() -> void:
	var processed := 0
	var skipped := 0

	for path in ANIMATIONS:
		var anim: Animation = load(path)
		if not anim:
			print("  SKIP: Could not load '%s'" % path)
			skipped += 1
			continue

		var stripped := _strip_root_motion(anim, path)
		if stripped:
			var err := ResourceSaver.save(anim, path)
			if err == OK:
				print("  OK: %s" % path)
				processed += 1
			else:
				print("  ERROR: Failed to save '%s' (error %d)" % [path, err])
				skipped += 1
		else:
			print("  SKIP: No root bone position track found in '%s'" % path)
			skipped += 1

	print("\nRoot motion strip complete: %d processed, %d skipped" % [processed, skipped])


func _strip_root_motion(anim: Animation, path: String) -> bool:
	# Find the position track for the root bone
	# Track paths look like "Skeleton3D:mixamorig_Hips" or just "mixamorig_Hips"
	var pos_track_idx := -1

	for i in anim.get_track_count():
		var track_path := anim.track_get_path(i)
		var track_type := anim.track_get_type(i)

		# We want position tracks (TYPE_POSITION_3D = 2)
		if track_type != Animation.TYPE_POSITION_3D:
			continue

		# Check if this track targets our root bone
		var subname := track_path.get_concatenated_subnames()
		var node_name := String(track_path.get_concatenated_names())
		if subname == ROOT_BONE or node_name.ends_with(ROOT_BONE):
			pos_track_idx = i
			break

	if pos_track_idx < 0:
		return false

	# Get the position at frame 0 (the reference "in place" position)
	var key_count := anim.track_get_key_count(pos_track_idx)
	if key_count == 0:
		return false

	var frame0_pos: Vector3 = anim.track_get_key_value(pos_track_idx, 0)

	# Flatten: set ALL keyframes to the frame 0 position (keeps Y for crouch)
	# Actually, zero XZ and keep Y relative to frame 0
	for k in key_count:
		var pos: Vector3 = anim.track_get_key_value(pos_track_idx, k)
		# Keep Y delta (crouch/jump motion), strip XZ (locomotion drift)
		pos.x = frame0_pos.x
		pos.z = frame0_pos.z
		anim.track_set_key_value(pos_track_idx, k, pos)

	return true
