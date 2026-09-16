class_name WorldScope
extends RefCounted
## Group lookups limited to one race.
##
## Groups are tree-wide. Offline there is only ever one race, so that never mattered. The
## dedicated server runs every room's race in the same process at once, each in its own
## physics world, and a tree-wide lookup would let a bot in one room open a box in another,
## or a spider hunt a racer it cannot physically reach. Everything that finds race objects
## by group goes through here instead.
##
## The race root is the node in group "cave_root" (GameWorld). A node outside any race
## sees the whole tree, which keeps test harnesses that build hazards directly working.


static func root_of(node: Node) -> Node:
	var n := node
	while n != null:
		if n.is_in_group("cave_root"):
			return n
		n = n.get_parent()
	return null


static func nodes(node: Node, group: String) -> Array[Node]:
	var out: Array[Node] = []
	if node == null or not node.is_inside_tree():
		return out
	var root := root_of(node)
	for n: Node in node.get_tree().get_nodes_in_group(group):
		if root == null or root == n or root.is_ancestor_of(n):
			out.append(n)
	return out


static func first(node: Node, group: String) -> Node:
	var found := nodes(node, group)
	return null if found.is_empty() else found[0]
