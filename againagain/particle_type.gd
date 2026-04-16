extends HBoxContainer

signal edit

var _name = ""
var texture = null

func update():
	$TextureRect.texture = texture
	$Label.text = _name

func _on_button_pressed() -> void:
	emit_signal('edit')
