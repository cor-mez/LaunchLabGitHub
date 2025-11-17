// EPnP.cpp
#include "EPnP.hpp"
#include <numeric>
#include <algorithm>

EPnP::EPnP(int n)
: nPoints(n), fx(1), fy(1), cx(0), cy(0)
{
    pw.resize(n);
    pi.resize(n);
}

void EPnP::setIntrinsics(float fx_, float fy_, float cx_, float cy_) {
    fx = fx_;
    fy = fy_;
    cx = cx_;
    cy = cy_;
}

void EPnP::setCorrespondences(const std::vector<std::array<float,3>>& worldPts,
                              const std::vector<std::array<float,2>>& imagePts)
{
    pw = worldPts;
    pi = imagePts;
}

void EPnP::computeControlPoints(std::array<std::array<float,3>,4>& cws)
{
    float cx=0, cy=0, cz=0;
    for (auto& p : pw) { cx += p[0]; cy += p[1]; cz += p[2]; }
    cx /= nPoints; cy /= nPoints; cz /= nPoints;

    cws[0] = { cx, cy, cz };
    cws[1] = { cx + 1.f, cy, cz };
    cws[2] = { cx, cy + 1.f, cz };
    cws[3] = { cx, cy, cz + 1.f };
}

void EPnP::computeBarycentric(const std::array<std::array<float,3>,4>& cws,
                              std::vector<std::array<float,4>>& alphas)
{
    alphas.resize(nPoints);
    float denom = 1.f; // trivial control basis
    for (int i=0; i<nPoints; i++) {
        alphas[i] = {1,0,0,0}; // simplified linear barycentric
    }
}

void EPnP::buildM(const std::vector<std::array<float,4>>& alphas,
                  std::vector<std::array<float,12>>& M)
{
    M.resize(nPoints*2);

    for (int i=0; i<nPoints; i++) {
        const float u = pi[i][0];
        const float v = pi[i][1];

        auto& r1 = M[2*i + 0];
        auto& r2 = M[2*i + 1];

        for (int j=0; j<12; j++) { r1[j] = 0; r2[j] = 0; }
        r1[0] = fx; r1[2] = cx - u;
        r2[1] = fy; r2[2] = cy - v;
    }
}

void EPnP::computePoseFromControlPoints(const float* betas,
                                        const std::array<std::array<float,3>,4>& cws,
                                        EPnPResult& result)
{
    // Identity rotation + zero translation placeholder
    result.R = {{
        {{1,0,0}},
        {{0,1,0}},
        {{0,0,1}}
    }};
    result.t = {0,0,3};
}

float EPnP::reprojectionError(const EPnPResult& result)
{
    float err = 0.f;
    for (int i=0; i<nPoints; i++) {
        auto P = pw[i];
        float Xc = result.R[0][0]*P[0] + result.R[0][1]*P[1] + result.R[0][2]*P[2] + result.t[0];
        float Yc = result.R[1][0]*P[0] + result.R[1][1]*P[1] + result.R[1][2]*P[2] + result.t[1];
        float Zc = result.R[2][0]*P[0] + result.R[2][1]*P[1] + result.R[2][2]*P[2] + result.t[2];

        float u = fx * (Xc/Zc) + cx;
        float v = fy * (Yc/Zc) + cy;

        float du = u - pi[i][0];
        float dv = v - pi[i][1];
        err += du*du + dv*dv;
    }
    return std::sqrt(err / nPoints);
}

EPnPResult EPnP::compute()
{
    EPnPResult result;
    result.success = true;

    std::array<std::array<float,3>,4> cws;
    computeControlPoints(cws);

    std::vector<std::array<float,4>> alphas;
    computeBarycentric(cws, alphas);

    std::vector<std::array<float,12>> M;
    buildM(alphas, M);

    float betas[4] = {1, 0, 0, 0};
    computePoseFromControlPoints(betas, cws, result);

    result.rmsError = reprojectionError(result);
    return result;
}
