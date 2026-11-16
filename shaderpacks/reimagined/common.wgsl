// Shared helpers: the pieces of Reimagined's colour code that every stage needs.
// Reimagined works in vanilla's gamma space with its own day/night factors; Horizon's
// stages are linear, so the factors stay and the colours are built here.

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

// 1 while the sun is up, fading through the horizon; 0 in the Nether and the End.
fn daylight() -> f32 {
    return select(0.0, smoothstep(-0.12, 0.12, frame.sun_direction.y), frame.dimension == 0);
}

// 1 with the sun on the horizon, 0 from a third of the way up (Reimagined's invNoonFactor).
fn sun_low() -> f32 {
    return 1.0 - smoothstep(0.0, 0.35, abs(frame.sun_direction.y));
}

fn night_factor() -> f32 {
    return 1.0 - daylight();
}

// Reimagined's rain handling: the weather greys the sky but never to black.
fn inv_rain() -> f32 {
    return 1.0 - frame.rain;
}

fn noon_factor() -> f32 {
    return sqrt(sat(frame.sun_direction.y));
}

fn inv_noon() -> f32 {
    return 1.0 - noon_factor();
}

fn sun_visibility() -> f32 {
    return smoothstep(-0.05, 0.05, frame.sun_direction.y);
}

fn daylight_color() -> vec3<f32> {
    let noon = vec3<f32>(0.65, 0.55, 0.375) * 2.05;
    let sunset = pow(vec3<f32>(0.64, 0.45, 0.3), vec3<f32>(1.5 + inv_noon())) * 5.0;
    let night = vec3<f32>(0.15, 0.14, 0.20) * (0.4 + 0.32);
    let day = mix(sunset, noon, noon_factor());
    return mix(night, day, sun_visibility());
}

fn daylight_ambient() -> vec3<f32> {
    let noon = pow(frame.sky_color.rgb, vec3<f32>(0.75)) * 0.85;
    let sunset = noon * vec3<f32>(1.21, 0.92, 0.76) * 0.95;
    let night = vec3<f32>(0.09, 0.12, 0.17) * (1.55 + 0.62);
    let day = mix(sunset, noon, noon_factor());
    return mix(night, day, sun_visibility());
}

fn rain_light() -> vec3<f32> {
    let day = vec3<f32>(0.21, 0.16, 0.13) * 0.85 + noon_factor() * vec3<f32>(0.0, 0.02, 0.06);
    let night = vec3<f32>(0.03, 0.035, 0.05) * 0.75;
    return mix(night, day, sun_visibility());
}

fn rain_ambient() -> vec3<f32> {
    let day = vec3<f32>(0.2, 0.2, 0.25) * 2.05;
    let night = vec3<f32>(0.16, 0.20, 0.3) * 1.05;
    return mix(night, day, sun_visibility());
}

fn light_color() -> vec3<f32> {
    return mix(daylight_color(), rain_light(), frame.rain);
}

fn ambient_color() -> vec3<f32> {
    return mix(daylight_ambient(), rain_ambient(), frame.rain);
}

fn block_color(tint: f32) -> vec3<f32> {
    let warm = vec3<f32>(1.0, 0.62, 0.32);
    let neutral = vec3<f32>(1.0);
    return mix(neutral, warm, sat(tint));
}

fn linear_to_rgb(c: vec3<f32>) -> vec3<f32> {
    let k = vec3<f32>(0.055);
    let curved = (vec3<f32>(1.0) + k) * pow(max(c, vec3<f32>(0.0)), vec3<f32>(1.0 / 2.4)) - k;
    let low = 12.92 * c;
    var out = curved;
    if c.r < 0.0031308 {
        out.r = low.r;
    }
    if c.g < 0.0031308 {
        out.g = low.g;
    }
    if c.b < 0.0031308 {
        out.b = low.b;
    }
    return out;
}

fn lottes(c_in: vec3<f32>, exposure: f32, contrast: f32, white_path: f32) -> vec3<f32> {
    let c = max(exposure * c_in, vec3<f32>(0.0));
    let a = vec3<f32>(contrast);
    let d = vec3<f32>(1.0);
    let hdr_max = vec3<f32>(8.0);
    let mid_in = vec3<f32>(0.25);
    let mid_out = vec3<f32>(0.25);
    let a_d = a * d;
    let hdr_max_a = pow(hdr_max, a);
    let hdr_max_ad = pow(hdr_max, a_d);
    let mid_in_a = pow(mid_in, a);
    let mid_in_ad = pow(mid_in, a_d);
    let hm1 = hdr_max_a * mid_out;
    let hm2 = hdr_max_ad - mid_in_ad;
    let b = (-mid_in_a + hm1) / (hm2 * mid_out);
    let cc = (hdr_max_ad * mid_in_a - hm1 * mid_in_ad) / (hm2 * mid_out);
    var out = pow(c, a) / (pow(c, a_d) * b + cc);

    let luminance_in = luminance(c_in);
    let lift = smoothstep(0.1, 0.0, luminance_in);
    out = mix(out, pow(max(c, vec3<f32>(0.0)), vec3<f32>(1.0 / 2.2)), lift * 0.75);

    let curve_max = 16.0;
    let shaped = pow(luminance_in / curve_max, 2.0 - white_path) * curve_max;
    out = mix(out, vec3<f32>(1.0), smoothstep(0.0, curve_max, shaped));

    let desaturate = smoothstep(0.1, 0.0, luminance_in);
    out = mix(out, vec3<f32>(luminance(out)), desaturate * 0.25);

    return clamp(out, vec3<f32>(0.0), vec3<f32>(1.0));
}
