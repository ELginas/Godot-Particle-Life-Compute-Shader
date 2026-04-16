extends HBoxContainer

signal changed

var label = ""
var value = ""

func update():
	$Label.text = label
	$LineEdit.text = value


func _on_line_edit_text_changed(new_text: String) -> void:
	value = new_text
	emit_signal("changed")
