extends Node
## Pulsing emissive material_overlay on MeshInstance3D children of the focused interactable.

var player: Node = null

var _last_focus: Node3D = null
var _meshes: Array[MeshInstance3D] = []
var _overlay: StandardMaterial3D

func _ready() -> void:
	_overlay = StandardMaterial3D.new()
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.cull_mode = BaseMaterial3D.CULL_DISABLED
	_overlay.albedo_color = Color(0, 0, 0, 0)
	_overlay.emission_enabled = true
	_overlay.emission = Color(0.28, 0.82, 1.0)
	_overlay.emission_energy_multiplier = 0.5
	_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD

func _physics_process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")

	var pulse := 0.38 + 0.42 * sin(Time.get_ticks_msec() * 0.0024)
	_overlay.emission_energy_multiplier = pulse

	if GameState.is_modal_open():
		if not _meshes.is_empty():
			_clear_meshes()
		_last_focus = null
		return

	var focus: Node3D = null
	if player != null:
		var v: Variant = player.get("focused_interactable")
		if v is Node3D:
			focus = v

	if focus != _last_focus:
		_clear_meshes()
		_last_focus = focus
		if focus != null and is_instance_valid(focus):
			_apply_focus(focus)

func _apply_focus(node: Node3D) -> void:
	_collect_meshes(node, _meshes)
	for mi in _meshes:
		mi.material_overlay = _overlay

func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.mesh != null:
				out.append(mi)
		_collect_meshes(child, out)

func _clear_meshes() -> void:
	for mi in _meshes:
		if is_instance_valid(mi) and mi.material_overlay == _overlay:
			mi.material_overlay = null
	_meshes.clear()
