extends HBoxContainer

signal delete
signal changed

var input = ""
var input2 = ""
var output = ""

func update():
	if $LineEdit.text != input:
		$LineEdit.text = input
	if $LineEdit2.text != input2:
		$LineEdit2.text = input2
	if $LineEdit3.text != output:
		$LineEdit3.text = output

func _on_line_edit_text_changed(new_text: String) -> void:
	input = new_text
	emit_signal("changed")

func _on_line_edit_2_text_changed(new_text: String) -> void:
	input2 = new_text
	emit_signal("changed")

func _on_line_edit_3_text_changed(new_text: String) -> void:
	output = new_text
	emit_signal("changed")

func _on_button_pressed() -> void:
	emit_signal("delete")
