## Debug overlay showing color-coded bone gizmos for ALL ragdoll characters
## in the scene. Press F3 to cycle detail levels: Off → Dots → Wireframe → Full.
## Self-contained — no configuration needed.
@icon("res://addons/kickback/icons/strength_debug_hud.svg")
class_name StrengthDebugHUD
extends Control

var _detail_level: int = 0  # 0=off, 1=dots, 2=wireframe+state, 3=full
var _active_targets: Array[Dictionary] = []   # [{spring, rig_builder, active_ctrl, kickback_char}]
var _partial_targets: Array[Dictionary] = []  # [{partial_ctrl, simulator}]
var _discovered: bool = false

const DOT_RADIUS_BASE := 5.0
const DOT_RADIUS_MIN := 2.0
const DOT_FADE_START := 10.0
const DOT_FADE_END := 50.0
const FONT_SIZE := 10
const FONT_SIZE_PANEL := 11
const LABEL_DIST := 15.0
const WIRE_WIDTH_BASE := 2.0
const WIRE_WIDTH_MIN := 0.5
const VEL_SCALE := 0.3
const VEL_MAX_LEN := 1.5

const WEAK_COLOR := Color(0.9, 0.2, 0.2)
const MID_COLOR := Color(0.9, 0.8, 0.2)
const FULL_COLOR := Color(0.2, 0.9, 0.3)
const PARTIAL_IDLE_COLOR := Color(0.6, 0.8, 0.9, 0.7)
const PARTIAL_REACT_COLOR := Color(1.0, 0.85, 0.2)
const OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.8)
const VEL_COLOR := Color(1.0, 1.0, 1.0, 0.6)
const COM_COLOR_GOOD := Color(0.3, 0.9, 0.4, 0.9)
const COM_COLOR_BAD := Color(0.9, 0.2, 0.2, 0.9)
const SUPPORT_COLOR := Color(0.5, 0.7, 1.0, 0.6)
const PANEL_BG := Color(0.0, 0.0, 0.0, 0.65)
const PANEL_BORDER := Color(0.4, 0.4, 0.4, 0.5)
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.7)

const STATE_COLORS := {
	"NORMAL": Color(0.3, 0.9, 0.4),
	"STAGGER": Color(0.9, 0.8, 0.2),
	"RAGDOLL": Color(0.9, 0.2, 0.2),
	"GETTING UP": Color(0.4, 0.6, 1.0),
	"PERSISTENT": Color(0.7, 0.3, 0.9),
}

const DETAIL_LABELS := ["OFF", "DOTS", "WIREFRAME", "FULL"]


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	print("Kickback: Press F3 to cycle debug gizmos (Off → Dots → Wireframe → Full)")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		_detail_level = (_detail_level + 1) % 4
		visible = _detail_level > 0
		if _detail_level > 0 and not _discovered:
			_discover_targets()
		queue_redraw()


func _discover_targets() -> void:
	_active_targets.clear()
	_partial_targets.clear()
	var root := get_tree().current_scene
	if not root:
		return
	var characters := KickbackCharacter.find_all(root)
	for kc: KickbackCharacter in characters:
		var parent := kc.get_parent()
		if not parent:
			continue
		var spring: SpringResolver = null
		var builder: PhysicsRigBuilder = null
		var active_ctrl: ActiveRagdollController = null
		var partial: PartialRagdollController = null
		for sibling in parent.get_children():
			if sibling is SpringResolver:
				spring = sibling
			elif sibling is PhysicsRigBuilder:
				builder = sibling
			elif sibling is ActiveRagdollController:
				active_ctrl = sibling
			elif sibling is PartialRagdollController:
				partial = sibling
		if spring and builder:
			_active_targets.append({
				"spring": spring,
				"rig_builder": builder,
				"active_ctrl": active_ctrl,
				"kickback_char": kc,
			})
		elif partial:
			var skel_path: NodePath = kc.get("skeleton_path")
			var skeleton := kc.get_node_or_null(skel_path) as Skeleton3D
			if skeleton:
				var sim := skeleton.get_node_or_null("PhysicalBoneSimulator3D") as PhysicalBoneSimulator3D
				if sim:
					_partial_targets.append({"partial_ctrl": partial, "simulator": sim})
	_discovered = true


func _process(_delta: float) -> void:
	if _detail_level > 0:
		queue_redraw()


func _draw() -> void:
	if _detail_level == 0:
		return

	var camera := get_viewport().get_camera_3d()
	if not camera:
		return

	if _active_targets.is_empty() and _partial_targets.is_empty():
		_discover_targets()

	var cam_pos := camera.global_position

	for target: Dictionary in _active_targets:
		_draw_active_target(target, camera, cam_pos)

	for target: Dictionary in _partial_targets:
		_draw_partial_target(target, camera, cam_pos)

	# Legend (level 2+)
	if _detail_level >= 2:
		_draw_legend()


# ── Active Ragdoll ──────────────────────────────────────────────────────────

func _draw_active_target(target: Dictionary, camera: Camera3D, cam_pos: Vector3) -> void:
	var builder: PhysicsRigBuilder = target.rig_builder
	var spring: SpringResolver = target.spring
	var active_ctrl: ActiveRagdollController = target.active_ctrl
	var bodies := builder.get_bodies()

	# Wireframe (level 2+)
	if _detail_level >= 2:
		_draw_skeleton_wireframe(builder, spring, camera, cam_pos)

	# Bone dots (all levels)
	_draw_bone_dots(bodies, spring, camera, cam_pos)

	# State label (level 2+)
	if _detail_level >= 2 and active_ctrl:
		_draw_state_label(bodies, active_ctrl, camera, cam_pos)

	# Full panel + CoM + velocity (level 3)
	if _detail_level >= 3:
		if active_ctrl:
			_draw_status_panel(bodies, spring, active_ctrl, camera, cam_pos)
		_draw_com_and_support(bodies, active_ctrl, camera, cam_pos)
		_draw_velocity_vectors(bodies, camera, cam_pos)


func _draw_bone_dots(bodies: Dictionary, spring: SpringResolver, camera: Camera3D, cam_pos: Vector3) -> void:
	var heatmap_mode := _detail_level >= 2  # Larger dots at WIREFRAME+
	var show_percent := _detail_level >= 3  # Strength % at FULL
	for rig_name: String in bodies:
		var body: RigidBody3D = bodies[rig_name]
		var world_pos := body.global_position
		if camera.is_position_behind(world_pos):
			continue
		var screen_pos := camera.unproject_position(world_pos)
		var dist := cam_pos.distance_to(world_pos)
		var alpha := _distance_alpha(dist)
		var strength := spring.get_bone_strength(rig_name)
		var base := spring.get_base_strength(rig_name)
		var ratio := strength / base if base > 0.001 else 1.0
		var color := _ratio_to_color(ratio)
		color.a *= alpha
		var dot_radius := _scaled_radius(dist)
		if heatmap_mode:
			dot_radius *= 1.6  # Larger dots for heatmap visibility
			# Pulse effect for weakened bones
			if ratio < 0.5:
				var pulse := sin(Time.get_ticks_msec() * 0.005) * 0.3 + 1.0
				dot_radius *= pulse
		# Outline
		draw_circle(screen_pos, dot_radius + 1.0, Color(OUTLINE_COLOR, OUTLINE_COLOR.a * alpha))
		# Fill
		draw_circle(screen_pos, dot_radius, color)
		# Label + strength percentage
		if dist < LABEL_DIST:
			var label := rig_name
			if show_percent:
				label += " %d%%" % int(ratio * 100.0)
			_draw_text_shadowed(screen_pos + Vector2(dot_radius + 3, 4),
				label, FONT_SIZE, color)


func _draw_skeleton_wireframe(builder: PhysicsRigBuilder, spring: SpringResolver, camera: Camera3D, cam_pos: Vector3) -> void:
	var profile := builder.get_profile()
	var bodies := builder.get_bodies()
	for joint_def: JointDefinition in profile.joints:
		if joint_def.parent_rig not in bodies or joint_def.child_rig not in bodies:
			continue
		var parent_body: RigidBody3D = bodies[joint_def.parent_rig]
		var child_body: RigidBody3D = bodies[joint_def.child_rig]
		var p_pos := parent_body.global_position
		var c_pos := child_body.global_position
		if camera.is_position_behind(p_pos) and camera.is_position_behind(c_pos):
			continue
		var p_screen := camera.unproject_position(p_pos)
		var c_screen := camera.unproject_position(c_pos)
		var mid_dist := cam_pos.distance_to((p_pos + c_pos) * 0.5)
		var alpha := _distance_alpha(mid_dist)
		# Color based on child bone strength
		var base := spring.get_base_strength(joint_def.child_rig)
		var strength := spring.get_bone_strength(joint_def.child_rig)
		var ratio := strength / base if base > 0.001 else 1.0
		var color := _ratio_to_color(ratio)
		color.a *= alpha * 0.7
		var width := lerpf(WIRE_WIDTH_BASE, WIRE_WIDTH_MIN,
			clampf((mid_dist - DOT_FADE_START) / (DOT_FADE_END - DOT_FADE_START), 0.0, 1.0))
		draw_line(p_screen, c_screen, color, width)


func _draw_state_label(bodies: Dictionary, ctrl: ActiveRagdollController, camera: Camera3D, cam_pos: Vector3) -> void:
	var head_body: RigidBody3D = bodies.get("Head")
	if not head_body:
		return
	var head_pos := head_body.global_position
	if camera.is_position_behind(head_pos):
		return
	var screen_pos := camera.unproject_position(head_pos + Vector3.UP * 0.25)
	var dist := cam_pos.distance_to(head_pos)
	if dist > DOT_FADE_END:
		return
	var state_name := ctrl.get_state_name()
	var color: Color = STATE_COLORS.get(state_name, Color.WHITE)
	color.a *= _distance_alpha(dist)
	_draw_text_shadowed(screen_pos + Vector2(-30, -15), state_name, FONT_SIZE_PANEL + 2, color)


func _draw_status_panel(bodies: Dictionary, spring: SpringResolver, ctrl: ActiveRagdollController, camera: Camera3D, cam_pos: Vector3) -> void:
	var hips_body: RigidBody3D = bodies.get("Hips")
	if not hips_body:
		return
	var hips_pos := hips_body.global_position
	if camera.is_position_behind(hips_pos):
		return
	var dist := cam_pos.distance_to(hips_pos)
	if dist > 30.0:
		return
	var alpha := clampf(1.0 - (dist - 15.0) / 15.0, 0.3, 1.0)
	var anchor := camera.unproject_position(hips_pos + Vector3.UP * 1.2)

	var panel_w := 180.0
	var row_h := 18.0
	var pad := 6.0
	var bar_w := 70.0
	var bar_h := 10.0
	var rows := 5
	var panel_h := row_h * rows + pad * 2

	var panel_rect := Rect2(anchor.x - panel_w * 0.5, anchor.y - panel_h, panel_w, panel_h)

	# Background
	draw_rect(panel_rect, Color(PANEL_BG.r, PANEL_BG.g, PANEL_BG.b, PANEL_BG.a * alpha))
	draw_rect(panel_rect, Color(PANEL_BORDER.r, PANEL_BORDER.g, PANEL_BORDER.b, PANEL_BORDER.a * alpha), false, 1.0)

	var x0 := panel_rect.position.x + pad
	var y0 := panel_rect.position.y + pad
	var font := ThemeDB.fallback_font

	# Row 1: State + hit streak
	var state_name := ctrl.get_state_name()
	var state_color: Color = STATE_COLORS.get(state_name, Color.WHITE)
	state_color.a = alpha
	draw_string(font, Vector2(x0, y0 + 12), state_name, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_PANEL, state_color)

	# Hit streak dots
	var streak := ctrl.get_hit_streak()
	var dot_x := x0 + panel_w - pad * 2 - 8
	for i in range(min(streak, 8), 0, -1):
		draw_circle(Vector2(dot_x, y0 + 7), 3.0, Color(1.0, 0.5, 0.2, alpha))
		dot_x -= 9.0

	y0 += row_h

	# Row 2: Balance bar
	var balance := ctrl.get_balance_ratio()
	_draw_bar(Vector2(x0, y0), bar_w, bar_h, balance / 1.5, _threshold_color(balance, 0.3, 0.6), alpha)
	draw_string(font, Vector2(x0 + bar_w + 6, y0 + 10), "BAL %.2f" % balance,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(0.8, 0.8, 0.8, alpha))
	y0 += row_h

	# Row 3: Pain bar
	var pain := ctrl.get_pain()
	_draw_bar(Vector2(x0, y0), bar_w, bar_h, pain, _threshold_color(pain, 0.3, 0.6), alpha)
	draw_string(font, Vector2(x0 + bar_w + 6, y0 + 10), "PAIN %.2f" % pain,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(0.8, 0.8, 0.8, alpha))
	y0 += row_h

	# Row 4: Fatigue bar
	var fatigue := ctrl.get_fatigue()
	_draw_bar(Vector2(x0, y0), bar_w, bar_h, fatigue, _threshold_color(fatigue, 0.3, 0.6), alpha)
	draw_string(font, Vector2(x0 + bar_w + 6, y0 + 10), "FTG %.2f" % fatigue,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(0.8, 0.8, 0.8, alpha))
	y0 += row_h

	# Row 5: Average strength bar
	var total := 0.0
	var count := 0
	for rig_name: String in spring.get_all_bone_names():
		var base: float = spring.get_base_strength(rig_name)
		if base > 0.001:
			total += spring.get_bone_strength(rig_name) / base
			count += 1
	var avg_str := total / float(count) if count > 0 else 1.0
	var str_color := _ratio_to_color(avg_str)
	str_color.a = alpha
	_draw_bar(Vector2(x0, y0), bar_w, bar_h, avg_str, str_color, alpha)
	draw_string(font, Vector2(x0 + bar_w + 6, y0 + 10), "STR %.2f" % avg_str,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(0.8, 0.8, 0.8, alpha))


func _draw_com_and_support(bodies: Dictionary, ctrl: ActiveRagdollController, camera: Camera3D, cam_pos: Vector3) -> void:
	var foot_l: RigidBody3D = bodies.get("Foot_L")
	var foot_r: RigidBody3D = bodies.get("Foot_R")
	if not foot_l or not foot_r:
		return

	# Get full balance state from controller
	var balance_state: Dictionary = ctrl.get_balance_state() if ctrl else {}
	var com: Vector3 = balance_state.get("com", Vector3.ZERO)
	var support_center: Vector3 = balance_state.get("support_center", Vector3.ZERO)
	var balance: float = balance_state.get("balance_ratio", 0.0)
	var imbalance_dir: Vector2 = balance_state.get("imbalance_dir", Vector2.ZERO)

	if com == Vector3.ZERO:
		return

	var mid_dist := cam_pos.distance_to(com)
	if mid_dist > DOT_FADE_END:
		return
	var alpha := _distance_alpha(mid_dist)

	# Support polygon — filled quad between feet
	var fl_pos := foot_l.global_position
	var fr_pos := foot_r.global_position
	var foot_fwd := (fl_pos - fr_pos).cross(Vector3.UP).normalized() * 0.1
	if not camera.is_position_behind(fl_pos) and not camera.is_position_behind(fr_pos):
		var fl_screen := camera.unproject_position(fl_pos)
		var fr_screen := camera.unproject_position(fr_pos)
		var fl_fwd_screen := camera.unproject_position(fl_pos + foot_fwd)
		var fr_fwd_screen := camera.unproject_position(fr_pos + foot_fwd)
		var fl_back_screen := camera.unproject_position(fl_pos - foot_fwd)
		var fr_back_screen := camera.unproject_position(fr_pos - foot_fwd)
		# Filled support area
		var support_poly := PackedVector2Array([fl_fwd_screen, fr_fwd_screen, fr_back_screen, fl_back_screen])
		draw_colored_polygon(support_poly, Color(SUPPORT_COLOR.r, SUPPORT_COLOR.g, SUPPORT_COLOR.b, 0.15 * alpha))
		draw_polyline(support_poly, Color(SUPPORT_COLOR.r, SUPPORT_COLOR.g, SUPPORT_COLOR.b, SUPPORT_COLOR.a * alpha), 2.0)
		# Close the polyline
		draw_line(fl_back_screen, fl_fwd_screen, Color(SUPPORT_COLOR.r, SUPPORT_COLOR.g, SUPPORT_COLOR.b, SUPPORT_COLOR.a * alpha), 2.0)

	# CoM marker — diamond shape, colored by balance
	if not camera.is_position_behind(com):
		var com_screen := camera.unproject_position(com)
		var com_color := COM_COLOR_GOOD.lerp(COM_COLOR_BAD, clampf(balance, 0.0, 1.0))
		com_color.a *= alpha
		var sz := 8.0
		var diamond := PackedVector2Array([
			com_screen + Vector2(0, -sz),
			com_screen + Vector2(sz, 0),
			com_screen + Vector2(0, sz),
			com_screen + Vector2(-sz, 0),
		])
		draw_colored_polygon(diamond, com_color)
		draw_polyline(diamond, Color(1.0, 1.0, 1.0, 0.5 * alpha), 1.0)

		# Balance ratio text
		_draw_text_shadowed(com_screen + Vector2(sz + 4, 4),
			"BAL %.2f" % balance, FONT_SIZE, com_color)

		# Support center marker
		if not camera.is_position_behind(support_center):
			var sc_screen := camera.unproject_position(support_center)
			draw_circle(sc_screen, 4.0, Color(SUPPORT_COLOR.r, SUPPORT_COLOR.g, SUPPORT_COLOR.b, 0.8 * alpha))
			# Line from support center to CoM
			draw_line(sc_screen, com_screen, Color(1.0, 1.0, 1.0, 0.3 * alpha), 1.5)

			# Imbalance direction arrow
			if imbalance_dir.length_squared() > 0.001 and balance > 0.05:
				var arrow_len := clampf(balance * 40.0, 10.0, 60.0)
				var arrow_dir := imbalance_dir.normalized()
				var arrow_end := sc_screen + Vector2(arrow_dir.x, arrow_dir.y) * arrow_len
				var arrow_color := com_color
				arrow_color.a = 0.8 * alpha
				draw_line(sc_screen, arrow_end, arrow_color, 2.5)
				# Arrowhead
				var perp := Vector2(-arrow_dir.y, arrow_dir.x) * 5.0
				var tip := arrow_end + Vector2(arrow_dir.x, arrow_dir.y) * 6.0
				var head := PackedVector2Array([tip, arrow_end + perp, arrow_end - perp])
				draw_colored_polygon(head, arrow_color)


func _draw_velocity_vectors(bodies: Dictionary, camera: Camera3D, cam_pos: Vector3) -> void:
	for body: RigidBody3D in bodies.values():
		var vel := body.linear_velocity
		if vel.length_squared() < 0.25:
			continue
		var world_pos := body.global_position
		if camera.is_position_behind(world_pos):
			continue
		var dist := cam_pos.distance_to(world_pos)
		if dist > DOT_FADE_END:
			continue
		var vel_len := vel.length()
		var vel_end := world_pos + vel.normalized() * minf(vel_len * VEL_SCALE, VEL_MAX_LEN)
		if camera.is_position_behind(vel_end):
			continue
		var screen_from := camera.unproject_position(world_pos)
		var screen_to := camera.unproject_position(vel_end)
		var alpha := _distance_alpha(dist) * clampf(vel_len / 5.0, 0.2, 0.8)
		draw_line(screen_from, screen_to, Color(VEL_COLOR.r, VEL_COLOR.g, VEL_COLOR.b, alpha), 1.5)


# ── Partial Ragdoll ─────────────────────────────────────────────────────────

func _draw_partial_target(target: Dictionary, camera: Camera3D, cam_pos: Vector3) -> void:
	var partial: PartialRagdollController = target.partial_ctrl
	var sim: PhysicalBoneSimulator3D = target.simulator
	var reacting := partial.is_reacting()
	var color := PARTIAL_REACT_COLOR if reacting else PARTIAL_IDLE_COLOR
	for child in sim.get_children():
		if not child is PhysicalBone3D:
			continue
		var pb: PhysicalBone3D = child
		var world_pos := pb.global_position
		if camera.is_position_behind(world_pos):
			continue
		var screen_pos := camera.unproject_position(world_pos)
		var dist := cam_pos.distance_to(world_pos)
		var alpha := _distance_alpha(dist)
		var dot_radius := _scaled_radius(dist)
		var c := Color(color.r, color.g, color.b, color.a * alpha)
		draw_circle(screen_pos, dot_radius + 1.0, Color(OUTLINE_COLOR, OUTLINE_COLOR.a * alpha))
		draw_circle(screen_pos, dot_radius, c)
		if dist < LABEL_DIST:
			_draw_text_shadowed(screen_pos + Vector2(dot_radius + 3, 4),
				pb.bone_name, FONT_SIZE, c)


# ── Legend ──────────────────────────────────────────────────────────────────

func _draw_legend() -> void:
	var x := 10.0
	var y := 10.0
	var font := ThemeDB.fallback_font
	var line_h := 16.0
	var level_text := "F3: %s" % DETAIL_LABELS[_detail_level]

	# Background
	var legend_w := 185.0
	var legend_h := line_h * 3 + 14.0 if _detail_level < 3 else line_h * 6 + 14.0
	draw_rect(Rect2(x, y, legend_w, legend_h), Color(PANEL_BG.r, PANEL_BG.g, PANEL_BG.b, 0.5))
	draw_rect(Rect2(x, y, legend_w, legend_h), Color(PANEL_BORDER.r, PANEL_BORDER.g, PANEL_BORDER.b, 0.4), false, 1.0)

	x += 8.0
	y += 4.0

	# Title
	draw_string(font, Vector2(x, y + 12), "Kickback Debug", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_PANEL, Color(0.9, 0.9, 0.9, 0.8))
	draw_string(font, Vector2(x + 110, y + 12), level_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(0.6, 0.6, 0.6, 0.7))
	y += line_h

	# Color key
	draw_circle(Vector2(x + 5, y + 7), 4.0, FULL_COLOR)
	draw_circle(Vector2(x + 40, y + 7), 4.0, MID_COLOR)
	draw_circle(Vector2(x + 75, y + 7), 4.0, WEAK_COLOR)
	draw_string(font, Vector2(x + 12, y + 11), "Strong", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.7, 0.7, 0.7, 0.7))
	draw_string(font, Vector2(x + 47, y + 11), "Mid", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.7, 0.7, 0.7, 0.7))
	draw_string(font, Vector2(x + 82, y + 11), "Weak", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.7, 0.7, 0.7, 0.7))
	y += line_h

	# Partial ragdoll key
	draw_circle(Vector2(x + 5, y + 7), 4.0, PARTIAL_IDLE_COLOR)
	draw_string(font, Vector2(x + 12, y + 11), "Partial Ragdoll", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.7, 0.7, 0.7, 0.7))
	y += line_h

	if _detail_level >= 3:
		# CoM key
		var diamond_x := x + 5
		var diamond_y := y + 7
		var sz := 4.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(diamond_x, diamond_y - sz), Vector2(diamond_x + sz, diamond_y),
			Vector2(diamond_x, diamond_y + sz), Vector2(diamond_x - sz, diamond_y),
		]), COM_COLOR_GOOD)
		draw_string(font, Vector2(x + 12, y + 11), "Center of Mass", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.7, 0.7, 0.7, 0.7))
		y += line_h

		# Support line key
		draw_line(Vector2(x + 1, y + 7), Vector2(x + 10, y + 7), SUPPORT_COLOR, 2.0)
		draw_string(font, Vector2(x + 14, y + 11), "Support polygon", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.7, 0.7, 0.7, 0.7))
		y += line_h

		# Velocity key
		draw_line(Vector2(x + 1, y + 7), Vector2(x + 12, y + 4), VEL_COLOR, 1.5)
		draw_string(font, Vector2(x + 14, y + 11), "Velocity", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.7, 0.7, 0.7, 0.7))


# ── Helpers ─────────────────────────────────────────────────────────────────

func _draw_text_shadowed(pos: Vector2, text: String, size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, SHADOW_COLOR)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _draw_bar(pos: Vector2, width: float, height: float, fill: float, color: Color, alpha: float) -> void:
	var bg := Rect2(pos, Vector2(width, height))
	draw_rect(bg, Color(0.15, 0.15, 0.15, 0.6 * alpha))
	var fill_w := width * clampf(fill, 0.0, 1.0)
	if fill_w > 0.5:
		var fill_rect := Rect2(pos, Vector2(fill_w, height))
		draw_rect(fill_rect, Color(color.r, color.g, color.b, 0.8 * alpha))
	draw_rect(bg, Color(0.4, 0.4, 0.4, 0.4 * alpha), false, 1.0)


func _scaled_radius(dist: float) -> float:
	var t := clampf((dist - DOT_FADE_START) / (DOT_FADE_END - DOT_FADE_START), 0.0, 1.0)
	return lerpf(DOT_RADIUS_BASE, DOT_RADIUS_MIN, t)


func _distance_alpha(dist: float) -> float:
	return clampf(1.0 - (dist - DOT_FADE_START) / (DOT_FADE_END - DOT_FADE_START), 0.15, 1.0)


func _ratio_to_color(ratio: float) -> Color:
	if ratio < 0.5:
		return WEAK_COLOR.lerp(MID_COLOR, ratio * 2.0)
	else:
		return MID_COLOR.lerp(FULL_COLOR, (ratio - 0.5) * 2.0)


func _threshold_color(value: float, mid_threshold: float, high_threshold: float) -> Color:
	if value < mid_threshold:
		return FULL_COLOR
	elif value < high_threshold:
		return MID_COLOR
	else:
		return WEAK_COLOR
