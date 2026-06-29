shader_type spatial;
render_mode cull_disabled, diffuse_burley;
// Stylised terrain: colour by world height and slope. Sea level is world y = 0;
// underwater terrain is hidden by the ocean so its colour doesn't matter much.

uniform vec3 sand_col  : source_color = vec3(0.80, 0.74, 0.55);
uniform vec3 grass_col : source_color = vec3(0.28, 0.42, 0.20);
uniform vec3 rock_col  : source_color = vec3(0.42, 0.40, 0.38);
uniform vec3 snow_col  : source_color = vec3(0.92, 0.93, 0.95);
uniform float sand_top   = 3.0;    // world units; beach band above the waterline
uniform float grass_top  = 35.0;
uniform float snow_bottom = 60.0;
uniform float rock_slope = 0.62;   // normal.y below this counts as steep -> rock

varying float v_height;
varying vec3 v_wnormal;

void vertex() {
	v_height  = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 col = sand_col;
	col = mix(col, grass_col, smoothstep(sand_top, sand_top + 8.0, v_height));
	col = mix(col, snow_col,  smoothstep(snow_bottom, snow_bottom + 25.0, v_height));
	float steep = 1.0 - smoothstep(rock_slope, rock_slope + 0.2, v_wnormal.y);
	col = mix(col, rock_col, steep);
	ALBEDO = col;
	ROUGHNESS = 0.95;
	METALLIC = 0.0;
}
