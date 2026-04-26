extends Camera2D

@onready var state = $"..".state
var mouse_delta
var camera_zooms
var camera_pan

func _ready():
	init()

func _on_gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_pan"):
		camera_pan = true
	if event.is_action_released("camera_pan"):
		camera_pan = false
	
	if camera_pan and event is InputEventMouseMotion:
		mouse_delta += event.relative
	
	if event.is_action_pressed("camera_zoom_in"):
		camera_zooms -= 1
	if event.is_action_pressed("camera_zoom_out"):
		camera_zooms += 1

func init():
	state['camera_position'] = [0, 0]
	state['camera_zoom'] = 1
	mouse_delta = Vector2(0, 0)
	camera_zooms = 0
	camera_pan = false
	update()

func update():
	var camera_pos = state['camera_position']
	offset = Vector2(camera_pos[0], camera_pos[1])
	var zoom_scalar = state['camera_zoom']
	zoom = Vector2(zoom_scalar, zoom_scalar)

func _process(_delta):
	tick()

func tick():
	var zoom_speed = state['camera_zoom_speed']
	var min_zoom = state['camera_min_zoom']
	var max_zoom = state['camera_max_zoom']
	
	var dirty = false
	if camera_zooms != 0:
		var zoom_scalar = state['camera_zoom']
		state['camera_zoom'] = clampf(zoom_scalar + zoom_speed * camera_zooms, min_zoom, max_zoom)
		camera_zooms = 0
		dirty = true
	if mouse_delta.length() > 0:
		var zoom_scalar = state['camera_zoom']
		mouse_delta /= zoom_scalar
		state['camera_position'][0] -= mouse_delta.x
		state['camera_position'][1] -= mouse_delta.y
		mouse_delta = Vector2(0, 0)
		dirty = true
	
	if dirty:
		update()
