//Bilateral.metal//

#include <metal_stdlib>
using namespace metal;

// ------------------------------------------------------------
// Horizontal bilateral
// ------------------------------------------------------------
kernel void bilateral_h(
    texture2d<float, access::read>  inTex  [[texture(0)]],
    texture2d<float, access::write> outTex [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    const int w = inTex.get_width();
    const int h = inTex.get_height();

    if (gid.x >= w || gid.y >= h) return;

    constexpr float sigma_s = 1.5;   // spatial
    constexpr float sigma_r = 40.0;  // range

    float center = inTex.read(gid).r;

    float num = 0.0;
    float den = 0.0;

    // 5-tap horizontal
    for (int dx = -2; dx <= 2; dx++) {
        int xx = int(gid.x) + dx;
        if (xx < 0 || xx >= w) continue;

        float s = exp(-(dx*dx) / (2.0f * sigma_s * sigma_s));

        float neigh = inTex.read(uint2(xx, gid.y)).r;
        float diff  = neigh - center;
        float r = exp(-(diff * diff) / (2.0f * sigma_r * sigma_r));

        float wgt = s * r;
        num += neigh * wgt;
        den += wgt;
    }

    float outVal = (den > 0.0 ? num / den : center);
    outTex.write(float4(outVal), gid);
}

// ------------------------------------------------------------
// Vertical bilateral
// ------------------------------------------------------------
kernel void bilateral_v(
    texture2d<float, access::read>  inTex  [[texture(0)]],
    texture2d<float, access::write> outTex [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    const int w = inTex.get_width();
    const int h = inTex.get_height();

    if (gid.x >= w || gid.y >= h) return;

    constexpr float sigma_s = 1.5;
    constexpr float sigma_r = 40.0;

    float center = inTex.read(gid).r;

    float num = 0.0;
    float den = 0.0;

    for (int dy = -2; dy <= 2; dy++) {
        int yy = int(gid.y) + dy;
        if (yy < 0 || yy >= h) continue;

        float s = exp(-(dy*dy) / (2.0f * sigma_s * sigma_s));

        float neigh = inTex.read(uint2(gid.x, yy)).r;
        float diff  = neigh - center;
        float r = exp(-(diff * diff) / (2.0f * sigma_r * sigma_r));

        float wgt = s * r;
        num += neigh * wgt;
        den += wgt;
    }

    float outVal = (den > 0.0 ? num / den : center);
    outTex.write(float4(outVal), gid);
}
