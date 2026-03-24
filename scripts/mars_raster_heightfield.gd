class_name MarsRasterHeightfield
extends RefCounted

var asset_dir: String = ""
var metadata: Dictionary = {}
var height_image: Image
var playability_delta_image: Image
var surface_texture: Texture2D

var world_size_m: float = 0.0
var heightmap_size: int = 0
var min_elevation_m: float = 0.0
var max_elevation_m: float = 0.0
var vertical_offset_m: float = 0.0
var playability_delta_abs_max_m: float = 0.0
var spawn_world_xz: Vector2 = Vector2.ZERO
var rover_world_xz: Vector2 = Vector2.ZERO
var center_lat: float = 0.0
var center_lon: float = 0.0
var surface_map_strength: float = 0.0
var surface_map_black_point: float = 0.0
var surface_map_white_point: float = 1.0

func load_from_directory(dir_path: String) -> Error:
	asset_dir = dir_path
	var metadata_path: String = dir_path.path_join("metadata.json")
	if not FileAccess.file_exists(metadata_path):
		push_warning("MarsRasterHeightfield: missing metadata at %s" % metadata_path)
		return ERR_FILE_NOT_FOUND

	var metadata_text: String = FileAccess.get_file_as_string(metadata_path)
	if metadata_text.is_empty():
		push_warning("MarsRasterHeightfield: metadata file is empty at %s" % metadata_path)
		return ERR_FILE_CORRUPT

	var parsed: Variant = JSON.parse_string(metadata_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("MarsRasterHeightfield: metadata is not a dictionary at %s" % metadata_path)
		return ERR_FILE_CORRUPT
	metadata = parsed

	world_size_m = float(metadata.get("world_size_m", 0.0))
	heightmap_size = int(metadata.get("heightmap_size", 0))
	min_elevation_m = float(metadata.get("min_elevation_m", 0.0))
	max_elevation_m = float(metadata.get("max_elevation_m", 0.0))
	vertical_offset_m = float(metadata.get("vertical_offset_m", 0.0))
	playability_delta_abs_max_m = float(metadata.get("playability_delta_abs_max_m", 0.0))
	center_lat = float(metadata.get("center_lat", 0.0))
	center_lon = float(metadata.get("center_lon", 0.0))
	surface_map_strength = float(metadata.get("surface_map_strength", 0.0))
	surface_map_black_point = float(metadata.get("surface_map_black_point", 0.0))
	surface_map_white_point = float(metadata.get("surface_map_white_point", 1.0))
	spawn_world_xz = _read_vector2(metadata.get("spawn_world_xz", [0.0, 0.0]))
	rover_world_xz = _read_vector2(metadata.get("rover_world_xz", [0.0, 0.0]))

	height_image = _load_png_image(dir_path.path_join("height_16.png"))
	if height_image == null:
		return ERR_FILE_NOT_FOUND

	var delta_name: String = str(metadata.get("playability_delta_path", ""))
	if not delta_name.is_empty():
		playability_delta_image = _load_png_image(dir_path.path_join(delta_name))

	var surface_name: String = str(metadata.get("surface_map_path", ""))
	if not surface_name.is_empty():
		var surface_image: Image = _load_png_image(dir_path.path_join(surface_name))
		if surface_image != null:
			surface_texture = ImageTexture.create_from_image(surface_image)

	return OK

func sample_world_height(x: float, z: float) -> float:
	return sample_elevation_meters(x, z) - vertical_offset_m

func sample_elevation_meters(x: float, z: float) -> float:
	var uv: Vector2 = _world_to_uv(x, z)
	var height01: float = _sample_image_channel(height_image, uv)
	var base_elevation: float = lerpf(min_elevation_m, max_elevation_m, height01)
	return base_elevation + _sample_playability_delta_meters(uv)

func get_surface_texture() -> Texture2D:
	return surface_texture

func get_world_half_size() -> float:
	return world_size_m * 0.5

func _world_to_uv(x: float, z: float) -> Vector2:
	if world_size_m <= 0.001:
		return Vector2(0.5, 0.5)
	var u: float = clampf((x / world_size_m) + 0.5, 0.0, 1.0)
	var v: float = clampf((z / world_size_m) + 0.5, 0.0, 1.0)
	return Vector2(u, v)

func _sample_playability_delta_meters(uv: Vector2) -> float:
	if playability_delta_image == null or playability_delta_abs_max_m <= 0.0:
		return 0.0
	var encoded: float = _sample_image_channel(playability_delta_image, uv)
	var signed_delta: float = (encoded * 2.0) - 1.0
	return signed_delta * playability_delta_abs_max_m

func _sample_image_channel(image: Image, uv: Vector2) -> float:
	if image == null:
		return 0.0
	var width: int = image.get_width()
	var height: int = image.get_height()
	if width <= 0 or height <= 0:
		return 0.0

	var fx: float = clampf(uv.x * float(width - 1), 0.0, float(width - 1))
	var fy: float = clampf(uv.y * float(height - 1), 0.0, float(height - 1))
	var x0: int = int(floor(fx))
	var y0: int = int(floor(fy))
	var x1: int = mini(x0 + 1, width - 1)
	var y1: int = mini(y0 + 1, height - 1)
	var tx: float = fx - float(x0)
	var ty: float = fy - float(y0)

	var c00: float = image.get_pixel(x0, y0).r
	var c10: float = image.get_pixel(x1, y0).r
	var c01: float = image.get_pixel(x0, y1).r
	var c11: float = image.get_pixel(x1, y1).r
	var top: float = lerpf(c00, c10, tx)
	var bottom: float = lerpf(c01, c11, tx)
	return lerpf(top, bottom, ty)

func _load_png_image(path: String) -> Image:
	if not FileAccess.file_exists(path):
		push_warning("MarsRasterHeightfield: missing image at %s" % path)
		return null
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		push_warning("MarsRasterHeightfield: empty image at %s" % path)
		return null
	var image: Image = Image.new()
	var error: int = image.load_png_from_buffer(bytes)
	if error != OK:
		push_warning("MarsRasterHeightfield: failed to load %s (error %d)" % [path, error])
		return null
	return image

func _read_vector2(value: Variant) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO
