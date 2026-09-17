extends Node
## Shape statistics for generated caves, for comparing generator versions.
## Run: godot --headless res://tests/cave_metrics.tscn -- seeds=100 size=1 [rush=180|300|480]

func _ready() -> void:
	await get_tree().process_frame
	var seeds := 100
	var size_index := 1
	var ruleset := "normal"
	var rush := 300
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("seeds="):
			seeds = int(arg.trim_prefix("seeds="))
		elif arg.begins_with("size="):
			size_index = int(arg.trim_prefix("size="))
		elif arg.begins_with("rush="):
			ruleset = "rush"
			rush = int(arg.trim_prefix("rush="))
	var m := CaveMetrics.new()
	var attempts := 0
	var long_cuts := 0
	var failures := 0
	var started := Time.get_ticks_msec()
	for s in seeds:
		var gen := CaveGenerator.new()
		gen.configure(size_index, ruleset, rush)
		var g := gen.generate(s)
		if g != null:
			m.add(g)
			attempts += gen.attempts_used
			long_cuts += gen.last_long_cuts
		else:
			failures += 1
	print("%s size %d" % [ruleset if ruleset == "normal" else "rush %ds" % rush, size_index])
	print(m.report())
	print("failures %d  attempts/cave %.1f  long cuts/cave %.1f  ms/cave %.0f" % [failures, float(attempts) / maxf(1, m.caves),
		float(long_cuts) / maxf(1, m.caves), float(Time.get_ticks_msec() - started) / maxf(1, seeds)])
	get_tree().quit()
