override ambient_tint: f32 = 1.0;
override torch_warmth: f32 = 1.0;
override shadow_softness: f32 = 1.0;
override shadows: bool = true;
override water_reflections: bool = false;

fn shadow_visibility(input: MaterialInput) -> f32 {
    if frame.has_shadow == 0u || !shadows {
        return 1.0;
    }

    let clip = shadow_position(input.position + input.normal * 0.06);
    if clip.z < 0.0 || clip.z > 1.0 {
        return 1.0;
    }

    let texel = 1.0 / max(frame.shadow_resolution, 1.0);
    let radius = max(texel * shadow_softness, texel * 0.5);
    let bias = -max(frame.shadow_center_texel * 1.5, texel * 2.0);

    var visible = 0.0;
    for (var y = -1; y <= 1; y = y + 1) {
        for (var x = -1; x <= 1; x = x + 1) {
            let offset = vec2<f32>(f32(x), f32(y)) * radius;
            visible += textureSampleCompareLevel(shadow_map, shadow_sampler, clip.xy + offset, clip.z + bias);
        }
    }
    visible = visible / 9.0;

    if input.fluid == 1u {
        return mix(visible, 1.0, 0.35);
    }

    return visible;
}

fn water_mirror(input: MaterialInput) -> vec3<f32> {
    if frame.has_reflection == 0u || !water_reflections || input.fluid != 1u || input.face != 1u {
        return vec3<f32>(0.0);
    }

    let up = vec3<f32>(0.0, 1.0, 0.0);
    let view = normalize(frame.camera_position - input.position);
    let fresnel = pow(1.0 - sat(dot(view, up)), 5.0);
    let size = max(frame.reflection_resolution, vec2<f32>(1.0, 1.0));
    let sample_uv = vec2<f32>(input.screen.x, sat(input.screen.y + 0.02));
    let pixel = vec2<i32>(vec2<f32>(sample_uv.x * size.x, sample_uv.y * size.y));
    let mirrored = textureLoad(reflection, pixel, 0).rgb;
    return mirrored * (0.25 + 0.6 * fresnel);
}

fn material(input: MaterialInput) -> Surface {
    let c = input.albedo * input.tint;
    let block = sat(input.light.x);
    let sky = sat(input.light.y);
    let shadow = shadow_visibility(input);

    let sun = light_color() * sky * shadow;
    let ambient = ambient_color() * sky * mix(0.55, 1.0, shadow) * ambient_tint;
    let torch = block_color(torch_warmth) * block * mix(0.92, 1.0, shadow);

    var colour = c.rgb * (sun + ambient + torch);

    if input.emission > 0.0 {
        colour = colour + c.rgb * input.emission * 0.7;
    }

    colour = colour + c.rgb * water_mirror(input);
    colour = colour * mix(1.0, 0.72, frame.rain);

    return Surface(vec4<f32>(colour, c.a));
}
