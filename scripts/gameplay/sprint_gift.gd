class_name SprintGift
extends Area3D
## Master Prompt 4: sprint is a gift, not a given. Walking into one opens a 5-second window
## in which holding Sprint (Shift by default) actually sprints. A second gift inside the
## window refreshes it to a full 5 seconds; it never stacks. The gift is used up and grows
## back after a while, so a route through it is worth remembering.
##
## Offline and on a server this decides the pickup. On an online client it only shows what
## the server says (NetMatch relays taken/back).

signal taken(gift: SprintGift, body: PlayerController)
signal restored(gift: SprintGift)

const RADIUS := 1.3

var gift_index: int = 0
var net_client: bool = false
var available: bool = true

var _visual: Node3D
var _mat: StandardMaterial3D
var _time := 0.0
var _respawn_left := 0.0


## Placed on the floor of `cell`. `index` is stable across machines (placement order).
static func create(index: int, cell: Vector3i) -> SprintGift:
	var gift := SprintGift.new()
	gift.gift_index = index
	gift.name = "SprintGift%d" % index
	gift.position = CaveBuilder.cell_to_world(cell) + Vector3(0.0, CaveBuilder.FLOOR_Y + 1.0, 0.0)
	return gift


func _ready() -> void:
	collision_layer = 0
	collision_mask = CaveBuilder.LAYER_RACERS
	add_to_group("sprint_gifts")
	var shape := SphereShape3D.new()
	shape.radius = RADIUS
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)
	body_entered.connect(_on_body_entered)

	_visual = Node3D.new()
	add_child(_visual)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.45, 1.0, 0.55)
	_mat.emission_enabled = true
	_mat.emission = Color(0.35, 1.0, 0.45)
	_mat.emission_energy_multiplier = 2.2
	for i in 2:
		var chevron := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(0.7, 0.45, 0.14)
		chevron.mesh = prism
		chevron.material_override = _mat
		chevron.position = Vector3(0.0, -0.2 + 0.32 * i, 0.0)
		_visual.add_child(chevron)
	var label := Label3D.new()
	label.text = "SPRINT"
	label.font_size = 44
	label.outline_size = 8
	label.modulate = Color(0.6, 1.0, 0.65)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0.0, 0.6, 0.0)
	_visual.add_child(label)
	var light := OmniLight3D.new()
	light.light_color = Color(0.45, 1.0, 0.5)
	light.light_energy = 1.2
	light.omni_range = 4.0
	_visual.add_child(light)


func _process(delta: float) -> void:
	_time += delta
	_visual.rotation.y = _time * 2.0
	_visual.position.y = sin(_time * 3.0) * 0.12
	if not available and not net_client:
		_respawn_left -= delta
		if _respawn_left <= 0.0:
			set_available(true)
			restored.emit(self)


func _on_body_entered(body: Node3D) -> void:
	if net_client or not available:
		return
	var racer := body as PlayerController
	if racer == null or not racer.input_enabled or racer.health.is_eliminated:
		return
	racer.grant_sprint_gift()
	set_available(false)
	_respawn_left = AppConfig.SPRINT_GIFT_RESPAWN
	taken.emit(self, racer)


func set_available(on: bool) -> void:
	available = on
	visible = on
	set_deferred("monitoring", on)
