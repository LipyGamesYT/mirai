#include "./lib/common.glsl"


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

#if CAUSTICS_MULTIPLIER_PASS
void main() {
    gl_FragData[0] = vec4(0.0, 0.0, 0.0, 1.0);
}
#endif

#if DIRECTIONAL_LIGHTING_PASS
uniform highp vec4 DirectionalLightSourceWorldSpaceDirection;
uniform highp vec4 Time;
uniform highp vec4 WorldOrigin;

SAMPLER2D_HIGHP_AUTOREG(s_ColorMetalnessSubsurface);
SAMPLER2D_HIGHP_AUTOREG(s_Normal);
USAMPLER2D_AUTOREG(s_EmissiveAmbientLinearRoughness);
SAMPLER2D_HIGHP_AUTOREG(s_SceneDepth);
SAMPLER2D_HIGHP_AUTOREG(s_CausticsMultiplier);

#include "./lib/materials.glsl"
#include "./lib/shadow.glsl"
#include "./lib/bsdf.glsl"
#include "./lib/water_wave.glsl"
#include "./lib/clouds.glsl"

vec3 projToWorld(vec3 projPos) {
    vec4 worldPos = mul(u_invViewProj, vec4(projPos, 1.0));
    return worldPos.xyz / worldPos.w;
}

void main() {
    gl_FragData[0] = vec4_splat(0.0);

    //somthing happen here
    float waterBodyMask = texture2D(s_CausticsMultiplier, v_texcoord0).r;
    gl_FragData[1] = vec4(waterBodyMask, 0.0, 0.0, 1.0);

    float depth = sampleDepth(s_SceneDepth, v_texcoord0);
    vec3 worldPos = projToWorld(vec3(v_projPos, depth));
    vec3 worldDir = normalize(worldPos);
    vec3 position = worldPos - WorldOrigin.xyz;

    //materials data from gbuffers
    uvec4 data16 = texelFetch(s_EmissiveAmbientLinearRoughness, ivec2(gl_FragCoord.xy), 0) & 0xFFFFu;
    float roughness = float(data16.r >> 8) / 255.0;
    vec4 data = texture2D(s_ColorMetalnessSubsurface, v_texcoord0);
    float metalness = unpackMetalness(data.a);
    float subsurface = unpackSubsurface(data.a);
    vec3 albedo = pow(data.rgb, vec3_splat(2.2)) * 2.0;
    vec3 f0 = mix(vec3_splat(0.02), albedo, metalness);
    vec3 normal = octToNdirSnorm(texture2D(s_Normal, v_texcoord0).rg);

    vec3 shadowMap = calcShadowMap(worldPos, normal).rgr;
    if (shadowMap.r > 0.9) subsurface = 0.0;

#ifdef VOLUMETRIC_CLOUDS_ENABLED
    CloudSetup cloudSetup = calcCloudSetup(DirectionalLightSourceWorldSpaceDirection.y, position.y);
    float cloudShadow = calcCloudShadow(position, DirectionalLightSourceWorldSpaceDirection.xyz, 2.0, cloudSetup);
    shadowMap.rg = min(shadowMap.rg, vec2_splat(cloudShadow * CLOUD_SHADOW_CONTRIBUTION + (1.0 - CLOUD_SHADOW_CONTRIBUTION)));
    shadowMap.b = min(shadowMap.b, cloudShadow); //used for specular
#endif

    if (waterBodyMask < 1.0) {
        float caustic = calcCaustic(position, DirectionalLightSourceWorldSpaceDirection.xyz, Time.x);
        shadowMap = shadowMap * (0.5 + caustic * 1.5);
    }

    vec3 bsdf = BSDF(normal, DirectionalLightSourceWorldSpaceDirection.xyz, -worldDir, f0, albedo, shadowMap, metalness, roughness, subsurface);
    if (depth < 1.0) gl_FragData[0].rgb = v_absorbColor * bsdf;
}

#endif //DIRECTIONAL_LIGHTING_PASS


#if DISCRETE_INDIRECT_COMBINED_LIGHTING_PASS
uniform highp vec4 CameraLightIntensity;
uniform highp vec4 DimensionID;

SAMPLER2D_HIGHP_AUTOREG(s_ColorMetalnessSubsurface);
USAMPLER2D_AUTOREG(s_EmissiveAmbientLinearRoughness);

#include "./lib/materials.glsl"
#include "./lib/atmosphere.glsl"

void main() {
    uvec4 data16 = texelFetch(s_EmissiveAmbientLinearRoughness, ivec2(gl_FragCoord.xy), 0) & 0xFFFFu;
    vec2 lightmap = vec2(data16.g >> 8, data16.g & 0xFFu) / 255.0;
    float ao = float(data16.b >> 8) / 255.0; //baked ao from gbufffers
    vec4 data = texture2D(s_ColorMetalnessSubsurface, v_texcoord0);
    vec3 albedo = pow(data.rgb, vec3_splat(2.2)) * 2.0;
    float metalness = unpackMetalness(data.a);

    vec3 blockAmbient = BLOCK_LIGHT_COLOR * uv1x2lig(lightmap.r) * BLOCK_LIGHT_INTENSITY;
    vec3 skyAmbient = (v_scatterColor + v_absorbColor * 0.01) * mix(pow(lightmap.g, 3.0), pow(lightmap.g, 5.0), CameraLightIntensity.y) * SKY_AMBIENT_INTENSITY;
    vec3 outColor = albedo * (1.0 - metalness) * max(blockAmbient + skyAmbient * ao * ao, vec3_splat(MIN_AMBIENT_LIGHT));

    //this will be added to directional lighting
    gl_FragData[0] = vec4(outColor, 1.0);
    gl_FragData[1] = vec4_splat(0.0);
    gl_FragData[2] = vec4_splat(0.0);
}

#endif //DISCRETE_INDIRECT_COMBINED_LIGHTING_PASS


#if SURFACE_RADIANCE_UPSCALE_PASS
uniform highp vec4 CameraIsUnderwater;
uniform highp vec4 DimensionID;
uniform highp vec4 FogColor;
uniform highp vec4 SunDir;
uniform highp vec4 MoonDir;
uniform highp vec4 DirectionalLightSourceWorldSpaceDirection;
uniform highp vec4 Time;
uniform highp vec4 FogAndDistanceControl;
uniform highp vec4 RenderChunkFogAlpha;
uniform highp vec4 WorldOrigin;

SAMPLER2D_HIGHP_AUTOREG(s_SceneDepth);
SAMPLER2D_HIGHP_AUTOREG(s_DiffuseLighting);
SAMPLER2D_HIGHP_AUTOREG(s_SpecularLighting);
SAMPLER2D_HIGHP_AUTOREG(s_ColorMetalnessSubsurface);
USAMPLER2D_AUTOREG(s_EmissiveAmbientLinearRoughness);
SAMPLER2D_HIGHP_AUTOREG(s_PreviousFrameAverageLuminance);

#include "./lib/materials.glsl"
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

    float worldDist = length(worldPos);
    float wDistNorm = worldDist / FogAndDistanceControl.z;
    float dither = texelFetch(s_CausticsTexture, ivec3(ivec2(gl_FragCoord.xy) % 256, 1), 0).r;

    vec3 outColor = vec3_splat(0.0);

    bool isTerrain = depth < 1.0;

    if (isTerrain) {
        outColor = texture2D(s_DiffuseLighting, v_texcoord0).rgb;

        //always lit
        vec3 albedo = pow(texture2D(s_ColorMetalnessSubsurface, v_texcoord0).rgb, vec3_splat(2.2)) * 2.0;
        uvec4 data16 = texelFetch(s_EmissiveAmbientLinearRoughness, ivec2(gl_FragCoord.xy), 0) & 0xFFFFu;
        float emssive = float(data16.r & 0xFFu) / 255.0;
        outColor += albedo * emssive * EMISSIVE_MATERIAL_INTENSITY;
    }

    if (int(DimensionID.r) == 0) {
        vec3 scattering = GetAtmosphere(worldDir, 1e10, SunDir.xyz, vec3_splat(1.0)) * SUN_MAX_ILLUMINANCE;
        scattering += GetAtmosphere(worldDir, 1e10, MoonDir.xyz, vec3_splat(1.0)) * MOON_MAX_ILLUMINANCE;
        if (!isTerrain) outColor = scattering;

        applyCirrusClouds(outColor, worldDir, DirectionalLightSourceWorldSpaceDirection.xyz, v_absorbColor, isTerrain);

#ifdef VOLUMETRIC_CLOUDS_ENABLED
        applyCumulusClouds(outColor, v_scatterColor, v_absorbColor, worldDir, wDistNorm, dither, isTerrain);
#endif

        //underwater tint (extinction)
        if (CameraIsUnderwater.r > 0.0 && texture2D(s_SpecularLighting, v_texcoord0).r < 1.0) {
            outColor *= exp(-WATER_EXTINCTION_COEFFICIENTS * worldDist);
        }

        applyVolumetricFog(outColor, projPos);
    } else {
        float borderFog = saturate((wDistNorm + RenderChunkFogAlpha.x - FogAndDistanceControl.x) * FogAndDistanceControl.y);
        outColor = mix(outColor, pow(FogColor.rgb, vec3_splat(2.2)), borderFog);
    }

    outColor = preExposeLighting(outColor, texture2D(s_PreviousFrameAverageLuminance, vec2_splat(0.5)).r);

    gl_FragColor = vec4(outColor, 1.0);
}
#endif //SURFACE_RADIANCE_UPSCALE_PASS

#endif //BGFX_SHADER_TYPE_FRAGMENT
