class_name LandingValley
extends Node3D

const TERRAIN_RESOLUTION: int = 256
const TERRAIN_SIZE: float = 1320.0
const BASE_HEIGHT: float = 30.0
const HEIGHT_SCALE: float = 74.0
# Camera / spawn locked for STRICT-COPY.jpg composition:
# Horizon at ~48% frame height, rover at ~60% width / 61% height.
const SPAWN_POSITION: Vector3 = Vector3(8.0, 0.0, 216.0)
const SPAWN_YAW: float = deg_to_rad(-2.4)
const SPAWN_PITCH: float = deg_to_rad(-1.8)
const SPAWN_CAMERA_FOV: float = 62.0
const ROVER_POSITION: Vector3 = Vector3(66.0, 0.0, 82.0)
const HUD_REVEAL_DELAY_SECONDS: float = 1.0
const HUD_REVEAL_DURATION_SECONDS: float = 0.45

const STRATA_COUNT: float = 12.0
const STRATA_SOFTNESS: float = 0.35
const TALUS_STRENGTH: float = 0.42

const MESA_PROFILES := [
	{"center": Vector2(-248.0, 108.0), "radius": Vector2(128.0, 168.0), "height": 256.0, "rotation": -0.244, "lean": 0.24, "terrace_strength": 0.22}, # LEFT MEGA-MESA
	{"center": Vector2(-168.0, 78.0), "radius": Vector2(18.0, 38.0), "height": 158.0, "rotation": -0.104, "lean": 0.08, "terrace_strength": 0.16}, # LEFT SPIRE
	{"center": Vector2(-226.0, 142.0), "radius": Vector2(92.0, 62.0), "height": 42.0, "rotation": -0.139, "lean": 0.06, "terrace_strength": 0.06}, # LEFT SLUMP
	{"center": Vector2(-22.0, -48.0), "radius": Vector2(78.0, 94.0), "height": 128.0, "rotation": 0.07, "lean": 0.06, "terrace_strength": 0.2}, # CENTER BROAD
	{"center": Vector2(16.0, -82.0), "radius": Vector2(22.0, 34.0), "height": 96.0, "rotation": 0.035, "lean": 0.04, "terrace_strength": 0.14}, # CENTER STACK 1
	{"center": Vector2(-48.0, -98.0), "radius": Vector2(16.0, 28.0), "height": 82.0, "rotation": -0.052, "lean": 0.05, "terrace_strength": 0.12}, # CENTER STACK 2
	{"center": Vector2(168.0, -28.0), "radius": Vector2(52.0, 72.0), "height": 112.0, "rotation": -0.087, "lean": 0.09, "terrace_strength": 0.18}, # RIGHT MID
	{"center": Vector2(132.0, -68.0), "radius": Vector2(14.0, 28.0), "height": 78.0, "rotation": 0.052, "lean": 0.03, "terrace_strength": 0.1}, # RIGHT SPIRE
	{"center": Vector2(312.0, 32.0), "radius": Vector2(98.0, 156.0), "height": 218.0, "rotation": 0.174, "lean": -0.16, "terrace_strength": 0.2}, # FAR-RIGHT HERO
	# Distant ridges
	{"center": Vector2(-86.0, -148.0), "radius": Vector2(28.0, 48.0), "height": 68.0, "rotation": 0.104, "lean": 0.04, "terrace_strength": 0.08},
	{"center": Vector2(36.0, -208.0), "radius": Vector2(46.0, 52.0), "height": 56.0, "rotation": -0.104, "lean": 0.05, "terrace_strength": 0.08},
	{"center": Vector2(148.0, -164.0), "radius": Vector2(36.0, 46.0), "height": 62.0, "rotation": 0.104, "lean": -0.03, "terrace_strength": 0.08},
	{"center": Vector2(318.0, -224.0), "radius": Vector2(58.0, 82.0), "height": 92.0, "rotation": 0.192, "lean": -0.08, "terrace_strength": 0.15},
	{"center": Vector2(-368.0, -178.0), "radius": Vector2(76.0, 92.0), "height": 76.0, "rotation": -0.139, "lean": 0.06, "terrace_strength": 0.16},
	{"center": Vector2(248.0, -142.0), "radius": Vector2(42.0, 58.0), "height": 72.0, "rotation": 0.07, "lean": -0.04, "terrace_strength": 0.1},
	{"center": Vector2(-312.0, 28.0), "radius": Vector2(64.0, 78.0), "height": 84.0, "rotation": -0.21, "lean": 0.08, "terrace_strength": 0.12}
]

const ROCK_SCENE_PATH: String = "res://scenes/rock.tscn"
const ROVER_SCENE_PATH: String = "res://scenes/rover.tscn"
const TERRAIN_VISUAL_DATA := preload("res://scripts/terrain_visual_data.gd")

const LIGHT_ROCK_POSITIONS := [
	Vector3(-132.0, 0.0, 196.0),
	Vector3(-96.0, 0.0, 182.0),
	Vector3(-58.0, 0.0, 168.0),
	Vector3(-18.0, 0.0, 154.0),
	Vector3(26.0, 0.0, 132.0),
	Vector3(58.0, 0.0, 110.0),
	Vector3(112.0, 0.0, 88.0),
	Vector3(148.0, 0.0, 62.0),
	Vector3(-42.0, 0.0, 96.0),
	Vector3(4.0, 0.0, 56.0),
	Vector3(-20.0, 0.0, 24.0),
	Vector3(42.0, 0.0, -14.0),
]

@onready var terrain: MeshInstance3D = $TerrainRoot/Terrain
@onready var terrain_collision: CollisionShape3D = $TerrainRoot/Terrain/StaticBody3D/CollisionShape3D
@onready var player: HeroPlayer = $Player
@onready var props_root: Node3D = $Props
@onready var hud: CanvasItem = $CanvasLayer/HUD
@onready var key_light: DirectionalLight3D = $DirectionalLight3D
@onready var fill_light: DirectionalLight3D = $FillLight
@onready var world_environment: WorldEnvironment = $WorldEnvironment

var macro_noise: FastNoiseLite
var detail_noise: FastNoiseLite
var erosion_noise: FastNoiseLite
var micro_noise: FastNoiseLite      # Fine pebble-scale displacement
var terrain_min_height: float = 0.0
var terrain_max_height: float = 0.0
var clone_iteration_id: int = 14
var clone_variation: float = 0.0
var landing_rover: Node3D = null

func _ready() -> void:
	if GameState != null and GameState.has_method("get_clone_iteration"):
		clone_iteration_id = int(GameState.get_clone_iteration())
	clone_variation = float(posmod(clone_iteration_id, 9)) / 9.0
	_build_noise()
	_configure_landing_visuals()
	_build_playable_terrain()
	_spawn_props()
	_position_player()
	_prepare_hud_reveal()
	_send_sudo_ai_context("Player has landed in the strict-copy valley. The rover is parked in the mid-ground corridor and the landing basin is clear for exploration.")
	EventBus.push_mission_log("Landing complete. Explore the valley.")
	# Proactively boot SudoAI so it greets the player on scene load
	# instead of waiting for the first keyboard/mouse input.
	if SudoAIAgent:
		SudoAIAgent.notify_gameplay_input_started()

func get_ground_height(x: float, z: float) -> float:
	return _sample_height(x, z)

func get_ground_normal(x: float, z: float) -> Vector3:
	var step := TERRAIN_SIZE / float(TERRAIN_RESOLUTION)
	var height_left := _sample_height(x - step, z)
	var height_right := _sample_height(x + step, z)
	var height_back := _sample_height(x, z - step)
	var height_forward := _sample_height(x, z + step)
	return Vector3(height_left - height_right, step * 2.0, height_back - height_forward).normalized()

func get_world_half_size() -> float:
	return TERRAIN_SIZE * 0.5

func get_storm_intensity(_world_position: Vector3, _view_direction: Vector3) -> float:
	return 0.0

func handle_voice_command(text: String) -> Dictionary:
	var normalized := text.to_lower().strip_edges()
	if normalized.is_empty():
		return {"command_id": "empty", "response_text": "Sudo AI here. I did not catch that request."}
	if normalized.contains("status"):
		return _handle_status_command()
	if normalized.contains("rover") or normalized.contains("waypoint") or normalized.contains("mark"):
		return _handle_rover_waypoint_command()
	if normalized.contains("scan"):
		return {"command_id": "scan_unavailable", "response_text": "There are no wreck scan targets in this landing valley yet. Ask for status or mark the rover instead."}
	if normalized.contains("where") or normalized.contains("location"):
		return _handle_status_command()
	return {"command_id": "unknown", "response_text": "Available valley commands are status, rover, and waypoint."}

func _build_noise() -> void:
	# Macro terrain shape — broad low-frequency hills
	macro_noise = FastNoiseLite.new()
	macro_noise.seed = 8207
	macro_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	macro_noise.frequency = 0.0034
	macro_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	macro_noise.fractal_octaves = 5
	macro_noise.fractal_gain = 0.50
	macro_noise.fractal_lacunarity = 2.1

	# Detail noise — mid-frequency surface roughness
	detail_noise = FastNoiseLite.new()
	detail_noise.seed = 4271 + posmod(clone_iteration_id, 23)
	detail_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	detail_noise.frequency = 0.016
	detail_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	detail_noise.fractal_octaves = 4
	detail_noise.fractal_gain = 0.46
	detail_noise.fractal_lacunarity = 2.1

	# Erosion noise — domain-warped fluvial channels
	erosion_noise = FastNoiseLite.new()
	erosion_noise.seed = 1931 + posmod(clone_iteration_id, 17)
	erosion_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	erosion_noise.frequency = 0.0085
	erosion_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	erosion_noise.fractal_octaves = 3
	erosion_noise.fractal_gain = 0.58

	# Micro noise — pebble-scale rock texture (very high frequency, tiny amplitude)
	micro_noise = FastNoiseLite.new()
	micro_noise.seed = 6317 + posmod(clone_iteration_id, 31)
	micro_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	micro_noise.frequency = 0.11
	micro_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	micro_noise.fractal_octaves = 3
	micro_noise.fractal_gain = 0.50
	micro_noise.fractal_lacunarity = 2.3

func _configure_landing_visuals() -> void:
	# ── Apply shared visual profile (STRICT-COPY.jpg reference) ──────
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

	var half_size := TERRAIN_SIZE * 0.5
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
		material.set_shader_parameter("height_scale", maxf(terrain_max_height - terrain_min_height, HEIGHT_SCALE * 2.0))
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

	var seal_floor_y := terrain_min_height - maxf(HEIGHT_SCALE * 3.4, 240.0)
	var seal_outset := TERRAIN_SIZE * 0.35

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
	var clone_offset_x: float = (clone_variation - 0.5) * 38.0
	var clone_offset_z: float = (clone_variation - 0.5) * -24.0

	# ── Domain warp for erosion — offset x,z by a low-freq field before sampling
	var warp_x := erosion_noise.get_noise_2d(x * 0.006 + 3.7, z * 0.006 - 2.1) * 28.0
	var warp_z := erosion_noise.get_noise_2d(x * 0.006 - 1.4, z * 0.006 + 4.8) * 28.0

	var macro_shape  := macro_noise.get_noise_2d(x, z) * 8.2
	var erosion_shape := erosion_noise.get_noise_2d(
		(x + warp_x) * 0.72 + 18.0 + clone_offset_x,
		(z + warp_z) * 0.72 - 12.0 + clone_offset_z) * 5.2
	var detail_shape := detail_noise.get_noise_2d((x * 1.4) - 30.0, (z * 1.4) + 11.0) * 2.1

	# Pebble/rock micro-displacement — very small but helps collision and looks
	var micro_shape  := micro_noise.get_noise_2d(x, z) * 0.38

	var dune_a := sin((x * 0.013) - (z * 0.007) + 0.8) * 2.4
	var dune_b := sin((x * 0.007) + (z * 0.015) - 1.1) * 1.6

	var corridor_progress := clampf((SPAWN_POSITION.z - z) / 620.0, 0.0, 1.0)
	var corridor_center := lerpf(18.0, -8.0, corridor_progress)
	var corridor_width := lerpf(68.0, 118.0, corridor_progress)
	var cw := (x - corridor_center) / corridor_width
	var corridor_mask := exp(-(cw * cw))
	var corridor_carve := corridor_mask * lerpf(8.2, 10.9, corridor_progress)
	var foreground_lane := _gaussian_ellipse(x, z, Vector2(24.0, 172.0), Vector2(298.0, 118.0), deg_to_rad(-1.5)) * 9.2

	# Wind-directed dune corridors that wrap around mesa bases
	var foreground_dune := _gaussian_ellipse(x, z, Vector2(88.0, 148.0), Vector2(138.0, 58.0), deg_to_rad(-12.0)) * 4.6
	var right_berm := _gaussian_ellipse(x, z, Vector2(186.0, 112.0), Vector2(102.0, 46.0), deg_to_rad(6.0)) * 6.2
	var left_shelf := _gaussian_ellipse(x, z, Vector2(-126.0, 98.0), Vector2(114.0, 46.0), deg_to_rad(14.0)) * 4.4
	# Saddle dune between left mega-mesa and center corridor
	var saddle_dune := _gaussian_ellipse(x, z, Vector2(-142.0, 52.0), Vector2(68.0, 38.0), deg_to_rad(-18.0)) * 3.8

	var basin_region := _crater_region(x, z, Vector2(-264.0, -238.0), 214.0, 34.0, 21.0)
	var basecamp_pad := _gaussian_ellipse(x, z, Vector2(-242.0, -174.0), Vector2(136.0, 76.0), deg_to_rad(18.0)) * 12.5
	var hero_demo_basin := _gaussian_ellipse(x, z, Vector2(258.0, -226.0), Vector2(206.0, 136.0), deg_to_rad(-14.0)) * 11.5
	var wreck_corridor := _gaussian_ellipse(x, z, Vector2(202.0, -138.0), Vector2(128.0, 74.0), deg_to_rad(-22.0)) * 7.8

	# ── STRICT-COPY.jpg Landmark Mesas ────────────────────────────────
	var landmark_height := 0.0
	var proximity_mask := 0.0
	for m in MESA_PROFILES:
		var mh_data := _mesa_height_v2(x, z, m.center, m.radius, m.height, m.rotation, m.lean, m.terrace_strength)
		landmark_height = maxf(landmark_height, mh_data.height)
		proximity_mask = maxf(proximity_mask, mh_data.proximity)

	# ── Fluvial erosion gullies on slopes ─────────────────────────────
	# Carve narrow channels into cliff flanks using domain-warped ridged noise
	var gully_mask := clampf(proximity_mask * 2.4 - 0.6, 0.0, 1.0)
	var gully_noise := erosion_noise.get_noise_2d(
		(x + warp_x * 0.5) * 1.8 + 9.2,
		(z + warp_z * 0.5) * 1.8 - 7.4)
	var gully_depth := (1.0 - absf(gully_noise)) * gully_mask * 3.2

	var half_size := TERRAIN_SIZE * 0.5
	var edge_distance := maxf(absf(x), absf(z))
	var edge_rim := _smoothstep(half_size - 180.0, half_size - 30.0, edge_distance)
	var edge_raise := edge_rim * edge_rim * 110.0

	var base_h := BASE_HEIGHT + macro_shape + erosion_shape + detail_shape + micro_shape \
		+ _gaussian_ellipse(x, z, Vector2(0, 0), Vector2(300, 300), 0.0) * 8.0
	var final_h := maxf(base_h, landmark_height)

	# Wind-Shadow Dunes
	var shadow_dune_f := 0.016
	var shadow_dune_freq := 1.8 + micro_noise.get_noise_2d(x * 0.008, z * 0.008) * 0.5
	var dune_bleed := macro_noise.get_noise_2d(x * shadow_dune_f, z * shadow_dune_f)
	var total_dunes := (dune_a + dune_b + foreground_dune + right_berm + left_shelf + saddle_dune) * (dune_bleed + 0.5)

	var dune_mask := clampf(1.0 - proximity_mask * 1.5, 0.0, 1.0)
	final_h += total_dunes * shadow_dune_freq * dune_mask

	# Basecamp and other regions
	final_h += basecamp_pad + edge_raise
	final_h -= corridor_carve + foreground_lane + basin_region + hero_demo_basin + wreck_corridor

	# Gully carving on cliff flanks (only affects elevated areas near mesas)
	final_h -= gully_depth

	# Spawn stabilization — flatten around the player start point
	var dist_to_spawn := Vector2(x - SPAWN_POSITION.x, z - SPAWN_POSITION.z).length()
	if dist_to_spawn < 128.0:
		var weight := 1.0 - _smoothstep(64.0, 128.0, dist_to_spawn)
		final_h = lerpf(final_h, SPAWN_POSITION.y + micro_noise.get_noise_2d(x * 0.2, z * 0.2) * 0.06, weight)

	return final_h

# Composite Geographic Primitive: Pedestal -> Cliff -> Caprock
func _mesa_height_v2(
	x: float,
	z: float,
	center: Vector2,
	radius: Vector2,
	height: float,
	rotation: float,
	lean: float,
	terrace_strength: float
) -> Dictionary:
	var local := Vector2(x - center.x, z - center.y).rotated(-rotation)
	local.x += local.y * lean
	var lx := local.x / maxf(radius.x, 0.001)
	var ly := local.y / maxf(radius.y, 0.001)
	var dist_sq := (lx * lx) + (ly * ly)
	var dist := sqrt(dist_sq)
	
	if dist >= 1.25:
		return {"height": 0.0, "proximity": 0.0}

	var radial := 1.0 - clampf(dist, 0.0, 1.0)
	var proximity := clampf(1.15 - dist, 0.0, 1.0)

	# 1. Pedestal (Broad base)
	var pedestal := pow(radial, 0.45) * 0.25
	
	# 2. Cliff Wall (Steep section)
	var cliff := _smoothstep(0.12, 0.42, radial) * 0.65
	
	# 3. Caprock Plateau (Flat top)
	var caprock := _smoothstep(0.38, 0.95, radial) * 0.18
	
	# 4. Talus Ramps (Accumulated debris at base)
	var talus_mask := _smoothstep(0.0, 0.28, dist) * (1.0 - _smoothstep(0.28, 0.52, dist))
	var talus := talus_mask * TALUS_STRENGTH * 0.12

	# Erosion and variation
	var erosion := erosion_noise.get_noise_2d((local.x + center.x) * 0.65, (local.y + center.y) * 0.65) * 0.08
	var detail := detail_noise.get_noise_2d(x * 0.42, z * 0.42) * 0.02
	
	var h_raw := pedestal + cliff + caprock + talus + erosion + detail
	var h_final := maxf(0.0, height * clampf(h_raw, 0.0, 1.25))

	# 5. Sedimentary Strata (Quantization)
	if h_final > 2.0:
		var strata_h: float = floor(h_final / (height / STRATA_COUNT)) * (height / STRATA_COUNT)
		var strata_mix: float = detail_noise.get_noise_2d(x * 0.8, z * 0.8) * STRATA_SOFTNESS
		h_final = lerpf(h_final, strata_h, 0.72 + strata_mix)

	return {"height": h_final, "proximity": proximity}

func _mesa_height(
	x: float,
	z: float,
	center: Vector2,
	radius: Vector2,
	height: float,
	rotation: float,
	lean: float,
	terrace_strength: float
) -> float:
	return _mesa_height_v2(x, z, center, radius, height, rotation, lean, terrace_strength).height

func _gaussian_ellipse(x: float, z: float, center: Vector2, radius: Vector2, rotation: float) -> float:
	var local := Vector2(x - center.x, z - center.y).rotated(-rotation)
	var nx := local.x / maxf(radius.x, 0.001)
	var nz := local.y / maxf(radius.y, 0.001)
	return exp(-((nx * nx) + (nz * nz)) * 2.4)

func _crater_region(x: float, z: float, center: Vector2, radius: float, depth: float, rim_height: float) -> float:
	var distance_to_center := Vector2(x - center.x, z - center.y).length()
	var basin_factor := clampf(1.0 - (distance_to_center / maxf(radius, 0.001)), 0.0, 1.0)
	var basin := (basin_factor * basin_factor) * depth
	var rim_inner := radius * 0.76
	var rim_outer := radius * 1.18
	var rim_a := _smoothstep(rim_inner, radius, distance_to_center)
	var rim_b := 1.0 - _smoothstep(radius, rim_outer, distance_to_center)
	var rim := maxf(rim_a * rim_b, 0.0) * rim_height
	return basin - rim

func _spawn_props() -> void:
	for child in props_root.get_children():
		child.queue_free()

	var rover_scene := load(ROVER_SCENE_PATH) as PackedScene
	if rover_scene == null:
		push_warning("LandingValley: Failed to load rover scene.")
		return
	landing_rover = rover_scene.instantiate() as Node3D
	props_root.add_child(landing_rover)
	landing_rover.scale = Vector3.ONE * 1.28
	landing_rover.rotation.y = deg_to_rad(-32.0)
	_place_on_ground(landing_rover, ROVER_POSITION, 1.08)

	var rock_scene := load(ROCK_SCENE_PATH) as PackedScene
	if rock_scene == null:
		push_warning("LandingValley: Failed to load rock scene.")
		return
	for rock_index in range(LIGHT_ROCK_POSITIONS.size()):
		var rock := rock_scene.instantiate() as Node3D
		props_root.add_child(rock)
		var scale_factor := 0.48 + (float(rock_index % 5) * 0.16)
		rock.scale = Vector3.ONE * scale_factor
		rock.rotation.y = deg_to_rad(float((rock_index * 37) % 360))
		_place_on_ground(rock, LIGHT_ROCK_POSITIONS[rock_index], 0.32)

func _place_on_ground(node: Node3D, position: Vector3, clearance: float) -> void:
	node.global_position = position
	node.global_position.y = _sample_height(position.x, position.z) + clearance

func _position_player() -> void:
	player.global_position = SPAWN_POSITION
	player.global_position.y = _sample_height(SPAWN_POSITION.x, SPAWN_POSITION.z) + _get_player_clearance()
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
		return {"command_id": "rover_missing", "response_text": "The landing rover is not available to mark right now."}
	if player != null and player.has_method("set_waypoint_target"):
		player.call("set_waypoint_target", landing_rover, "Landing Rover")
	_send_sudo_ai_context("Marked the landing rover as the active waypoint.")
	return {"command_id": "mark_rover", "response_text": "Waypoint locked. Guiding you toward the landing rover now."}

func _handle_status_command() -> Dictionary:
	var rover_distance := -1.0
	if landing_rover != null and is_instance_valid(landing_rover):
		rover_distance = player.global_position.distance_to(landing_rover.global_position)
	var status_text := "Clone %d is stable in the landing valley. Rover distance is %s and the basin is clear for free exploration." % [
		clone_iteration_id,
		("%.0f meters" % rover_distance) if rover_distance >= 0.0 else "unknown",
	]
	_send_sudo_ai_context(status_text)
	return {"command_id": "status", "response_text": status_text}

func _send_sudo_ai_context(text: String) -> void:
	if SudoAIAgent and SudoAIAgent.has_method("set_scene_context"):
		SudoAIAgent.set_scene_context(text)

func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	var t := clampf((value - edge0) / maxf(edge1 - edge0, 0.001), 0.0, 1.0)
	return t * t * (3.0 - (2.0 * t))
