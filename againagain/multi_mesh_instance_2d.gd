extends MultiMeshInstance2D

var image: Image
var tex: ImageTexture

func _ready():
	var size = Vector2i(256, 256)
	multimesh.instance_count = size.x * size.y
	multimesh.mesh.size = texture.get_size() * Vector2(1, -1)
	
	for i in multimesh.instance_count:
		var new_position = Vector2(0, 0)
		multimesh.set_instance_transform_2d(i, Transform2D(0, new_position))

	image = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBAF)
	tex = ImageTexture.create_from_image(image)
	update_image()
	material.set_shader_parameter("particle_texture", tex)
	material.set_shader_parameter("size", size)

func _process(delta: float) -> void:
	update_image()

func update_image():
	for y in image.get_height():
		for x in image.get_width():
			var color = Color(randf_range(-50, 50), randf_range(-50, 50), 0, 0)
			image.set_pixel(x, y, color)
	tex.update(image)
