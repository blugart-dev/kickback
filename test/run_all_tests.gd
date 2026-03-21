## Test runner — executes all test scripts headless and exits.
## Usage: godot --headless --path . --script test/run_all_tests.gd
extends SceneTree


func _init() -> void:
	var test_files := [
		"res://test/test_hit_event.gd",
		"res://test/test_resources.gd",
		"res://test/test_skeleton_detector.gd",
		"res://test/test_state_machine.gd",
		"res://test/test_tuning_validation.gd",
	]

	var root_node := Node.new()
	root_node.name = "TestRoot"

	for path in test_files:
		var script: GDScript = load(path) as GDScript
		if not script:
			print("ERROR: Failed to load %s" % path)
			continue
		var node := Node.new()
		node.set_script(script)
		node.name = path.get_file().get_basename()
		root_node.add_child(node)

	get_root().add_child(root_node)


func _process(_delta: float) -> bool:
	# Quit after one frame (all _ready() calls have fired)
	quit(0)
	return true
