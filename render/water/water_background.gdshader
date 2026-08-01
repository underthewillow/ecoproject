shader_type canvas_item;

// Phase B2 (§8, §7.1): depth fog, caustics, light shafts, a surface band,
// and a vignette, all procedural except one small tileable texture
// (render/water/caustic_tile.png) used for the caustics. Pure atmosphere,
// entirely independent of population counts or sim state, same as the
// rest of Track B.
//
// Two rounds of hand-written caustics (sine waves, then synthetic
// FastNoiseLite noise sampled twice and multiplied) both looked wrong -
// too regular, or washed-out, or tiled visibly. caustic_tile.png is the
// pure "upper" terrain tile cropped out of a PixelLab Wang tileset
// (render/water/extract_caustic_tile.gd) - genuinely seamless by
// construction, and an actual illustrated caustic pattern rather than
// statistical noise, so it's sampled once (scrolled slowly for motion)
// and thresholded by luminance, not multiplied against a second sample.
//
// Full pixel-art commitment: this node now renders inside a low-res
// SubViewport (see look_study.tscn) that gets nearest-neighbor upscaled
// to fill the window, so the tile is sampled with filter_nearest (crisp,
// no blur) and tiled at close to its native 32px pixel density instead
// of being stretched to cover the whole (much larger) window.

uniform float time_scale : hint_range(0.0, 2.0) = 0.3;
uniform sampler2D caustic_tex : source_color, repeat_enable, filter_nearest;

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

	// Caustics: a STATIC sample of the generated caustic tile, tiled at
	// close to its native 32px pixel density across the low-res canvas
	// (288x162 -> ~9x5 repeats), not stretched to fill it - that
	// stretching (and, before this pass, sampling at 1:1 canvas scale
	// against a much larger non-pixel-art window) is what caused a
	// visible tiling grid and blur in earlier attempts. No scroll: the
	// tile's content is one bold arc/wave shape rather than an evenly
	// distributed texture, so scrolling it made that shape periodically
	// sweep across the screen as a distracting pulsing line (confirmed
	// on video - see git history). Threshold by luminance so only the
	// brightest part of the illustrated pattern shows, rather than
	// blending its own water-colored background on top of ours.
	vec2 caustic_uv = uv * vec2(9.0, 5.0);
	vec3 caustic_sample = texture(caustic_tex, caustic_uv).rgb;
	float luminance = dot(caustic_sample, vec3(0.299, 0.587, 0.114));
	float caustic_strength = 1.0 - uv.y * 0.85;
	float caustics = smoothstep(0.4, 0.75, luminance) * caustic_strength;
	base = screen_blend(base, caustics * vec3(0.32, 0.5, 0.44));

	// Light shafts: a few fixed, slowly-drifting beams, spreading wider
	// with depth like real light cones do. Much dimmer than the previous
	// pass - they should be a subtle accent, not a dominant feature.
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
