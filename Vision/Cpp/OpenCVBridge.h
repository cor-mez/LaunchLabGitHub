#import <Foundation/Foundation.h>

// OpenCV Framework Headers
#import <opencv2/opencv.hpp>
#import <opencv2/calib3d.hpp>
#import <opencv2/core.hpp>
#import <opencv2/imgproc.hpp>

#ifdef __cplusplus
extern "C" {
#endif

float solveEPnP(float* modelPoints,
                float* imagePoints,
                int count,
                float* rvecOut,
                float* tvecOut);

#ifdef __cplusplus
}
#endif
