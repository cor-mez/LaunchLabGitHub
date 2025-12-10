#include <metal_stdlib>
using namespace metal;

struct VSOut {
    float4 position [[position]];
    float2 uv;
};

struct OVS {
    float4 position [[position]];
};

vertex VSOut vtx_main(
    uint vid [[vertex_id]],
    const device float4 *quad [[buffer(0)]]
) {
    VSOut o;
    float4 v = quad[vid];
    o.position = float4(v.x, v.y, 0.0, 1.0);
    o.uv = float2(v.z, v.w);
    return o;
}

fragment float4 frag_y(
    VSOut in [[stage_in]],
    texture2d<float> yTex [[texture(0)]],
    sampler s [[sampler(0)]]
) {
    float y = yTex.sample(s, in.uv).r;
    return float4(y, y, y, 1.0);
}

fragment float4 frag_cb(
    VSOut in [[stage_in]],
    texture2d<float> cbTex [[texture(0)]],
    sampler s [[sampler(0)]]
) {
    float c = cbTex.sample(s, in.uv).r;
    return float4(c, c, c, 1.0);
}

fragment float4 frag_norm(
    VSOut in [[stage_in]],
    texture2d<float> t [[texture(0)]],
    sampler s [[sampler(0)]]
) {
    float v = t.sample(s, in.uv).r;
    return float4(v, v, v, 1.0);
}

vertex OVS vtx_overlay(
    uint vid [[vertex_id]],
    const device float2 *pts [[buffer(0)]]
) {
    OVS o;
    float2 p = pts[vid];
    o.position = float4(p.x, p.y, 0.0, 1.0);
    return o;
}

fragment float4 frag_overlay(OVS in [[stage_in]]) {
    return float4(1.0, 1.0, 0.0, 1.0);
}

kernel void k_cb_extract(
    texture2d<float, access::read> uvTex [[texture(0)]],
    texture2d<float, access::write> cbTex [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint w = cbTex.get_width();
    uint h = cbTex.get_height();
    if (gid.x >= w || gid.y >= h) return;
    if (gid.x >= uvTex.get_width() || gid.y >= uvTex.get_height()) return;
    float4 uv = uvTex.read(gid);
    float c = uv.r;
    cbTex.write(float4(c, c, c, 1.0), gid);
}

kernel void k_cb_min(
    texture2d<float, access::read> src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    uint tid [[thread_index_in_threadgroup]]
) {
    threadgroup float tile[256];
    uint w = src.get_width();
    uint h = src.get_height();
    uint total = w * h;
    float v = 1.0;
    uint idx = tid;
    uint step = 256;
    for (uint i = idx; i < total; i += step) {
        uint x = i % w;
        uint y = i / w;
        float p = src.read(uint2(x, y)).r;
        v = min(v, p);
    }
    tile[tid] = v;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint s = 128; s > 0; s >>= 1) {
        if (tid < s) {
            tile[tid] = min(tile[tid], tile[tid + s]);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if (tid == 0) {
        float m = tile[0];
        dst.write(float4(m, m, m, 1.0), uint2(0,0));
    }
}

kernel void k_cb_max(
    texture2d<float, access::read> src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    uint tid [[thread_index_in_threadgroup]]
) {
    threadgroup float tile[256];
    uint w = src.get_width();
    uint h = src.get_height();
    uint total = w * h;
    float v = 0.0;
    uint idx = tid;
    uint step = 256;
    for (uint i = idx; i < total; i += step) {
        uint x = i % w;
        uint y = i / w;
        float p = src.read(uint2(x, y)).r;
        v = max(v, p);
    }
    tile[tid] = v;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint s = 128; s > 0; s >>= 1) {
        if (tid < s) {
            tile[tid] = max(tile[tid], tile[tid + s]);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if (tid == 0) {
        float m = tile[0];
        dst.write(float4(m, m, m, 1.0), uint2(0,0));
    }
}

kernel void k_cb_norm(
    texture2d<float, access::read> src [[texture(0)]],
    texture2d<float, access::read> mnTex [[texture(1)]],
    texture2d<float, access::read> mxTex [[texture(2)]],
    texture2d<float, access::write> dst [[texture(3)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint w = dst.get_width();
    uint h = dst.get_height();
    if (gid.x >= w || gid.y >= h) return;
    float minv = mnTex.read(uint2(0,0)).r;
    float maxv = mxTex.read(uint2(0,0)).r;
    float v = src.read(uint2(gid.x, gid.y)).r;
    float nv = (maxv > minv) ? ((v - minv) / (maxv - minv)) : 0.0;
    nv = clamp(nv, 0.0, 1.0);
    dst.write(float4(nv, nv, nv, 1.0), gid);
}

kernel void k_chroma_edge(
    texture2d<float, access::read> src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint w = src.get_width();
    uint h = src.get_height();
    if (gid.x >= w || gid.y >= h) return;
    float c = src.read(gid).r;
    float l = src.read(uint2(max(int(gid.x) - 1, 0), gid.y)).r;
    float r = src.read(uint2(min(gid.x + 1, w - 1), gid.y)).r;
    float u = src.read(uint2(gid.x, max(int(gid.y) - 1, 0))).r;
    float d = src.read(uint2(gid.x, min(gid.y + 1, h - 1))).r;
    float gx = r - l;
    float gy = d - u;
    float e = clamp(abs(gx) + abs(gy), 0.0, 1.0);
    dst.write(float4(e, e, e, 1.0), gid);
}

kernel void k_y_min(
    texture2d<float, access::read> src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    uint tid [[thread_index_in_threadgroup]]
) {
    threadgroup float tile[256];
    uint w = src.get_width();
    uint h = src.get_height();
    uint total = w * h;
    float v = 1.0;
    uint idx = tid;
    uint step = 256;
    for (uint i = idx; i < total; i += step) {
        uint x = i % w;
        uint y = i / w;
        float p = src.read(uint2(x, y)).r;
        v = min(v, p);
    }
    tile[tid] = v;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint s = 128; s > 0; s >>= 1) {
        if (tid < s) {
            tile[tid] = min(tile[tid], tile[tid + s]);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if (tid == 0) {
        float m = tile[0];
        dst.write(float4(m, m, m, 1.0), uint2(0,0));
    }
}

kernel void k_y_max(
    texture2d<float, access::read> src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    uint tid [[thread_index_in_threadgroup]]
) {
    threadgroup float tile[256];
    uint w = src.get_width();
    uint h = src.get_height();
    uint total = w * h;
    float v = 0.0;
    uint idx = tid;
    uint step = 256;
    for (uint i = idx; i < total; i += step) {
        uint x = i % w;
        uint y = i / w;
        float p = src.read(uint2(x, y)).r;
        v = max(v, p);
    }
    tile[tid] = v;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint s = 128; s > 0; s >>= 1) {
        if (tid < s) {
            tile[tid] = max(tile[tid], tile[tid + s]);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if (tid == 0) {
        float m = tile[0];
        dst.write(float4(m, m, m, 1.0), uint2(0,0));
    }
}

kernel void k_y_norm(
    texture2d<float, access::read> src [[texture(0)]],
    texture2d<float, access::read> mnTex [[texture(1)]],
    texture2d<float, access::read> mxTex [[texture(2)]],
    texture2d<float, access::write> dst [[texture(3)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint w = dst.get_width();
    uint h = dst.get_height();
    if (gid.x >= w || gid.y >= h) return;
    float minv = mnTex.read(uint2(0,0)).r;
    float maxv = mxTex.read(uint2(0,0)).r;
    float v = src.read(uint2(gid.x, gid.y)).r;
    float nv = (maxv > minv) ? ((v - minv) / (maxv - minv)) : 0.0;
    nv = clamp(nv, 0.0, 1.0);
    dst.write(float4(nv, nv, nv, 1.0), gid);
}

kernel void k_y_edge(
    texture2d<float, access::read> src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint w = src.get_width();
    uint h = src.get_height();
    if (gid.x >= w || gid.y >= h) return;
    float c = src.read(gid).r;
    float l = src.read(uint2(max(int(gid.x) - 1, 0), gid.y)).r;
    float r = src.read(uint2(min(gid.x + 1, w - 1), gid.y)).r;
    float u = src.read(uint2(gid.x, max(int(gid.y) - 1, 0))).r;
    float d = src.read(uint2(gid.x, min(gid.y + 1, h - 1))).r;
    float gx = r - l;
    float gy = d - u;
    float e = clamp(abs(gx) + abs(gy), 0.0, 1.0);
    dst.write(float4(e, e, e, 1.0), gid);
}

kernel void k_roi_crop(
    texture2d<float, access::read> src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    constant float4 &roi [[buffer(0)]],
    constant float &zoom [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint w = dst.get_width();
    uint h = dst.get_height();
    if (gid.x >= w || gid.y >= h) return;
    float sx = roi.x + (float(gid.x) / zoom);
    float sy = roi.y + (float(gid.y) / zoom);
    sx = clamp(sx, 0.0, float(src.get_width() - 1));
    sy = clamp(sy, 0.0, float(src.get_height() - 1));
    float v = src.read(uint2(uint(sx), uint(sy))).r;
    dst.write(float4(v, v, v, 1.0), gid);
}

kernel void k_fast9_gpu(
    texture2d<float, access::read> src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    constant int &thrFast [[buffer(0)]],
    constant int &thrLocal [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint w = src.get_width();
    uint h = src.get_height();
    if (gid.x >= w || gid.y >= h) return;
    if (gid.x < 3 || gid.x + 3 >= w || gid.y < 3 || gid.y + 3 >= h) {
        dst.write(float4(0.0, 0.0, 0.0, 1.0), gid);
        return;
    }
    float c = src.read(gid).r;

    float up = src.read(uint2(gid.x, gid.y - 1)).r;
    float down = src.read(uint2(gid.x, gid.y + 1)).r;
    float left = src.read(uint2(gid.x - 1, gid.y)).r;
    float right = src.read(uint2(gid.x + 1, gid.y)).r;

    float maxDiff = max(max(abs(up - c), abs(down - c)), max(abs(left - c), abs(right - c)));
    if (maxDiff < float(thrLocal)) {
        dst.write(float4(0.0, 0.0, 0.0, 1.0), gid);
        return;
    }

    int2 circleOffsets[16] = {
        int2( 0,-3), int2( 1,-3), int2( 2,-2), int2( 3,-1),
        int2( 3, 0), int2( 3, 1), int2( 2, 2), int2( 1, 3),
        int2( 0, 3), int2(-1, 3), int2(-2, 2), int2(-3, 1),
        int2(-3, 0), int2(-3,-1), int2(-2,-2), int2(-1,-3)
    };

    int brighter = 0;
    int darker = 0;
    float minOnArc = 1e6;

    for (int i = 0; i < 16; ++i) {
        int2 o = circleOffsets[i];
        uint2 p = uint2(int(gid.x) + o.x, int(gid.y) + o.y);
        float v = src.read(p).r;
        float d = v - c;
        float isBright = d >= float(thrFast) ? 1.0 : 0.0;
        float isDark = d <= -float(thrFast) ? 1.0 : 0.0;
        brighter += int(isBright);
        darker += int(isDark);
        float mag = abs(d);
        float used = (isBright + isDark) > 0.0 ? 1.0 : 0.0;
        minOnArc = used > 0.0 ? min(minOnArc, mag) : minOnArc;
    }

    int support = max(brighter, darker);
    float score = (minOnArc < 1e6) ? minOnArc : 0.0;
    float scoreMin = float(thrFast) * 0.8;

    if (support >= 9 && score >= scoreMin) {
        dst.write(float4(1.0, 1.0, 1.0, 1.0), gid);
    } else {
        dst.write(float4(0.0, 0.0, 0.0, 1.0), gid);
    }
}
