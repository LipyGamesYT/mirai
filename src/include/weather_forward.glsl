#include "./lib/taau_util.glsl"


///////////////////////////////////////////////////////////
// VERTEX SHADER
///////////////////////////////////////////////////////////
#if BGFX_SHADER_TYPE_VERTEX
uniform vec4 Dimensions;
uniform vec4 ViewPosition;
uniform vec4 UVOffsetAndScale;
uniform vec4 Velocity;
uniform vec4 PositionBaseOffset;
uniform vec4 PositionForwardOffset;
uniform vec4 PrevPositionForwardOffset;

vec3 calcWorldPos(vec3 position) {
    vec3 p = mod(position + PositionBaseOffset.xyz, 30.0);
    p -= 15.0;
    p += PositionForwardOffset.xyz;
    return p;
}

void main() {
    vec3 worldPos = calcWorldPos(a_position);
    vec4 projPosBottom = jitterVertexPosition(worldPos);
    vec3 worldPosTop = worldPos + (Velocity.xyz * Dimensions.y);
    vec4 projPosTop = jitterVertexPosition(worldPosTop);

    vec2 projPosUpDir = (projPosTop.xy / projPosTop.w) - (projPosBottom.xy / projPosBottom.w);
    vec2 projPosRightDir = normalize(vec2(-projPosUpDir.y, projPosUpDir.x));

    v_texcoord0 = UVOffsetAndScale.xy + (a_texcoord0 * UVOffsetAndScale.zw);
#if NO_VARIETY__OFF
    v_texcoord0.x += a_color0.x * 255.0 * UVOffsetAndScale.z;
#endif
    v_occlusionUV = (worldPos.xz + ViewPosition.xz) / 64.0 + 0.5;
    v_occlusionHeight = (worldPos.y + (ViewPosition.y - 0.5)) / 255.0;
    v_worldPos = worldPos;
    v_prevWorldPos = worldPos + PrevPositionForwardOffset.xyz;

    gl_Position = mix(projPosTop, projPosBottom, a_texcoord0.y);
    gl_Position.xy += (0.5 - a_texcoord0.x) * projPosRightDir * Dimensions.x;
}

#endif //BGFX_SHADER_TYPE_VERTEX




///////////////////////////////////////////////////////////
// FRAGMENT/PIXEL SHADER
///////////////////////////////////////////////////////////
#if BGFX_SHADER_TYPE_FRAGMENT
uniform highp vec4 OcclusionHeightOffset;

SAMPLER2D_HIGHP_AUTOREG(s_LightingTexture);
SAMPLER2D_HIGHP_AUTOREG(s_OcclusionTexture);
SAMPLER2D_HIGHP_AUTOREG(s_WeatherTexture);

#if FORWARD_PBR_TRANSPARENT_PASS
#include "./lib/common.glsl"
SAMPLER2D_HIGHP_AUTOREG(s_PreviousFrameAverageLuminance);
#endif

bool isOccluded(vec2 occlusionUV, float occlusionHeight, float occlusionHeightThreshold) {
#if NO_OCCLUSION__ON
    return false;
#else
    bool occlusionUv = occlusionUV.x >= 0.0 && occlusionUV.x <= 1.0 && occlusionUV.y >= 0.0 && occlusionUV.y <= 1.0;
#if FLIP_OCCLUSION__ON
    return (occlusionUv && occlusionHeight > occlusionHeightThreshold);
#else
    return (occlusionUv && occlusionHeight < occlusionHeightThreshold);
#endif
#endif
}

vec2 calculateOcclusionAndLightingUV(vec2 occlusionUV, float occlusionHeight) {
    vec4 o = texture2D(s_OcclusionTexture, occlusionUV);
    float occlusionLuminance = o.r;
    float occlusionHeightThreshold = o.g + (o.b * 255.0) - (OcclusionHeightOffset.x / 255.0);
    float fade = saturate(occlusionLuminance - ((occlusionHeight - occlusionHeightThreshold) * 25.0) * occlusionLuminance);
#if NO_OCCLUSION__OFF
    if (isOccluded(occlusionUV, occlusionHeight, occlusionHeightThreshold)) return vec2_splat(0.0);
#endif
    return vec2(fade, 1.0);
}

void main() {
    vec4 albedo = texture2D(s_WeatherTexture, v_texcoord0);

#if FORWARD_PBR_TRANSPARENT_PASS
    vec2 lighting = calculateOcclusionAndLightingUV(v_occlusionUV, v_occlusionHeight);
    albedo.rgb = pow(albedo.rgb, vec3_splat(2.2));

    vec3 outColor = albedo.rgb * 0.01;
    outColor = preExposeLighting(outColor, texture2D(s_PreviousFrameAverageLuminance, vec2_splat(0.5)).r);

    gl_FragColor = vec4(outColor, albedo.a * lighting.g);

#elif MOTION_ONLY_PASS
    if (albedo.a < 0.5) discard;

    vec4 o = texture2D(s_OcclusionTexture, v_occlusionUV);
    float occlusionHeightThreshold = o.g + o.b * 255.0 - OcclusionHeightOffset.x / 255.0;
    bool inside = v_occlusionUV.x >= 0.0 && v_occlusionUV.x <= 1.0 && v_occlusionUV.y >= 0.0 && v_occlusionUV.y <= 1.0;
    if (inside && v_occlusionHeight > occlusionHeightThreshold) discard;

    vec2 motionVec = (distance(v_worldPos, v_prevWorldPos - u_prevWorldPosOffset.xyz) > 27.0) ? calculateMotionVector(v_worldPos, v_worldPos) : calculateMotionVector(v_worldPos, v_prevWorldPos - u_prevWorldPosOffset.xyz);
    gl_FragData[0] = vec4(1.0, 1.0, motionVec);
#else

    gl_FragColor = vec4_splat(0.0);
#endif
}

#endif //BGFX_SHADER_TYPE_FRAGMENT
