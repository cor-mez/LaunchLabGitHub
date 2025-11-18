#import "OpenCVBridge.h"
#import <opencv2/opencv.hpp>
#import "PyrLKFlow.hpp"    // you already have this
#include <vector>

using namespace std;

// ---------------------------------------------------------
// PyrLK FLOW (unchanged from your current implementation)
// ---------------------------------------------------------
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
) {
    if (!prevLuma || !currLuma || !prevPoints || !outPoints || !status || !error) return;

    cv::Mat prevGray(height, width, CV_8UC1,
                     const_cast<uint8_t *>(prevLuma), bytesPerRow);
    cv::Mat currGray(height, width, CV_8UC1,
                     const_cast<uint8_t *>(currLuma), bytesPerRow);

    vector<cv::Point2f> prevPts;
    prevPts.reserve(pointCount);
    for (int i = 0; i < pointCount; ++i)
        prevPts.emplace_back(prevPoints[2*i], prevPoints[2*i+1]);

    vector<cv::Point2f> outPts;
    vector<unsigned char> statusVec;
    vector<float> errorVec;

    launchlab::computePyrLK(prevGray, currGray, prevPts, outPts, statusVec, errorVec);
    
    int n = min(pointCount, (int)outPts.size());
    for (int i = 0; i < n; ++i) {
        outPoints[2*i+0] = outPts[i].x;
        outPoints[2*i+1] = outPts[i].y;
        status[i] = statusVec[i];
        error[i] = errorVec[i];
    }
}

// ---------------------------------------------------------
// EPnP Pose Solver (OpenCV SOLVEPNP_EPNP)
// ---------------------------------------------------------
int ll_solveEPnP(
    const float *modelPoints,
    const float *imagePoints,
    int count,
    float fx, float fy,
    float cx, float cy,
    float *R_out,
    float *T_out,
    float *error_out
) {
    if (count < 4) return 0;

    vector<cv::Point3f> obj;
    obj.reserve(count);
    for (int i = 0; i < count; i++)
        obj.emplace_back(modelPoints[i*3+0],
                         modelPoints[i*3+1],
                         modelPoints[i*3+2]);

    vector<cv::Point2f> img;
    img.reserve(count);
    for (int i = 0; i < count; i++)
        img.emplace_back(imagePoints[i*2+0],
                         imagePoints[i*2+1]);

    cv::Mat K = (cv::Mat_<double>(3,3) <<
        fx, 0,  cx,
        0,  fy, cy,
        0,  0,  1
    );

    cv::Mat dist = cv::Mat::zeros(1,5,CV_64F);
    cv::Mat rvec, tvec;

    bool ok = cv::solvePnP(
        obj,
        img,
        K,
        dist,
        rvec,
        tvec,
        false,
        cv::SOLVEPNP_EPNP
    );

    if (!ok) return 0;

    cv::Mat R;
    cv::Rodrigues(rvec, R);

    for (int r = 0; r < 3; r++)
        for (int c = 0; c < 3; c++)
            R_out[r*3 + c] = (float)R.at<double>(r,c);

    for (int i = 0; i < 3; i++)
        T_out[i] = (float)tvec.at<double>(i);

    if (error_out) *error_out = 0.0f;

    return 1;
}
