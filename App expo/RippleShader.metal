#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

[[ stitchable ]]
half4 ripple(
    float2 position,
    SwiftUI::Layer layer,
    float2 origin,
    float time,
    float amplitude,
    float frequency,
    float decay,
    float speed
) {
    // The distance of the current pixel position from `origin`.
    float distance = length(position - origin);

    // The amount of time it takes for the ripple to arrive at the current pixel position.
    float delay = distance / speed;

    // Adjust for delay, clamp to 0.
    time -= delay;
    time = max(0.0, time);

    // The ripple is a sine wave scaled by an exponential decay function.
    float rippleAmount = amplitude * sin(frequency * time) * exp(-decay * time);

    // A vector of length `rippleAmount` that points away from origin.
    float2 n = normalize(position - origin);

    // Scale `n` by the ripple amount and add it to the current pixel position.
    float2 newPosition = position + rippleAmount * n;

    // Sample the layer at the new position.
    half4 color = layer.sample(newPosition);

    // Lighten or darken the color based on the ripple amount and its alpha component.
    color.rgb += 0.3 * (rippleAmount / amplitude) * color.a;

    return color;
}

// MARK: - Apple Books Style Page Curl Shader (PREVIOUS VERSION - COMMENTED OUT)
// Uncomment this and comment the new version below to revert

/*
[[ stitchable ]]
half4 pageCurl_v1(
    float2 position,
    SwiftUI::Layer layer,
    float2 size,
    float progress,
    float curlRadius,
    float2 cornerOrigin
) {
    if (progress < 0.001) {
        return layer.sample(position);
    }

    float2 uv = position / size;
    float cylPos = 1.0 - progress;
    float curledWidth = 1.0 - cylPos;
    float coverageEnd = max(0.0, 2.0 * cylPos - 1.0);

    // REGION 1: Right of cylinder - paper has lifted away
    if (uv.x > cylPos) {
        return half4(0, 0, 0, 0);
    }

    // REGION 2: Covered by curled paper
    if (uv.x >= coverageEnd) {
        float d = cylPos - uv.x;
        float cylinderRadius = curlRadius * 3.5;
        float distIntoCurl = d;
        float halfCircumference = M_PI_F * cylinderRadius;
        float originalX;
        float3 lighting = float3(1.0);

        if (distIntoCurl < halfCircumference) {
            // ON THE CYLINDER - create strong depth effect
            float theta = (distIntoCurl / cylinderRadius);
            theta = min(theta, M_PI_F);
            float arcLength = theta * cylinderRadius;
            originalX = cylPos + arcLength;

            // Strong 3D Cylinder lighting
            float normalX = sin(theta);
            float normalZ = cos(theta);
            float3 lightDir = normalize(float3(0.6, 0.4, 0.8));
            float3 normal = float3(normalX, 0.0, normalZ);
            float diffuse = max(0.0, dot(normal, lightDir));
            float shade = 0.25 + 0.75 * diffuse;

            float3 viewDir = float3(0.0, 0.0, 1.0);
            float3 halfVec = normalize(lightDir + viewDir);
            float spec = pow(max(0.0, dot(normal, halfVec)), 24.0);

            float innerShadow = 1.0;
            if (theta > M_PI_F * 0.5) {
                innerShadow = 1.0 - (theta - M_PI_F * 0.5) / (M_PI_F * 0.5) * 0.4;
            }
            lighting = float3(shade * innerShadow) + float3(spec * 0.6);
        } else {
            // FLAT FOLDED PART
            float pastCylinder = distIntoCurl - halfCircumference;
            originalX = cylPos + halfCircumference + pastCylinder;
            float shadowFade = exp(-pastCylinder * 2.0);
            lighting = float3(0.5 + 0.2 * shadowFade);
        }

        originalX = clamp(originalX, 0.0, 1.0);
        float2 samplePos = float2(originalX * size.x, position.y);
        half4 color = layer.sample(samplePos);
        color.rgb *= half3(lighting);
        return color;
    }

    // REGION 3: Original flat content
    return layer.sample(position);
}
*/

// MARK: - Angled Cylinder Page Curl (PREVIOUS VERSION v2 - COMMENTED OUT)
/*
[[ stitchable ]]
half4 pageCurl_v2(
    float2 position,
    SwiftUI::Layer layer,
    float2 size,
    float progress,
    float curlRadius,
    float2 dragStart,
    float2 dragCurrent
) {
    if (progress < 0.001) {
        return layer.sample(position);
    }

    float2 uv = position / size;
    float2 dragDir = dragStart - dragCurrent;
    float dragLen = length(dragDir);

    if (dragLen < 0.001) {
        dragDir = float2(1.0, 0.0);
    } else {
        dragDir = normalize(dragDir);
    }

    float2 curlAxis = float2(-dragDir.y, dragDir.x);
    float cylDistance = 1.0 - progress;
    float2 cylCenter = dragStart - dragDir * (1.0 - cylDistance);
    float2 toPixel = uv - cylCenter;
    float d = dot(toPixel, dragDir);

    float cylinderRadius = curlRadius * 3.5;
    float halfCircumference = M_PI_F * cylinderRadius;

    if (d > 0.0) {
        return half4(0, 0, 0, 0);
    }

    float distIntoCurl = -d;
    float axisPos = dot(toPixel, curlAxis);
    float3 lighting = float3(1.0);
    float2 sampleUV;

    if (distIntoCurl < halfCircumference) {
        float theta = distIntoCurl / cylinderRadius;
        theta = min(theta, M_PI_F);
        float unrolledDist = theta * cylinderRadius;
        float2 sampleOffset = dragDir * unrolledDist;
        sampleUV = cylCenter + curlAxis * axisPos + sampleOffset;

        float normalAlongDrag = sin(theta);
        float normalZ = cos(theta);
        float3 lightDir = normalize(float3(0.6, 0.4, 0.8));
        float3 normal = float3(normalAlongDrag * dragDir.x, normalAlongDrag * dragDir.y, normalZ);
        float diffuse = max(0.0, dot(normal, lightDir));
        float shade = 0.25 + 0.75 * diffuse;

        float3 viewDir = float3(0.0, 0.0, 1.0);
        float3 halfVec = normalize(lightDir + viewDir);
        float spec = pow(max(0.0, dot(normal, halfVec)), 24.0);

        float innerShadow = 1.0;
        if (theta > M_PI_F * 0.5) {
            innerShadow = 1.0 - (theta - M_PI_F * 0.5) / (M_PI_F * 0.5) * 0.4;
        }
        lighting = float3(shade * innerShadow) + float3(spec * 0.6);
    } else {
        float pastCylinder = distIntoCurl - halfCircumference;
        float totalDist = halfCircumference + pastCylinder;
        float2 sampleOffset = dragDir * totalDist;
        sampleUV = cylCenter + curlAxis * axisPos + sampleOffset;
        float shadowFade = exp(-pastCylinder * 2.0);
        lighting = float3(0.5 + 0.2 * shadowFade);
    }

    sampleUV = clamp(sampleUV, float2(0.0), float2(1.0));
    float2 samplePos = sampleUV * size;
    half4 color = layer.sample(samplePos);
    color.rgb *= half3(lighting);
    return color;
}
*/

// MARK: - Page Curl Shader
// Each pixel's signed distance d from the fold line determines its zone:
//   d > R        → paper peeled away (transparent)
//   0 <= d <= R  → on the cylinder surface
//   d < 0        → flat side (check if folded-back paper covers it)
// Sampling is relative to uv (the pixel itself) to preserve the perpendicular component.

[[ stitchable ]]
half4 pageCurl(
    float2 position,
    SwiftUI::Layer layer,
    float2 size,
    float progress,
    float curlRadius,
    float2 dragStart,      // Where drag started (normalized 0-1)
    float2 dragCurrent     // Current drag position (normalized 0-1)
) {
    if (progress < 0.001) {
        return layer.sample(position);
    }

    float2 uv = position / size;
    float R = curlRadius * 0.35;  // Tight cylinder radius

    // Fold direction
    float2 dir = dragStart - dragCurrent;
    if (length(dir) < 0.001) {
        dir = float2(1.0, 0.0);
    } else {
        dir = normalize(dir);
    }

    // Find origin on the edge of the page (trace from dragStart along +dir to boundary)
    float tX = (dir.x > 0.001) ? (1.0 - dragStart.x) / dir.x :
               (dir.x < -0.001) ? -dragStart.x / dir.x : 1000.0;
    float tY = (dir.y > 0.001) ? (1.0 - dragStart.y) / dir.y :
               (dir.y < -0.001) ? -dragStart.y / dir.y : 1000.0;
    float t = min(abs(tX), abs(tY));
    if (t > 100.0) t = 0.0;
    float2 origin = clamp(dragStart + dir * t, float2(0.0), float2(1.0));

    // Distance from origin to opposite edge (trace from origin along -dir to boundary)
    float sX = 1000.0, sY = 1000.0;
    if (dir.x > 0.001) sX = origin.x / dir.x;
    else if (dir.x < -0.001) sX = (origin.x - 1.0) / dir.x;
    if (dir.y > 0.001) sY = origin.y / dir.y;
    else if (dir.y < -0.001) sY = (origin.y - 1.0) / dir.y;
    float maxTravel = max(0.5, min(sX, sY));

    // Fold line position
    float foldTravel = progress * maxTravel;
    float2 foldCenter = origin - dir * foldTravel;

    // Signed distance from fold line along dir
    // positive = toward origin (paper being folded), negative = flat side
    float d = dot(uv - foldCenter, dir);

    // === ZONE: Paper peeled away (d > R) ===
    if (d > R) {
        return half4(0, 0, 0, 0);
    }

    // === ZONE: On the cylinder (0 <= d <= R) ===
    if (d >= 0.0) {
        float theta = asin(clamp(d / R, 0.0, 1.0));

        // Back surface (paper wrapping over the top of the cylinder)
        float backArc = (M_PI_F - theta) * R;
        float2 backUV = uv + dir * (backArc - d);
        bool backValid = (backUV.x >= 0.0 && backUV.x <= 1.0 &&
                          backUV.y >= 0.0 && backUV.y <= 1.0);

        if (backValid) {
            half4 color = layer.sample(clamp(backUV, float2(0.0), float2(1.0)) * size);
            // Smooth gradient: 0.75 at top of cylinder (d=R) → 0.85 at fold line (d=0)
            float cylT = theta / (M_PI_F / 2.0);  // 0 at fold line, 1 at top
            float shade = mix(0.85, 0.75, cylT);
            color.rgb *= half3(shade);
            return color;
        }

        // Front surface
        float frontArc = theta * R;
        float2 frontUV = uv + dir * (frontArc - d);
        // If sample UV is out of bounds, show nothing instead of clamping
        // (clamping samples the gold border, creating a bright ray)
        if (frontUV.x < 0.0 || frontUV.x > 1.0 || frontUV.y < 0.0 || frontUV.y > 1.0) {
            return half4(0, 0, 0, 0);
        }
        half4 color = layer.sample(frontUV * size);
        // Smooth gradient: 0.85 at fold line (theta=0) → 0.6 at top (theta=π/2)
        // Matches flat shadow at the fold boundary
        float cylFrontT = theta / (M_PI_F / 2.0);  // 0 at fold line, 1 at top
        float shade = mix(0.85, 0.6, cylFrontT);
        color.rgb *= half3(shade);
        return color;
    }

    // === ZONE: Flat side (d < 0) ===
    // Folded-back paper follows a second, larger cylinder (radius R2)
    // using asin mapping (like the main cylinder) for real visible curving.
    // Screen distance = R2 * sin(theta2), so content foreshortens at the edge.
    float R2 = R * mix(5.0, 1.5, progress);  // Gentle at start, tight curl as user drags more
    float behindDist = -d;  // positive screen distance behind fold line

    // Only visible if screen distance < R2 (paper has curled away past that)
    if (behindDist < R2) {
        // Inverse: screen height = R2 * sin(theta2), so theta2 = asin(behindDist / R2)
        float theta2 = asin(clamp(behindDist / R2, 0.0, 1.0));

        // Arc length on original paper = theta2 * R2 (NOT equal to behindDist)
        float arcLen2 = theta2 * R2;
        float origDist = M_PI_F * R + arcLen2;

        // Fold line point for this pixel = uv - dir * d = uv + dir * behindDist
        float2 foldPoint = uv + dir * behindDist;
        float2 backUV = foldPoint + dir * origDist;

        bool backCovers = (backUV.x >= 0.0 && backUV.x <= 1.0 &&
                           backUV.y >= 0.0 && backUV.y <= 1.0);

        if (backCovers) {
            half4 color = layer.sample(backUV * size);
            // Smooth darkness: 0.85 at fold line → 0.75 as it curls deeper
            float curlT = theta2 / (M_PI_F / 2.0);  // 0 at fold, 1 at max visible
            float shadow = mix(0.85, 0.75, curlT);
            color.rgb *= half3(shadow);
            return color;
        }
    }

    // Original flat content with shadow near fold line
    // Smoothly fades from 0.85 (15% dark, matching cylinder front at fold) to 1.0
    half4 flat = layer.sample(position);
    if (d > -0.08) {
        float shadowT = exp(d * 20.0);
        float shade = mix(1.0, 0.85, shadowT);
        flat.rgb *= half3(shade);
    }
    return flat;
}
