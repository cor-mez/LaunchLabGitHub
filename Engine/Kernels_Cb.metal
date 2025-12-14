#include <metal_stdlib>
using namespace metal;

kernel void k_cb_extract(texture2d<float, access::read> src    [[ texture(0) ]],
                         texture2d<float, access::write> dst   [[ texture(1) ]],
                         uint2 gid [[ thread_position_in_grid ]]) {

    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;

    float v = src.read(gid).r;
    dst.write(float4(v), gid);
}

kernel void k_cb_min(texture2d<float, access::read> src [[ texture(0) ]],
                     texture2d<float, access::write> out [[ texture(1) ]],
                     uint2 gid [[thread_position_in_grid]]) {

    if (gid.x != 0 || gid.y != 0) return;

    float m = 1.0;
    uint w = src.get_width();
    uint h = src.get_height();

    for (uint y = 0; y < h; y++) {
        for (uint x = 0; x < w; x++) {
            float v = src.read(uint2(x,y)).r;
            m = v < m ? v : m;
        }
    }

    out.write(float4(m), uint2(0,0));
}

kernel void k_cb_max(texture2d<float, access::read> src [[ texture(0) ]],
                     texture2d<float, access::write> out [[ texture(1) ]],
                     uint2 gid [[thread_position_in_grid]]) {

    if (gid.x != 0 || gid.y != 0) return;

    float m = 0.0;
    uint w = src.get_width();
    uint h = src.get_height();

    for (uint y = 0; y < h; y++) {
        for (uint x = 0; x < w; x++) {
            float v = src.read(uint2(x,y)).r;
            m = v > m ? v : m;
        }
    }

    out.write(float4(m), uint2(0,0));
}

kernel void k_cb_norm(texture2d<float, access::read> src [[ texture(0) ]],
                      texture2d<float, access::write> dst [[ texture(1) ]],
                      texture2d<float, access::read> minT [[ texture(2) ]],
                      texture2d<float, access::read> maxT [[ texture(3) ]],
                      uint2 gid [[ thread_position_in_grid ]]) {

    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;

    float mn = minT.read(uint2(0,0)).r;
    float mx = maxT.read(uint2(0,0)).r;
    float r = mx - mn;

    float v = src.read(gid).r;
    float nv = (r > 0.0) ? (v - mn) / r : 0.0;
    nv = clamp(nv, 0.0, 1.0);

    dst.write(float4(nv), gid);
}

kernel void k_cb_edge(texture2d<float, access::read> src [[ texture(0) ]],
                      texture2d<float, access::write> dst [[ texture(1) ]],
                      uint2 gid [[ thread_position_in_grid ]]) {

    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;

    int2 p = int2(gid);
    int w = dst.get_width();
    int h = dst.get_height();

    int sx = 0;
    int sy = 0;

    int gx[3][3] = { {-1,0,1}, {-2,0,2}, {-1,0,1} };
    int gy[3][3] = { {-1,-2,-1}, {0,0,0}, {1,2,1} };

    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {

            int xx = clamp(p.x + i, 0, w-1);
            int yy = clamp(p.y + j, 0, h-1);

            float v = src.read(uint2(xx,yy)).r * 255.0;

            sx += gx[j+1][i+1] * int(v);
            sy += gy[j+1][i+1] * int(v);
        }
    }

    int mag = abs(sx) + abs(sy);
    mag = mag > 255 ? 255 : mag;

    dst.write(float4(float(mag) / 255.0), gid);
}

kernel void k_roi_crop_cb(texture2d<float, access::read> src [[ texture(0) ]],
                          texture2d<float, access::write> dst [[ texture(1) ]],
                          constant uint32_t &ox [[ buffer(0) ]],
                          constant uint32_t &oy [[ buffer(1) ]],
                          uint2 gid [[ thread_position_in_grid ]]) {

    uint w = dst.get_width();
    uint h = dst.get_height();
    if (gid.x >= w || gid.y >= h) return;

    uint sx = gid.x + ox;
    uint sy = gid.y + oy;

    float v = src.read(uint2(sx,sy)).r;

    dst.write(float4(v), gid);
}

kernel void k_sr_nearest_cb(texture2d<float, access::read> src [[ texture(0) ]],
                            texture2d<float, access::write> dst [[ texture(1) ]],
                            constant float &scale [[ buffer(0) ]],
                            uint2 gid [[ thread_position_in_grid ]]) {

    uint w = dst.get_width();
    uint h = dst.get_height();
    if (gid.x >= w || gid.y >= h) return;

    uint sx = uint(float(gid.x) / scale);
    uint sy = uint(float(gid.y) / scale);

    sx = min(sx, src.get_width()  - 1);
    sy = min(sy, src.get_height() - 1);

    float v = src.read(uint2(sx,sy)).r;

    dst.write(float4(v), gid);
}
