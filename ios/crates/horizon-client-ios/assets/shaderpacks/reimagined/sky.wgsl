override sky_brightness: f32 = 1.0;
override sunset_strength: f32 = 1.0;
override night_brightness: f32 = 1.0;

fn sky(input: SkyInput) -> vec4<f32> {
    let view = input.direction;
    let up = view.y;
    let sun = frame.sun_direction;
    let rain = frame.rain;
    let ir = inv_rain();

    let day = daylight();
    let low = sun_low();
    let night = night_factor();

    let sky_colour = max(input.color.rgb, vec3<f32>(0.0));
    let sky_sqrt = sqrt(sky_colour);
    let sky_m = mix(max(sky_sqrt, vec3<f32>(0.63, 0.67, 0.73) * ir), sky_sqrt, ir * ir);
    let sky_m2 = mix(max(sky_colour, vec3<f32>(0.265, 0.295, 0.35) * day), sky_colour, ir * ir);

    let noon_up = sky_m * sky_m * sky_m * vec3<f32>(0.85, 0.92, 0.81);
    let noon_middle = sky_m * vec3<f32>(1.4, 1.3, 1.3) + noon_up * 0.25;
    let noon_down = sky_m * vec3<f32>(0.9) + noon_up * 0.25;

    let sunset_up = sky_m2 * vec3<f32>(0.72, 0.522, 0.47);
    let sunset_middle = sky_m2 * vec3<f32>(1.8, 1.3, 1.2);
    let sunset_band = vec3<f32>(1.45, 0.86, 0.5) - vec3<f32>(0.8, 0.3, 0.0) * rain;
    let sunset_down = sunset_band * 0.5 + sunset_middle * 0.25;

    let day_up = mix(noon_up, sunset_up, low);
    let day_middle = mix(noon_middle, sunset_middle, low);
    let day_down = mix(noon_down, sunset_down, low);

    let night_base = 0.9 * vec3<f32>(0.07, 0.14, 0.24) * (1.0 - 0.5 * rain) + sky_colour;
    let night_up = sqrt(night_base) * 0.45 * night_brightness;
    let night_middle = sqrt(night_up) * 0.65;
    let night_down = night_middle * vec3<f32>(0.82, 0.82, 0.88);

    let up_colour = mix(night_up, day_up, day);
    let middle_colour = mix(night_middle, day_middle, day);
    let down_colour = mix(night_down, day_down, day);

    let above = max(up, 0.0);
    var blend = sq(1.0 - above);
    blend = pow(blend, (1.0 - 0.4 * sq(low)) * (1.15 - 0.15 * rain * rain));
    blend = mix(blend, 1.0, rain * rain * 0.15);
    var colour = mix(up_colour, middle_colour, blend);

    var band = sq(1.0 - abs(up));
    band = band * band * (3.0 - 2.0 * band);
    band *= (0.7 - 0.4 * night + sq(day)) * low * day * sunset_strength;
    colour = mix(colour, sunset_band, sat(band) * ir);

    var ground = sat((-up + 0.08) / 0.35);
    ground = smoothstep1(ground);
    let ground_mix = mix(vec3<f32>(ground), vec3<f32>(ground * ground, sqrt(ground), ground), 0.75 - 0.5 * rain);
    colour = mix(colour, down_colour * ground_mix, vec3<f32>(1.0) * ground);

    return vec4<f32>(colour * sky_brightness, input.color.a);
}
