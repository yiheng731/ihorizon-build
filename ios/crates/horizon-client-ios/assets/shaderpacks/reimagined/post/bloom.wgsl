override bloom_strength: f32 = 0.35;
override bloom_threshold: f32 = 0.75;

fn bright(c: vec3<f32>) -> vec3<f32> {
    let l = luminance(c);
    return select(vec3<f32>(0.0), c, l > bloom_threshold);
}

fn post(input: PostInput) -> vec4<f32> {
    let size = max(frame.resolution, vec2<f32>(1.0, 1.0));
    let px = 1.0 / size;

    var glow = bright(input.color.rgb);
    var weight = 1.0;

    let near = 1.0;
    let far = 3.0;
    glow += bright(textureSampleLevel(previous, linear_sampler, input.uv + vec2<f32>( near,  0.0) * px, 0.0).rgb);
    glow += bright(textureSampleLevel(previous, linear_sampler, input.uv + vec2<f32>(-near,  0.0) * px, 0.0).rgb);
    glow += bright(textureSampleLevel(previous, linear_sampler, input.uv + vec2<f32>( 0.0,  near) * px, 0.0).rgb);
    glow += bright(textureSampleLevel(previous, linear_sampler, input.uv + vec2<f32>( 0.0, -near) * px, 0.0).rgb);
    glow += bright(textureSampleLevel(previous, linear_sampler, input.uv + vec2<f32>( far,  far) * px, 0.0).rgb);
    glow += bright(textureSampleLevel(previous, linear_sampler, input.uv + vec2<f32>(-far,  far) * px, 0.0).rgb);
    glow += bright(textureSampleLevel(previous, linear_sampler, input.uv + vec2<f32>( far, -far) * px, 0.0).rgb);
    glow += bright(textureSampleLevel(previous, linear_sampler, input.uv + vec2<f32>(-far, -far) * px, 0.0).rgb);
    weight = 9.0;

    glow = glow / weight * bloom_strength;

    let sky_lift = select(1.0, 0.35, frame.dimension == 0);
    return vec4<f32>(input.color.rgb + glow * sky_lift, input.color.a);
}
