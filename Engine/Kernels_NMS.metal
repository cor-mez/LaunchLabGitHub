// Kernels_NMS.metal
#include <metal_stdlib>
using namespace metal;

// -----------------------------------------------------------------------------
// MARK: - 3×3 Non-Maximum Suppression Kernel
// -----------------------------------------------------------------------------

kernel void k_nms_3x3(
    texture2d<float, access::read>  src [[ texture(0) ]],
    texture2d<float, access::write> dst [[ texture(1) ]],
    uint2 gid [[ thread_position_in_grid ]]
) {
    uint w = src.get_width();
    uint h = src.get_height();

    // Border pixels are discarded
    if (gid.x == 0 || gid.y == 0 ||
        gid.x >= w - 1 || gid.y >= h - 1) {
        dst.write(float4(0.0), gid);
        return;
    }

    float center = src.read(gid).r;

    // Early out: nothing to suppress
    if (center <= 0.0) {
        dst.write(float4(0.0), gid);
        return;
    }

    // Compare against 8 neighbors
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {

            if (dx == 0 && dy == 0) continue;

            float neighbor =
                src.read(uint2(gid.x + dx, gid.y + dy)).r;

            if (neighbor >= center) {
                dst.write(float4(0.0), gid);
                return;
            }
        }
    }

    // Center is strict local maximum
    dst.write(float4(center), gid);
}
