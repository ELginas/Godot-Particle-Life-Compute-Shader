extends TextureRect

# CONFIG
var compute_texture_size: int = 256 # Holds up to 256*256 pixel particles
var viewport_size: int = 800
var shader_local_size_x := 16
var shader_local_size_y := 16
@onready var image_size = compute_texture_size
var world_size_mult: int = 20
var point_count: int = 1024 * 10
var species_count: int = 8

# STARTUP PARAMS
var rand_start_interaction_range: float = 2.0 # force will be random between -X and +X
var rand_start_radius_mul: float = 2.0 # different startup patterns use this multiplier
var start_point_count: int = point_count # only used when restarting new field
var start_species_count: int = species_count # only used when restarting new field
var starting_method: int = 2 # which method to use when restarting new field?

# SPEED/TIME
var dt: float = .1 # .25
var paused_dt: float = dt # only used for pause/resume feature

# PARTICLE SIZE
var interaction_radius: float = 150.0

# COLLISION FORCE
var collision_radius: float = 15.0 # 3.5
var collision_strength: float = 1.0 # 10.0 # 20.0 # 30.0 # 15.0 # 4.0 #2.0 # 5.0 # 10.0 # 0.0

# BORDER STYLE (optional)
var border_style: float = 0.0 # 0 no boundary, 1 bounded rectangle, 2 bounded circle, 3 bouncy rectangle, 4 bouncy circle
var border_size_scale: float = 1.0 # scaled from image_size

# CENTER FORCE (optional)
var center_attraction: float = 0.0 # 0.1 #0.28 #0.35 # 0.01 # # set to 0 to turn off

# FORCE ADJUSTMENTS
var damping: float = 0.95 # 1.0 # 0.85 #0.99 # FRICTION
var max_force: float = 500.0 # 13.0 # 3.0 #0.1 # 20.0 # 5.0 # 0.0 to 5.0
var force_softening_mul: float = 0.05
var max_velocity_mul: float = 0.25
var force_softening: float = interaction_radius * force_softening_mul:
	get():
		return interaction_radius * force_softening_mul

var max_velocity: float = interaction_radius * max_velocity_mul:
	get():
		return interaction_radius * max_velocity_mul

# CAMERA
var camera_center: Vector2 = Vector2.ZERO
var zoom: float = 0.82 # 0.52 # 0.16 # 0.24 #0.16 # 0.34 # 0.21 # 0.6
const MIN_ZOOM := 0.1
const MAX_ZOOM := 5.0

# SPATIAL HASHING
var cell_size: int = 500 # 250 # 500
var cells_per_row: int = 0
var num_cells: int = 0

# INTERACTION MATRIX
var interaction_matrix: PackedFloat32Array = []

# RENDERER SETUP
var rdmain := RenderingServer.get_rendering_device()
var textureRD: Texture2DRD
var shader: RID
var pipeline: RID
var uniform_set: RID
var output_tex: RID
var fmt := RDTextureFormat.new()
var view := RDTextureView.new()
var buffers: Array[RID] = []
var uniforms: Array[RDUniform] = []
var output_tex_uniform: RDUniform # TODO: CONFIRM IF NEEDED
var input_particles: RID
var output_particles: RID
var multimesh := MultiMesh.new()
var quadmesh := QuadMesh.new()
var render_material := ShaderMaterial.new()

func _ready():
	randomize()
	image_size = %ComputeParticleLife.size.x
	
	fmt.width = compute_texture_size
	fmt.height = compute_texture_size
	fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT \
					| RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
					| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT \
					| RenderingDevice.TEXTURE_USAGE_CPU_READ_BIT \
					| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	view = RDTextureView.new()
	textureRD = Texture2DRD.new()
	
	RenderingServer.call_on_render_thread(restart_simulation)

func _exit_tree():
	#if textureRD:
		#textureRD.texture_rd_rid = RID()
	RenderingServer.call_on_render_thread(_free_compute_resources)

func _free_compute_resources():
	if textureRD:
		textureRD.texture_rd_rid = RID()
	for i in range(buffers.size()):
		if buffers[i]:
			rdmain.free_rid(buffers[i])
	if shader:
		rdmain.free_rid(shader)
	if input_particles:
		rdmain.free_rid(input_particles)
	if output_particles:
		rdmain.free_rid(output_particles)
	# TODO: consider other RIDs

func restart_simulation():
	# Use startup settings - consider refactor locking logic for %CheckBoxLockMatrix
	point_count = start_point_count
	if (species_count != start_species_count && !%CheckBoxLockMatrix.disabled && %CheckBoxLockMatrix.button_pressed):
		%CheckBoxLockMatrix.button_pressed = false
	species_count = start_species_count

	# Create playfield
	var start_data: Dictionary = {}
	match starting_method:
		0: start_data = StartupManager.build_particles(self, StartupManager.pos_random, false)
		1: start_data = StartupManager.build_particles(self, StartupManager.pos_ring, true)
		2:
			StartupManager.setup_spiral_params(self)
			start_data = StartupManager.build_particles(self, StartupManager.pos_spiral, false)
		3:
			StartupManager.setup_spiral_params(self)
			start_data = StartupManager.build_particles(self, StartupManager.pos_spiral, true)
		4: start_data = StartupManager.build_particles(self, StartupManager.pos_columns, false)
		5: start_data = StartupManager.build_particles(self, StartupManager.pos_columns, true)
		_: start_data = StartupManager.build_particles(self, StartupManager.pos_random, false)
	rebuild_buffers(start_data)

	# Unlock Checkbox
	%CheckBoxLockMatrix.disabled = false

func rebuild_buffers(data: Dictionary):
	_free_compute_resources()
	buffers.clear()

	var img_particles := Image.create(
		compute_texture_size,
		compute_texture_size,
		false,
		Image.FORMAT_RGBAF
	)

	for i in point_count:
		var x: int = i % compute_texture_size
		@warning_ignore("integer_division")
		var y: int = i / compute_texture_size
		img_particles.set_pixel(
			x, y,
			Color(data["pos"][i].x, data["pos"][i].y, data["vel"][i].x, data["vel"][i].y)
		)
	var data_particles := img_particles.get_data()
	input_particles = rdmain.texture_create(fmt, view, [data_particles])
	output_particles = rdmain.texture_create(fmt, view, [data_particles])

	# IN BUFFERS 
	var species_bytes: PackedByteArray = data["species"].to_byte_array()
	var interaction_bytes: PackedByteArray = data["interaction_matrix"].to_byte_array()
	buffers.append(rdmain.storage_buffer_create(species_bytes.size(), species_bytes)) # 2
	buffers.append(rdmain.storage_buffer_create(interaction_bytes.size(), interaction_bytes)) # 5

	# SPATIAL HASIHNG BUFFERS
	# Compute Number of Cells
	var world_size := float(image_size) * float(world_size_mult) # same as GLSL's world
	cells_per_row = int(ceil(world_size / cell_size))
	num_cells = cells_per_row * cells_per_row # SETS global property: num_cells
	# Cell counts buffer (per cell)
	var cell_counts_b := PackedByteArray()
	cell_counts_b.resize(num_cells * 4)
	buffers.append(rdmain.storage_buffer_create(cell_counts_b.size(), cell_counts_b)) # binding 3
	# Cell offsets buffer (per cell)
	var cell_offsets_b := PackedByteArray()
	cell_offsets_b.resize(num_cells * 4)
	buffers.append(rdmain.storage_buffer_create(cell_offsets_b.size(), cell_offsets_b)) # binding 4
	# Sorted indices (per agent)
	var sorted_indices_b := PackedByteArray()
	sorted_indices_b.resize(int(point_count) * 4)
	buffers.append(rdmain.storage_buffer_create(sorted_indices_b.size(), sorted_indices_b)) # binding 5
	# Agent -> cell mapping (per agent)
	var agent_cell_b := PackedByteArray()
	agent_cell_b.resize(int(point_count) * 4)
	buffers.append(rdmain.storage_buffer_create(agent_cell_b.size(), agent_cell_b)) # binding 6
	# Cursor per cell (per cell)
	var cursor_b := PackedByteArray()
	cursor_b.resize(num_cells * 4)
	buffers.append(rdmain.storage_buffer_create(cursor_b.size(), cursor_b)) # binding 7

	# Output texture
	textureRD.texture_rd_rid = output_particles

	# multimesh/instance/mesh/material
	#var mask :Texture2D= load("res://triangle.png")
	var mask: GradientTexture2D = load("res://my_circle.tres")
	render_material.shader = load("res://particle_draw.gdshader")
	render_material.set_shader_parameter("alpha_tex", mask)
	render_material.set_shader_parameter("particle_buffer", textureRD)
	var heatmap_colors: GradientTexture1D = load("res://my_gradient_heatmap.tres")
	render_material.set_shader_parameter("gradient_texture", heatmap_colors)
	render_material.set_shader_parameter("species_count", species_count)
	render_material.set_shader_parameter("camera_center", camera_center)
	render_material.set_shader_parameter("zoom", zoom)
	render_material.set_shader_parameter("compute_texture_size", compute_texture_size)
	render_material.set_shader_parameter("viewport_size", Vector2(viewport_size, viewport_size))
	%MMI.material = render_material # 2D

	quadmesh.size = Vector2.ONE
	multimesh.instance_count = 0 # can only set other values when instance_count==0
	multimesh.mesh = quadmesh
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = false
	multimesh.use_custom_data = true
	multimesh.instance_count = point_count # actual point count
	for i in range(point_count):
		multimesh.set_instance_transform_2d(i, Transform2D())
		multimesh.set_instance_custom_data(i, Color(data["species"][i], 0, 0, 0))

	%MMI.multimesh = multimesh

	# SHADER + PIPELINE
	var shader_file := load("res://compute_particle_life.glsl") as RDShaderFile
	shader = rdmain.shader_create_from_spirv(shader_file.get_spirv())
	pipeline = rdmain.compute_pipeline_create(shader)

func compute_stage(run_mode: int, input_set, output_set):
	var global_size_x: int
	var global_size_y: int
	
	var group_size = shader_local_size_x * shader_local_size_y # 16*16 = 256
	
	# --- texture based passes ---
	if run_mode in [0, 10]:
		global_size_x = int(ceil(float(compute_texture_size) / shader_local_size_x))
		global_size_y = int(ceil(float(compute_texture_size) / shader_local_size_y))

	# --- prefix scan ---
	elif run_mode == 11:
		global_size_x = int(ceil(float(num_cells) / float(group_size)))
		global_size_y = 1

	# --- scatter ---
	elif run_mode == 12:
		global_size_x = int(ceil(float(point_count) / float(group_size)))
		global_size_y = 1
		
	
	var compute_list := rdmain.compute_list_begin()
	rdmain.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rdmain.compute_list_bind_uniform_set(compute_list, input_set, 0)
	rdmain.compute_list_bind_uniform_set(compute_list, output_set, 1)

	# PUSH CONSTANT PARAMETERS
	var params := PackedFloat32Array([
		run_mode,
		dt,
		compute_texture_size,
		damping,
		point_count,
		species_count,
		interaction_radius,
		collision_radius,
		collision_strength,
		border_style,
		border_size_scale, # diff name
		image_size,
		world_size_mult,
		center_attraction,
		force_softening,
		max_force,
		max_velocity,
		cell_size,
		cells_per_row,
		# 0.0 # padding to 4 # actually padding causes issues
	])
	var params_bytes := PackedByteArray()
	params_bytes.append_array(params.to_byte_array())

	rdmain.compute_list_set_push_constant(compute_list, params_bytes, params_bytes.size())
	rdmain.compute_list_dispatch(compute_list, global_size_x, global_size_y, 1)
	rdmain.compute_list_end()

func _process(_delta):
	RenderingServer.call_on_render_thread(run_simulation)

func run_simulation():
	# Flip buffers via uniformsets
	var frame_flip = flip_buffers()
	var input_set = frame_flip[0]
	var output_set = frame_flip[1]

	# ---------- SPATIAL HASHING PASSES ----------
	# zero cell counts # TODO confirm buffer
	var empty_counts_bytes: PackedByteArray
	empty_counts_bytes.resize(num_cells * 4)
	rdmain.buffer_update(buffers[2], 0, empty_counts_bytes.size(), empty_counts_bytes)
	# count cells (agents per cell)
	compute_stage(10, input_set, output_set)
	# compute prefix sum
	compute_stage(11, input_set, output_set)
	# scatter sorted indices
	compute_stage(12, input_set, output_set)
	
	# ---------- SIMULATION PASSES ----------
	# RUN SIM STEP
	compute_stage(0, input_set, output_set)
	
	# UPDATE MATERIAL BUFFERS
	render_material.set_shader_parameter("particle_buffer", textureRD)
	render_material.set_shader_parameter("camera_center", camera_center)
	render_material.set_shader_parameter("zoom", zoom)

	rdmain.free_rid(input_set)
	rdmain.free_rid(output_set)

var ping: bool = false
func flip_buffers():
	# Flip buffers
	ping = !ping
	var read_main: RID
	var read_sec: RID
	var write_main: RID
	var write_sec: RID
	if ping:
		read_main = output_particles
		write_main = input_particles
	else:
		read_main = input_particles
		write_main = output_particles

	# use correct output image
	if textureRD:
		textureRD.texture_rd_rid = write_main
	
	# Create uniform sets
	var input_set := _create_uniform_set(read_main, read_sec, 0)
	var output_set := _create_uniform_set(write_main, write_sec, 1)
	
	return [input_set, output_set]

func _create_uniform_set(texture_rd: RID, texture_rd2: RID, _uniform_set: int) -> RID:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = 0
	uniform.add_id(texture_rd)
	
	var uniform2 := RDUniform.new()
	uniform2.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform2.binding = 0
	uniform2.add_id(texture_rd2)
	
	var uniform3 := RDUniform.new()
	uniform3.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform3.binding = 1
	uniform3.add_id(buffers[0]) # in_species_buffer

	var uniform4 := RDUniform.new()
	uniform4.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform4.binding = 2
	uniform4.add_id(buffers[1]) # interaction_matrix
	
	var uniform5 := RDUniform.new()
	uniform5.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform5.binding = 3
	uniform5.add_id(buffers[2]) # Cell counts buffer
	
	var uniform6 := RDUniform.new()
	uniform6.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform6.binding = 4
	uniform6.add_id(buffers[3]) # Cell offsets buffer
	
	var uniform7 := RDUniform.new()
	uniform7.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform7.binding = 5
	uniform7.add_id(buffers[4]) # Sorted indices
	
	var uniform8 := RDUniform.new()
	uniform8.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform8.binding = 6
	uniform8.add_id(buffers[5]) # Agent -> cell mapping
	
	var uniform9 := RDUniform.new()
	uniform9.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform9.binding = 7
	uniform9.add_id(buffers[6]) # Cursor per cell
	
	var new_set = [uniform, uniform2, uniform3, uniform4, uniform5, uniform6, uniform7, uniform8, uniform9]
	
	return rdmain.uniform_set_create(new_set, shader, _uniform_set)
