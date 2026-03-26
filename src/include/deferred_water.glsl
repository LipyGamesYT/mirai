#include "./lib/common.glsl"
#include "./lib/atmosphere.glsl"

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

void main() {
    v_texcoord0 = a_texcoord0;
    v_projPos = a_position.xy * 2.0 - 1.0;

    //add smooth transition between night and sunrise, sunset and night
    float sunFade = smoothstep(0.0, 0.1, SunDir.y);
    float moonFade = smoothstep(0.0, 0.1, MoonDir.y);

    v_absorbColor = GetSunTransmittance(SunDir.xyz) * sunFade * SUN_MAX_ILLUMINANCE;
    v_absorbColor += GetMoonTransmittance(MoonDir.xyz) * moonFade * MOON_MAX_ILLUMINANCE;

    AtmosphereParams sunAtmParams;
    sunAtmParams.rayStart = vec3(0.0, 10.0, 0.0);
    sunAtmParams.rayDir = vec3(0.0, 1.0, 0.0);
    sunAtmParams.lightDir = SunDir.xyz;
    sunAtmParams.rayLength = 1e10;
    sunAtmParams.aerial = 1.0;
    sunAtmParams.occlusion = 1.0;
    sunAtmParams.mieMod = 1.0;
    v_scatterColor = GetAtmosphere(sunAtmParams) * SUN_MAX_ILLUMINANCE;

    AtmosphereParams moonAtmParams;
    moonAtmParams.rayStart = vec3(0.0, 10.0, 0.0);
    moonAtmParams.rayDir = vec3(0.0, 1.0, 0.0);
    moonAtmParams.lightDir = MoonDir.xyz;
    moonAtmParams.rayLength = 1e10;
    moonAtmParams.aerial = 1.0;
    moonAtmParams.occlusion = 1.0;
    moonAtmParams.mieMod = 1.0;
    v_scatterColor += GetAtmosphere(moonAtmParams) * MOON_MAX_ILLUMINANCE;

    if (int(DimensionID.r) != 0) {
        v_absorbColor = vec3_splat(0.0);
        v_scatterColor = vec3_splat(1.0);
    }

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
#else

uniform highp vec4 DimensionID;
uniform highp vec4 FogColor;
uniform highp vec4 SunDir;
uniform highp vec4 MoonDir;
uniform highp vec4 DirectionalLightSourceWorldSpaceDirection;
uniform highp vec4 FogAndDistanceControl;
uniform highp vec4 RenderChunkFogAlpha;
uniform highp vec4 CameraIsUnderwater;
uniform highp vec4 WorldOrigin;
uniform highp vec4 Time;
uniform highp vec4 CameraLightIntensity;

SAMPLER2D_HIGHP_AUTOREG(s_Normal);
USAMPLER2D_AUTOREG(s_EmissiveAmbientLinearRoughness);
SAMPLER2D_HIGHP_AUTOREG(s_SceneDepth);
SAMPLER2D_HIGHP_AUTOREG(s_PreviousFrameAverageLuminance);

#include "./lib/materials.glsl"
#include "./lib/shadow.glsl"
#include "./lib/bsdf.glsl"
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
    vec3 position = worldPos - WorldOrigin.xyz;
    float worldDist = length(worldPos);

    vec3 normal = octToNdirSnorm(texture2D(s_Normal, v_texcoord0).rg);
    float shadowMap = calcShadowMap(worldPos, normal).r;

#ifdef VOLUMETRIC_CLOUDS_ENABLED
    CloudSetup cloudSetup = calcCloudSetup(DirectionalLightSourceWorldSpaceDirection.y, position.y);
    float cloudShadow = calcCloudShadow(position, DirectionalLightSourceWorldSpaceDirection.xyz, 2.0, cloudSetup);
    shadowMap = min(shadowMap, cloudShadow);
#endif

    vec3 brdf = BRDFSpecular(normal, DirectionalLightSourceWorldSpaceDirection.xyz, -worldDir, vec3_splat(0.5), shadowMap, 0.0);
    vec3 outColor = v_absorbColor * brdf;

    gl_FragColor.a = 0.2;

    if (int(DimensionID.r) == 0) {
        if (CameraIsUnderwater.r > 0.0) {
            outColor = exp(-WATER_EXTINCTION_COEFFICIENTS * 10.0) * luminance(v_absorbColor) * 0.01 * CameraLightIntensity.y;
            gl_FragColor.a = smoothstep(1.0, 0.0, dot(normal, refract(worldDir, -normal, 1.333)) * exp(-length(worldPos) * 0.15));
        }

#ifdef VOLUMETRIC_CLOUDS_ENABLED
        float dither = texelFetch(s_CausticsTexture, ivec3(ivec2(gl_FragCoord.xy) % 256, 1), 0).r;
        applyCumulusClouds(outColor, v_scatterColor, v_absorbColor, worldDir, worldDist, dither, true);
#endif

        applyVolumetricFog(outColor, projPos);
    } else {
        float wDistNorm = worldDist / FogAndDistanceControl.z;
        float borderFog = saturate((wDistNorm + RenderChunkFogAlpha.x - FogAndDistanceControl.x) * FogAndDistanceControl.y);
        outColor = mix(outColor, pow(FogColor.rgb, vec3_splat(2.2)), borderFog);
    }

    outColor = preExposeLighting(outColor, texture2D(s_PreviousFrameAverageLuminance, vec2_splat(0.5)).r);

    gl_FragColor.rgb = outColor;
}

#endif //!FALLBACK_PASS
#endif //BGFX_SHADER_TYPE_FRAGMENT
