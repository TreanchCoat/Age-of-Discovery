shader_type spatial;
render_mode specular_schlick_ggx, cull_back;

// Stylised ocean using summed GERSTNER waves: each wave displaces vertices both
// vertically AND horizontally (toward the crest), giving sharp peaks and flatter
// troughs — the real "choppy sea" shape rather than rolling sine bumps. The
// fragment stage tints troughs/crests, foams the steep breaking crests, and adds
// a fresnel sheen. Driven from the game's WindSystem via wave_strength / wind_dir.

uniform vec3 deep_color : source_color = vec3(0.02, 0.11, 0.20);
uniform vec3 shallow_color : source_color = vec3(0.10, 0.34, 0.45);
uniform vec3 foam_color : source_color = vec3(0.85, 0.92, 0.95);
uniform float base_amp = 0.5;          // base wave height, multiplied by wave_strength
uniform float base_wavelength = 34.0;  // longest swell, in world units
uniform float wave_speed = 1.0;
uniform float steepness : hint_range(0.0, 1.0) = 0.55; // crest sharpness / choppiness
uniform float foam_amount : hint_range(0.0, 1.0) = 0.5;
uniform float wave_strength = 1.0;     // set each frame from wind.strength (0.2..2.0)
uniform vec2 wind_dir = vec2(1.0, 0.0); // set each frame from wind.direction

const int NUM_WAVES = 6;
const float G = 9.81;

varying float v_height; // world-space wave height at this vertex
varying float v_steep;  // 0 flat .. 1 steep crest (drives foam)

// Sums NUM_WAVES Gerstner waves at world position p and time t.
// Returns the xyz displacement; writes the surface normal and a steepness factor.
vec3 gerstner(vec2 p, float t, out vec3 nrm, out float steep_out) {
	vec3 disp = vec3(0.0);
	float nx = 0.0;
	float nz = 0.0;
	float ny = 0.0;
	steep_out = 0.0;
	float ang = atan(wind_dir.y, wind_dir.x);
	float wl = base_wavelength;
	float amp = base_amp * wave_strength;
	for (int i = 0; i < NUM_WAVES; i++) {
		vec2 d = vec2(cos(ang), sin(ang));
		float k = 6.28318530 / wl;            // wave number
		float c = sqrt(G / k);                // phase speed (deep water)
		float phase = k * dot(d, p) - c * t * wave_speed;
		float s = sin(phase);
		float co = cos(phase);
		float q = steepness;                  // horizontal pinch toward crest
		// Gerstner displacement
		disp.x += q * amp * d.x * co;
		disp.z += q * amp * d.y * co;
		disp.y += amp * s;
		// Analytic normal accumulation
		float wa = k * amp;
		nx += d.x * wa * co;
		nz += d.y * wa * co;
		ny += q * wa * s;
		steep_out += q * wa * s;
		// Next octave: shorter, smaller, rotated so crests cross
		ang += 0.62;
		wl *= 0.76;
		amp *= 0.82;
	}
	nrm = normalize(vec3(-nx, 1.0 - ny, -nz));
	return disp;
}

void vertex() {
	vec2 world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	vec3 nrm;
	float steep;
	vec3 disp = gerstner(world_xz, TIME, nrm, steep);
	VERTEX += disp;
	v_height = disp.y;
	v_steep = clamp(steep, 0.0, 1.0);
	NORMAL = nrm;
}

void fragment() {
	float amp = max(base_amp * wave_strength, 0.001);
	float crest = clamp(v_height / amp * 0.5 + 0.5, 0.0, 1.0);   // 0 trough .. 1 crest
	vec3 base = mix(deep_color, shallow_color, crest);
	// Foam on steep, breaking crests.
	float foam = smoothstep(1.0 - foam_amount, 1.0, v_steep * crest);
	ALBEDO = mix(base, foam_color, foam);
	METALLIC = 0.0;
	ROUGHNESS = mix(0.06, 0.35, foam);
	SPECULAR = 0.55;
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0), 4.0);
	ALBEDO += vec3(fres * 0.10);
}
