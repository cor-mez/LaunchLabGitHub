#pragma once

#ifdef __OBJC__
#import <Foundation/Foundation.h>
#endif

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// ------------------------
// PyrLK Optical Flow
// ------------------------
void ll_computePyrLKFlow(
    const uint8_t *prevLuma,
    const uint8_t *currLuma,
    int width,
    int height,
    int bytesPerRow,
    const float *prevPoints,
    int pointCount,
    float *outPoints,
    uint8_t *status,
    float *error
);

// ------------------------
// EPnP Pose Solver
// ------------------------
int ll_solveEPnP(
    const float *modelPoints,
    const float *imagePoints,
    int count,
    float fx, float fy,
    float cx, float cy,
    float *R_out,
    float *T_out,
    float *error_out
);

#ifdef __cplusplus
}
#endif
