extends HBoxContainer

signal changed

var label = ""
var value = 0

func update():
	$Label.text = label
	$SpinBox.value = value


func _on_spin_box_value_changed(new_value: float) -> void:
	value = new_value as int
	emit_signal("changed")
