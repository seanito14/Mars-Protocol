class_name HeroDemo
extends Node3D

const TERRAIN_RESOLUTION: int = 140
const ROCK_SCENE := preload("res://scenes/rock.tscn")
const ROVER_SCENE := preload("res://scenes/rover.tscn")
const DRONE_SCENE := preload("res://scenes/drone.tscn")
const HERO_DEMO_CONFIG_SCRIPT := preload("res://scripts/hero_demo_config.gd")
const HERO_WRECK_SCRIPT := preload("res://scripts/hero_wreck.gd")
const DECORATIVE_PEBBLE_COUNT: int = 340
const DECORATIVE_BOULDER_COUNT: int = 96
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

@onready var terrain: MeshInstance3D = $TerrainRoot/Terrain
@onready var terrain_collision: CollisionShape3D = $TerrainRoot/Terrain/StaticBody3D/CollisionShape3D
@onready var player: Node = $Player
@onready var props_root: Node3D = $Props
@onready var voice_service: Node = $VoiceService

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

var terrain_size: float = 280.0
var terrain_height_scale: float = 52.0
var storm_visuals: Array[MeshInstance3D] = []
var primary_wreck: Node3D = null
var secondary_wreck: Node3D = null
var current_waypoint: Node3D = null
var scan_completed_targets: Dictionary = {}

func _ready() -> void:
	terrain_size = config.terrain_size
	terrain_height_scale = config.terrain_height_scale
	_build_noise()
	_build_playable_terrain()
	_spawn_environment_dressing()
	_position_player()
	voice_service.send_contextual_update("Spawned in the crater basin with a storm on the horizon and two wreck clusters in view.")
	EventBus.push_mission_log("Hero demo ready. Walk the crater, inspect the wreckage, and talk to Marvin.")
	var canvas_layer := get_node_or_null("CanvasLayer")
	if canvas_layer:
		var overlay := SudoAIOverlay.new()
		overlay.name = "SudoAIOverlay"
		canvas_layer.add_child(overlay)
	if SudoAIAgent and SudoAIAgent.is_connected_to_agent():
		SudoAIAgent.send_contextual_update("Player has spawned in a Mars crater. Two wreck sites visible. Storm approaching. Press F or say 'Sudo' to talk.")

func _process(delta: float) -> void:
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
	EventBus.push_mission_log("> Marvin: %s" % result["response_text"])

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
	if voice_service != null and voice_service.has_method("send_contextual_update"):
		voice_service.call("send_contextual_update", "Player inspected %s." % str(wreck.get("wreck_name")))
	EventBus.agent_response_received.emit(response_text)
	EventBus.push_mission_log("> Marvin: %s" % response_text)

func handle_voice_command(text: String) -> Dictionary:
	var normalized := text.to_lower().strip_edges()
	if normalized.is_empty():
		return { "command_id": "empty", "response_text": "Marvin here. I didn't catch that command." }
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
	var radial: float = Vector2(x, z).length() / max(terrain_size * 0.5, 0.001)

	# ── 1. Primary impact crater bowl ────────────────────────────────
	# Complex bowl: steep inner wall, relatively flat floor, raised rim
	var crater_floor := _smoothstep(0.0, 0.42, radial)
	var bowl_depth   := -pow(1.0 - clampf(radial / 0.46, 0.0, 1.0), 1.6) * terrain_height_scale * 0.42
	var rim_peak     := exp(-pow((radial - 0.52) * 9.5, 2.0)) * terrain_height_scale * 0.28
	# Outer ejecta blanket — raised and rough
	var ejecta       := _smoothstep(0.55, 1.0, radial) * terrain_height_scale * 0.22
	# Terraced inner wall — slumped material creates benches
	var terrace_a    := exp(-pow((radial - 0.22) * 14.0, 2.0)) * 2.8
	var terrace_b    := exp(-pow((radial - 0.34) * 12.0, 2.0)) * 2.0

	# ── 2. Macro tectonic warping ─────────────────────────────────────
	# Tilts the whole basin slightly — no perfectly flat craters on Mars
	var tectonic_tilt  := (x * 0.0042 + z * 0.0018) * terrain_height_scale * 0.06
	var macro_warp     := macro_noise.get_noise_2d(x, z) * terrain_height_scale * 0.14

	# ── 3. Meso ridges / dune trains ──────────────────────────────────
	# Ridged noise mimics wind-sculpted yardangs and dune crests
	var meso_ridge := meso_noise.get_noise_2d(x * 0.9, z * 0.9) * terrain_height_scale * 0.07
	# Dune trains: long sinuous forms aligned with prevailing wind (≈NW)
	var dune_a := sin((x * 0.048 - z * 0.022) + 0.6) * 1.6
	var dune_b := sin((x * 0.022 + z * 0.038) - 1.1) * 1.1
	var dune_c := sin((x * 0.071 - z * 0.011) + 2.4) * 0.7
	var dune_roll := (dune_a + dune_b + dune_c) * clampf(1.0 - radial * 0.8, 0.0, 1.0)

	# ── 4. Detail regolith / ejecta texture ───────────────────────────
	var detail    := detail_noise.get_noise_2d(x * 1.1, z * 1.1) * terrain_height_scale * 0.022
	var fine_grit := detail_noise.get_noise_2d(x * 3.8 + 41.0, z * 3.8 - 17.0) * terrain_height_scale * 0.006

	# ── 5. Secondary micro-crater pitting ─────────────────────────────
	# Cellular noise gives the characteristic pockmarked surface of old terrain
	var pit_raw  := crater_noise.get_noise_2d(x, z)  # ~0..1 from distance2div
	var pit_mask := clampf(radial * 1.2, 0.0, 1.0)   # more pitting on ejecta apron
	var pitting  := pit_raw * terrain_height_scale * 0.018 * pit_mask

	# ── 6. Volcanic rise — subtle asymmetric uplift ───────────────────
	# Mars craters often have an asymmetric floor due to underlying geology
	var volcanic_rise := exp(-pow((x + 8.0) * 0.022, 2.0) - pow((z + 14.0) * 0.018, 2.0)) * 3.8

	# ── 7. Central peak remnant (low, eroded) ─────────────────────────
	# Many mid-size craters have a worn central mound
	var central_peak := exp(-pow(Vector2(x, z).length() * 0.085, 2.0)) * 2.4 * (1.0 - _smoothstep(0.0, 0.18, radial))

	# ── 8. Far horizon ridge ──────────────────────────────────────────
	var horizon_mask  := clampf((-z - 10.0) / 130.0, 0.0, 1.0)
	var far_ridge     := horizon_mask * (5.8 + sin(x * 0.031 + 1.2) * 3.1 + macro_noise.get_noise_2d(x * 0.11, -38.0) * 3.4)
	var left_ridge    := exp(-pow((x + 88.0) * 0.024, 2.0)) * clampf((-z + 18.0) / 148.0, 0.0, 1.0) * 10.2
	var right_ridge   := exp(-pow((x - 106.0) * 0.021, 2.0)) * clampf((-z + 8.0) / 128.0, 0.0, 1.0) * 7.8

	# ── 9. Compose all layers ─────────────────────────────────────────
	var height := 38.0
	height += bowl_depth + rim_peak + ejecta
	height += terrace_a + terrace_b
	height += tectonic_tilt + macro_warp
	height += meso_ridge + dune_roll
	height += detail + fine_grit + pitting
	height += volcanic_rise + central_peak
	height += far_ridge + left_ridge + right_ridge

	# ── 10. Spawn pad flattening (preserve gameplay) ──────────────────
	var spawn_dist := Vector2(x - config.spawn_position.x, z - config.spawn_position.z).length()
	if spawn_dist < 20.0:
		var blend := 1.0 - clampf(spawn_dist / 20.0, 0.0, 1.0)
		var pad_h  := 39.8 + tectonic_tilt  # keep the tilt so it doesn't feel artificial
		height = lerpf(height, pad_h, _smoothstep(0.0, 1.0, blend) * 0.92)

	return height

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
	for zi in range(grid_width):
		var v := float(zi) / float(TERRAIN_RESOLUTION)
		var z := lerpf(-half, half, v)
		for xi in range(grid_width):
			var u := float(xi) / float(TERRAIN_RESOLUTION)
			var x := lerpf(-half, half, u)
			var idx := zi * grid_width + xi
			vertices[idx] = Vector3(x, _sample_height(x, z), z)
			uvs[idx] = Vector2(u, v)

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

	var drone := DRONE_SCENE.instantiate() as Node3D
	props_root.add_child(drone)
	_place_node(drone, config.drone_position, 4.3)

	_build_storm_column()
	_set_waypoint_target(primary_wreck, str(primary_wreck.get("waypoint_name")), player)

func _build_decorative_rock_field() -> void:
	var pebble_root := MultiMeshInstance3D.new()
	pebble_root.name = "DecorativePebbles"
	pebble_root.multimesh = MultiMesh.new()
	pebble_root.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	pebble_root.multimesh.instance_count = DECORATIVE_PEBBLE_COUNT
	pebble_root.multimesh.visible_instance_count = DECORATIVE_PEBBLE_COUNT
	var pebble_mesh := SphereMesh.new()
	pebble_mesh.radius = 0.28
	pebble_mesh.height = 0.56
	var pebble_material := StandardMaterial3D.new()
	pebble_material.albedo_color = Color(0.17, 0.12, 0.1, 1.0)
	pebble_material.roughness = 0.98
	pebble_material.metallic = 0.02
	pebble_mesh.material = pebble_material
	pebble_root.multimesh.mesh = pebble_mesh
	props_root.add_child(pebble_root)
	_populate_rock_multimesh(pebble_root.multimesh, DECORATIVE_PEBBLE_COUNT, 0.12, 0.52, 0.12, 0.42, 6.0)

	var boulder_root := MultiMeshInstance3D.new()
	boulder_root.name = "DecorativeBoulders"
	boulder_root.multimesh = MultiMesh.new()
	boulder_root.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	boulder_root.multimesh.instance_count = DECORATIVE_BOULDER_COUNT
	boulder_root.multimesh.visible_instance_count = DECORATIVE_BOULDER_COUNT
	var boulder_mesh := BoxMesh.new()
	boulder_mesh.size = Vector3(1.0, 0.72, 0.9)
	var boulder_material := StandardMaterial3D.new()
	boulder_material.albedo_color = Color(0.13, 0.1, 0.1, 1.0)
	boulder_material.roughness = 0.96
	boulder_material.metallic = 0.03
	boulder_mesh.material = boulder_material
	boulder_root.multimesh.mesh = boulder_mesh
	props_root.add_child(boulder_root)
	_populate_rock_multimesh(boulder_root.multimesh, DECORATIVE_BOULDER_COUNT, 0.45, 1.35, 0.18, 0.34, 10.0)

func _populate_rock_multimesh(multimesh: MultiMesh, count: int, scale_min: float, scale_max: float, clearance: float, max_slope: float, reserve_padding: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s-%s" % [count, scale_min])
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
		filled += 1
	multimesh.visible_instance_count = filled

func _is_reserved_rock_zone(position: Vector3, padding: float) -> bool:
	if position.distance_to(config.spawn_position) < 24.0 + padding: return true
	if position.distance_to(config.primary_wreck_position) < 14.0 + padding: return true
	if position.distance_to(config.secondary_wreck_position) < 14.0 + padding: return true
	if position.distance_to(config.rover_position) < 10.0 + padding: return true
	if position.distance_to(config.drone_position) < 10.0 + padding: return true
	if abs(position.x - 2.0) < 4.5 and position.z > -8.0 and position.z < 92.0: return true
	return false

func _place_node(node: Node3D, position: Vector3, clearance: float) -> void:
	node.global_position = position
	node.global_position.y = _sample_height(position.x, position.z) + clearance

func _build_storm_column() -> void:
	var storm_root := Node3D.new()
	storm_root.name = "StormFront"
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

# ── Voice / command helpers (unchanged) ─────────────────────────────────

func _begin_scan(target: Node, hero_player: Node, source: String) -> Dictionary:
	if target == null:
		return { "command_id": "scan", "response_text": "No wreck signature is available right now." }
	target.begin_highlight(10.0)
	_set_waypoint_target(target, str(target.get("waypoint_name")), hero_player)
	if voice_service != null and voice_service.has_method("send_contextual_update"):
		voice_service.call("send_contextual_update", "Targeting %s from %s command." % [str(target.get("wreck_name")), source])
	EventBus.scan_started.emit(str(target.get("wreck_name")))
	return { "command_id": "scan", "response_text": "Scanning locked. Highlighting %s on your visor now." % str(target.get("wreck_name")) }

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
