// OpenCVBridge.h
// Swift-visible header (Objective-C only)

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Swift-visible C wrapper for cv::solvePnP.
bool solveEPnP(
    const float* modelPoints,     // count * 3 floats
    const float* imagePoints,     // count * 2 floats
    int count,
    float fx, float fy,
    float cx, float cy,
    float* outR,                  // 9 floats
    float* outT,                  // 3 floats
    float* outError
);

#ifdef __cplusplus
}
#endif
