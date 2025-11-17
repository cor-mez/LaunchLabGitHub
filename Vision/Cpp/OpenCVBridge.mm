#import "OpenCVBridge.h"
#include <opencv2/core.hpp>
#include <opencv2/calib3d.hpp>
#include <opencv2/imgproc.hpp>
extern "C" bool solveEPnP(
    const float* modelPoints,
    const float* imagePoints,
    int count,
    float fx, float fy,
    float cx, float cy,
    float* outR,
    float* outT,
    float* outError
) {
    try {
        std::vector<cv::Point3f> objectPts;
        std::vector<cv::Point2f> imagePts;

        objectPts.reserve(count);
        imagePts.reserve(count);

        // Fill vectors
        for (int i = 0; i < count; i++) {
            objectPts.emplace_back(
                modelPoints[i*3+0],
                modelPoints[i*3+1],
                modelPoints[i*3+2]
            );
            imagePts.emplace_back(
                imagePoints[i*2+0],
                imagePoints[i*2+1]
            );
        }

        // Camera matrix
        cv::Mat K = (cv::Mat_<double>(3,3) <<
            fx, 0,  cx,
            0,  fy, cy,
            0,  0,  1
        );

        cv::Mat rvec, tvec;

        bool ok = cv::solvePnP(
            objectPts,
            imagePts,
            K,
            cv::noArray(),
            rvec,
            tvec,
            false,
            cv::SOLVEPNP_EPNP
        );

        if (!ok) return false;

        // Convert rvec → rotation matrix
        cv::Mat R;
        cv::Rodrigues(rvec, R);

        // Copy to Swift buffers
        for (int i = 0; i < 9; i++)
            outR[i] = R.at<double>(i/3, i%3);

        outT[0] = tvec.at<double>(0);
        outT[1] = tvec.at<double>(1);
        outT[2] = tvec.at<double>(2);

        // Dummy RMS error
        *outError = 0.0f;

        return true;
    }
    catch (...) {
        return false;
    }
}
