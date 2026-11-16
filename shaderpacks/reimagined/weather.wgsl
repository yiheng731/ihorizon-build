override rain_darken: f32 = 1.0;

fn weather(input: WeatherInput) -> vec4<f32> {
    let darken = rain_darken;
    let light = mix(0.35, 1.0, clamp(input.light.y, 0.0, 1.0)) * mix(1.0, 0.55, darken * frame.rain);

    var colour = input.color.rgb * light;
    if input.snow {
        colour = mix(colour, colour * vec3<f32>(1.05, 1.06, 1.12), 0.5);
    } else {
        colour = colour * vec3<f32>(0.86, 0.92, 1.05);
    }
    if frame.thunder > 0.0 {
        colour = colour * (1.0 + 0.25 * frame.thunder);
    }

    return vec4<f32>(colour, input.color.a);
}
