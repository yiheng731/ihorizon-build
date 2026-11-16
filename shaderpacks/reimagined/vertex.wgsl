override waving_plants: f32 = 1.0;

fn vertex(input: VertexInput) -> vec3<f32> {
    let amplitude = waving_plants;
    if amplitude <= 0.0 || input.material == 0u {
        return input.position;
    }

    let world = input.position + frame.camera_position;
    let phase = world.x * 0.7 + world.z * 0.9 + world.y * 0.35;
    let t = frame.time * 1.9;
    let sway = sin(t + phase) + 0.45 * sin(t * 2.3 + phase * 1.7);

    var strength = 0.0;
    var lift = 0.0;
    if input.material == 1u {
        strength = 0.045;
        lift = 0.012;
    } else if input.material == 2u {
        strength = 0.115;
        lift = 0.035;
    }

    strength = strength * amplitude;
    lift = lift * amplitude;

    let gust = 0.55 + 0.45 * sin(frame.time * 0.31 + world.x * 0.05);
    let offset = vec3<f32>(sway * strength * gust, lift * (0.5 + 0.5 * sin(t + phase)), sway * strength * 0.4);

    return input.position + offset;
}
