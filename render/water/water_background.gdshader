shader_type canvas_item;

// Phase B2 (§8, §7.1): depth fog, caustics, light shafts, and a surface
// band, all procedural - no textures. Pure atmosphere, entirely
// independent of population counts or sim state, same as the rest of
// Track B. Applied to a full-rect ColorRect behind the particle layer.

uniform float time_scale : hint_range(0.0, 2.0) = 0.3;

float caustic_pattern(vec2 uv, float t) {
	float v = 0.0;
	v += sin(uv.x * 12.0 + t * 1.3) * 0.5 + 0.5;
	v += sin(uv.y * 10.0 - t * 1.1 + sin(uv.x * 4.0 + t)) * 0.5 + 0.5;
	v += sin((uv.x + uv.y) * 9.0 + t * 0.7) * 0.5 + 0.5;
	v /= 3.0;
	return pow(v, 3.0);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * time_scale;

	// Depth fog: shallow water near the top, darker and more saturated
	// toward the bottom where less light reaches.
	vec3 shallow_color = vec3(0.07, 0.20, 0.24);
	vec3 deep_color = vec3(0.01, 0.05, 0.09);
	vec3 base = mix(shallow_color, deep_color, uv.y);

	// Caustics: shifting light patterns, strongest near the surface and
	// fading out with depth (real caustics don't reach far down either).
	float caustics = caustic_pattern(uv * 3.0, t);
	float caustic_strength = (1.0 - uv.y) * 0.5;
	base += caustics * caustic_strength * vec3(0.3, 0.5, 0.4);

	// Light shafts: a handful of soft diagonal-ish beams drifting slowly,
	// brightest at the top and fading with depth.
	float shafts = 0.0;
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float shaft_x = fract(uv.x + sin(t * 0.05 + fi * 2.1) * 0.05 + fi * 0.27);
		float dist = abs(shaft_x - 0.5);
		shafts += smoothstep(0.12, 0.0, dist) * (1.0 - uv.y);
	}
	base += shafts * vec3(0.15, 0.22, 0.20);

	// Surface treatment: a gently undulating bright band at the very top.
	float wave = sin(uv.x * 20.0 + t * 2.0) * 0.01;
	float surface = smoothstep(0.06 + wave, 0.0 + wave, uv.y);
	base += surface * vec3(0.2, 0.3, 0.3);

	COLOR = vec4(base, 1.0);
}
