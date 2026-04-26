extends Node2D

@export var shader_file: RDShaderFile
var rd: RenderingDevice
var shader_rid: RID
var pipeline_rid: RID

var image: Image

var state = {}

func _ready():
	pass
	#rd = RenderingServer.get_rendering_device()
	# Anything interacting with RenderingDevice should run in render thread (or is it only
	# RenderingServer?)
	# rendering/driver/threads/thread_model="safe" so it doesn't matter in this case.
	#RenderingServer.call_on_render_thread(_rendering_main)

func load_state(new_state):
	state = new_state
	$HUD.state = state
	$Camera2D.state = state
	$MultiMeshInstance2D.state = state

func _create_state():
	image = Image.create_empty(64, 64, false, Image.FORMAT_RGBAF)
	for y in 64:
		for x in 64:
			var color := Color(randf_range(0, 100), randf_range(0, 100), randf_range(0, 10), randf_range(0, 10))
			image.set_pixel(x, y, color)

## GPU THREAD REGION ##

func _rendering_main():
	var spirv := shader_file.get_spirv()
	shader_rid = rd.shader_create_from_spirv(spirv)
	pipeline_rid = rd.compute_pipeline_create(shader_rid)
	
	_create_state()
	
	var indices := [0, 1]
	
	# Slightly misleading name as it is list of uniforms which are used to create
	# uniform sets dynamically
	var uniform_sets := []
	for i in 2:
		uniform_sets.append(_create_uniforms())
	
	# Need to set shader set ID dynamically.
	# Instead of creating uniform sets dynamically which I assume are cheap,
	# it is possible to have 4 kind of static sets instead. TODO
	var uniform_set_rids := []
	for i in len(uniform_sets):
		var uniforms = uniform_sets[i]
		uniform_set_rids.append(rd.uniform_set_create(uniforms, shader_rid, indices[i]))
	
	# I considered having PackedByteArray and using encode_*() to support
	# multiple different types but at this point there's no reason to support
	# multiple types like integers.
	var push_constants := PackedFloat32Array([
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
	])
	var push_constants_bytes := push_constants.to_byte_array()
	
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_rid)
	for i in len(indices):
		rd.compute_list_bind_uniform_set(compute_list, uniform_set_rids[i], i)
	rd.compute_list_set_push_constant(compute_list, push_constants_bytes, push_constants_bytes.size())
	rd.compute_list_dispatch(compute_list, 1, 1, 1)
	rd.compute_list_end()
	
	_cleanup()

func _create_uniforms():
	var uniforms := []
	
	# Uniform 0
	var format := RDTextureFormat.new()
	format.width = 64
	format.height = 64
	format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
					  | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	var texture_view := RDTextureView.new()
	var texture_rid := rd.texture_create(format, texture_view, [image.get_data()])
	
	var uniform := RDUniform.new()
	uniform.binding = 0
	# UniformType enum docs: godot:servers/rendering/rendering_device_commons.h:649
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.add_id(texture_rid)
	uniforms.append(uniform)
	
	for i in 7:
		# Storage buffers are faster at larger size than uniform buffers
		# (https://vkguide.dev/docs/chapter-4/storage_buffers/)
		_add_uniform(uniforms, _storage_buffer_create(4096))
	
	return uniforms

func _add_uniform(uniform_list, uniform):
	uniform.binding = uniform_list.size()
	uniform_list.append(uniform)

func _storage_buffer_create(size):
	var buffer_rid := rd.storage_buffer_create(size)
	
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.add_id(buffer_rid)
	return uniform

func _cleanup():
	if shader_rid != null:
		rd.free_rid(shader_rid)
	# Calling free_rid if RID is not null but is not valid pipeline causes error
	if pipeline_rid != null and rd.compute_pipeline_is_valid(pipeline_rid):
		rd.free_rid(pipeline_rid)
