extends Node
## Shape statistics for generated caves, for comparing generator versions.
## Run: godot --headless res://tests/cave_metrics.tscn -- seeds=100 size=1

func _ready() -> void:
	await get_tree().process_frame
	var seeds := 100
	var size_index := 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("seeds="):
			seeds = int(arg.trim_prefix("seeds="))
		elif arg.begins_with("size="):
			size_index = int(arg.trim_prefix("size="))
	var m := CaveMetrics.new()
	for s in seeds:
		var gen := CaveGenerator.new()
		gen.apply_size_preset(size_index)
		var g := gen.generate(s)
		if g != null:
			m.add(g)
	print(m.report())
	get_tree().quit()
