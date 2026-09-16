class_name RacerTrail
extends MeshInstance3D
## VFX-009: a short ribbon behind a racer, flat against the surface they are running on.
## Its width lies across the racer's own local up, so a trail left on a wall shows at a
## glance which way that racer's gravity runs.

const POINTS := 18
const SAMPLE := 0.045
const WIDTH := 0.28

var _racer: PlayerController
var _positions: Array[Vector3] = []
var _sides: Array[Vector3] = []
var _timer := 0.0
var _imesh := ImmediateMesh.new()
var _mat := StandardMaterial3D.new()


func setup(racer: PlayerController) -> void:
	_racer = racer
	top_level = true
	mesh = _imesh
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.vertex_color_use_as_albedo = true
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(delta: float) -> void:
	if _racer == null or not is_instance_valid(_racer):
		queue_free()
		return
	global_transform = Transform3D.IDENTITY
	_timer += delta
	if _timer >= SAMPLE:
		_timer = 0.0
		var up := _racer.gravity.local_up()
		var vel := _racer.velocity - up * _racer.velocity.dot(up)
		var side := up.cross(vel.normalized()) if vel.length() > 0.5 else Vector3.ZERO
		_positions.push_front(_racer.global_position - up * 0.75)
		_sides.push_front(side * WIDTH)
		if _positions.size() > POINTS:
			_positions.pop_back()
			_sides.pop_back()

	_imesh.clear_surfaces()
	if _positions.size() < 2:
		return
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var colour := _racer.racer_colour
	for i in _positions.size():
		var fade := 1.0 - float(i) / float(POINTS)
		_imesh.surface_set_color(Color(colour, 0.5 * fade * fade))
		_imesh.surface_add_vertex(_positions[i] + _sides[i])
		_imesh.surface_add_vertex(_positions[i] - _sides[i])
	_imesh.surface_end()
