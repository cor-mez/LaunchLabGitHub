#include "PyrLKFlow.hpp"
#include <opencv2/opencv.hpp>

namespace launchlab {

void computePyrLK(
    const cv::Mat& prevGray,
    const cv::Mat& currGray,
    const std::vector<cv::Point2f>& prevPoints,
    std::vector<cv::Point2f>& outPoints,
    std::vector<unsigned char>& status,
    std::vector<float>& error
) {
    if (prevPoints.empty()) {
        outPoints.clear();
        status.clear();
        error.clear();
        return;
    }

    outPoints = prevPoints;
    status.assign(prevPoints.size(), 0);
    error.assign(prevPoints.size(), 0.0f);

    const cv::Size winSize(21, 21);
    const int maxLevel = 3;
    const cv::TermCriteria termcrit(
        cv::TermCriteria::COUNT | cv::TermCriteria::EPS,
        30,
        0.01
    );

    cv::calcOpticalFlowPyrLK(
        prevGray,
        currGray,
        prevPoints,
        outPoints,
        status,
        error,
        winSize,
        maxLevel,
        termcrit,
        0,
        1e-4
    );
}

} // namespace launchlab
