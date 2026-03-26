///////////////////////////////////////////////////////////
// VERTEX SHADER
///////////////////////////////////////////////////////////
#if BGFX_SHADER_TYPE_VERTEX
#if FALLBACK_PASS
void main() {
    gl_Position = vec4_splat(0.0);
}
#else
void main() {
    v_texcoord0 = a_texcoord0;
    v_projPos = a_position.xy * 2.0 - 1.0;
    gl_Position = vec4(a_position.xy * 2.0 - 1.0, a_position.z, 1.0);
}
#endif //!FALLBACK_PASS
#endif //BGFX_SHADER_TYPE_VERTEX




///////////////////////////////////////////////////////////
// FRAGMENT/PIXEL SHADER
///////////////////////////////////////////////////////////
#if BGFX_SHADER_TYPE_FRAGMENT
#if FALLBACK_PASS
void main() {
    gl_FragColor = vec4_splat(0.0);
}
#endif

#if DO_INDIRECT_SPECULAR_SHADING_DUAL_TARGET_PASS || DO_INDIRECT_SPECULAR_SHADING_SINGLE_TARGET_PASS
uniform highp vec4 CameraIsUnderwater;
uniform highp vec4 FogAndDistanceControl;
uniform highp vec4 RenderChunkFogAlpha;
uniform highp vec4 DimensionID;
uniform highp vec4 WorldOrigin;
uniform highp vec4 Time;

SAMPLER2D_HIGHP_AUTOREG(s_ColorMetalnessSubsurface);
USAMPLER2D_AUTOREG(s_EmissiveAmbientLinearRoughness);
SAMPLER2D_HIGHP_AUTOREG(s_Normal);
SAMPLER2D_HIGHP_AUTOREG(s_PreviousFrameAverageLuminance);
SAMPLER2D_HIGHP_AUTOREG(s_SceneDepth);
SAMPLER2DARRAY_AUTOREG(s_ScatteringBuffer);

#include "./lib/common.glsl"
#include "./lib/materials.glsl"
#include "./lib/froxel_util.glsl"
#include "./lib/clouds.glsl"
#include "./lib/ibl.glsl"

vec3 projToWorld(vec3 projPos) {
    vec4 worldPos = mul(u_invViewProj, vec4(projPos, 1.0));
    return worldPos.xyz / worldPos.w;
}

void main() {
    float depth = sampleDepth(s_SceneDepth, v_texcoord0);
    vec3 projPos = vec3(v_projPos, depth);
    vec3 worldPos = projToWorld(projPos);
    vec3 worldDir = normalize(worldPos);

    //materials data from gbuffers
    uvec4 data16 = texelFetch(s_EmissiveAmbientLinearRoughness, ivec2(gl_FragCoord.xy), 0) & 0xFFFFu;
    vec4 blightColor = vec4(data16.g >> 8, data16.g & 0xFFu, data16.b >> 8, data16.b & 0xFFu) / 255.0;
    float skyLightmap = float(data16.a & 0xFFu) / 255.0;
    float roughness = float(data16.r >> 8) / 255.0;
    vec4 data = texture2D(s_ColorMetalnessSubsurface, v_texcoord0);
    float metalness = unpackMetalness(data.a);
    vec3 albedo = toLinear(data.rgb) * 2.0;
    vec3 f0 = mix(vec3_splat(0.02), albedo, metalness);
    vec3 normal = octToNdirSnorm(texture2D(s_Normal, v_texcoord0).rg);

    bool isOverworld = int(DimensionID.r) == 0;
    bool isNeedSkyReflection = !(CameraIsUnderwater.r > 0.0) && isOverworld;

    float exposure = texture2D(s_PreviousFrameAverageLuminance, vec2_splat(0.5)).r;

    vec3 blockAmbient = blightColor.rgb * blightColor.a * 6.0;
    vec3 outColor = vec3_splat(0.0);

    if (depth < 1.0) {
        outColor = indirectSpecular(f0, worldDir, normal, blockAmbient, v_texcoord0, roughness, metalness, skyLightmap, exposure, isNeedSkyReflection);

        float wDistNorm = length(worldPos) / FogAndDistanceControl.z;
        float borderFog = saturate((wDistNorm + RenderChunkFogAlpha.x - FogAndDistanceControl.x) * FogAndDistanceControl.y);
        if (!isOverworld) outColor = outColor * saturate(1.0 - borderFog);

#ifdef VOLUMETRIC_CLOUDS_ENABLED
        float dither = texelFetch(s_CausticsTexture, ivec3(ivec2(gl_FragCoord.xy) % 256, 1), 0).r;
        CloudSetup cloudSetup = calcCloudSetup(worldDir.y, -WorldOrigin.y);
        float cloudTransmittance = calcCloudTransmittanceOnly(worldDir, wDistNorm, dither, true, cloudSetup);
        outColor *= cloudTransmittance;
#endif

        vec3 uvw = ndcToVolume(projPos);
        vec4 volumetricFog = sampleVolume(s_ScatteringBuffer, uvw);
        if (VolumeScatteringEnabledAndPointLightVolumetricsEnabled.x > 0.0) outColor *= volumetricFog.a;

        outColor = preExposeLighting(outColor.rgb, exposure);
    }

#if DO_INDIRECT_SPECULAR_SHADING_SINGLE_TARGET_PASS
    gl_FragColor = vec4(outColor, 1.0);
#else
    gl_FragData[0] = vec4(outColor, 1.0);
    gl_FragData[1] = vec4_splat(0.0);
#endif
}

#endif //DO_INDIRECT_SPECULAR_SHADING_DUAL_TARGET_PASS || DO_INDIRECT_SPECULAR_SHADING_SINGLE_TARGET_PASS

#if DO_INDIRECT_SPECULAR_UPSCALE_PASS
SAMPLER2D_HIGHP_AUTOREG(s_SpecularLighting);
SAMPLER2D_HIGHP_AUTOREG(s_SceneDepth);

void main() {
    gl_FragColor = vec4_splat(0.0);
    if (texture2D(s_SceneDepth, v_texcoord0).r < 1.0) gl_FragColor.rgb = texture2D(s_SpecularLighting, v_texcoord0).rgb;
}
#endif //DO_INDIRECT_SPECULAR_UPSCALE_PASS

#endif //BGFX_SHADER_TYPE_FRAGMENT
