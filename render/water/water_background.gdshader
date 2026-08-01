shader_type canvas_item;

// Phase B2 (§8, §7.1): depth fog, caustics, light shafts, a surface band,
// and a vignette, all procedural - no textures. Pure atmosphere, entirely
// independent of population counts or sim state, same as the rest of
// Track B. Applied to a full-rect ColorRect behind the particle layer.
//
// caustic_pattern is also replicated (loosely) in look_study.gd so the
// organisms can pick up matching shimmer instead of looking pasted on
// top of the water rather than inside it.

uniform float time_scale : hint_range(0.0, 2.0) = 0.3;

// Two rotated sine grids multiplied together and sharpened - the
// interference between them breaks up the regular grid into an organic,
// net-like pattern much closer to real caustics than a plain sine sum
// (which just reads as a plaid).
float caustic_pattern(vec2 uv, float t) {
	vec2 p1 = uv;
	vec2 p2 = vec2(uv.x * 0.6 + uv.y * 0.8, uv.x * -0.8 + uv.y * 0.6);
	float a = sin(p1.x + t) * sin(p1.y + t * 0.8);
	float b = sin(p2.x * 1.3 - t * 0.9) * sin(p2.y * 1.3 + t * 1.1);
	float v = abs(a * b);
	return pow(1.0 - v, 6.0);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * time_scale;

	// Depth fog: shallow water near the top, darker and more saturated
	// toward the bottom where less light reaches.
	vec3 shallow_color = vec3(0.07, 0.20, 0.24);
	vec3 deep_color = vec3(0.01, 0.05, 0.09);
	vec3 base = mix(shallow_color, deep_color, uv.y);

	// Caustics: thin, shifting bright net, strongest near the surface and
	// fading out with depth (real caustics don't reach far down either).
	float caustics = caustic_pattern(uv * 6.0, t);
	float caustic_strength = (1.0 - uv.y * 0.9);
	base += caustics * caustic_strength * vec3(0.35, 0.6, 0.5);

	// Light shafts: a few fixed, slowly-drifting beams (not a wrapping
	// fract() pattern, which produced a visible seam), spreading wider
	// with depth like real light cones do.
	float shafts = 0.0;
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float shaft_x = 0.15 + fi * 0.24 + sin(t * 0.07 + fi * 2.1) * 0.03;
		float width = mix(0.025, 0.07, uv.y);
		shafts += smoothstep(width, 0.0, abs(uv.x - shaft_x)) * (1.0 - uv.y * 0.85);
	}
	base += shafts * vec3(0.16, 0.24, 0.22);

	// Surface treatment: a gently undulating bright band at the very top.
	float wave = sin(uv.x * 20.0 + t * 2.0) * 0.01;
	float surface = smoothstep(0.06 + wave, 0.0 + wave, uv.y);
	base += surface * vec3(0.2, 0.3, 0.3);

	// Vignette: darkens the corners so the frame reads as a composed shot
	// rather than a flat, evenly-lit rectangle.
	float vignette = smoothstep(0.9, 0.35, length(uv - vec2(0.5)));
	base *= mix(0.55, 1.0, vignette);

	COLOR = vec4(base, 1.0);
}
