fn luminance(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn sq(x: f32) -> f32 {
    return x * x;
}

fn sat(x: f32) -> f32 {
    return clamp(x, 0.0, 1.0);
}

fn smoothstep1(x: f32) -> f32 {
    let t = sat(x);
    return t * t * (3.0 - 2.0 * t);
}

fn daylight() -> f32 {
    return select(0.0, smoothstep(-0.12, 0.12, frame.sun_direction.y), frame.dimension == 0);
}

fn sun_low() -> f32 {
    return 1.0 - smoothstep(0.0, 0.35, abs(frame.sun_direction.y));
}

fn night_factor() -> f32 {
    return 1.0 - daylight();
}

fn inv_rain() -> f32 {
    return 1.0 - frame.rain;
}

fn aces(c: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let cc = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((c * (a * c + b)) / (c * (cc * c + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}
