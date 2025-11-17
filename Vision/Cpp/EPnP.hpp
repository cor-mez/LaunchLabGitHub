// EPnP.hpp
// Minimal STL-only EPnP solver
#pragma once
#include <vector>
#include <array>
#include <cmath>

struct EPnPResult {
    std::array<std::array<float,3>,3> R;   // Rotation matrix
    std::array<float,3> t;                 // Translation
    float rmsError;                         // Average reprojection error
    bool success;                           // True if solution is valid
};

class EPnP {
public:
    EPnP(int n);
    
    void setIntrinsics(float fx, float fy, float cx, float cy);
    void setCorrespondences(const std::vector<std::array<float,3>>& worldPts,
                            const std::vector<std::array<float,2>>& imagePts);

    EPnPResult compute();

private:
    int nPoints;

    float fx, fy, cx, cy;

    std::vector<std::array<float,3>> pw;   // world points (X,Y,Z)
    std::vector<std::array<float,2>> pi;   // image points (u,v)

    void computeControlPoints(std::array<std::array<float,3>,4>& cws);
    void computeBarycentric(const std::array<std::array<float,3>,4>& cws,
                            std::vector<std::array<float,4>>& alphas);
    void buildM(const std::vector<std::array<float,4>>& alphas,
                std::vector<std::array<float,12>>& M);
    void computePoseFromControlPoints(const float* betas,
                                      const std::array<std::array<float,3>,4>& cws,
                                      EPnPResult& result);

    float reprojectionError(const EPnPResult& result);
};
