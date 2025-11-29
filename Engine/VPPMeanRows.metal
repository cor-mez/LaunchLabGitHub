// File: Engine/Metal/VPPMeanRows.metal
#include <metal_stdlib>
using namespace metal;

// Computes per-row mean luminance from a single-channel Y texture.
// Assumes srcY is r8Unorm (0–1 range).
kernel void vpp_mean_rows(
    texture2d<float, access::read>  srcY      [[texture(0)]],
    device float                   *rowMeans  [[buffer(0)]],
    uint2                           gid       [[thread_position_in_grid]]
) {
    const uint width  = srcY.get_width();
    const uint height = srcY.get_height();

    // One thread per row (x == 0).
    if (gid.y >= height || gid.x != 0) {
        return;
    }

    const uint y = gid.y;
    float sum = 0.0f;

    for (uint x = 0; x < width; ++x) {
        float yVal = srcY.read(uint2(x, y)).r; // 0–1
        sum += yVal;
    }

    float mean = (width > 0) ? (sum / float(width)) : 0.0f;
    rowMeans[y] = mean;
}
