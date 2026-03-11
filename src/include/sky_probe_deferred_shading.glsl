///////////////////////////////////////////////////////////
// VERTEX SHADER
///////////////////////////////////////////////////////////
#if BGFX_SHADER_TYPE_VERTEX
#if FALLBACK_PASS
void main() {
    gl_Position = vec4_splat(0.0);
}
#else
uniform vec4 SunDir;
uniform vec4 MoonDir;
uniform vec4 DimensionID;

#include "./lib/common.glsl"
#include "./lib/atmosphere.glsl"

void main() {
    v_texcoord0 = a_texcoord0;
    v_projPos = a_position.xy * 2.0 - 1.0;

    //add smooth transition between night and sunrise, sunset and night
    float sunFade = smoothstep(0.0, 0.2, SunDir.y);
    float moonFade = smoothstep(0.0, 0.2, MoonDir.y);

    v_absorbColor = GetLightTransmittance(SunDir.xyz) * sunFade * PI * M_EXPOSURE_MUL * SUN_MAX_ILLUMINANCE;
    v_absorbColor += GetLightTransmittance(MoonDir.xyz) * moonFade * PI * M_EXPOSURE_MUL * MOON_MAX_ILLUMINANCE;
    v_scatterColor = GetAtmosphere(vec3(0.0, 1.0, 0.0), 1e10, SunDir.xyz, vec3_splat(1.0)) * SUN_MAX_ILLUMINANCE;
    v_scatterColor += GetAtmosphere(vec3(0.0, 1.0, 0.0), 1e10, MoonDir.xyz, vec3_splat(1.0)) * MOON_MAX_ILLUMINANCE;

    if (int(DimensionID.r) != 0) {
        v_absorbColor = vec3_splat(0.0);
        v_scatterColor = vec3_splat(1.0);
    }

    gl_Position = vec4(a_position.xy * 2.0 - 1.0, a_position.z, 1.0);
}
#endif
#endif





///////////////////////////////////////////////////////////
// FRAGMENT/PIXEL SHADER
///////////////////////////////////////////////////////////
#if BGFX_SHADER_TYPE_FRAGMENT
#if FALLBACK_PASS
void main() {
    gl_FragColor = vec4_splat(0.0);
}
#else

uniform highp vec4 ClampViewVectors;
uniform highp vec4 MoonDir;
uniform highp vec4 SunDir;
uniform highp vec4 DirectionalLightSourceWorldSpaceDirection;
uniform highp vec4 Time;
uniform highp vec4 WorldOrigin;
uniform highp vec4 SkyProbeUVFadeParameters;
uniform highp vec4 CurrentFace;

SAMPLER2D_HIGHP_AUTOREG(s_SceneDepth);

#include "./lib/common.glsl"
#include "./lib/atmosphere.glsl"
#include "./lib/volumetrics.glsl"

vec3 projToWorld(vec3 projPos) {
    vec4 worldPos = mul(u_invViewProj, vec4(projPos, 1.0));
    return worldPos.xyz / worldPos.w;
}

void main() {
    float depth = sampleDepth(s_SceneDepth, v_texcoord0);
    vec3 projPos = vec3(v_projPos, depth);
    vec3 worldPos = projToWorld(projPos);
    vec3 worldDir = normalize(worldPos);
    if (worldDir.y < 0.1 && ClampViewVectors.x > 0.0) worldDir = normalize(vec3(worldDir.x, 0.1, worldDir.z));

    vec3 outColor = GetAtmosphere(worldDir, 1e10, SunDir.xyz, vec3_splat(1.0)) * SUN_MAX_ILLUMINANCE;
    outColor += GetAtmosphere(worldDir, 1e10, MoonDir.xyz, vec3_splat(1.0)) * MOON_MAX_ILLUMINANCE;

    applyCirrusClouds(outColor, worldDir, DirectionalLightSourceWorldSpaceDirection.xyz, v_absorbColor, false);

#ifdef VOLUMETRIC_CLOUDS_ENABLED
    float dither = texelFetch(s_CausticsTexture, ivec3(ivec2(gl_FragCoord.xy) % 256, 1), 0).r;
    applyCumulusClouds(outColor, v_scatterColor, v_absorbColor, worldDir, 0.0, dither, false);
#endif

    applyVolumetricFog(outColor, projPos);

    if (int(CurrentFace.x) == 3) {
        outColor *= SkyProbeUVFadeParameters.z;
    } else if(int(CurrentFace.x) != 2) {
        float fadeRange = (SkyProbeUVFadeParameters.x - SkyProbeUVFadeParameters.y) + EPSILON;
        float fade = (clamp(projPos.y * 0.5 + 0.5, SkyProbeUVFadeParameters.y, SkyProbeUVFadeParameters.x) - SkyProbeUVFadeParameters.y) / fadeRange;
        outColor *= max(fade, SkyProbeUVFadeParameters.z);
    }

    gl_FragColor = vec4(outColor, 1.0);
}
#endif //!FALLBACK_PASS
#endif //BGFX_SHADER_TYPE_FRAGMENT
