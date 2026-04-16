shader_type canvas_item;

uniform sampler2D particle_texture;
uniform ivec2 size;
varying vec2 tex_uv;

void vertex() {
	int x = INSTANCE_ID % size.x;
	int y = INSTANCE_ID / size.x;
	vec2 pos = vec2(float(x), float(y));
	vec2 sizef = vec2(float(size.x), float(size.y));
	vec2 uv = vec2(pos.x / sizef.x, pos.y / sizef.y);
	vec2 position = texture(particle_texture, uv).xy;
	VERTEX += position;
	tex_uv = uv;
}

void fragment() {
	vec2 position = texture(particle_texture, tex_uv).xy;
	COLOR *= vec4(position.x, position.y, 0., 1.);
}