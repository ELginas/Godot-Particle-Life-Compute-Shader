extends MultiMeshInstance2D

@onready var state = $"..".state
var texture_indices = []
var textures = [load("res://icon.svg")]
var tex_atlas_image: Image
var tex_atlas: ImageTexture

func init():
	state['world_positions'] = []
	state['world_velocities'] = []
	state['world_texture_indices'] = []

func update():
	var particle_limit = state['world_particle_limit']
	state['world_particle_count'] = particle_limit
	var positions = state['world_positions']
	var velocities = state['world_velocities']
	var texture_indices = state['world_texture_indices']
	
	for i in particle_limit:
		positions.append([i * 12, i * 6])
		velocities.append([i, i])
		texture_indices.append(i % 4)
	
	multimesh.instance_count = state['world_particle_count']
	var tex_size_arr = state['world_tex_size']
	var tex_size = Vector2(tex_size_arr[0], tex_size_arr[1])
	multimesh.mesh.size = tex_size * Vector2(1, -1)
	
	var tex_atlas_size = 128
	#var tex_row_length = (int)(tex_atlas_size / tex_size.x)
	#tex_atlas_image = Image.create_empty(tex_atlas_size, tex_atlas_size, false, Image.FORMAT_RGBA8)
	#for i in len(textures):
		#var x = i % tex_row_length
		#var y = i / tex_row_length
		#
		#var tex_image = textures[i].get_image()
		#tex_atlas_image.blit_rect(tex_image, Rect2i(0, 0, tex_size.x, tex_size.y), Vector2i(x * tex_size.x, y * tex_size.y))
	tex_atlas_image = textures[0].get_image()
	
	tex_atlas = ImageTexture.create_from_image(tex_atlas_image)
	texture = tex_atlas
	
	material.set_shader_parameter("tex_atlas_size", tex_atlas_size)
	material.set_shader_parameter("tex_size", tex_size)
	
	update_tick()

func update_tick():
	var positions = state['world_positions']
	var texture_indices = state['world_texture_indices']
	var particle_count = state['world_particle_count']
	for i in particle_count:
		var position = Vector2(positions[i][0], positions[i][1])
		multimesh.set_instance_transform_2d(i, Transform2D(0, position))
		multimesh.set_instance_custom_data(i, Color(texture_indices[i], 0, 0, 0))

func _process(delta):
	tick(delta)

func tick(delta):
	var positions = state['world_positions']
	var velocities = state['world_velocities']
	var particle_count = state['world_particle_count']
	for i in particle_count:
		positions[i][0] += velocities[i][0] * delta
		positions[i][1] += velocities[i][1] * delta
	update_tick()
