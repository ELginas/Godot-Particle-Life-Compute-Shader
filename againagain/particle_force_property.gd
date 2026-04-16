extends HBoxContainer

signal changed
signal delete

var particle_type = ""
var force = 0

func update():
	$LineEdit.text = particle_type
	$SpinBox.value = force

func _on_button_pressed() -> void:
	emit_signal("delete")

func _on_line_edit_text_changed(new_text: String) -> void:
	particle_type = new_text
	emit_signal("changed")

func _on_spin_box_value_changed(value: float) -> void:
	force = value
	emit_signal("changed")
