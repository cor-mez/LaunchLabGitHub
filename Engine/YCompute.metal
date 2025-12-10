#include <metal_stdlib>
using namespace metal;

kernel void k_y_extract(
    texture2d<float, access::read>     inY        [[texture(0)]],
    texture2d<half, access::write>     outY       [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outY.get_width() || gid.y >= outY.get_height()) return;
    float v = inY.read(gid).r;
    outY.write(half(v), gid);
}

kernel void k_y_min(
    texture2d<half, access::read>  texIn   [[texture(0)]],
    texture2d<float, access::write> texOut [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x > 0 || gid.y > 0) return;
    float mn = FLT_MAX;
    uint W = texIn.get_width();
    uint H = texIn.get_height();
    for (uint y = 0; y < H; ++y) {
        for (uint x = 0; x < W; ++x) {
            float v = float(texIn.read(uint2(x,y)).r);
            mn = (v < mn ? v : mn);
        }
    }
    texOut.write(mn, uint2(0,0));
}

kernel void k_y_max(
    texture2d<half, access::read>  texIn   [[texture(0)]],
    texture2d<float, access::write> texOut [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x > 0 || gid.y > 0) return;
    float mx = -FLT_MAX;
    uint W = texIn.get_width();
    uint H = texIn.get_height();
    for (uint y = 0; y < H; ++y) {
        for (uint x = 0; x < W; ++x) {
            float v = float(texIn.read(uint2(x,y)).r);
            mx = (v > mx ? v : mx);
        }
    }
    texOut.write(mx, uint2(0,0));
}

kernel void k_y_norm(
    texture2d<half, access::read>   texIn     [[texture(0)]],
    texture2d<half, access::write>  texOut    [[texture(1)]],
    texture2d<float, access::read>  texMin    [[texture(2)]],
    texture2d<float, access::read>  texMax    [[texture(3)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= texOut.get_width() || gid.y >= texOut.get_height()) return;
    float v  = float(texIn.read(gid).r);
    float mn = texMin.read(uint2(0,0)).r;
    float mx = texMax.read(uint2(0,0)).r;
    float d  = mx - mn;
    d = (d < 1e-6f ? 1e-6f : d);
    float n = (v - mn) / d;
    n = clamp(n, 0.0f, 1.0f);
    texOut.write(half(n), gid);
}


kernel void k_y_edge(
    texture2d<half, access::read>   texIn   [[texture(0)]],
    texture2d<half, access::write>  texOut  [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint W = texIn.get_width();
    uint H = texIn.get_height();
    if (gid.x >= W || gid.y >= H) return;

    int2 p  = int2(gid);
    int2 xm = int2(max(p.x - 1, 0), p.y);
    int2 xp = int2(min(p.x + 1, int(W - 1)), p.y);
    int2 ym = int2(p.x, max(p.y - 1, 0));
    int2 yp = int2(p.x, min(p.y + 1, int(H - 1)));

    float L = float(texIn.read(uint2(xm)).r);
    float R = float(texIn.read(uint2(xp)).r);
    float U = float(texIn.read(uint2(ym)).r);
    float D = float(texIn.read(uint2(yp)).r);

    float gx = R - L;
    float gy = D - U;
    float mag = clamp(abs(gx) + abs(gy), 0.0f, 1.0f);

    texOut.write(half(mag), gid);
}

kernel void k_roi_crop_y(
    texture2d<half, access::read>  texIn    [[texture(0)]],
    texture2d<half, access::write> texOut   [[texture(1)]],
    constant uint &ox [[buffer(0)]],
    constant uint &oy [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= texOut.get_width() || gid.y >= texOut.get_height()) return;

    uint sx = gid.x + ox;
    uint sy = gid.y + oy;

    sx = min(sx, texIn.get_width()  - 1);
    sy = min(sy, texIn.get_height() - 1);

    half v = texIn.read(uint2(sx, sy)).r;
    texOut.write(v, gid);
}

kernel void k_sr_nearest_y(
    texture2d<half, access::read>  texIn    [[texture(0)]],
    texture2d<half, access::write> texOut   [[texture(1)]],
    constant float &scale [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
){
    uint sw = texOut.get_width();
    uint sh = texOut.get_height();

    if (gid.x >= sw || gid.y >= sh) return;

    float fx = float(gid.x) / scale;
    float fy = float(gid.y) / scale;

    uint sx = min((uint)fx, texIn.get_width()  - 1);
    uint sy = min((uint)fy, texIn.get_height() - 1);

    half v = texIn.read(uint2(sx, sy)).r;
    texOut.write(v, gid);
}

kernel void k_fast9_gpu(
    texture2d<half, access::read>  texIn     [[texture(0)]],
    texture2d<uint8_t, access::write> texOut [[texture(1)]],
    constant float &threshold                  [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
){
    uint W = texIn.get_width();
    uint H = texIn.get_height();
    if (gid.x >= W || gid.y >= H) return;

    int2 p = int2(gid);
    float c = float(texIn.read(uint2(p)).r);

    const int2 circleOffsets[16] = {
        int2(0,-3), int2(1,-3), int2(2,-2), int2(3,-1),
        int2(3,0),  int2(3,1),  int2(2,2),  int2(1,3),
        int2(0,3),  int2(-1,3), int2(-2,2), int2(-3,1),
        int2(-3,0), int2(-3,-1),int2(-2,-2),int2(-1,-3)
    };

    uint support = 0;
    float minArc = 9999.0f;
    float thr = threshold;

    for (uint i = 0; i < 16; i++) {
        int2 o = p + circleOffsets[i];
        o.x = clamp(o.x, 0, int(W - 1));
        o.y = clamp(o.y, 0, int(H - 1));

        float v = float(texIn.read(uint2(o)).r);
        float d = abs(v - c);
        if (d >= thr) {
            support++;
            minArc = min(minArc, d);
        }
    }

    uint8_t isCorner = (support >= 9) ? 255 : 0;
    texOut.write(isCorner, gid);
}

kernel void k_fast9_score_gpu(
    texture2d<half, access::read>     texIn     [[texture(0)]],
    texture2d<uint8_t, access::write> texScore  [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
){
    uint W = texIn.get_width();
    uint H = texIn.get_height();
    if (gid.x >= W || gid.y >= H) return;

    int2 p = int2(gid);
    float c = float(texIn.read(uint2(p)).r);

    const int2 circleOffsets[16] = {
        int2(0,-3), int2(1,-3), int2(2,-2), int2(3,-1),
        int2(3,0),  int2(3,1),  int2(2,2),  int2(1,3),
        int2(0,3),  int2(-1,3), int2(-2,2), int2(-3,1),
        int2(-3,0), int2(-3,-1),int2(-2,-2),int2(-1,-3)
    };

    float minArc = 9999.0f;

    for (uint i = 0; i < 16; i++) {
        int2 o = p + circleOffsets[i];
        o.x = clamp(o.x, 0, int(W - 1));
        o.y = clamp(o.y, 0, int(H - 1));

        float v = float(texIn.read(uint2(o)).r);
        float d = abs(v - c);
        minArc = min(minArc, d);
    }

    float score = clamp(minArc, 0.0f, 255.0f);
    texScore.write((uint8_t)score, gid);
}
