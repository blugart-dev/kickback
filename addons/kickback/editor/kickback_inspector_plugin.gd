@tool
extends EditorInspectorPlugin

var _editor_plugin: EditorPlugin


func _can_handle(object: Object) -> bool:
	return object is KickbackCharacter


func _parse_begin(object: Object) -> void:
	var kc := object as KickbackCharacter
	if not kc:
		return

	var panel := preload("res://addons/kickback/editor/kickback_status_panel.gd").new()
	panel.setup(kc, _editor_plugin)
	add_custom_control(panel)
