class_name HeroWreck
extends Node3D

const HIGHLIGHT_FADE_SPEED: float = 1.8

@export var wreck_name: String = "Ares Wreck Alpha"
@export var scan_summary: String = "Hull breach detected. Passive transponder still responding."
@export var waypoint_name: String = "WRECK ALPHA"
@export var primary_target: bool = false

var inspected: bool = false
var highlight_timer: float = 0.0
var highlight_strength: float = 0.0
var beacon_light: OmniLight3D
var beacon_material: StandardMaterial3D
var beam_material: StandardMaterial3D

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("hero_wreck")
	if get_child_count() == 0:
		_build_visuals()

func _process(delta: float) -> void:
	highlight_timer = max(highlight_timer - delta, 0.0)
	var target_strength := 1.0 if highlight_timer > 0.0 or primary_target else 0.22
	highlight_strength = lerpf(highlight_strength, target_strength, delta * HIGHLIGHT_FADE_SPEED)
	_update_visuals()

func get_interaction_name() -> String:
	return wreck_name

func get_interaction_prompt() -> String:
	if inspected:
		return "Press E or tap INTERACT to review Marvin's wreckage notes."
	return "Press E or tap INTERACT to inspect this wreck cluster."

func get_focus_position() -> Vector3:
	return global_position + Vector3(0.0, 1.8, 0.0)

func interact(player: Node) -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("inspect_wreck"):
		scene.call("inspect_wreck", self, player)

func begin_highlight(duration: float = 9.0) -> void:
	highlight_timer = max(highlight_timer, duration)

func set_primary_target(enabled: bool) -> void:
	primary_target = enabled

func mark_inspected() -> void:
	inspected = true

func _build_visuals() -> void:
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Color(0.18, 0.16, 0.15, 1.0)
	body_material.metallic = 0.42
	body_material.roughness = 0.7

	beacon_material = StandardMaterial3D.new()
	beacon_material.albedo_color = Color(0.12, 0.24, 0.24, 0.8)
	beacon_material.emission_enabled = true
	beacon_material.emission = Color(0.3, 0.9, 1.0, 1.0)
	beacon_material.emission_energy_multiplier = 1.8
	beacon_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beacon_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	beam_material = StandardMaterial3D.new()
	beam_material.albedo_color = Color(0.18, 0.8, 0.92, 0.18)
	beam_material.emission_enabled = true
	beam_material.emission = Color(0.2, 0.85, 1.0, 1.0)
	beam_material.emission_energy_multiplier = 1.2
	beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_material.no_depth_test = true

	_add_part(BoxMesh.new(), Vector3.ZERO, Vector3(2.7, 0.8, 1.5), Vector3(0.18, 0.52, -0.08), body_material)

	var mast := CylinderMesh.new()
	mast.top_radius = 0.18
	mast.bottom_radius = 0.28
	mast.height = 2.2
	_add_part(mast, Vector3(0.0, 1.4, 0.0), Vector3(1.0, 1.0, 1.0), Vector3.ZERO, body_material)

	var fin := BoxMesh.new()
	_add_part(fin, Vector3(-1.4, 1.0, -0.2), Vector3(0.28, 1.45, 2.2), Vector3(-0.3, 0.0, 0.2), body_material)
	_add_part(fin, Vector3(1.35, 0.64, 0.32), Vector3(0.24, 1.1, 1.4), Vector3(0.12, 0.38, -0.26), body_material)

	var hull := BoxMesh.new()
	_add_part(hull, Vector3(0.18, 1.9, -0.7), Vector3(1.15, 0.36, 0.78), Vector3(0.0, 0.64, 0.24), body_material)

	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.22
	beam_mesh.bottom_radius = 0.48
	beam_mesh.height = 6.2
	_add_part(beam_mesh, Vector3(0.0, 3.5, 0.0), Vector3(1.0, 1.0, 1.0), Vector3.ZERO, beam_material)

	var beacon_mesh := SphereMesh.new()
	beacon_mesh.radius = 0.24
	beacon_mesh.height = 0.5
	_add_part(beacon_mesh, Vector3(0.0, 2.55, 0.0), Vector3(1.0, 1.0, 1.0), Vector3.ZERO, beacon_material)

	beacon_light = OmniLight3D.new()
	beacon_light.light_color = Color(0.4, 0.9, 1.0, 1.0)
	beacon_light.omni_range = 8.0
	beacon_light.light_energy = 1.5
	add_child(beacon_light)
	beacon_light.position = Vector3(0.0, 2.7, 0.0)

func _add_part(mesh: PrimitiveMesh, position: Vector3, scale_value: Vector3, rotation_value: Vector3, material: Material) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.scale = scale_value
	mesh_instance.rotation = rotation_value
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)

func _update_visuals() -> void:
	var beacon_energy := 1.6 + (highlight_strength * 4.2)
	if beacon_material != null:
		beacon_material.emission_energy_multiplier = beacon_energy
		beacon_material.albedo_color.a = 0.55 + (highlight_strength * 0.4)
	if beam_material != null:
		beam_material.albedo_color.a = 0.06 + (highlight_strength * 0.18)
		beam_material.emission_energy_multiplier = 0.8 + (highlight_strength * 1.6)
	if beacon_light != null:
		beacon_light.light_energy = 1.4 + (highlight_strength * 4.4)
