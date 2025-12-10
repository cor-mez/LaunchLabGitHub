#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float4 data;   // x, y, u, v
};

struct VSOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VSOut cbview_vertex(
    uint vid [[vertex_id]],
    const device float4 *quad [[buffer(0)]]
) {
    VSOut out;

    float4 v = quad[vid];

    // Clip-space position
    out.position = float4(v.x, v.y, 0.0, 1.0);

    // Texture coordinates
    out.texCoord = float2(v.z, v.w);

    return out;
}

fragment float4 cbview_fragment(
    VSOut in [[stage_in]],
    texture2d<float> tex [[texture(0)]],
    sampler samp [[sampler(0)]]
) {
    // Texture may be nil or invalid during transitions — avoid GPU stalls
    if (tex.get_width() == 0 || tex.get_height() == 0) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    // Sample grayscale from r8Unorm → float
    float g = tex.sample(samp, in.texCoord).r;

    // Return as grayscale RGBA
    return float4(g, g, g, 1.0);
}
