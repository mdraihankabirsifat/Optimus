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
	for s in seeds:
		var gen := CaveGenerator.new()
		gen.configure(size_index, ruleset, rush)
		var g := gen.generate(s)
		if g != null:
			m.add(g)
	print("%s size %d" % [ruleset if ruleset == "normal" else "rush %ds" % rush, size_index])
	print(m.report())
	get_tree().quit()
