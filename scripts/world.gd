class_name WorldScene
extends Node3D

const TERRAIN_RESOLUTION: int = 128
const ROCK_SCENE := preload("res://scenes/rock.tscn")
const DRONE_SCENE := preload("res://scenes/drone.tscn")
const DEBRIS_SCENE := preload("res://scenes/debris_cube.tscn")
const BASECAMP_TERMINAL_SCENE := preload("res://scenes/basecamp_terminal.tscn")
const ROCK_LAYOUTS := [
	Vector3(22.0, 0.0, 10.0),
	Vector3(-26.0, 0.0, 6.0),
	Vector3(34.0, 0.0, -28.0),
	Vector3(-18.0, 0.0, -24.0),
	Vector3(8.0, 0.0, -42.0),
	Vector3(-36.0, 0.0, 26.0),
]
const DEBRIS_LAYOUTS := [
	Vector3(0.0, 0.0, 18.0),
	Vector3(-18.0, 0.0, 4.0),
	Vector3(16.0, 0.0, -10.0),
	Vector3(-28.0, 0.0, -18.0),
	Vector3(30.0, 0.0, 8.0),
	Vector3(-6.0, 0.0, -32.0),
	Vector3(22.0, 0.0, -32.0),
	Vector3(-24.0, 0.0, 22.0),
]
const BASECAMP_TERMINAL_POSITION := Vector3(0.0, 0.0, 77.0)
const BASECAMP_SPAWN_POSITION := Vector3(0.0, 0.0, 92.0)
const ROVER_POSITION := Vector3(14.0, 0.0, 70.0)
const DRONE_POSITION := Vector3(-16.0, 0.0, 68.0)

@onready var navigation_region: NavigationRegion3D = $NavigationRegion3D
@onready var terrain: MeshInstance3D = $NavigationRegion3D/Terrain
@onready var terrain_collision: CollisionShape3D = $NavigationRegion3D/Terrain/StaticBody3D/CollisionShape3D
@onready var player: CharacterBody3D = $Player
@onready var rover: CharacterBody3D = $Rover
@onready var props_root: Node3D = $Props

var terrain_noise: FastNoiseLite
var terrain_size: float = 340.0
var terrain_height_scale: float = 85.0

func _ready() -> void:
	_cache_terrain_settings()
	_configure_navigation_mesh()
	_build_playable_terrain()
	_position_core_actors()
	_spawn_interactables()
	call_deferred("_bake_navigation_mesh")

func _cache_terrain_settings() -> void:
	var plane_mesh := terrain.mesh as PlaneMesh
	if plane_mesh:
		terrain_size = min(plane_mesh.size.x, terrain_size)

	var shader_material := terrain.material_override as ShaderMaterial
	if shader_material:
		terrain_height_scale = float(shader_material.get_shader_parameter("height_scale"))
		var height_map := shader_material.get_shader_parameter("height_map") as NoiseTexture2D
		if height_map and height_map.noise is FastNoiseLite:
			terrain_noise = height_map.noise as FastNoiseLite

	if terrain_noise == null:
		terrain_noise = FastNoiseLite.new()
		terrain_noise.seed = 1337
		terrain_noise.frequency = 0.012
		terrain_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		terrain_noise.fractal_octaves = 8
		terrain_noise.fractal_gain = 0.55

func _configure_navigation_mesh() -> void:
	var navigation_mesh := navigation_region.navigation_mesh
	if navigation_mesh == null:
		return

	navigation_mesh.cell_size = 2.0
	navigation_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navigation_mesh.cell_height = 0.5
	navigation_mesh.agent_height = 2.0
	navigation_mesh.agent_radius = 2.0
	navigation_mesh.agent_max_climb = 2.0

func _position_core_actors() -> void:
	player.global_position = BASECAMP_SPAWN_POSITION
	player.rotation = Vector3.ZERO
	_place_actor_on_terrain(player)
	GameState.set_respawn_transform(player.global_position, player.rotation.y)

	rover.global_position = ROVER_POSITION
	_place_actor_on_terrain(rover)

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

	var half_size := terrain_size * 0.5
	for z_index in range(grid_width):
		var v := float(z_index) / float(TERRAIN_RESOLUTION)
		var z := lerpf(-half_size, half_size, v)
		for x_index in range(grid_width):
			var u := float(x_index) / float(TERRAIN_RESOLUTION)
			var x := lerpf(-half_size, half_size, u)
			var vertex_index := z_index * grid_width + x_index
			vertices[vertex_index] = Vector3(x, _sample_height(x, z), z)
			uvs[vertex_index] = Vector2(u, v)

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

	for vertex_index in range(normals.size()):
		normals[vertex_index] = normals[vertex_index].normalized()

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

func _place_actor_on_terrain(actor: CharacterBody3D) -> void:
	if actor == null:
		return

	var clearance := _get_actor_clearance(actor)
	_snap_node_to_ground(actor, clearance)
	actor.velocity = Vector3.ZERO

func _snap_node_to_ground(node: Node3D, clearance: float) -> void:
	var node_position := node.global_position
	node_position.y = _sample_height(node_position.x, node_position.z) + clearance
	node.global_position = node_position

func _get_actor_clearance(actor: CharacterBody3D) -> float:
	var collision_shape := actor.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null or collision_shape.shape == null:
		return 2.0

	var shape := collision_shape.shape
	if shape is CapsuleShape3D:
		var capsule_shape := shape as CapsuleShape3D
		return (capsule_shape.height * 0.5) + capsule_shape.radius + 0.2
	if shape is BoxShape3D:
		var box_shape := shape as BoxShape3D
		return (box_shape.size.y * 0.5) + 0.2
	if shape is SphereShape3D:
		var sphere_shape := shape as SphereShape3D
		return sphere_shape.radius + 0.2

	return 2.0

func _sample_height(x: float, z: float) -> float:
	var radial: float = Vector2(x, z).length() / max(terrain_size * 0.5, 0.001)
	var crater_mask: float = clampf(1.0 - radial, 0.0, 1.0)
	var broad_noise: float = terrain_noise.get_noise_2d(x * 0.85, z * 0.85) * terrain_height_scale * 0.16
	var detail_noise: float = terrain_noise.get_noise_2d((x * 2.5) + 91.0, (z * 2.5) - 67.0) * terrain_height_scale * 0.04
	var crater_basin: float = -pow(crater_mask, 2.15) * terrain_height_scale * 0.58
	var crater_rim: float = _smoothstep(0.38, 0.8, radial) * terrain_height_scale * 0.34
	var shelves: float = sin((x + z) * 0.05) * 1.8 * clampf(radial, 0.0, 1.0)
	var height: float = 28.0 + broad_noise + detail_noise + crater_basin + crater_rim + shelves

	var basecamp_distance: float = Vector2(x - BASECAMP_TERMINAL_POSITION.x, z - BASECAMP_TERMINAL_POSITION.z).length()
	if basecamp_distance < 22.0:
		var pad_blend: float = 1.0 - clampf(basecamp_distance / 22.0, 0.0, 1.0)
		height = lerpf(height, 41.0, pad_blend * 0.88)

	return height

func get_ground_height(x: float, z: float) -> float:
	return _sample_height(x, z)

func get_ground_normal(x: float, z: float) -> Vector3:
	var sample_step := terrain_size / float(TERRAIN_RESOLUTION)
	var height_left := _sample_height(x - sample_step, z)
	var height_right := _sample_height(x + sample_step, z)
	var height_back := _sample_height(x, z - sample_step)
	var height_forward := _sample_height(x, z + sample_step)
	return Vector3(height_left - height_right, sample_step * 2.0, height_back - height_forward).normalized()

func get_world_half_size() -> float:
	return terrain_size * 0.5

func _spawn_interactables() -> void:
	if props_root.get_child_count() > 0:
		return

	var terminal := BASECAMP_TERMINAL_SCENE.instantiate() as Node3D
	props_root.add_child(terminal)
	terminal.global_position = BASECAMP_TERMINAL_POSITION
	_snap_node_to_ground(terminal, 0.2)

	for rock_offset in ROCK_LAYOUTS:
		var rock := ROCK_SCENE.instantiate() as Node3D
		props_root.add_child(rock)
		rock.global_position = Vector3(rock_offset.x, 0.0, rock_offset.z)
		_snap_node_to_ground(rock, 0.7)

	for debris_offset in DEBRIS_LAYOUTS:
		var debris := DEBRIS_SCENE.instantiate() as Node3D
		props_root.add_child(debris)
		debris.global_position = Vector3(debris_offset.x, 0.0, debris_offset.z)
		_snap_node_to_ground(debris, 1.0)

	var drone := DRONE_SCENE.instantiate() as Node3D
	props_root.add_child(drone)
	drone.global_position = DRONE_POSITION
	_snap_node_to_ground(drone, 4.4)

	EventBus.push_mission_log("Basecamp deployed. Recover the glowing debris cubes across the crater.")

func _bake_navigation_mesh() -> void:
	if navigation_region.navigation_mesh == null:
		return

	navigation_region.bake_navigation_mesh(true)

func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	var t := clampf((value - edge0) / max(edge1 - edge0, 0.001), 0.0, 1.0)
	return t * t * (3.0 - (2.0 * t))
