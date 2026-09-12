extends GutTest

# ── KickbackTraceRecorder ───────────────────────────────────────────────────
# Records a live harness rig for a few ticks and checks the JSON-lines file:
# a header, one row per tick, one character entry per row with the analysed
# fields. tools/bench/trace_report.py consumes exactly this format.

const RigHarness := preload("res://test/helpers/rig_harness.gd")


func test_records_header_and_per_tick_rows():
	var h = RigHarness.new()
	add_child_autoqfree(h)
	h.setup(null, null, true)
	assert_true(await h.await_ready(60))
	var rec := KickbackTraceRecorder.new()
	add_child_autoqfree(rec)
	var path := rec.start("user://kickback_traces/test_trace.jsonl")
	assert_ne(path, "", "trace file opened")
	print("TRACE_PATH=%s" % path)
	assert_true(rec.is_recording())
	await wait_physics_frames(12)
	var out := rec.stop()
	assert_eq(out, path)
	assert_false(rec.is_recording())

	var f := FileAccess.open("user://kickback_traces/test_trace.jsonl", FileAccess.READ)
	assert_not_null(f)
	var lines: PackedStringArray = []
	while not f.eof_reached():
		var l := f.get_line()
		if not l.is_empty():
			lines.append(l)
	assert_gte(lines.size(), 12, "header + at least 11 tick rows (%d lines)" % lines.size())
	var header: Dictionary = JSON.parse_string(lines[0])
	assert_true(bool(header.get("header", false)), "first line is the header")
	assert_eq(int(header.physics_hz), Engine.physics_ticks_per_second)
	var row: Dictionary = JSON.parse_string(lines[5])
	assert_true(row.has("t") and row.has("tick") and row.has("chars"), "row has t / tick / chars")
	var chars: Array = row.chars
	assert_eq(chars.size(), 1, "one character sampled")
	var c: Dictionary = chars[0]
	for key in ["name", "state", "balance", "hips", "hips_v", "worst_err", "worst_body", "lowest_y", "lowest_body", "motor_mode", "root_cmd", "root_limit"]:
		assert_true(c.has(key), "entry has '%s'" % key)
	assert_eq(c.state, "NORMAL")
	assert_true(bool(c.motor_mode), "default mode recorded as motor mode")
	assert_lt(float(c.worst_err), 20.0, "sane error value")
