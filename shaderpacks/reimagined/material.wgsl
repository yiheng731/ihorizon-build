// Reimagined lights a block as `albedo * tint * lightmap`, with the sky light cooled and the
// block light warmed before they meet. This stage does the same, in Horizon's linear space.

override ambient_tint: f32 = 1.0;
override torch_warmth: f32 = 1.0;

fn material(input: MaterialInput) -> Surface {
    let c = input.albedo * input.tint;

    // Vanilla's light for this point, split back into the two lights that made it.
    let block = sat(input.light.x);
    let sky = sat(input.light.y);
    let vanilla_light = max(input.lightmap, vec3<f32>(0.0));

    // Light from the sky leans blue in a shadow and neutral in the open, the way
    // Reimagined's ambient does; torch light leans orange.
    let cool = mix(vec3<f32>(1.0), vec3<f32>(0.82, 0.93, 1.12), ambient_tint * (1.0 - block));
    let warm = mix(vec3<f32>(1.0), vec3<f32>(1.14, 0.86, 0.62), torch_warmth * block);
    let lit = vanilla_light * cool * warm;

    return Surface(vec4<f32>(c.rgb * lit, c.a));
}
