#include <metal_stdlib>
using namespace metal;

// -----------------------------------------------------------------------------
// Vertex output
// -----------------------------------------------------------------------------
struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// -----------------------------------------------------------------------------
// Fullscreen triangle vertex
// -----------------------------------------------------------------------------
vertex VertexOut passthroughVertex(uint vid [[vertex_id]]) {

    float2 pos[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };

    float2 uv[3] = {
        float2(0.0, 0.0),
        float2(2.0, 0.0),
        float2(0.0, 2.0)
    };

    VertexOut out;
    out.position = float4(pos[vid], 0.0, 1.0);
    out.texCoord = uv[vid];
    return out;
}

// -----------------------------------------------------------------------------
// RAW CAMERA PREVIEW FRAGMENT (VERTICAL FLIP FIX)
// -----------------------------------------------------------------------------
fragment float4 passthroughFragment(
    VertexOut in [[stage_in]],
    texture2d<float> tex [[texture(0)]],
    sampler s [[sampler(0)]]
) {
    // 🔧 FIX: flip Y
    float2 uv = clamp(float2(in.texCoord.x, 1.0 - in.texCoord.y), 0.0, 1.0);

    float y = tex.sample(s, uv).r;
    return float4(y, y, y, 1.0);
}
