class_name GhostRacer
extends Node3D
## FUN-002: your own best run on this cave, replayed as a translucent figure.
##
## Recording samples the local racer's transform on a fixed clock. Playback interpolates
## between samples by race time, so the ghost moves at exactly the pace you did. Stored per
## (seed, size) in user://ghosts, so it survives restarts and never needs a server.

const SAMPLE := 0.1
const DIR := "user://ghosts"

var _frames: Array = []   # [Vector3 origin, Quaternion rotation] per SAMPLE seconds
var _mat := StandardMaterial3D.new()
var _body: MeshInstance3D


static func path_for(p_seed: int, size: int, tag: String = "") -> String:
	if tag == "":
		return "%s/%d_%d.ghost" % [DIR, p_seed, size]
	return "%s/%s_%d_%d.ghost" % [DIR, tag, p_seed, size]


static func load_for(p_seed: int, size: int, tag: String = "") -> GhostRacer:
	var path := path_for(p_seed, size, tag)
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var data = f.get_var()
	if not (data is Array) or (data as Array).size() < 2:
		return null
	var ghost := GhostRacer.new()
	ghost._frames = data
	return ghost


static func save(p_seed: int, size: int, frames: Array, tag: String = "") -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(path_for(p_seed, size, tag), FileAccess.WRITE)
	if f != null:
		f.store_var(frames)


func _ready() -> void:
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(0.7, 0.9, 1.0, 0.28)
	_body = MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.38
	capsule.height = 1.8
	_body.mesh = capsule
	_body.material_override = _mat
	add_child(_body)
	var label := Label3D.new()
	label.text = "your best"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 36
	label.pixel_size = 0.006
	label.modulate = Color(0.7, 0.9, 1.0, 0.7)
	label.position.y = 1.3
	add_child(label)


## `race_time` is seconds since GO.
func show_at(race_time: float) -> void:
	var f := race_time / SAMPLE
	var i := int(f)
	if i >= _frames.size() - 1:
		visible = false
		return
	visible = true
	var a: Array = _frames[i]
	var b: Array = _frames[i + 1]
	var t := f - float(i)
	global_position = (a[0] as Vector3).lerp(b[0], t)
	global_basis = Basis((a[1] as Quaternion).slerp(b[1], t))
