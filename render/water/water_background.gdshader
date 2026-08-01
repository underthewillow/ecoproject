shader_type canvas_item;

// Phase B2 (§8, §7.1): depth fog, light shafts, a surface band, and a
// vignette. Pure atmosphere, entirely independent of population counts or
// sim state, same as the rest of Track B.
//
// The caustic-net layer (three hand-written attempts, then a PixelLab-
// generated tile) is gone. Every version had a real problem: sine math
// looked geometrically regular, synthetic noise either washed everything
// out or tiled visibly, and the generated tile's one bold arc/wave shape
// created a distracting periodic sweep once animated (confirmed on
// video) or just sat there looking un-water-like once frozen to fix that.
// Rather than keep iterating on a sub-effect that hasn't landed after
// several tries, cutting it entirely and keeping the parts of this
// background that were never a problem.

uniform float time_scale : hint_range(0.0, 2.0) = 0.3;

vec3 screen_blend(vec3 base, vec3 light) {
	return 1.0 - (1.0 - base) * (1.0 - light);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * time_scale;

	// Depth fog: shallow water near the top, darker and more saturated
	// toward the bottom where less light reaches.
	vec3 shallow_color = vec3(0.06, 0.17, 0.21);
	vec3 deep_color = vec3(0.01, 0.04, 0.08);
	vec3 base = mix(shallow_color, deep_color, uv.y);

	// Light shafts: a few fixed, slowly-drifting beams, spreading wider
	// with depth like real light cones do.
	float shafts = 0.0;
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float shaft_x = 0.15 + fi * 0.24 + sin(t * 0.07 + fi * 2.1) * 0.03;
		float width = mix(0.015, 0.045, uv.y);
		shafts += smoothstep(width, 0.0, abs(uv.x - shaft_x)) * (1.0 - uv.y * 0.85);
	}
	base = screen_blend(base, clamp(shafts, 0.0, 1.0) * vec3(0.1, 0.15, 0.14));

	// Surface treatment: a gently undulating bright band at the very top.
	float wave = sin(uv.x * 20.0 + t * 2.0) * 0.01;
	float surface = smoothstep(0.05 + wave, 0.0 + wave, uv.y);
	base = screen_blend(base, surface * vec3(0.18, 0.26, 0.24));

	// Vignette: darkens the corners so the frame reads as a composed shot
	// rather than a flat, evenly-lit rectangle.
	float vignette = smoothstep(0.9, 0.35, length(uv - vec2(0.5)));
	base *= mix(0.5, 1.0, vignette);

	COLOR = vec4(base, 1.0);
}
