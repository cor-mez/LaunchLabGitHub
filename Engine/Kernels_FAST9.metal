#include <metal_stdlib>
using namespace metal;

constant int circle_x[16] = {0,1,2,3,3,3,2,1,0,-1,-2,-3,-3,-3,-2,-1};
constant int circle_y[16] = {-3,-3,-2,-1,0,1,2,3,3,3,2,1,0,-1,-2,-3};

kernel void k_fast9_gpu(texture2d<uchar, access::read> src  [[ texture(0) ]],
                        texture2d<uchar, access::write> dst [[ texture(1) ]],
                        constant int &threshold              [[ buffer(0) ]],
                        uint2 gid [[ thread_position_in_grid ]]) {
    uint w = src.get_width();
    uint h = src.get_height();
    if (gid.x >= w || gid.y >= h) return;

    uchar c = src.read(gid).r;
    int count = 0;

    for (int i = 0; i < 16; i++) {
        int xx = int(gid.x) + circle_x[i];
        int yy = int(gid.y) + circle_y[i];
        if (xx < 0 || xx >= w || yy < 0 || yy >= h) continue;
        uchar v = src.read(uint2(xx,yy)).r;
        if (abs(int(v) - int(c)) > threshold) count++;
    }

    dst.write(uchar(count > 9 ? 255 : 0), gid);
}

kernel void k_fast9_score_gpu(texture2d<uchar, access::read> src [[ texture(0) ]],
                              texture2d<uchar, access::write> dst [[ texture(1) ]],
                              constant int &threshold              [[ buffer(0) ]],
                              uint2 gid [[ thread_position_in_grid ]]) {
    uint w = src.get_width();
    uint h = src.get_height();
    if (gid.x >= w || gid.y >= h) return;

    uchar c = src.read(gid).r;
    int score = 0;

    for (int i = 0; i < 16; i++) {
        int xx = int(gid.x) + circle_x[i];
        int yy = int(gid.y) + circle_y[i];
        if (xx < 0 || xx >= w || yy < 0 || yy >= h) continue;
        uchar v = src.read(uint2(xx,yy)).r;
        if (abs(int(v) - int(c)) > threshold) score++;
    }

    score = score > 255 ? 255 : score;
    dst.write(uchar(score), gid);
}
