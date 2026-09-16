extends Node
## Launcher for a scripted network client. See tests/net_probe_driver.gd.

func _ready() -> void:
	var driver: Node = preload("res://tests/net_probe_driver.gd").new()
	driver.name = "NetProbeDriver"
	get_tree().root.add_child.call_deferred(driver)
