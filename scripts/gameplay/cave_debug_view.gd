class_name CaveDebugView
extends Node3D
## Developer visualisation (master prompt section 11). F3 toggles, F4 cycles the bot whose
## knowledge is drawn. Drawn through walls:
##   grey     every linked edge            amber   the guaranteed spine route
##   blue     vertical links (shafts)      green   spawn        red   the exit
##   yellow   mystery boxes                orange  fire, pistons, spiders
##   lime     what the selected bot has discovered     magenta  its current plan
##
## It draws the exit, so it only exists in debug runs (editor or source). Exported release
## builds never create it: GameWorld checks OS.is_debug_build() before adding it.

const REFRESH := 0.25

var _world: Node3D
var _graph: CaveGraph
var _static_mesh: MeshInstance3D
var _bot_mesh: MeshInstance3D
var _label: Label
var _layer: CanvasLayer
var _bot_index: int = 0
var _timer: float = 0.0


static func available() -> bool:
	return OS.is_debug_build() and AppConfig.DEBUG_HUD


func setup(world: Node3D, graph: CaveGraph) -> void:
	_world = world
	_graph = graph
	name = "CaveDebugView"
	visible = false
	_static_mesh = MeshInstance3D.new()
	_static_mesh.mesh = _build_static()
	_static_mesh.material_override = _line_material()
	add_child(_static_mesh)
	_bot_mesh = MeshInstance3D.new()
	_bot_mesh.material_override = _line_material()
	add_child(_bot_mesh)
	_layer = CanvasLayer.new()
	_layer.layer = 30
	_layer.visible = false
	add_child(_layer)
	_label = Label.new()
	_label.position = Vector2(20, 420)
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 5)
	_layer.add_child(_label)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F3:
		visible = not visible
		_layer.visible = visible
		_timer = 0.0
	elif key.keycode == KEY_F4 and visible:
		_bot_index += 1
		_timer = 0.0


func _process(delta: float) -> void:
	if not visible:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REFRESH
	var bots: Array = _world.get("bots")
	if bots.is_empty():
		_bot_mesh.mesh = null
		_label.text = "DEBUG  F3 hide  |  seed %d  |  %d cells, %d loops, spine %d  |  no bots" % [
			int(_world.get("seed_value")), _graph.cell_count(), _graph.cycle_count(), _graph.spine.size()]
		return
	var bot := bots[_bot_index % bots.size()] as Node
	var controller := bot.get_node_or_null("BotController") as BotController
	if controller == null:
		return
	_bot_mesh.mesh = _build_bot(controller)
	_label.text = "DEBUG  F3 hide  F4 next bot  |  seed %d  |  %d cells, %d loops\n%s knows %d of %d cells, exit %s, clue %s, %d Moves, plan %d steps" % [
		int(_world.get("seed_value")), _graph.cell_count(), _graph.cycle_count(),
		controller.display_name, controller.knowledge.discovered.cell_count(), _graph.cell_count(),
		"FOUND" if controller.knowledge.exit_found else "unknown",
		"yes" if controller.knowledge.has_clue else "no",
		(bot as PlayerController).gravity.charges, controller.get("_path").size()]


func _build_static() -> ImmediateMesh:
	var m := ImmediateMesh.new()
	m.surface_begin(Mesh.PRIMITIVE_LINES)
	var spine_edges := {}
	for i in range(1, _graph.spine.size()):
		spine_edges[_edge_key(_graph.spine[i - 1], _graph.spine[i])] = true
	for c: Vector3i in _graph.sorted_cells():
		for d in [CaveGraph.DIR_PLUS_X, CaveGraph.DIR_UP, CaveGraph.DIR_PLUS_Z]:
			if not _graph.is_linked(c, d):
				continue
			var n: Vector3i = c + CaveGraph.DIRS[d]
			var colour := Color(0.6, 0.6, 0.6, 0.6)
			if d == CaveGraph.DIR_UP:
				colour = Color(0.35, 0.75, 1.0)
			if spine_edges.has(_edge_key(c, n)):
				colour = Color(1.0, 0.65, 0.15)
			_line(m, CaveBuilder.cell_to_world(c), CaveBuilder.cell_to_world(n), colour)
	_cross(m, CaveBuilder.cell_to_world(_graph.spawn_cell), 2.0, Color(0.3, 1.0, 0.4))
	_cross(m, CaveBuilder.cell_to_world(_graph.finish_cell), 2.5, Color(1.0, 0.2, 0.2))
	for b: Dictionary in _graph.boxes:
		_cross(m, CaveBuilder.cell_to_world(b["cell"]) + Vector3(0, -2.5, 0), 0.8, Color(1.0, 0.9, 0.2))
	for h: Dictionary in _graph.hazards:
		_cross(m, CaveBuilder.cell_to_world(h["cell"]) + Vector3(0, -3.0, 0), 1.2, Color(1.0, 0.45, 0.1))
	for f: Dictionary in _graph.features:
		if f["kind"] in ["piston", "spider"]:
			_cross(m, CaveBuilder.cell_to_world(f["cell"]), 1.2, Color(1.0, 0.45, 0.1))
	m.surface_end()
	return m


func _build_bot(controller: BotController) -> ImmediateMesh:
	var m := ImmediateMesh.new()
	m.surface_begin(Mesh.PRIMITIVE_LINES)
	var lift := Vector3(0.35, 0.35, 0.35)
	var known := controller.knowledge.discovered
	for c: Vector3i in known.sorted_cells():
		for d in 6:
			if known.is_linked(c, d) and known.has_cell(c + CaveGraph.DIRS[d]):
				_line(m, CaveBuilder.cell_to_world(c) + lift,
					CaveBuilder.cell_to_world(c + CaveGraph.DIRS[d]) + lift, Color(0.6, 1.0, 0.2))
	var path: Array = controller.get("_path")
	var body := controller.get_parent() as Node3D
	var from := body.global_position
	for cell: Vector3i in path:
		var to := CaveBuilder.cell_to_world(cell) + lift * 2.0
		_line(m, from, to, Color(1.0, 0.3, 1.0))
		from = to
	m.surface_end()
	return m


func _line(m: ImmediateMesh, a: Vector3, b: Vector3, colour: Color) -> void:
	m.surface_set_color(colour)
	m.surface_add_vertex(a)
	m.surface_set_color(colour)
	m.surface_add_vertex(b)


func _cross(m: ImmediateMesh, at: Vector3, size: float, colour: Color) -> void:
	for axis: Vector3 in [Vector3.RIGHT, Vector3(0, 1, 0), Vector3.BACK]:
		_line(m, at - axis * size, at + axis * size, colour)


func _line_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.render_priority = 10
	return mat


func _edge_key(a: Vector3i, b: Vector3i) -> String:
	return "%s|%s" % [a, b] if str(a) < str(b) else "%s|%s" % [b, a]
