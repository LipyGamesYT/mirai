// deobfuscated from vanilla material with some modifications

///////////////////////////////////////////////////////////
// VERTEX SHADER
///////////////////////////////////////////////////////////
#if BGFX_SHADER_TYPE_VERTEX
uniform vec4 ViewportScale;
void main() {
    v_texcoord0 = a_texcoord0 * ViewportScale.xy;
    v_projPos = a_position.xy * 2.0 - 1.0;
    gl_Position = vec4(a_position.xy * 2.0 - 1.0, 0.0, 1.0);
}
#endif




///////////////////////////////////////////////////////////
// FRAGMENT/PIXEL SHADER
///////////////////////////////////////////////////////////
#if BGFX_SHADER_TYPE_FRAGMENT
uniform highp vec4 SSRRoughnessCutoffParams;
uniform highp vec4 SSRRayMarchingParams;
uniform highp vec4 SSRFadingParamsAndThickness;
uniform highp vec4 CameraData;
uniform highp vec4 ScreenSize;

SAMPLER2D_HIGHP_AUTOREG(s_GbufferDepth);
SAMPLER2D_HIGHP_AUTOREG(s_GbufferNormal);
USAMPLER2D_AUTOREG(s_GbufferRoughness);
SAMPLER2D_HIGHP_AUTOREG(s_InputTexture);
SAMPLER2D_HIGHP_AUTOREG(s_RasterColor);

#include "./lib/common.glsl"
#include "./lib/materials.glsl"

vec3 projToView(vec3 projPos) {
    vec4 viewPos = mul(u_invProj, vec4(projPos, 1.0));
    return viewPos.xyz / viewPos.w;
}

vec3 projToWorld(vec3 projPos) {
    vec4 worldPos = mul(u_invViewProj, vec4(projPos, 1.0));
    return worldPos.xyz / worldPos.w;
}

vec3 viewToProj(vec3 viewPos) {
    vec4 clipPos = mul(u_proj, vec4(viewPos, 1.0));
    vec3 ndc = clipPos.xyz / clipPos.w;
    vec2 uv = ndc.xy * 0.5 + 0.5;
#if !BGFX_SHADER_LANGUAGE_GLSL
    uv.y = 1.0 - uv.y;
#endif
    return vec3(uv, ndc.z);
}

vec2 getPreviousUV(vec3 ndc) {
    vec3 worldPos = projToWorld(ndc);
    vec4 prevClipPos = mul(u_prevViewProj, vec4(worldPos, 1.0));
    vec3 prevNdc = prevClipPos.xyz / prevClipPos.w;
    vec2 prevUV = prevNdc.xy * 0.5 + 0.5;
    return prevUV;
}

bool isDepthInCameraBounds(float depth) {
    if (CameraData.x < CameraData.y) {
        return CameraData.x < depth && depth < CameraData.y;
    } else {
        return CameraData.x > depth && depth > CameraData.y; //reverse z case
    }
}

float projToLinearDepth(float z) {
#if BGFX_SHADER_LANGUAGE_GLSL
    return CameraData.x * (z + 1.0) / (CameraData.y + CameraData.x - z * (CameraData.y - CameraData.x));
#else
    return -z / (CameraData.y - z * (CameraData.y - CameraData.x));
#endif
}

float calcFadingValue(float roughness, float rayPercentage) {
    float fadeValueRayPercentage = 1.0 - smoothstep(0.85, 1.0, rayPercentage);
    float roughnessFadeDuration = SSRRoughnessCutoffParams.x - SSRRoughnessCutoffParams.y;
    float roughnessLerpAlpha = (max(roughness, SSRRoughnessCutoffParams.y) - SSRRoughnessCutoffParams.y) / roughnessFadeDuration;
    float fadeValueRoughness = mix(1.0, 0.0, roughnessLerpAlpha);
    float fadeValue = min(fadeValueRayPercentage, fadeValueRoughness);
    return fadeValue;
}

int calcStepsCount(vec3 rayStartSS, vec3 rayStepSS) {
    vec3 stepsCountTopLeftNearCorner = rayStartSS / rayStepSS;
    vec3 stepsCountBottomRightFarCorner = (vec3_splat(1.0) - rayStartSS) / rayStepSS;

    vec3 lowestStepCounts3 = vec3(
        rayStepSS.x < 0.0 ? abs(stepsCountTopLeftNearCorner.x) : stepsCountBottomRightFarCorner.x,
        rayStepSS.y < 0.0 ? abs(stepsCountTopLeftNearCorner.y) : stepsCountBottomRightFarCorner.y,
        rayStepSS.z < 0.0 ? abs(stepsCountTopLeftNearCorner.z) : stepsCountBottomRightFarCorner.z
    );

    float minStepsCount = min(min(lowestStepCounts3.x, lowestStepCounts3.y), lowestStepCounts3.z);
    int stepsCount = int(min(minStepsCount, SSRRayMarchingParams.x));
    return stepsCount;
}

int doLinearSearch(vec3 rayStartSS, vec3 rayStepSS, int stepsCount, highp sampler2D depthBuffer, inout vec2 foundCoord) {
    int foundIter = -1;
    float prevRayDepth = projToLinearDepth(rayStartSS.z);

    LOOP
    for (int i = 1; i <= stepsCount; i++) {
        vec3 posSS = rayStartSS + rayStepSS * float(i);
        float rayLinearDepth = projToLinearDepth(posSS.z);
        float sceneDepth = sampleDepth(depthBuffer, posSS.xy);
        float sceneLinearDepth = projToLinearDepth(sceneDepth);
        if ((sceneLinearDepth <= rayLinearDepth) && (prevRayDepth <= (sceneLinearDepth + sceneLinearDepth * SSRFadingParamsAndThickness.a))) {
            foundIter = i;
            foundCoord = posSS.xy;
            break;
        }
        prevRayDepth = rayLinearDepth;
    }

    return foundIter;
}

float doBinarySearch(int foundIter, vec3 rayStartSS, vec3 rayStepSS, highp sampler2D depthBuffer, inout vec2 foundCoord) {
    float iterBeforeHit = float(foundIter - 1);
    float iterAfterHit = float(foundIter);
    float refinedIter = iterAfterHit;
    int bStepCount = int(SSRRayMarchingParams.w);

    LOOP
    for (int i = 0; i < bStepCount; i++) {
        float iterMid = (iterBeforeHit + iterAfterHit) * 0.5;
        vec3 posMid = rayStartSS + (rayStepSS * iterMid);
        float rayLinearDepth = projToLinearDepth(posMid.z);
        float sceneDepth = sampleDepth(depthBuffer, posMid.xy);
        float sceneLinearDepth = projToLinearDepth(sceneDepth);
        if (rayLinearDepth > sceneLinearDepth) {
            iterAfterHit = iterMid;
            refinedIter = iterMid;
            foundCoord = posMid.xy;
        } else {
            iterBeforeHit = iterMid;
        }
    }

    return refinedIter;
}

void main() {
#if SSR_RAY_MARCH_PASS
    vec2 stexcoord = (floor(v_texcoord0.xy * ScreenSize.xy) + 0.5) * ScreenSize.zw;

    uvec4 data16 = texelFetch(s_GbufferRoughness, ivec2(vec2(textureSize(s_GbufferRoughness, 0)) * stexcoord), 0) & 0xFFFFu;
    float roughness = float(data16.r >> 8) / 255.0;
    if (roughness > SSRRoughnessCutoffParams.x) {
        gl_FragColor = vec4_splat(0.0);
        return;
    }

    float depth = sampleDepth(s_GbufferDepth, stexcoord);
    vec3 viewPos = projToView(vec3(v_projPos, depth));
    vec3 normal = octToNdirSnorm(texture2D(s_GbufferNormal, stexcoord).rg);
    vec3 viewNormal = mul(u_view, vec4(normal, 0.0)).xyz;

    vec3 reflectedView = reflect(normalize(viewPos), viewNormal);
    vec3 rayStartView = viewPos + viewNormal * SSRRayMarchingParams.z;
    vec3 rayEndView = rayStartView + reflectedView;

    if (!isDepthInCameraBounds(rayStartView.z) || !isDepthInCameraBounds(rayEndView.z)) {
        gl_FragColor = vec4_splat(0.0);
        return;
    }

    vec3 rayStartSS = viewToProj(rayStartView);
    vec3 rayEndSS = viewToProj(rayEndView);
    vec3 raySpanSS = rayEndSS - rayStartSS;
    vec3 rayStepSS = normalize(raySpanSS) / SSRRayMarchingParams.x;

    int stepsCount = calcStepsCount(rayStartSS, rayStepSS);

    vec2 foundCoord = stexcoord;
    int foundIter = doLinearSearch(rayStartSS, rayStepSS, stepsCount, s_GbufferDepth, foundCoord);
    if (foundIter < 1) {
        gl_FragColor = vec4_splat(0.0);
        return;
    }

    float refinedIter = doBinarySearch(foundIter, rayStartSS, rayStepSS, s_GbufferDepth, foundCoord);
    float rayPercentage = refinedIter / float(stepsCount);
    float fadingValue = (foundCoord.x > 0.0 && foundCoord.x < 1.0 && foundCoord.y > 0.0 && foundCoord.y < 1.0) ? calcFadingValue(roughness, rayPercentage) : 0.0;

    gl_FragColor = vec4(foundCoord, 0.0, fadingValue);
#endif //SSR_RAY_MARCH_PASS

#if SSR_FILL_GAPS_PASS
    gl_FragColor = texture2D(s_InputTexture, v_texcoord0);
#endif

#if SSR_GET_REFLECTED_COLOR_PASS
    vec4 hitData = texture2D(s_InputTexture, v_texcoord0);
    float depth = sampleDepth(s_GbufferDepth, hitData.xy);
    vec2 prevUV = getPreviousUV(vec3(hitData.xy * 2.0 - 1.0, depth));
    gl_FragData[0] = vec4(texture2D(s_RasterColor, prevUV).rgb, hitData.a);
#endif
}

#endif //BGFX_SHADER_TYPE_FRAGMENT
