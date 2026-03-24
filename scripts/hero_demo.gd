class_name HeroDemo
extends Node3D

const TERRAIN_RESOLUTION: int = 350
const ROCK_SCENE := preload("res://scenes/rock.tscn")
const DEBRIS_SCENE := preload("res://scenes/debris_cube.tscn")
const ROVER_SCENE := preload("res://scenes/rover.tscn")
const DRONE_SCENE := preload("res://scenes/drone.tscn")
const HERO_DEMO_CONFIG_SCRIPT := preload("res://scripts/hero_demo_config.gd")
const HERO_WRECK_SCRIPT := preload("res://scripts/hero_wreck.gd")
const INTERACT_FOCUS_HIGHLIGHTER := preload("res://scripts/interact_focus_highlighter.gd")
const TERRAIN_VISUAL_DATA := preload("res://scripts/terrain_visual_data.gd")
const DECORATIVE_PEBBLE_COUNT: int = 4500
const DECORATIVE_BOULDER_COUNT: int = 800
const DECORATIVE_BRUSH_COUNT: int = 260
const ROCK_LAYOUTS := [
	Vector3(-34.0, 0.0, 48.0),
	Vector3(-22.0, 0.0, 24.0),
	Vector3(-4.0, 0.0, 18.0),
	Vector3(18.0, 0.0, 6.0),
	Vector3(34.0, 0.0, -4.0),
	Vector3(-48.0, 0.0, -22.0),
	Vector3(-58.0, 0.0, 12.0),
	Vector3(46.0, 0.0, 20.0),
]

const POI_COUNT: int = 8
const DATA_LOG_COUNT: int = 5
const MESA_MARKER_COUNT: int = 3

@onready var terrain: MeshInstance3D = $TerrainRoot/Terrain
@onready var terrain_collision: CollisionShape3D = $TerrainRoot/Terrain/StaticBody3D/CollisionShape3D
@onready var player: Node = $Player
@onready var props_root: Node3D = $Props
@onready var key_light: DirectionalLight3D = $DirectionalLight3D
@onready var fill_light: DirectionalLight3D = $FillLight
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var player_camera: Camera3D = $Player/BreathPivot/TiltPivot/PitchPivot/Camera3D

var config = HERO_DEMO_CONFIG_SCRIPT.new()

# ── Terrain noise layers ─────────────────────────────────────────────────
# Each layer targets a different scale of Martian geology:
#   macro_noise   — broad tectonic warping / basin shape
#   meso_noise    — mid-scale ridge/dune undulation
#   detail_noise  — regolith texture & small ejecta
#   crater_noise  — secondary micro-crater pitting
var macro_noise: FastNoiseLite
var meso_noise: FastNoiseLite
var detail_noise: FastNoiseLite
var crater_noise: FastNoiseLite

var terrain_size: float = 520.0
var terrain_height_scale: float = 52.0
var storm_visuals: Array[MeshInstance3D] = []
var storm_front_root: Node3D = null
var _base_fog_density: float = 0.00038
var _base_fog_height_density: float = 0.045
var _base_fog_aerial: float = 0.26
var _base_cam_far: float = 4000.0
var primary_wreck: Node3D = null
var secondary_wreck: Node3D = null
var current_waypoint: Node3D = null
var scan_completed_targets: Dictionary = {}

func _ready() -> void:
	terrain_size = config.terrain_size
	terrain_height_scale = config.terrain_height_scale
	_build_noise()
	_configure_terrain_visuals()
	_build_playable_terrain()
	_spawn_environment_dressing()
	_position_player()
	var focus_hilite := INTERACT_FOCUS_HIGHLIGHTER.new()
	focus_hilite.name = "InteractFocusHighlighter"
	focus_hilite.player = player
	add_child(focus_hilite)
	_send_sudo_ai_context("Player has spawned in the crater basin. Two wreck sites are visible and a storm front is building on the horizon.")
	EventBus.push_mission_log("Hero demo ready. Walk the crater, inspect the wreckage, and survey the basin.")
	_cache_storm_atmosphere_baseline()
	if RuntimeFeatures != null and RuntimeFeatures.is_sudo_ai_enabled() and SudoAIAgent:
		SudoAIAgent.notify_gameplay_input_started()

func _configure_terrain_visuals() -> void:
	MarsExteriorProfile.apply_key_light(key_light)
	MarsExteriorProfile.apply_fill_light(fill_light)
	if world_environment.environment != null:
		var environment := world_environment.environment.duplicate(true) as Environment
		world_environment.environment = environment
		MarsExteriorProfile.apply_environment(environment)
	if terrain.material_override is ShaderMaterial:
		var material := (terrain.material_override as ShaderMaterial).duplicate() as ShaderMaterial
		terrain.material_override = material
		MarsExteriorProfile.apply_terrain_shader(material)

func _cache_storm_atmosphere_baseline() -> void:
	var env := world_environment.environment
	_base_fog_density = env.fog_density
	_base_fog_height_density = env.fog_height_density
	_base_fog_aerial = env.fog_aerial_perspective
	var cf: float = player_camera.far
	_base_cam_far = cf if cf > 1.0 else 4000.0

func _storm_effect_strength() -> float:
	if GameState.storm_eta_seconds <= 0.0:
		return 1.0
	return clampf(1.0 - GameState.storm_eta_seconds / 300.0, 0.0, 1.0)

func _update_storm_atmosphere() -> void:
	var s := _storm_effect_strength()
	var env := world_environment.environment
	env.fog_density = lerpf(_base_fog_density, _base_fog_density * 2.75, s)
	env.fog_height_density = lerpf(_base_fog_height_density, _base_fog_height_density * 1.85, s)
	env.fog_aerial_perspective = lerpf(_base_fog_aerial, minf(_base_fog_aerial * 1.35, 0.62), s)
	player_camera.far = lerpf(_base_cam_far, 520.0, s)

func _advance_storm_front(delta_time: float) -> void:
	if storm_front_root == null or player == null:
		return
	var target_xz := Vector3(player.global_position.x, storm_front_root.global_position.y, player.global_position.z)
	var toward := target_xz - storm_front_root.global_position
	toward.y = 0.0
	var dist := toward.length()
	if dist < 2.2:
		return
	var speed := 5.5
	var step: float = minf(speed * delta_time, dist - 1.0)
	storm_front_root.global_position += toward.normalized() * step
	config.storm_center.x = storm_front_root.global_position.x
	config.storm_center.z = storm_front_root.global_position.z

func _process(delta: float) -> void:
	_update_storm_atmosphere()
	if GameState.storm_eta_seconds > 0.0:
		_advance_storm_front(delta)
	for index in range(storm_visuals.size()):
		var storm_visual := storm_visuals[index]
		var material := storm_visual.material_override as StandardMaterial3D
		if material == null:
			continue
		var shimmer := 0.12 + (0.05 * sin(Time.get_ticks_msec() * 0.0014 + index))
		material.albedo_color.a = shimmer
		material.emission_energy_multiplier = 0.25 + (0.12 * sin(Time.get_ticks_msec() * 0.0018 + index))

func get_ground_height(x: float, z: float) -> float:
	return _sample_height(x, z)

func get_ground_normal(x: float, z: float) -> Vector3:
	var step := terrain_size / float(TERRAIN_RESOLUTION)
	var hl := _sample_height(x - step, z)
	var hr := _sample_height(x + step, z)
	var hb := _sample_height(x, z - step)
	var hf := _sample_height(x, z + step)
	return Vector3(hl - hr, step * 2.0, hb - hf).normalized()

func get_world_half_size() -> float:
	return terrain_size * 0.5

func get_storm_intensity(position: Vector3, forward: Vector3) -> float:
	var to_storm: Vector3 = config.storm_center - position
	var dist_factor := clampf(1.0 - ((to_storm.length() - config.storm_radius) / 190.0), 0.0, 1.0)
	var dir_factor := clampf(((forward.normalized().dot(to_storm.normalized())) + 1.0) * 0.5, 0.0, 1.0)
	return clampf((dist_factor * 0.65) + (dir_factor * 0.35), 0.0, 1.0)

func trigger_manual_scan(hero_player: Node) -> void:
	var result: Dictionary = _begin_scan(primary_wreck, hero_player, "manual")
	if hero_player != null and hero_player.has_method("set_marvin_state"):
		hero_player.call("set_marvin_state", "SCANNING", result["response_text"])
	EventBus.agent_response_received.emit(result["response_text"])
	EventBus.push_mission_log("> System: %s" % result["response_text"])

func inspect_wreck(wreck: Node, hero_player: Node) -> void:
	if wreck == null or hero_player == null:
		return
	wreck.mark_inspected()
	var response_text := ""
	if wreck == primary_wreck:
		scan_completed_targets[wreck.wreck_name] = true
		secondary_wreck.begin_highlight(12.0)
		secondary_wreck.set_primary_target(true)
		primary_wreck.set_primary_target(false)
		_set_waypoint_target(secondary_wreck, str(secondary_wreck.get("waypoint_name")), hero_player)
		response_text = "Primary wreck inspected. I found a weak distress ping to the west. Marking the secondary hull breach now."
		EventBus.scan_completed.emit(str(primary_wreck.get("wreck_name")))
	elif wreck == secondary_wreck:
		scan_completed_targets[str(wreck.get("wreck_name"))] = true
		secondary_wreck.set_primary_target(false)
		response_text = "Secondary wreck logged. This closes the demo trail. You can keep exploring the crater at will."
		EventBus.scan_completed.emit(str(secondary_wreck.get("wreck_name")))
	else:
		response_text = str(wreck.get("scan_summary"))
	if hero_player.has_method("set_marvin_state"):
		hero_player.call("set_marvin_state", "INSPECTION COMPLETE", response_text)
	_send_sudo_ai_context("Player inspected %s." % str(wreck.get("wreck_name")))
	EventBus.agent_response_received.emit(response_text)
	EventBus.push_mission_log("> System: %s" % response_text)

func handle_voice_command(text: String) -> Dictionary:
	var normalized := text.to_lower().strip_edges()
	if normalized.is_empty():
		return { "command_id": "empty", "response_text": "I didn't catch that command." }
	if normalized.contains("scan"):
		return _begin_scan(primary_wreck, player, "voice")
	if normalized.contains("inspect") or normalized.contains("wreckage"):
		return _handle_inspect_command()
	if normalized.contains("mark") or normalized.contains("waypoint"):
		return _handle_waypoint_command()
	if normalized.contains("status"):
		return _handle_status_command()
	return { "command_id": "unknown", "response_text": "Available commands are scan, inspect wreckage, mark waypoint, and status." }

# ── Noise Construction ───────────────────────────────────────────────────

func _build_noise() -> void:
	# Macro: broad tectonic warping, very low frequency
	macro_noise = FastNoiseLite.new()
	macro_noise.seed = 1935
	macro_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	macro_noise.frequency = 0.004
	macro_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	macro_noise.fractal_octaves = 6
	macro_noise.fractal_gain = 0.50
	macro_noise.fractal_lacunarity = 2.1

	# Meso: ridgelines, dune trains, aeolian deposits
	meso_noise = FastNoiseLite.new()
	meso_noise.seed = 7712
	meso_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	meso_noise.frequency = 0.014
	meso_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	meso_noise.fractal_octaves = 5
	meso_noise.fractal_gain = 0.48
	meso_noise.fractal_lacunarity = 2.0

	# Detail: regolith texture, small rocks, ejecta pitting
	detail_noise = FastNoiseLite.new()
	detail_noise.seed = 3301
	detail_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	detail_noise.frequency = 0.055
	detail_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail_noise.fractal_octaves = 4
	detail_noise.fractal_gain = 0.45

	# Crater pitting: secondary micro-impact craters
	crater_noise = FastNoiseLite.new()
	crater_noise.seed = 8821
	crater_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	crater_noise.frequency = 0.038
	crater_noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_DIV
	crater_noise.cellular_jitter = 0.92

# ── Height Sampling ──────────────────────────────────────────────────────

func _sample_height(x: float, z: float) -> float:
	# ── 1. Flat Desert Floor & Tectonic Warping ───────────────────────
	# Slight tilt so it's not perfectly flat
	var tectonic_tilt  := (x * 0.0042 + z * 0.0018) * terrain_height_scale * 0.06
	var macro_warp     := macro_noise.get_noise_2d(x, z) * terrain_height_scale * 0.08
	var floor_base     := 38.0 + tectonic_tilt + macro_warp

	# ── 2. Meso ridges / dune trains ──────────────────────────────────
	var meso_ridge := meso_noise.get_noise_2d(x * 0.9, z * 0.9) * terrain_height_scale * 0.07
	var dune_a := sin((x * 0.048 - z * 0.022) + 0.6) * 3.2
	var dune_b := sin((x * 0.022 + z * 0.038) - 1.1) * 2.2
	var dune_c := sin((x * 0.071 - z * 0.011) + 2.4) * 1.4
	var dune_roll := (dune_a + dune_b + dune_c)

	# ── 3. Detail regolith / ejecta texture ───────────────────────────
	var detail    := detail_noise.get_noise_2d(x * 1.1, z * 1.1) * terrain_height_scale * 0.022
	var fine_grit := detail_noise.get_noise_2d(x * 3.8 + 41.0, z * 3.8 - 17.0) * terrain_height_scale * 0.006

	# ── 4. Secondary micro-crater pitting (Keep for Mars feel) ────────
	var pit_raw  := crater_noise.get_noise_2d(x, z)
	var pitting  := pit_raw * terrain_height_scale * 0.012

	# ── 5. Procedural Noise Mesas ─────────────────────────────────────
	var noise_val := macro_noise.get_noise_2d(x * 1.5, z * 1.5) * 0.5 + 0.5
	var mesa1 := _smoothstep(0.65, 0.70, noise_val) * 18.0
	var mesa2 := _smoothstep(0.76, 0.79, noise_val) * 25.0
	var mesa3 := _smoothstep(0.86, 0.88, noise_val) * 12.0
	var proc_mesas := mesa1 + mesa2 + mesa3

	# ── 6. Compositional "Hero" Mesas ─────────────────────────────────
	# Placed mathematically to frame the scene perfectly (Monument Valley style)
	var hero_m1 := _mesa_shape(x, z, -182.0, 48.0, 68.0) * 176.0  # Massive left foreground
	var hero_m2 := _mesa_shape(x, z, 124.0, -64.0, 44.0) * 86.0   # Right mid butte
	var hero_m3 := _mesa_shape(x, z, 48.0, -146.0, 30.0) * 72.0   # Center far stack
	var hero_m4 := _mesa_shape(x, z, -42.0, -88.0, 58.0) * 88.0   # Center-left mesa
	var hero_m5 := _mesa_shape(x, z, 198.0, -12.0, 54.0) * 116.0  # Far-right mesa wall
	var hero_m6 := _mesa_shape(x, z, -134.0, 34.0, 24.0) * 92.0   # Left-side companion
	var hero_m7 := _mesa_shape(x, z, -98.0, 24.0, 13.0) * 102.0   # Thin spire (left)
	var hero_m8 := _mesa_shape(x, z, 166.0, -78.0, 12.0) * 88.0   # Thin spire (right)
	var hero_m9 := _mesa_shape(x, z, 88.0, -188.0, 34.0) * 64.0   # Distant center support
	var hero_m10 := _mesa_shape(x, z, -16.0, -162.0, 28.0) * 58.0 # Distant left support
	var hero_m11 := _mesa_shape(x, z, 236.0, 58.0, 42.0) * 92.0   # Horizon right block
	var hero_mesas: float = maxf(
		hero_m1,
		maxf(
			hero_m2,
			maxf(
				hero_m3,
				maxf(
					hero_m4,
					maxf(
						hero_m5,
						maxf(hero_m6, maxf(hero_m7, maxf(hero_m8, maxf(hero_m9, maxf(hero_m10, hero_m11)))))
					)
				)
			)
		)
	)

	# ── 7. Compose all layers ─────────────────────────────────────────
	var height := floor_base
	height += meso_ridge + dune_roll
	height += detail + fine_grit + pitting
	
	# Add the mesas (using max to blend them seamlessly out of the floor)
	height += maxf(proc_mesas, hero_mesas)

	# ── 8. Spawn pad flattening (preserve gameplay) ──────────────────
	var spawn_dist := Vector2(x - config.spawn_position.x, z - config.spawn_position.z).length()
	if spawn_dist < 20.0:
		var blend := 1.0 - clampf(spawn_dist / 20.0, 0.0, 1.0)
		var pad_h  := 39.8 + tectonic_tilt
		height = lerpf(height, pad_h, _smoothstep(0.0, 1.0, blend) * 0.92)

	return height

func _mesa_shape(x: float, z: float, cx: float, cz: float, radius: float) -> float:
	var dist := Vector2(x - cx, z - cz).length()
	var profile := 1.0 - clampf(dist / radius, 0.0, 1.0)
	
	# Layered terrace logic with extra strata for sharper sedimentary silhouettes.
	var cliff_mass := pow(profile, 0.34) * 0.42
	var layer1 := _smoothstep(0.0, 0.12, profile) * 0.22
	var layer2 := _smoothstep(0.18, 0.27, profile) * 0.19
	var layer3 := _smoothstep(0.34, 0.46, profile) * 0.17
	var layer4 := _smoothstep(0.52, 0.64, profile) * 0.14
	var layer5 := _smoothstep(0.7, 0.84, profile) * 0.11
	
	# Add slight randomness to the terrace edges so they look eroded
	var edge_noise := detail_noise.get_noise_2d(x * 2.5, z * 2.5) * 0.13
	return clampf(cliff_mass + layer1 + layer2 + layer3 + layer4 + layer5 + (edge_noise * profile), 0.0, 1.0)

# ── Terrain Mesh Build ───────────────────────────────────────────────────

func _build_playable_terrain() -> void:
	var grid_width := TERRAIN_RESOLUTION + 1
	var vertex_count := grid_width * grid_width
	var vertices := PackedVector3Array()
	var normals  := PackedVector3Array()
	var uvs      := PackedVector2Array()
	var indices  := PackedInt32Array()
	vertices.resize(vertex_count)
	normals.resize(vertex_count)
	uvs.resize(vertex_count)

	var half := terrain_size * 0.5
	var min_height := INF
	var max_height := -INF
	for zi in range(grid_width):
		var v := float(zi) / float(TERRAIN_RESOLUTION)
		var z := lerpf(-half, half, v)
		for xi in range(grid_width):
			var u := float(xi) / float(TERRAIN_RESOLUTION)
			var x := lerpf(-half, half, u)
			var idx := zi * grid_width + xi
			var sampled_height := _sample_height(x, z)
			vertices[idx] = Vector3(x, sampled_height, z)
			uvs[idx] = Vector2(u, v)
			min_height = minf(min_height, sampled_height)
			max_height = maxf(max_height, sampled_height)

	for zi in range(TERRAIN_RESOLUTION):
		for xi in range(TERRAIN_RESOLUTION):
			var tl := zi * grid_width + xi
			var bl := (zi + 1) * grid_width + xi
			var tr := tl + 1
			var br := bl + 1
			indices.push_back(tl); indices.push_back(bl); indices.push_back(tr)
			indices.push_back(tr); indices.push_back(bl); indices.push_back(br)

	for ti in range(0, indices.size(), 3):
		var a := indices[ti]; var b := indices[ti + 1]; var c := indices[ti + 2]
		var fn := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]).normalized()
		normals[a] += fn; normals[b] += fn; normals[c] += fn

	for vi in range(normals.size()):
		normals[vi] = normals[vi].normalized()

	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX]  = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	terrain.mesh = mesh
	terrain_collision.shape = mesh.create_trimesh_shape()
	if terrain.material_override is ShaderMaterial:
		var material := terrain.material_override as ShaderMaterial
		material.set_shader_parameter("height_scale", maxf(max_height - min_height, terrain_height_scale * 2.0))
		TERRAIN_VISUAL_DATA.apply_to_material(material, vertices, normals, grid_width, min_height, max_height)
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

	var min_height := INF
	for vertex in vertices:
		min_height = minf(min_height, vertex.y)
	var seal_floor_y := min_height - maxf(terrain_height_scale * 2.0, 80.0)

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
		var bottom_a := Vector3(top_a.x, seal_floor_y, top_a.z)
		var bottom_b := Vector3(top_b.x, seal_floor_y, top_b.z)
		var edge := top_b - top_a
		var outward := Vector3(edge.z, 0.0, -edge.x).normalized()
		if outward.length_squared() < 0.0001:
			outward = Vector3.UP

		var base_index := skirt_vertices.size()
		skirt_vertices.push_back(top_a)
		skirt_vertices.push_back(bottom_a)
		skirt_vertices.push_back(top_b)
		skirt_vertices.push_back(bottom_b)
		for normal_index in range(4):
			skirt_normals.push_back(outward)
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

	var cap_instance := MeshInstance3D.new()
	cap_instance.name = "TerrainSubFloorCap"
	var cap_mesh := PlaneMesh.new()
	cap_mesh.size = Vector2(terrain_size * 1.35, terrain_size * 1.35)
	cap_instance.mesh = cap_mesh
	cap_instance.position = Vector3(0.0, seal_floor_y + 1.0, 0.0)
	cap_instance.material_override = seal_material.duplicate()
	cap_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	terrain_root.add_child(cap_instance)

func _make_terrain_seal_material() -> StandardMaterial3D:
	return MarsExteriorProfile.make_seal_material()

# ── Scene population (unchanged from original) ──────────────────────────

func _position_player() -> void:
	player.global_position = config.spawn_position
	player.global_position.y = _sample_height(player.global_position.x, player.global_position.z) + 1.7
	player.rotation.y = config.spawn_yaw

func _spawn_environment_dressing() -> void:
	for child in props_root.get_children():
		child.queue_free()

	primary_wreck = HERO_WRECK_SCRIPT.new()
	primary_wreck.set("wreck_name", "ARES WRECK ALPHA")
	primary_wreck.set("waypoint_name", "ALPHA WRECK")
	primary_wreck.set("scan_summary", "Telemetry spike detected. Hull signature is still alive.")
	primary_wreck.set("primary_target", true)
	props_root.add_child(primary_wreck)
	_place_node(primary_wreck, config.primary_wreck_position, 0.2)

	secondary_wreck = HERO_WRECK_SCRIPT.new()
	secondary_wreck.set("wreck_name", "ARES WRECK BETA")
	secondary_wreck.set("waypoint_name", "BETA WRECK")
	secondary_wreck.set("scan_summary", "Secondary hull shows fragmented power cells and an exposed relay spine.")
	props_root.add_child(secondary_wreck)
	_place_node(secondary_wreck, config.secondary_wreck_position, 0.2)

	_build_decorative_rock_field()

	for rock_position in ROCK_LAYOUTS:
		var rock := ROCK_SCENE.instantiate() as Node3D
		props_root.add_child(rock)
		_place_node(rock, rock_position, 0.55)

	var rover := ROVER_SCENE.instantiate() as Node3D
	props_root.add_child(rover)
	_place_node(rover, config.rover_position, 1.1)
	_build_rover_tracks(config.rover_position)

	var drone := DRONE_SCENE.instantiate() as Node3D
	props_root.add_child(drone)
	_place_node(drone, config.drone_position, 4.3)

	_spawn_debris_fields()
	_build_storm_column()
	_build_world_boundary()
	_set_waypoint_target(primary_wreck, str(primary_wreck.get("waypoint_name")), player)

func _build_decorative_rock_field() -> void:
	var pebble_root := MultiMeshInstance3D.new()
	pebble_root.name = "DecorativePebbles"
	pebble_root.multimesh = MultiMesh.new()
	pebble_root.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	pebble_root.multimesh.use_colors = true
	pebble_root.multimesh.instance_count = DECORATIVE_PEBBLE_COUNT
	pebble_root.multimesh.visible_instance_count = DECORATIVE_PEBBLE_COUNT
	pebble_root.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pebble_mesh := BoxMesh.new()
	pebble_mesh.size = Vector3(0.36, 0.24, 0.32)
	var pebble_material := StandardMaterial3D.new()
	pebble_material.albedo_color = Color(0.58, 0.24, 0.1, 1.0)
	pebble_material.roughness = 0.98
	pebble_material.metallic = 0.02
	pebble_mesh.material = pebble_material
	pebble_root.multimesh.mesh = pebble_mesh
	props_root.add_child(pebble_root)
	var pebble_palette: Array[Color] = [
		Color(0.54, 0.21, 0.09, 1.0),
		Color(0.42, 0.16, 0.08, 1.0),
		Color(0.68, 0.31, 0.12, 1.0),
		Color(0.33, 0.13, 0.07, 1.0),
	]
	_populate_rock_multimesh(pebble_root.multimesh, DECORATIVE_PEBBLE_COUNT, 0.14, 0.66, 0.12, 0.42, 6.0, pebble_palette)

	var boulder_root := MultiMeshInstance3D.new()
	boulder_root.name = "DecorativeBoulders"
	boulder_root.multimesh = MultiMesh.new()
	boulder_root.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	boulder_root.multimesh.use_colors = true
	boulder_root.multimesh.instance_count = DECORATIVE_BOULDER_COUNT
	boulder_root.multimesh.visible_instance_count = DECORATIVE_BOULDER_COUNT
	boulder_root.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var boulder_mesh := BoxMesh.new()
	boulder_mesh.size = Vector3(1.0, 0.72, 0.9)
	var boulder_material := StandardMaterial3D.new()
	boulder_material.albedo_color = Color(0.48, 0.2, 0.09, 1.0)
	boulder_material.roughness = 0.96
	boulder_material.metallic = 0.03
	boulder_mesh.material = boulder_material
	boulder_root.multimesh.mesh = boulder_mesh
	props_root.add_child(boulder_root)
	var boulder_palette: Array[Color] = [
		Color(0.46, 0.19, 0.08, 1.0),
		Color(0.34, 0.14, 0.08, 1.0),
		Color(0.58, 0.24, 0.1, 1.0),
		Color(0.27, 0.11, 0.07, 1.0),
	]
	_populate_rock_multimesh(boulder_root.multimesh, DECORATIVE_BOULDER_COUNT, 0.65, 2.15, 0.18, 0.34, 10.0, boulder_palette)

	var brush_root := MultiMeshInstance3D.new()
	brush_root.name = "DecorativeBrush"
	brush_root.multimesh = MultiMesh.new()
	brush_root.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	brush_root.multimesh.use_colors = true
	brush_root.multimesh.instance_count = DECORATIVE_BRUSH_COUNT
	brush_root.multimesh.visible_instance_count = DECORATIVE_BRUSH_COUNT
	brush_root.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var brush_mesh := CylinderMesh.new()
	brush_mesh.top_radius = 0.12
	brush_mesh.bottom_radius = 0.34
	brush_mesh.height = 0.2
	var brush_material := StandardMaterial3D.new()
	brush_material.albedo_color = Color(0.1, 0.06, 0.04, 1.0)
	brush_material.roughness = 0.99
	brush_material.metallic = 0.0
	brush_mesh.material = brush_material
	brush_root.multimesh.mesh = brush_mesh
	props_root.add_child(brush_root)
	var brush_palette: Array[Color] = [
		Color(0.09, 0.05, 0.035, 1.0),
		Color(0.13, 0.07, 0.045, 1.0),
		Color(0.06, 0.04, 0.03, 1.0),
	]
	_populate_rock_multimesh(brush_root.multimesh, DECORATIVE_BRUSH_COUNT, 0.72, 1.28, 0.06, 0.5, 8.0, brush_palette)

func _populate_rock_multimesh(multimesh: MultiMesh, count: int, scale_min: float, scale_max: float, clearance: float, max_slope: float, reserve_padding: float, color_palette: Array[Color] = []) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s-%s" % [count, scale_min])
	var use_palette := color_palette.size() > 0 and multimesh.use_colors
	var half_size: float = terrain_size * 0.5 - 6.0
	var filled: int = 0
	var attempts: int = 0
	while filled < count and attempts < count * 30:
		attempts += 1
		var x: float = rng.randf_range(-half_size, half_size)
		var z: float = rng.randf_range(-half_size, half_size)
		if _is_reserved_rock_zone(Vector3(x, 0.0, z), reserve_padding):
			continue
		var ground_normal: Vector3 = get_ground_normal(x, z)
		var slope: float = 1.0 - ground_normal.y
		if slope > max_slope:
			continue
		var scale_bias: float = 0.76 + (abs(macro_noise.get_noise_2d((x * 1.4) + 21.0, (z * 1.4) - 9.0)) * 0.5)
		var scale: float = rng.randf_range(scale_min, scale_max) * scale_bias
		var rotation_basis: Basis = Basis.from_euler(Vector3(
			rng.randf_range(-0.14, 0.14),
			rng.randf_range(0.0, TAU),
			rng.randf_range(-0.14, 0.14)
		))
		var scale_basis: Basis = Basis.IDENTITY.scaled(Vector3(
			scale * rng.randf_range(0.85, 1.35),
			scale * rng.randf_range(0.58, 0.92),
			scale * rng.randf_range(0.82, 1.24)
		))
		var rock_height: float = _sample_height(x, z) + clearance
		multimesh.set_instance_transform(filled, Transform3D(rotation_basis * scale_basis, Vector3(x, rock_height, z)))
		if use_palette:
			var palette_index := rng.randi_range(0, color_palette.size() - 1)
			var instance_color := color_palette[palette_index] * (0.88 + (rng.randf() * 0.24))
			instance_color.a = 1.0
			multimesh.set_instance_color(filled, instance_color)
		filled += 1
	multimesh.visible_instance_count = filled

func _is_reserved_rock_zone(position: Vector3, padding: float) -> bool:
	if position.distance_to(config.spawn_position) < 24.0 + padding: return true
	if position.distance_to(config.primary_wreck_position) < 14.0 + padding: return true
	if position.distance_to(config.secondary_wreck_position) < 14.0 + padding: return true
	if position.distance_to(config.rover_position) < 10.0 + padding: return true
	if position.distance_to(config.drone_position) < 10.0 + padding: return true
	if abs(position.x - 2.0) < 6.0 and position.z > 38.0 and position.z < 196.0: return true
	return false

func _place_node(node: Node3D, position: Vector3, clearance: float) -> void:
	node.global_position = position
	node.global_position.y = _sample_height(position.x, position.z) + clearance

func _spawn_debris_fields() -> void:
	_spawn_debris_cluster(config.primary_wreck_position, 22, 4.0, 20.0)
	_spawn_debris_cluster(config.secondary_wreck_position, 15, 3.0, 16.0)
	_build_debris_trail(config.spawn_position, config.primary_wreck_position, 34)

func _spawn_debris_cluster(center: Vector3, count: int, min_radius: float, max_radius: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s-%s" % [center, count])
	for index in range(count):
		var angle := rng.randf_range(0.0, TAU)
		var distance := rng.randf_range(min_radius, max_radius)
		var position := center + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
		var debris := DEBRIS_SCENE.instantiate() as Node3D
		if debris == null:
			continue
		props_root.add_child(debris)
		_place_node(debris, position, 0.52 + rng.randf_range(0.0, 0.24))

func _build_debris_trail(start: Vector3, target: Vector3, segment_count: int) -> void:
	var trail_root := Node3D.new()
	trail_root.name = "DebrisTrail"
	props_root.add_child(trail_root)

	var trail_material := StandardMaterial3D.new()
	trail_material.albedo_color = Color(0.3, 0.18, 0.14, 1.0)
	trail_material.roughness = 0.95
	trail_material.metallic = 0.2

	var planar_start := Vector3(start.x, 0.0, start.z)
	var planar_target := Vector3(target.x, 0.0, target.z)
	var trail_dir := (planar_target - planar_start).normalized()
	if trail_dir.length_squared() < 0.001:
		trail_dir = Vector3.FORWARD
	var trail_right := trail_dir.cross(Vector3.UP).normalized()

	var rng := RandomNumberGenerator.new()
	rng.seed = 442191
	var denom := float(maxi(segment_count - 1, 1))
	for index in range(segment_count):
		var t := float(index) / denom
		var center := planar_start.lerp(planar_target, t)
		var lateral_jitter := rng.randf_range(-2.6, 2.6)
		var longitudinal_jitter := rng.randf_range(-2.0, 2.0)
		var chunk_pos := center + (trail_right * lateral_jitter) + (trail_dir * longitudinal_jitter)
		if chunk_pos.distance_to(config.primary_wreck_position) < 3.8:
			continue

		var chunk := MeshInstance3D.new()
		var chunk_mesh := BoxMesh.new()
		chunk_mesh.size = Vector3(
			rng.randf_range(0.28, 0.92),
			rng.randf_range(0.06, 0.22),
			rng.randf_range(0.32, 1.34)
		)
		chunk_mesh.material = trail_material
		chunk.mesh = chunk_mesh
		chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		trail_root.add_child(chunk)
		chunk.global_position = chunk_pos
		chunk.global_position.y = _sample_height(chunk_pos.x, chunk_pos.z) + rng.randf_range(0.03, 0.12)
		chunk.rotation = Vector3(
			rng.randf_range(-0.25, 0.25),
			atan2(trail_dir.x, trail_dir.z) + rng.randf_range(-0.4, 0.4),
			rng.randf_range(-0.18, 0.18)
		)

func _build_rover_tracks(rover_position: Vector3) -> void:
	var track_root := MultiMeshInstance3D.new()
	track_root.name = "RoverTracks"
	track_root.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	props_root.add_child(track_root)

	var tracks := MultiMesh.new()
	tracks.transform_format = MultiMesh.TRANSFORM_3D
	var segment_count := 36
	tracks.instance_count = segment_count * 2
	tracks.visible_instance_count = segment_count * 2

	var track_mesh := BoxMesh.new()
	track_mesh.size = Vector3(0.46, 0.04, 1.15)
	var track_material := StandardMaterial3D.new()
	track_material.albedo_color = Color(0.2, 0.08, 0.06, 1.0)
	track_material.roughness = 0.98
	track_material.metallic = 0.02
	track_mesh.material = track_material
	tracks.mesh = track_mesh
	track_root.multimesh = tracks

	var travel_dir := Vector3(config.primary_wreck_position.x - rover_position.x, 0.0, config.primary_wreck_position.z - rover_position.z).normalized()
	if travel_dir.length_squared() < 0.001:
		travel_dir = Vector3.FORWARD
	var right_dir := travel_dir.cross(Vector3.UP).normalized()
	var lane_half_width := 0.9
	var denom := float(maxi(segment_count - 1, 1))
	for index in range(segment_count):
		var t := float(index) / denom
		var march := lerpf(-8.0, 48.0, t)
		var meander := sin(t * PI * 1.8) * 1.6
		var center := rover_position + (travel_dir * march) + (right_dir * meander * 0.22)
		var heading := atan2(travel_dir.x, travel_dir.z) + (sin(t * PI * 2.2) * 0.09)
		for lane_index in range(2):
			var side := -1.0 if lane_index == 0 else 1.0
			var lane_pos := center + (right_dir * lane_half_width * side)
			var basis := Basis.from_euler(Vector3(0.0, heading, 0.0)).scaled(Vector3(1.0 + (0.16 * sin(t * PI * 3.2)), 1.0, 1.0))
			var instance_index := (index * 2) + lane_index
			tracks.set_instance_transform(instance_index, Transform3D(basis, Vector3(
				lane_pos.x,
				_sample_height(lane_pos.x, lane_pos.z) + 0.04,
				lane_pos.z
			)))

func _build_storm_column() -> void:
	var storm_root := Node3D.new()
	storm_root.name = "StormFront"
	storm_front_root = storm_root
	props_root.add_child(storm_root)
	storm_root.global_position = Vector3(config.storm_center.x, _sample_height(config.storm_center.x, config.storm_center.z), config.storm_center.z)
	for index in range(6):
		var storm_mesh := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 10.0 + (index * 2.0)
		cylinder.bottom_radius = 18.0 + (index * 4.0)
		cylinder.height = 80.0 + (index * 12.0)
		storm_mesh.mesh = cylinder
		var storm_material := StandardMaterial3D.new()
		storm_material.albedo_color = Color(0.74, 0.34, 0.16, 0.12)
		storm_material.emission_enabled = true
		storm_material.emission = Color(0.82, 0.34, 0.18, 1.0)
		storm_material.emission_energy_multiplier = 0.28
		storm_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		storm_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		storm_material.no_depth_test = true
		storm_mesh.material_override = storm_material
		storm_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		storm_mesh.position = Vector3((index - 2.5) * 10.0, (40.0 + (index * 6.0)), float(index % 2) * -6.0)
		storm_root.add_child(storm_mesh)
		storm_visuals.append(storm_mesh)

func _build_world_boundary() -> void:
	var boundary_root := MultiMeshInstance3D.new()
	boundary_root.name = "WorldBoundary"
	boundary_root.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	props_root.add_child(boundary_root)

	var boundary_multimesh := MultiMesh.new()
	boundary_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var segment_count := 80
	boundary_multimesh.instance_count = segment_count
	boundary_multimesh.visible_instance_count = segment_count

	var boundary_mesh := CylinderMesh.new()
	boundary_mesh.top_radius = 7.0
	boundary_mesh.bottom_radius = 11.0
	boundary_mesh.height = 54.0

	var boundary_material := StandardMaterial3D.new()
	boundary_material.albedo_color = Color(0.66, 0.29, 0.14, 0.14)
	boundary_material.emission_enabled = true
	boundary_material.emission = Color(0.85, 0.38, 0.2, 1.0)
	boundary_material.emission_energy_multiplier = 0.18
	boundary_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	boundary_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	boundary_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	boundary_mesh.material = boundary_material

	boundary_multimesh.mesh = boundary_mesh
	boundary_root.multimesh = boundary_multimesh

	var ring_radius := (terrain_size * 0.5) - 6.0
	for index in range(segment_count):
		var angle := (float(index) / float(segment_count)) * TAU
		var x := cos(angle) * ring_radius
		var z := sin(angle) * ring_radius
		var ring_noise: float = 0.92 + (absf(sin((float(index) * 0.87) + 1.2)) * 0.42)
		var y: float = _sample_height(x, z) + (20.0 * ring_noise)
		var basis := Basis.from_euler(Vector3(0.0, angle + (PI * 0.5), 0.0)).scaled(Vector3(
			0.8 + (ring_noise * 0.35),
			1.1 + (ring_noise * 0.4),
			0.8 + (ring_noise * 0.35)
		))
		boundary_multimesh.set_instance_transform(index, Transform3D(basis, Vector3(x, y, z)))

# ── Voice / command helpers (unchanged) ─────────────────────────────────

func _begin_scan(target: Node, hero_player: Node, source: String) -> Dictionary:
	if target == null:
		return { "command_id": "scan", "response_text": "No wreck signature is available right now." }
	target.begin_highlight(10.0)
	_set_waypoint_target(target, str(target.get("waypoint_name")), hero_player)
	_send_sudo_ai_context("Targeting %s from %s command." % [str(target.get("wreck_name")), source])
	EventBus.scan_started.emit(str(target.get("wreck_name")))
	return { "command_id": "scan", "response_text": "Scanning locked. Highlighting %s on your visor now." % str(target.get("wreck_name")) }

func _send_sudo_ai_context(text: String) -> void:
	if RuntimeFeatures != null and RuntimeFeatures.is_sudo_ai_enabled() and SudoAIAgent and SudoAIAgent.has_method("set_scene_context"):
		SudoAIAgent.set_scene_context(text)

func _handle_inspect_command() -> Dictionary:
	var focus_target: Node = primary_wreck
	var current_focus: Variant = player.get("focused_interactable")
	if current_focus != null and current_focus is Node and current_focus.has_method("mark_inspected"):
		focus_target = current_focus
	if focus_target == null:
		return { "command_id": "inspect", "response_text": "No wreckage is centered in your visor. Move closer or ask me to mark the waypoint." }
	if focus_target == primary_wreck and not bool(primary_wreck.get("inspected")):
		return { "command_id": "inspect", "response_text": "Primary wreck is ready for inspection. Close the gap and interact with the hull panel." }
	if focus_target == secondary_wreck and not bool(secondary_wreck.get("inspected")):
		return { "command_id": "inspect", "response_text": "Secondary wreck is ready. Move in and inspect the exposed relay spine." }
	return { "command_id": "inspect", "response_text": "Wreckage notes are already logged. You can keep exploring or request status." }

func _handle_waypoint_command() -> Dictionary:
	var target: Node = primary_wreck
	if primary_wreck != null and bool(primary_wreck.get("inspected")) and secondary_wreck != null and not bool(secondary_wreck.get("inspected")):
		target = secondary_wreck
	if target == null:
		return { "command_id": "waypoint", "response_text": "No waypoint target is available." }
	target.begin_highlight(8.0)
	_set_waypoint_target(target, str(target.get("waypoint_name")), player)
	return { "command_id": "waypoint", "response_text": "Waypoint pinned to %s." % str(target.get("wreck_name")) }

func _handle_status_command() -> Dictionary:
	var waypoint_text := active_waypoint_label()
	var response_text := "Oxygen steady at %d percent. Storm front remains %s out. Active waypoint is %s." % [
		int(round(float(player.get("oxygen")))),
		GameState.get_storm_eta_label(),
		waypoint_text,
	]
	return { "command_id": "status", "response_text": response_text }

func _set_waypoint_target(target: Node3D, label: String, hero_player: Node) -> void:
	current_waypoint = target
	if hero_player != null and hero_player.has_method("set_waypoint_target"):
		hero_player.call("set_waypoint_target", target, label)

func active_waypoint_label() -> String:
	if current_waypoint == null: return "no active mark"
	if current_waypoint.has_method("get_interaction_name"):
		return str(current_waypoint.call("get_interaction_name"))
	return current_waypoint.name

func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	var t := clampf((value - edge0) / max(edge1 - edge0, 0.001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
