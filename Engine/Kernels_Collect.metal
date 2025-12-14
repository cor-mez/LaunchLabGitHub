// Kernels_Collect.metal
#include <metal_stdlib>
using namespace metal;

// -----------------------------------------------------------------------------
// MARK: - Output Struct
// -----------------------------------------------------------------------------

struct CornerOut {
    ushort x;
    ushort y;
    ushort score;   // scaled [0–65535]
};

// -----------------------------------------------------------------------------
// MARK: - Atomic Counter
// -----------------------------------------------------------------------------

struct Counter {
    atomic_uint count;
};

// -----------------------------------------------------------------------------
// MARK: - Collect NMS Peaks Kernel
// -----------------------------------------------------------------------------

kernel void k_collect_corners(
    texture2d<float, access::read> src      [[ texture(0) ]],
    device CornerOut*              outBuf   [[ buffer(0) ]],
    device Counter*                counter  [[ buffer(1) ]],
    uint2 gid [[ thread_position_in_grid ]]
) {
    uint w = src.get_width();
    uint h = src.get_height();

    if (gid.x >= w || gid.y >= h) return;

    float v = src.read(gid).r;
    if (v <= 0.0) return;

    uint idx = atomic_fetch_add_explicit(
        &counter->count,
        1,
        memory_order_relaxed
    );

    outBuf[idx] = CornerOut{
        ushort(gid.x),
        ushort(gid.y),
        ushort(clamp(v, 0.0, 1.0) * 65535.0)
    };
}
