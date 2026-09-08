shader_type canvas_item;

// Pixel-palette swap for the dude sprite set.
// Targets are raw sRGB values (0..1) set from enemy.gd as Vector3 values.
uniform vec3 skin_target = vec3(0.858824, 0.600000, 0.470588);
uniform vec3 top_target = vec3(0.227451, 0.305882, 0.262745);
uniform vec3 pants_target = vec3(0.580392, 0.517647, 0.392157);
uniform float palette_strength : hint_range(0.0, 1.0) = 1.0;

const float MATCH_EPSILON = 0.012;

const vec3 SKIN_ANCHOR = vec3(0.858824, 0.600000, 0.470588); // 219,153,120
const vec3 TOP_ANCHOR = vec3(0.227451, 0.305882, 0.262745);  // 58,78,67
const vec3 PANTS_ANCHOR = vec3(0.580392, 0.517647, 0.392157); // 148,132,100

// Capture AnimatedSprite2D modulate/self_modulate before the default canvas
// fragment stage combines COLOR with the texture. This keeps hit flash intact.
varying vec4 sprite_tint;

void vertex() {
	sprite_tint = COLOR;
}

vec3 srgb_to_linear(vec3 c) {
	vec3 low = c / 12.92;
	vec3 high = pow((c + vec3(0.055)) / 1.055, vec3(2.4));
	return mix(low, high, step(vec3(0.04045), c));
}

vec3 linear_to_srgb(vec3 c) {
	c = max(c, vec3(0.0));
	vec3 low = c * 12.92;
	vec3 high = 1.055 * pow(c, vec3(1.0 / 2.4)) - vec3(0.055);
	return mix(low, high, step(vec3(0.0031308), c));
}

vec3 rgb_to_hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

bool palette_match(vec3 sampled, vec3 source_srgb) {
	float srgb_distance = distance(sampled, source_srgb);
	float linear_distance = distance(sampled, srgb_to_linear(source_srgb));
	return min(srgb_distance, linear_distance) <= MATCH_EPSILON;
}

bool sample_is_linear_for(vec3 sampled, vec3 source_srgb) {
	return distance(sampled, srgb_to_linear(source_srgb)) < distance(sampled, source_srgb);
}

vec3 recolor_from_match(
	vec3 sampled,
	vec3 matched_source,
	vec3 source_anchor,
	vec3 target_srgb
) {
	bool linear_sample = sample_is_linear_for(sampled, matched_source);

	// "source_color" is reserved by Godot, so use base_color instead.
	vec3 base_color = sampled;

	if (linear_sample) {
		base_color = linear_to_srgb(sampled);
	}

	vec3 source_hsv = rgb_to_hsv(base_color);
	vec3 anchor_hsv = rgb_to_hsv(source_anchor);
	vec3 target_hsv = rgb_to_hsv(target_srgb);

	// Preserve the original per-pixel light/dark relationships while
	// shifting the ramp toward the requested target palette.
	float sat_ratio = target_hsv.y / max(anchor_hsv.y, 0.06);
	float value_ratio = target_hsv.z / max(anchor_hsv.z, 0.06);

	vec3 shifted_hsv = vec3(
		target_hsv.x,
		clamp(source_hsv.y * sat_ratio, 0.0, 1.0),
		clamp(source_hsv.z * value_ratio, 0.0, 1.0)
	);

	vec3 recolored_srgb = hsv_to_rgb(shifted_hsv);
	vec3 recolored = recolored_srgb;

	if (linear_sample) {
		recolored = srgb_to_linear(recolored_srgb);
	}

	return mix(sampled, recolored, palette_strength);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec3 c = tex.rgb;
	vec3 out_color = c;

	// Skin ramp used by face/hands. Dark hair/outline colors are intentionally
	// excluded so changing skin tone does not erase facial definition.
	if (palette_match(c, vec3(0.858824, 0.600000, 0.470588))) {
		out_color = recolor_from_match(c, vec3(0.858824, 0.600000, 0.470588), SKIN_ANCHOR, skin_target);
	} else if (palette_match(c, vec3(0.768627, 0.556863, 0.443137))) {
		out_color = recolor_from_match(c, vec3(0.768627, 0.556863, 0.443137), SKIN_ANCHOR, skin_target);
	} else if (palette_match(c, vec3(0.678431, 0.462745, 0.384314))) {
		out_color = recolor_from_match(c, vec3(0.678431, 0.462745, 0.384314), SKIN_ANCHOR, skin_target);
	} else if (palette_match(c, vec3(0.549020, 0.384314, 0.298039))) {
		out_color = recolor_from_match(c, vec3(0.549020, 0.384314, 0.298039), SKIN_ANCHOR, skin_target);
	} else if (palette_match(c, vec3(0.447059, 0.301961, 0.250980))) {
		out_color = recolor_from_match(c, vec3(0.447059, 0.301961, 0.250980), SKIN_ANCHOR, skin_target);
	} else if (palette_match(c, vec3(0.513725, 0.309804, 0.274510))) {
		out_color = recolor_from_match(c, vec3(0.513725, 0.309804, 0.274510), SKIN_ANCHOR, skin_target);

	// Shirt/jacket/hat cool ramp.
	} else if (palette_match(c, vec3(0.227451, 0.305882, 0.262745))) {
		out_color = recolor_from_match(c, vec3(0.227451, 0.305882, 0.262745), TOP_ANCHOR, top_target);
	} else if (palette_match(c, vec3(0.156863, 0.203922, 0.211765))) {
		out_color = recolor_from_match(c, vec3(0.156863, 0.203922, 0.211765), TOP_ANCHOR, top_target);
	} else if (palette_match(c, vec3(0.396078, 0.423529, 0.384314))) {
		out_color = recolor_from_match(c, vec3(0.396078, 0.423529, 0.384314), TOP_ANCHOR, top_target);
	} else if (palette_match(c, vec3(0.333333, 0.380392, 0.352941))) {
		out_color = recolor_from_match(c, vec3(0.333333, 0.380392, 0.352941), TOP_ANCHOR, top_target);
	} else if (palette_match(c, vec3(0.290196, 0.337255, 0.333333))) {
		out_color = recolor_from_match(c, vec3(0.290196, 0.337255, 0.333333), TOP_ANCHOR, top_target);
	} else if (palette_match(c, vec3(0.152941, 0.172549, 0.196078))) {
		out_color = recolor_from_match(c, vec3(0.152941, 0.172549, 0.196078), TOP_ANCHOR, top_target);

	// Trouser/khaki warm ramp.
	} else if (palette_match(c, vec3(0.580392, 0.517647, 0.392157))) {
		out_color = recolor_from_match(c, vec3(0.580392, 0.517647, 0.392157), PANTS_ANCHOR, pants_target);
	} else if (palette_match(c, vec3(0.650980, 0.549020, 0.396078))) {
		out_color = recolor_from_match(c, vec3(0.650980, 0.549020, 0.396078), PANTS_ANCHOR, pants_target);
	} else if (palette_match(c, vec3(0.513725, 0.431373, 0.329412))) {
		out_color = recolor_from_match(c, vec3(0.513725, 0.431373, 0.329412), PANTS_ANCHOR, pants_target);
	} else if (palette_match(c, vec3(0.458824, 0.380392, 0.294118))) {
		out_color = recolor_from_match(c, vec3(0.458824, 0.380392, 0.294118), PANTS_ANCHOR, pants_target);
	} else if (palette_match(c, vec3(0.388235, 0.321569, 0.250980))) {
		out_color = recolor_from_match(c, vec3(0.388235, 0.321569, 0.250980), PANTS_ANCHOR, pants_target);
	} else if (palette_match(c, vec3(0.317647, 0.266667, 0.211765))) {
		out_color = recolor_from_match(c, vec3(0.317647, 0.266667, 0.211765), PANTS_ANCHOR, pants_target);
	} else if (palette_match(c, vec3(0.364706, 0.392157, 0.270588))) {
		out_color = recolor_from_match(c, vec3(0.364706, 0.392157, 0.270588), PANTS_ANCHOR, pants_target);
	}

	// Preserve AnimatedSprite2D self_modulate/modulate. This keeps the existing
	// red damage flash working on top of the palette swap.
	COLOR = vec4(out_color, tex.a) * sprite_tint;
}
