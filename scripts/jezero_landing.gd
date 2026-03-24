class_name JezeroLanding
extends Node3D

const TERRAIN_RESOLUTION: int = 256
const TERRAIN_ASSET_DIR: String = "res://assets/mars/jezero"
const LEGACY_FALLBACK_SCENE: String = "res://scenes/landing_valley.tscn"
const ROCK_SCENE_PATH: String = "res://scenes/rock.tscn"
const ROVER_SCENE_PATH: String = "res://scenes/rover.tscn"
const TERRAIN_VISUAL_DATA := preload("res://scripts/terrain_visual_data.gd")
const HEIGHTFIELD_SCRIPT := preload("res://scripts/mars_raster_heightfield.gd")

const HUD_REVEAL_DELAY_SECONDS: float = 1.0
const HUD_REVEAL_DURATION_SECONDS: float = 0.45
const SPAWN_YAW: float = deg_to_rad(-12.0)
const SPAWN_PITCH: float = deg_to_rad(-1.5)
const SPAWN_CAMERA_FOV: float = 66.0

const LIGHT_ROCK_OFFSETS := [
	Vector3(-18.0, 0.0, 10.0),
	Vector3(-11.0, 0.0, 18.0),
	Vector3(-6.0, 0.0, 26.0),
	Vector3(8.0, 0.0, 20.0),
	Vector3(16.0, 0.0, 8.0),
	Vector3(21.0, 0.0, -4.0),
	Vector3(30.0, 0.0, 4.0),
	Vector3(37.0, 0.0, -8.0),
	Vector3(44.0, 0.0, -16.0),
	Vector3(12.0, 0.0, -12.0),
	Vector3(-22.0, 0.0, -8.0),
	Vector3(-28.0, 0.0, 6.0),
]

@export_dir var terrain_asset_dir: String = TERRAIN_ASSET_DIR
@export var fallback_spawn_world_xz: Vector2 = Vector2(0.0, 0.0)
@export var fallback_rover_world_xz: Vector2 = Vector2(38.0, -10.0)

@onready var terrain: MeshInstance3D = $TerrainRoot/Terrain
@onready var terrain_collision: CollisionShape3D = $TerrainRoot/Terrain/StaticBody3D/CollisionShape3D
@onready var player: HeroPlayer = $Player
@onready var props_root: Node3D = $Props
@onready var hud: CanvasItem = $CanvasLayer/HUD
@onready var key_light: DirectionalLight3D = $DirectionalLight3D
@onready var fill_light: DirectionalLight3D = $FillLight
@onready var world_environment: WorldEnvironment = $WorldEnvironment

var heightfield = null
var terrain_min_height: float = 0.0
var terrain_max_height: float = 0.0
var spawn_world_xz: Vector2 = Vector2.ZERO
var rover_world_xz: Vector2 = Vector2.ZERO
var landing_rover: Node3D = null

func _ready() -> void:
	var error: int = _load_heightfield()
	if error != OK:
		push_error("JezeroLanding: failed to load raster terrain assets from %s (error %d)." % [terrain_asset_dir, error])
		call_deferred("_fallback_to_legacy_scene")
		return
	_configure_landing_visuals()
	_build_playable_terrain()
	_spawn_props()
	_position_player()
	_prepare_hud_reveal()
	_send_sudo_ai_context("Player has landed in Jezero crater on a raster-backed terrain patch derived from USGS Mars 2020 data.")
	EventBus.push_mission_log("Landing complete. Explore the Jezero crater patch.")
	if RuntimeFeatures != null and RuntimeFeatures.is_sudo_ai_enabled() and SudoAIAgent:
		SudoAIAgent.notify_gameplay_input_started()

func get_ground_height(x: float, z: float) -> float:
	return _sample_height(x, z)

func get_ground_elevation_meters(x: float, z: float) -> float:
	if heightfield == null:
		return 0.0
	return heightfield.sample_elevation_meters(x, z)

func get_ground_normal(x: float, z: float) -> Vector3:
	var step := _get_sample_step()
	var height_left := _sample_height(x - step, z)
	var height_right := _sample_height(x + step, z)
	var height_back := _sample_height(x, z - step)
	var height_forward := _sample_height(x, z + step)
	return Vector3(height_left - height_right, step * 2.0, height_back - height_forward).normalized()

func get_world_half_size() -> float:
	if heightfield == null:
		return 660.0
	return heightfield.get_world_half_size()

func get_storm_intensity(_world_position: Vector3, _view_direction: Vector3) -> float:
	return 0.0

func handle_voice_command(text: String) -> Dictionary:
	var normalized := text.to_lower().strip_edges()
	if normalized.is_empty():
		return {"command_id": "empty", "response_text": "I did not catch that request."}
	if normalized.contains("status"):
		return _handle_status_command()
	if normalized.contains("rover") or normalized.contains("waypoint") or normalized.contains("mark"):
		return _handle_rover_waypoint_command()
	if normalized.contains("scan"):
		return {"command_id": "scan_unavailable", "response_text": "There are no wreck scan targets in this Jezero landing patch yet. Ask for status or mark the rover instead."}
	if normalized.contains("where") or normalized.contains("location"):
		return _handle_status_command()
	return {"command_id": "unknown", "response_text": "Available Jezero commands are status, rover, and waypoint."}

func _load_heightfield() -> Error:
	heightfield = HEIGHTFIELD_SCRIPT.new()
	var error: int = int(heightfield.load_from_directory(terrain_asset_dir))
	if error != OK:
		return error
	spawn_world_xz = heightfield.spawn_world_xz if heightfield.spawn_world_xz != Vector2.ZERO else fallback_spawn_world_xz
	rover_world_xz = heightfield.rover_world_xz if heightfield.rover_world_xz != Vector2.ZERO else fallback_rover_world_xz
	return OK

func _configure_landing_visuals() -> void:
	MarsExteriorProfile.apply_key_light(key_light)
	MarsExteriorProfile.apply_fill_light(fill_light)

	if world_environment.environment != null:
		var environment := world_environment.environment.duplicate(true) as Environment
		world_environment.environment = environment
		MarsExteriorProfile.apply_sky_and_fog(environment)

	if terrain.material_override is ShaderMaterial:
		var material := (terrain.material_override as ShaderMaterial).duplicate() as ShaderMaterial
		terrain.material_override = material
		MarsExteriorProfile.apply_terrain_shader(material)
		material.set_shader_parameter("surface_map", heightfield.get_surface_texture())
		material.set_shader_parameter("surface_map_strength", heightfield.surface_map_strength)
		material.set_shader_parameter("surface_map_black_point", heightfield.surface_map_black_point)
		material.set_shader_parameter("surface_map_white_point", heightfield.surface_map_white_point)

func _build_playable_terrain() -> void:
	var grid_width := TERRAIN_RESOLUTION + 1
	var vertex_count := grid_width * grid_width
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	vertices.resize(vertex_count)
	normals.resize(vertex_count)
	uvs.resize(vertex_count)

	var half_size := get_world_half_size()
	var min_height := INF
	var max_height := -INF
	for z_index in range(grid_width):
		var v := float(z_index) / float(TERRAIN_RESOLUTION)
		var z := lerpf(-half_size, half_size, v)
		for x_index in range(grid_width):
			var u := float(x_index) / float(TERRAIN_RESOLUTION)
			var x := lerpf(-half_size, half_size, u)
			var vertex_index := z_index * grid_width + x_index
			var sampled_height := _sample_height(x, z)
			vertices[vertex_index] = Vector3(x, sampled_height, z)
			uvs[vertex_index] = Vector2(u, v)
			min_height = minf(min_height, sampled_height)
			max_height = maxf(max_height, sampled_height)

	for z_index in range(TERRAIN_RESOLUTION):
		for x_index in range(TERRAIN_RESOLUTION):
			var top_left := z_index * grid_width + x_index
			var bottom_left := (z_index + 1) * grid_width + x_index
			var top_right := top_left + 1
			var bottom_right := bottom_left + 1
			indices.push_back(top_left)
			indices.push_back(bottom_left)
			indices.push_back(top_right)
			indices.push_back(top_right)
			indices.push_back(bottom_left)
			indices.push_back(bottom_right)

	for triangle_index in range(0, indices.size(), 3):
		var a := indices[triangle_index]
		var b := indices[triangle_index + 1]
		var c := indices[triangle_index + 2]
		var face_normal := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]).normalized()
		normals[a] += face_normal
		normals[b] += face_normal
		normals[c] += face_normal

	for normal_index in range(normals.size()):
		normals[normal_index] = normals[normal_index].normalized()

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var terrain_mesh := ArrayMesh.new()
	terrain_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	terrain.mesh = terrain_mesh
	terrain_collision.shape = terrain_mesh.create_trimesh_shape()
	terrain_min_height = min_height
	terrain_max_height = max_height

	if terrain.material_override is ShaderMaterial:
		var material := terrain.material_override as ShaderMaterial
		material.set_shader_parameter("height_scale", maxf(terrain_max_height - terrain_min_height, 32.0))
		TERRAIN_VISUAL_DATA.apply_to_material(material, vertices, normals, grid_width, terrain_min_height, terrain_max_height)

	_build_terrain_underside_seal(vertices, grid_width)

func _build_terrain_underside_seal(vertices: PackedVector3Array, grid_width: int) -> void:
	if vertices.is_empty():
		return
	var terrain_root := terrain.get_parent() as Node3D
	if terrain_root == null:
		return

	var old_skirt := terrain_root.get_node_or_null("TerrainEdgeSkirt")
	if old_skirt != null:
		old_skirt.queue_free()
	var old_cap := terrain_root.get_node_or_null("TerrainSubFloorCap")
	if old_cap != null:
		old_cap.queue_free()

	var seal_floor_y := terrain_min_height - 120.0
	var seal_outset := get_world_half_size() * 0.45

	var border_indices: Array[int] = []
	var last := grid_width - 1
	for x_index in range(grid_width):
		border_indices.append(x_index)
	for z_index in range(1, grid_width):
		border_indices.append((z_index * grid_width) + last)
	for x_index in range(last - 1, -1, -1):
		border_indices.append((last * grid_width) + x_index)
	for z_index in range(last - 1, 0, -1):
		border_indices.append(z_index * grid_width)
	if border_indices.size() < 3:
		return

	var skirt_vertices := PackedVector3Array()
	var skirt_normals := PackedVector3Array()
	var skirt_indices := PackedInt32Array()
	for border_index in range(border_indices.size()):
		var a_index := border_indices[border_index]
		var b_index := border_indices[(border_index + 1) % border_indices.size()]
		var top_a := vertices[a_index]
		var top_b := vertices[b_index]
		var outward_a := Vector2(top_a.x, top_a.z).normalized()
		var outward_b := Vector2(top_b.x, top_b.z).normalized()
		if outward_a.length_squared() < 0.0001:
			outward_a = Vector2.RIGHT
		if outward_b.length_squared() < 0.0001:
			outward_b = Vector2.RIGHT
		var bottom_a := Vector3(top_a.x + (outward_a.x * seal_outset), seal_floor_y, top_a.z + (outward_a.y * seal_outset))
		var bottom_b := Vector3(top_b.x + (outward_b.x * seal_outset), seal_floor_y, top_b.z + (outward_b.y * seal_outset))
		var side_normal := (bottom_a - top_a).cross(top_b - top_a).normalized()
		if side_normal.length_squared() < 0.0001:
			side_normal = Vector3.UP

		var base_index := skirt_vertices.size()
		skirt_vertices.push_back(top_a)
		skirt_vertices.push_back(bottom_a)
		skirt_vertices.push_back(top_b)
		skirt_vertices.push_back(bottom_b)
		for _normal_slot in range(4):
			skirt_normals.push_back(side_normal)
		skirt_indices.push_back(base_index)
		skirt_indices.push_back(base_index + 1)
		skirt_indices.push_back(base_index + 2)
		skirt_indices.push_back(base_index + 2)
		skirt_indices.push_back(base_index + 1)
		skirt_indices.push_back(base_index + 3)

	var skirt_arrays := []
	skirt_arrays.resize(Mesh.ARRAY_MAX)
	skirt_arrays[Mesh.ARRAY_VERTEX] = skirt_vertices
	skirt_arrays[Mesh.ARRAY_NORMAL] = skirt_normals
	skirt_arrays[Mesh.ARRAY_INDEX] = skirt_indices

	var skirt_mesh := ArrayMesh.new()
	skirt_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, skirt_arrays)
	var seal_material := _make_terrain_seal_material()

	var skirt_instance := MeshInstance3D.new()
	skirt_instance.name = "TerrainEdgeSkirt"
	skirt_instance.mesh = skirt_mesh
	skirt_instance.material_override = seal_material
	skirt_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	terrain_root.add_child(skirt_instance)

func _make_terrain_seal_material() -> StandardMaterial3D:
	return MarsExteriorProfile.make_seal_material()

func _sample_height(x: float, z: float) -> float:
	if heightfield == null:
		return 0.0
	return heightfield.sample_world_height(x, z)

func _get_sample_step() -> float:
	return (get_world_half_size() * 2.0) / float(TERRAIN_RESOLUTION)

func _spawn_props() -> void:
	for child in props_root.get_children():
		child.queue_free()

	var rover_scene := load(ROVER_SCENE_PATH) as PackedScene
	if rover_scene == null:
		push_warning("JezeroLanding: Failed to load rover scene.")
		return
	landing_rover = rover_scene.instantiate() as Node3D
	props_root.add_child(landing_rover)
	landing_rover.scale = Vector3.ONE * 1.24
	landing_rover.rotation.y = deg_to_rad(-28.0)
	_place_on_ground(landing_rover, Vector3(rover_world_xz.x, 0.0, rover_world_xz.y), 1.08)

	var rock_scene := load(ROCK_SCENE_PATH) as PackedScene
	if rock_scene == null:
		push_warning("JezeroLanding: Failed to load rock scene.")
		return
	for rock_index in range(LIGHT_ROCK_OFFSETS.size()):
		var rock := rock_scene.instantiate() as Node3D
		props_root.add_child(rock)
		var scale_factor := 0.44 + (float(rock_index % 5) * 0.14)
		rock.scale = Vector3.ONE * scale_factor
		rock.rotation.y = deg_to_rad(float((rock_index * 37) % 360))
		var rock_world: Vector3 = Vector3(spawn_world_xz.x, 0.0, spawn_world_xz.y) + LIGHT_ROCK_OFFSETS[rock_index]
		_place_on_ground(rock, rock_world, 0.26)

func _place_on_ground(node: Node3D, position: Vector3, clearance: float) -> void:
	node.global_position = position
	node.global_position.y = _sample_height(position.x, position.z) + clearance

func _position_player() -> void:
	player.global_position = Vector3(spawn_world_xz.x, 0.0, spawn_world_xz.y)
	player.global_position.y = _sample_height(spawn_world_xz.x, spawn_world_xz.y) + _get_player_clearance()
	player.velocity = Vector3.ZERO
	player.rotation = Vector3.ZERO
	player.rotation.y = SPAWN_YAW
	player.look_pitch = SPAWN_PITCH
	player.pitch_pivot.rotation.x = SPAWN_PITCH
	GameState.set_respawn_transform(player.global_position, player.rotation.y)

	var camera := player.get_node_or_null("BreathPivot/TiltPivot/PitchPivot/Camera3D") as Camera3D
	if camera != null:
		camera.fov = SPAWN_CAMERA_FOV

func _get_player_clearance() -> float:
	var collision_shape := player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null or collision_shape.shape == null:
		return 1.7

	if collision_shape.shape is CapsuleShape3D:
		var capsule_shape := collision_shape.shape as CapsuleShape3D
		return (capsule_shape.height * 0.5) + capsule_shape.radius + 0.2
	return 1.7

func _prepare_hud_reveal() -> void:
	if hud == null:
		return
	hud.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var delay_timer := get_tree().create_timer(HUD_REVEAL_DELAY_SECONDS)
	delay_timer.timeout.connect(_reveal_hud)

func _reveal_hud() -> void:
	if hud == null:
		return
	var reveal_tween := create_tween()
	reveal_tween.tween_property(hud, "modulate:a", 1.0, HUD_REVEAL_DURATION_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _handle_rover_waypoint_command() -> Dictionary:
	if landing_rover == null or not is_instance_valid(landing_rover):
		return {"command_id": "rover_missing", "response_text": "The Jezero landing rover is not available to mark right now."}
	if player != null and player.has_method("set_waypoint_target"):
		player.call("set_waypoint_target", landing_rover, "Landing Rover")
	_send_sudo_ai_context("Marked the Jezero rover as the active waypoint.")
	return {"command_id": "mark_rover", "response_text": "Waypoint locked. Guiding you toward the Jezero landing rover now."}

func _handle_status_command() -> Dictionary:
	var rover_distance := -1.0
	if landing_rover != null and is_instance_valid(landing_rover):
		rover_distance = player.global_position.distance_to(landing_rover.global_position)
	var status_text := "Jezero landing site is stable. Rover distance is %s and current elevation is %.1f meters above the areoid." % [
		("%.0f meters" % rover_distance) if rover_distance >= 0.0 else "unknown",
		get_ground_elevation_meters(player.global_position.x, player.global_position.z),
	]
	_send_sudo_ai_context(status_text)
	return {"command_id": "status", "response_text": status_text}

func _send_sudo_ai_context(text: String) -> void:
	if RuntimeFeatures != null and RuntimeFeatures.is_sudo_ai_enabled() and SudoAIAgent and SudoAIAgent.has_method("set_scene_context"):
		SudoAIAgent.set_scene_context(text)

func _fallback_to_legacy_scene() -> void:
	if ResourceLoader.exists(LEGACY_FALLBACK_SCENE):
		get_tree().change_scene_to_file(LEGACY_FALLBACK_SCENE)
