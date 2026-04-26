extends CanvasLayer

@export var TOOL_PROPERTY_STRING_SCENE: PackedScene
@export var TOOL_PROPERTY_NUMBER_SCENE: PackedScene
@export var PARTICLE_TYPE_SCENE: PackedScene
@export var PARTICLE_FORCE_PROPERTY_SCENE: PackedScene
@export var INTERACTION_PROPERTY_SCENE: PackedScene

@onready var tool_buttons = {
	'add_particles': $Panel/TabContainer/Tools/VBoxContainer/AddParticlesBtn,
	'remove_particles': $Panel/TabContainer/Tools/VBoxContainer/RemoveParticlesBtn,
	'pull_particles': $Panel/TabContainer/Tools/VBoxContainer/PullParticlesBtn,
	'push_particles': $Panel/TabContainer/Tools/VBoxContainer/PushParticlesBtn,
}

@onready var state = $"..".state

func _ready():
	tools_init()
	particle_types_init()
	interactions_init()
	world_init()
	camera_init()

func update_all():
	tools_update()
	particle_types_update()
	interactions_update()
	world_update()
	camera_update()
	$"../Camera2D".update()

func tools_init():
	state['tool_active'] = 'add_particles'
	state['tool_settings'] = {
		'add_particles': {
			'amount': 100,
			'name': 'Fire',
		},
		'remove_particles': {},
		'pull_particles': {},
		'push_particles': {},
	}
	for tool_name in tool_buttons:
		var tool_button = tool_buttons[tool_name]
		tool_button.connect('pressed', tools_on_pressed.bind(tool_name))
	tools_update()

func tools_on_pressed(tool_name):
	state['tool_active'] = tool_name
	tools_update()

func tools_update():
	var active_tool = state['tool_active']
	for tool_name in tool_buttons:
		var tool_button = tool_buttons[tool_name]
		var desired_state = false
		if tool_name == active_tool:
			desired_state = true
		
		if desired_state != tool_button.button_pressed:
			tool_button.button_pressed = desired_state
	
	var vbox_settings = $Panel/TabContainer/Tools/VBoxContainer/VBoxSettings
	for child in vbox_settings.get_children():
		child.queue_free()
	
	var tool_settings = state['tool_settings'][active_tool]
	for setting_name in tool_settings:
		var value = tool_settings[setting_name]
		var instance
		if value is int or value is float:
			instance = TOOL_PROPERTY_NUMBER_SCENE.instantiate()
		if value is String:
			instance = TOOL_PROPERTY_STRING_SCENE.instantiate()
		instance.label = setting_name.to_pascal_case()
		instance.value = value
		instance.connect('changed', tools_on_property_changed.bind(instance, setting_name))
		instance.update()
		vbox_settings.add_child(instance)

func tools_on_property_changed(instance, setting_name):
	var active_tool = state['tool_active']
	var tool_settings = state['tool_settings'][active_tool]
	tool_settings[setting_name] = instance.value

func particle_types_init():
	state['particle_types_edit'] = null
	state['particle_types'] = [
		{
			'name': 'Fire',
			'texture': null,
			'forces': {
				'Fire': 25.2,
			},
		}
	]
	particle_types_update()

func particle_types_update():
	var is_viewing = state['particle_types_edit'] == null
	$"Panel/TabContainer/Particle types/ParticleTypes".visible = is_viewing
	$"Panel/TabContainer/Particle types/ParticleEdit".visible = !is_viewing
	
	var particle_types = state['particle_types']
	if is_viewing:
		$"Panel/TabContainer/Particle types/ParticleTypes/HBoxContainer/Label".text = "Particle types (%d):" % len(particle_types)
		
		var vbox = $"Panel/TabContainer/Particle types/ParticleTypes/VBoxContainer"
		for child in vbox.get_children():
			child.queue_free()
		
		for particle_type in particle_types:
			var instance = PARTICLE_TYPE_SCENE.instantiate()
			instance.texture = particle_type['texture']
			instance._name = particle_type['name']
			instance.connect('edit', particle_types_on_edit.bind(particle_type['name']))
			instance.update()
			vbox.add_child(instance)
	else:
		particle_types_update_edit()

func particle_types_update_edit():
	var particle_types = state['particle_types']
	var current_particle_name = state['particle_types_edit']
	var current_particle_type = null
	for particle_type in particle_types:
		if particle_type['name'] == current_particle_name:
			current_particle_type = particle_type
			break
	
	if $"Panel/TabContainer/Particle types/ParticleEdit/HBoxContainer/LineEdit".text != current_particle_type['name']:
		$"Panel/TabContainer/Particle types/ParticleEdit/HBoxContainer/LineEdit".text = current_particle_type['name']
	
	var forces = current_particle_type['forces']
	$"Panel/TabContainer/Particle types/ParticleEdit/HBoxContainer3/Label2".text = "Forces (%d):" % len(forces)
	var vbox = $"Panel/TabContainer/Particle types/ParticleEdit/VBoxContainer"
	for child in vbox.get_children():
		child.queue_free()
	
	for force_type_name in forces:
		var instance = PARTICLE_FORCE_PROPERTY_SCENE.instantiate()
		var force = forces[force_type_name]
		instance.particle_type = force_type_name
		instance.force = force
		instance.connect("changed", particle_types_on_force_change.bind(instance, forces, force_type_name))
		instance.connect("delete", particle_types_on_force_delete.bind(forces, force_type_name))
		instance.update()
		vbox.add_child(instance)
	
	# TODO: texture

func particle_types_generate_name():
	var particle_types = state['particle_types']
	var number = 1
	while true:
		var current_name = "New particle %d" % number
		var is_found = false
		for particle_type in particle_types:
			if particle_type['name'] == current_name:
				number += 1
				is_found = true
				break
		
		if is_found:
			continue
		return current_name

func particle_types_on_create_pressed():
	var particle_name = particle_types_generate_name()
	var particle_types = state['particle_types']
	particle_types.append(
		{
			'name': particle_name,
			'texture': null,
			'forces': {},
		}
	)
	state['particle_types_edit'] = particle_name
	particle_types_update()

func particle_types_on_go_back():
	state['particle_types_edit'] = null
	particle_types_update()

func particle_types_on_edit(particle_name):
	state['particle_types_edit'] = particle_name
	particle_types_update()

func particle_types_on_name_change(new_text):
	var current_particle_name = state['particle_types_edit']
	var particle_types = state['particle_types']
	
	var current_particle_type = null
	for particle_type in particle_types:
		if particle_type['name'] == current_particle_name:
			current_particle_type = particle_type
			break
	
	current_particle_type['name'] = new_text
	state['particle_types_edit'] = new_text
	particle_types_update()

func particle_types_force_generate_name(forces):
	var number = 1
	while true:
		var current_name = "Particle %d" % number
		var is_found = false
		for particle_type_name in forces:
			if particle_type_name == current_name:
				number += 1
				is_found = true
				break
		
		if is_found:
			continue
		return current_name

func particle_types_on_force_create():
	var particle_types = state['particle_types']
	var current_particle_name = state['particle_types_edit']
	var current_particle_type = null
	for particle_type in particle_types:
		if particle_type['name'] == current_particle_name:
			current_particle_type = particle_type
			break
	
	var forces = current_particle_type['forces']
	var new_name = particle_types_force_generate_name(forces)
	forces[new_name] = 0
	particle_types_update_edit()

func particle_types_on_force_change(instance, forces, force_type_name):
	# TODO: delete old one (doesn't change currently, force_type_name is original one)
	forces[force_type_name] = instance.force
	particle_types_update_edit()

func particle_types_on_force_delete(forces, force_type_name):
	forces.erase(force_type_name)
	particle_types_update_edit()

func particle_types_on_delete():
	var current_particle_name = state['particle_types_edit']
	var particle_types = state['particle_types']
	
	var particle_index = null
	for i in len(particle_types):
		var particle_type = particle_types[i]
		if particle_type['name'] == current_particle_name:
			particle_index = i
			break
	
	particle_types.remove_at(particle_index)
	state['particle_types_edit'] = null
	particle_types_update()

func interactions_init():
	state['interactions'] = []
	interactions_update()

func interactions_update():
	var interactions = state['interactions']
	$Panel/TabContainer/Interactions/ParticleTypes/HBoxContainer/Label.text = "Interactions (%d):" % len(interactions)

	var vbox = $Panel/TabContainer/Interactions/ParticleTypes/VBoxContainer
	for child in vbox.get_children():
		child.queue_free()
	
	for i in len(interactions):
		var interaction = interactions[i]
		var instance = INTERACTION_PROPERTY_SCENE.instantiate()
		instance.input = interaction[0]
		instance.input2 = interaction[1]
		instance.output = interaction[2]
		instance.connect('changed', interactions_on_change.bind(instance, interaction))
		instance.connect('delete', interactions_on_delete.bind(i))
		instance.update()
		vbox.add_child(instance)

func interactions_on_create():
	state['interactions'].append(['', '', ''])
	interactions_update()

func interactions_on_change(instance, interaction):
	interaction[0] = instance.input
	interaction[1] = instance.input2
	interaction[2] = instance.output
	interactions_update()

func interactions_on_delete(i):
	state['interactions'].remove_at(i)
	interactions_update()

func world_init():
	state['world_particle_limit'] = 2500
	state['world_tex_size'] = [64, 64]
	$"../MultiMeshInstance2D".init()
	world_update()

func world_reset():
	$"../MultiMeshInstance2D".init()
	world_update()

func world_update():
	$Panel/TabContainer/World/VBoxContainer/HBoxContainer/SpinBox.value = state['world_particle_limit']
	$"../MultiMeshInstance2D".update()

func world_on_world_particle_limit_change(new_value):
	state['world_particle_limit'] = new_value as int

func world_on_reset_world():
	world_reset()

func world_on_quick_save():
	var json = JSON.stringify(state)
	var file = FileAccess.open("user://quick_save.json", FileAccess.WRITE)
	file.store_string(json)

func world_on_quick_load():
	var file = FileAccess.open("user://quick_save.json", FileAccess.READ)
	var content = file.get_as_text()
	var new_state = JSON.parse_string(content)
	new_state['world_particle_limit'] = new_state['world_particle_limit'] as int
	$"..".load_state(new_state)
	update_all()

func world_on_save_world_file():
	pass

func world_on_load_world_file():
	pass

func camera_init():
	state['camera_min_zoom'] = 0.1
	state['camera_max_zoom'] = 50
	state['camera_zoom_speed'] = 0.1
	camera_update()

func camera_update():
	$Panel/TabContainer/Camera/VBoxContainer/HBoxContainer/SpinBox.value = state['camera_min_zoom']
	$Panel/TabContainer/Camera/VBoxContainer/HBoxContainer2/SpinBox.value = state['camera_max_zoom']
	$Panel/TabContainer/Camera/VBoxContainer/HBoxContainer3/SpinBox.value = state['camera_zoom_speed']

func camera_on_min_zoom_change(new_value):
	state['camera_min_zoom'] = new_value

func camera_on_max_zoom_change(new_value):
	state['camera_max_zoom'] = new_value

func camera_on_zoom_speed_change(new_value):
	state['camera_zoom_speed'] = new_value

func camera_on_reset_position():
	pass
