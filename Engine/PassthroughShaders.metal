// PassthroughShaders.metal
#include <metal_stdlib>
using namespace metal;

// -----------------------------------------------------------------------------
// MARK: - Vertex Types
// -----------------------------------------------------------------------------

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// -----------------------------------------------------------------------------
// MARK: - Fullscreen Triangle Vertex
// -----------------------------------------------------------------------------

vertex VertexOut passthroughVertex(uint vid [[vertex_id]]) {

    float2 pos[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };

    float2 uv[3] = {
        float2(0.0, 0.0),
        float2(2.0, 0.0),
        float2(0.0, 2.0)
    };

    VertexOut out;
    out.position = float4(pos[vid], 0.0, 1.0);
    out.texCoord = uv[vid];
    return out;
}

// -----------------------------------------------------------------------------
// MARK: - Fragment Uniforms
// -----------------------------------------------------------------------------

struct PreviewUniforms {
    uint  debugMode = 2; // 0 = raw, 1 = thresh, 2 = edge, 3 = mask
    float threshold;   // normalized [0–1]
};

// -----------------------------------------------------------------------------
// MARK: - Passthrough / Diagnostic Fragment
// -----------------------------------------------------------------------------

fragment float4 passthroughFragment(
    VertexOut in [[stage_in]],
    texture2d<float> tex [[texture(0)]],
    sampler s [[sampler(0)]],
    constant PreviewUniforms& u [[buffer(0)]]
) {
    // Flip Y for camera coordinate space
    float2 uv = float2(in.texCoord.x, 1.0 - in.texCoord.y);

    // Sample luminance
    float y = tex.sample(s, uv).r;

    switch (u.debugMode) {

        // ---------------------------------------------------------------------
        // 0 — Raw luminance
        // ---------------------------------------------------------------------
        case 0:
            return float4(y, y, y, 1.0);

        // ---------------------------------------------------------------------
        // 1 — Hard threshold
        // ---------------------------------------------------------------------
        case 1: {
            float v = y > u.threshold ? 1.0 : 0.0;
            return float4(v, v, v, 1.0);
        }

        // ---------------------------------------------------------------------
        // 2 — Edge magnitude (derivative-based)
        // ---------------------------------------------------------------------
        case 2: {
            float dx = abs(dfdx(y));
            float dy = abs(dfdy(y));

            float edge = dx + dy;

            // Binary edge mask
            float v = edge > u.threshold ? .05 : 0.0;

            return float4(v, v, v, 1.0);
        }

        // ---------------------------------------------------------------------
        // 3 — Soft binary mask
        // ---------------------------------------------------------------------
        case 3: {
            float v = smoothstep(
                u.threshold - 0.05,
                u.threshold + 0.05,
                y
            );
            return float4(v, v, v, 1.0);
        }
        case 4: {
            float dx = abs(dfdx(y));
            float dy = abs(dfdy(y));
            float edge = dx + dy;

            // Binary edge
            float e = edge > u.threshold ? 1 : 0.0;

            // Penalize long continuous edges
            float ex = abs(dfdx(e));
            float ey = abs(dfdy(e));

            float localVar = ex + ey;

            // Dot-like regions have higher local variance
            float v = localVar > 0.01 ? 1.0 : 0.0;

            return float4(v, v, v, 1.0);
        }
        // ---------------------------------------------------------------------
        // Error state
        // ---------------------------------------------------------------------
        default:
            return float4(1.0, 0.0, 1.0, 1.0); // magenta = invalid mode
    }
}
