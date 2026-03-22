class_name TerrainVisualData
extends RefCounted

static func build_runtime_texture(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	grid_width: int,
	min_height: float,
	max_height: float
) -> ImageTexture:
	if vertices.is_empty() or grid_width <= 1:
		return null

	var image := Image.create(grid_width, grid_width, false, Image.FORMAT_RGBA8)
	var height_range := maxf(max_height - min_height, 0.001)

	for z_index in range(grid_width):
		for x_index in range(grid_width):
			var vertex_index := z_index * grid_width + x_index
			var vertex := vertices[vertex_index]
			var normal := Vector3.UP
			if vertex_index < normals.size():
				normal = normals[vertex_index]

			var height_norm := clampf((vertex.y - min_height) / height_range, 0.0, 1.0)
			var slope_norm := clampf(1.0 - clampf(normal.y, 0.0, 1.0), 0.0, 1.0)
			var dust_accumulation := clampf((1.0 - (slope_norm * 1.65)) * (1.0 - pow(height_norm, 1.15)), 0.0, 1.0)
			image.set_pixel(x_index, z_index, Color(height_norm, slope_norm, dust_accumulation, 1.0))

	return ImageTexture.create_from_image(image)

static func apply_to_material(
	material: ShaderMaterial,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	grid_width: int,
	min_height: float,
	max_height: float
) -> void:
	if material == null:
		return
	var terrain_texture := build_runtime_texture(vertices, normals, grid_width, min_height, max_height)
	if terrain_texture == null:
		return
	material.set_shader_parameter("terrain_data", terrain_texture)
