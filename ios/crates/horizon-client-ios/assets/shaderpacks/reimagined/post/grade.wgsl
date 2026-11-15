// Reimagined's final pass: exposure, contrast, saturation, a filmic curve and a vignette.
// The GLSL version's film curve is ACES-fitted, which is what `aces` in common.wgsl is.

override exposure: f32 = 1.0;
override saturation: f32 = 1.05;
override contrast: f32 = 1.05;
override vignette: bool = true;

fn post(input: PostInput) -> vec4<f32> {
    var c = input.color.rgb * exposure;
    let l = luminance(c);

    // Saturation around the pixel's own luminance, then contrast around middle grey.
    c = mix(vec3<f32>(l), c, saturation);
    c = (c - vec3<f32>(0.5)) * contrast + vec3<f32>(0.5);

    // Filmic shoulder: highlights roll off instead of clipping.
    c = aces(max(c, vec3<f32>(0.0)));

    if vignette {
        let aspect = frame.resolution.x / max(frame.resolution.y, 1.0);
        let d = length((input.uv - 0.5) * vec2<f32>(aspect, 1.0)) / length(vec2<f32>(aspect, 1.0) * 0.5);
        c *= 1.0 - smoothstep(0.55, 1.2, d) * 0.28;
    }

    // A touch of dither, so a dark gradient doesn't band on an OLED phone.
    let noise = fract(sin(dot(input.pixel, vec2<f32>(12.9898, 78.233))) * 43758.5453) - 0.5;
    c += vec3<f32>(noise / 255.0);

    return vec4<f32>(clamp(c, vec3<f32>(0.0), vec3<f32>(1.0)), input.color.a);
}
