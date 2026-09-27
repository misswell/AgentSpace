/// A single full-screen triangle samples the captured BGRA texture directly.
/// Metal texture rows and fragment pixel coordinates both start at the top;
/// unlike Core Image, no vertical transform is needed between them.
enum MetalSurfaceShader {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    vertex float4 surfaceVertex(uint id [[vertex_id]]) {
        const float2 positions[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
        return float4(positions[id], 0, 1);
    }

    fragment float4 surfaceFragment(float4 pixel [[position]],
                                    texture2d<float> source [[texture(0)]],
                                    constant float4 &fitted [[buffer(0)]]) {
        float2 uv = (pixel.xy - fitted.xy) / fitted.zw;
        if (any(uv < float2(0)) || any(uv >= float2(1))) discard_fragment();
        constexpr sampler sampleFilter(coord::normalized, address::clamp_to_edge, filter::linear);
        return source.sample(sampleFilter, uv);
    }
    """
}
