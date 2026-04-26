shader_type canvas_item;

uniform int tex_atlas_size;
uniform ivec2 tex_size;
varying float v;

void vertex() {
	int i = int(INSTANCE_CUSTOM.r);
	int tex_row_length = tex_atlas_size / tex_size.x;
	int tex_col_length = tex_atlas_size / tex_size.y;
	int x = i % tex_row_length;
	int y = i / tex_row_length;

	vec2 size = vec2(float(tex_row_length), float(tex_col_length));
	vec2 pos = vec2(float(x), float(y));
	UV /= size;
	UV += pos / size;
}

void fragment() {
	
}