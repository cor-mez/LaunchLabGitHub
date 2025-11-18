#pragma once

// Use umbrella include for OpenCV 4.x on macOS/iOS
#include <opencv2/opencv.hpp>

namespace launchlab {

void computePyrLK(
    const cv::Mat& prevGray,
    const cv::Mat& currGray,
    const std::vector<cv::Point2f>& prevPoints,
    std::vector<cv::Point2f>& outPoints,
    std::vector<unsigned char>& status,
    std::vector<float>& error
);

} // namespace launchlab
