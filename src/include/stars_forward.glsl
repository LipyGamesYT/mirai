///////////////////////////////////////////////////////////
// VERTEX SHADER
///////////////////////////////////////////////////////////
#if BGFX_SHADER_TYPE_VERTEX
void main() {
#if INSTANCING__ON
    vec3 worldPos = mul(mtxFromCols(i_data1, i_data2, i_data3, vec4(0.0, 0.0, 0.0, 1.0)), vec4(a_position, 1.0)).xyz;
#else
    vec3 worldPos = mul(u_model[0], vec4(a_position, 1.0)).xyz;
#endif
    vec4 clipPos = mul(u_viewProj, vec4(worldPos, 1.0));
    v_color0 = a_color0;
    v_clipPos = clipPos;
    v_worldPos = worldPos;
    gl_Position = clipPos;
}
#endif




///////////////////////////////////////////////////////////
// FRAGMENT/PIXEL SHADER
///////////////////////////////////////////////////////////
#if BGFX_SHADER_TYPE_FRAGMENT
uniform highp vec4 Time;
uniform highp vec4 WorldOrigin;
uniform highp vec4 StarsColor;
uniform highp vec4 SkyProbeUVFadeParameters;

SAMPLER2D_HIGHP_AUTOREG(s_PreviousFrameAverageLuminance);
SAMPLER2DARRAY_AUTOREG(s_ScatteringBuffer);

#include "./lib/common.glsl"
#include "./lib/atmosphere.glsl"
#include "./lib/froxel_util.glsl"
#include "./lib/clouds.glsl"

void main() {
    vec4 outColor = v_color0 * StarsColor;

#ifdef VOLUMETRIC_CLOUDS_ENABLED
    vec3 worldDir = normalize(v_worldPos);
    float dither = texelFetch(s_CausticsTexture, ivec3(ivec2(gl_FragCoord.xy) % 256, 1), 0).r;
    CloudSetup cloudSetup = calcCloudSetup(worldDir.y, -WorldOrigin.y);
    float cloudTransmittance = calcCloudTransmittanceOnly(worldDir, 0.0, dither, false, cloudSetup);
    outColor *= cloudTransmittance;
#endif

    vec3 projPos = v_clipPos.xyz / v_clipPos.w;
    vec3 uvw = ndcToVolume(projPos);
    vec4 volumetricFog = sampleVolume(s_ScatteringBuffer, uvw);
    if (VolumeScatteringEnabledAndPointLightVolumetricsEnabled.x > 0.0) outColor *= volumetricFog.a;

#if FORWARD_PBR_TRANSPARENT_PASS
    outColor.rgb = preExposeLighting(outColor.rgb, texture2D(s_PreviousFrameAverageLuminance, vec2_splat(0.5)).r);
    gl_FragColor = outColor;
#else
    gl_FragColor = vec4_splat(0.0);
#endif
}
#endif
