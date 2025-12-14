// -----------------------------------------------------------------------------
// Kernels_FAST9.metal
// Reference-correct FAST-9 binary corner detector + score kernel
// -----------------------------------------------------------------------------

#include <metal_stdlib>
using namespace metal;

// -----------------------------------------------------------------------------
// FAST-9 circle offsets (radius = 3 pixels)
// -----------------------------------------------------------------------------

constant int2 FAST9_OFFSETS[16] = {
    int2( 0, -3), int2( 1, -3), int2( 2, -2), int2( 3, -1),
    int2( 3,  0), int2( 3,  1), int2( 2,  2), int2( 1,  3),
    int2( 0,  3), int2(-1,  3), int2(-2,  2), int2(-3,  1),
    int2(-3,  0), int2(-3, -1), int2(-2, -2), int2(-1, -3)
};

// -----------------------------------------------------------------------------
// MARK: - FAST-9 Binary Detection Kernel
// -----------------------------------------------------------------------------

kernel void k_fast9_gpu(
    texture2d<float, access::read>  src [[ texture(0) ]],
    texture2d<float, access::write> dst [[ texture(1) ]],
    constant int& threshold              [[ buffer(0) ]],
    uint2 gid [[ thread_position_in_grid ]]
) {
    uint w = src.get_width();
    uint h = src.get_height();
    if (gid.x >= w || gid.y >= h) return;

    int2 p = int2(gid);

    // ✅ convert to uint2 at read site
    float center = src.read(uint2(p)).r * 255.0;

    int brightRun = 0;
    int darkRun   = 0;

    for (int i = 0; i < 16; i++) {

        int2 q = p + FAST9_OFFSETS[i];

        // bounds check in int space
        if (q.x < 0 || q.y < 0 || q.x >= int(w) || q.y >= int(h)) {
            brightRun = 0;
            darkRun   = 0;
            continue;
        }

        // ✅ convert to uint2 only here
        float v = src.read(uint2(q)).r * 255.0;

        if (v > center + threshold) {
            brightRun++;
            darkRun = 0;
        }
        else if (v < center - threshold) {
            darkRun++;
            brightRun = 0;
        }
        else {
            brightRun = 0;
            darkRun   = 0;
        }

        if (brightRun >= 9 || darkRun >= 9) {
            dst.write(float4(1.0), gid);
            return;
        }
    }

    dst.write(float4(0.0), gid);
}

// -----------------------------------------------------------------------------
// MARK: - FAST-9 Score Kernel
// -----------------------------------------------------------------------------

kernel void k_fast9_score_gpu(
    texture2d<float, access::read>  src [[ texture(0) ]],
    texture2d<float, access::write> dst [[ texture(1) ]],
    constant int& threshold              [[ buffer(0) ]],
    uint2 gid [[ thread_position_in_grid ]]
) {
    uint w = src.get_width();
    uint h = src.get_height();
    if (gid.x >= w || gid.y >= h) return;

    int2 p = int2(gid);
    float center = src.read(uint2(p)).r * 255.0;

    int support = 0;

    for (int i = 0; i < 16; i++) {

        int2 q = p + FAST9_OFFSETS[i];
        if (q.x < 0 || q.y < 0 || q.x >= int(w) || q.y >= int(h))
            continue;

        float v = src.read(uint2(q)).r * 255.0;

        if (abs(v - center) > threshold)
            support++;
    }

    float score = clamp(float(support) / 16.0, 0.0, 1.0);
    dst.write(float4(score), gid);
}
