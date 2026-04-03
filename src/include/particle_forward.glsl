#include "./lib/common.glsl"
#include "./lib/atmosphere.glsl"


///////////////////////////////////////////////////////////
// VERTEX SHADER
///////////////////////////////////////////////////////////
#if BGFX_SHADER_TYPE_VERTEX
uniform vec4 SunDir;
uniform vec4 MoonDir;
uniform vec4 DimensionID;

void main() {
#if INSTANCING__ON
    vec3 worldPos = mul(mtxFromCols(i_data1, i_data2, i_data3, vec4(0.0, 0.0, 0.0, 1.0)), vec4(a_position, 1.0)).xyz;
#else
    vec3 worldPos = mul(u_model[0], vec4(a_position, 1.0)).xyz;
#endif
    vec4 clipPos = mul(u_viewProj, vec4(worldPos, 1.0));

    v_clipPos = clipPos;
    v_color0 = a_color0;
    v_worldPos = worldPos;
    v_texcoord0 = a_texcoord0;

    //unpack block light color and lightmap
    uvec2 data16 = uvec2(a_texcoord1 * 65535.0) & 0xFFFFu;
    uint lowByte = data16.g & 0xFFu;
    v_coloredLighting = vec3(data16.r >> 8, data16.r & 0xFFu, data16.g >> 8) / 255.0;
    v_vanillaLighting = vec2(uvec2(lowByte >> 4, lowByte) & 15u) / 15.0;

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

    gl_Position = clipPos;
}
#endif //BGFX_SHADER_TYPE_VERTEX




///////////////////////////////////////////////////////////
// FRAGMENT/PIXEL SHADER
///////////////////////////////////////////////////////////
#if BGFX_SHADER_TYPE_FRAGMENT
SAMPLER2D_HIGHP_AUTOREG(s_ParticleTexture);

#if FORWARD_PBR_TRANSPARENT_PASS
uniform highp vec4 CameraIsUnderwater;
uniform highp vec4 CameraLightIntensity;
uniform highp vec4 CausticsParameters;
uniform highp vec4 DirectionalLightSourceWorldSpaceDirection;
uniform highp vec4 MERSUniforms;
uniform highp vec4 PBRTextureFlags;
uniform highp vec4 SunDir;
uniform highp vec4 MoonDir;
uniform highp vec4 DimensionID;
uniform highp vec4 Time;
uniform highp vec4 WorldOrigin;
uniform highp vec4 FogAndDistanceControl;
uniform highp vec4 RenderChunkFogAlpha;
uniform highp vec4 FogColor;

SAMPLER2D_HIGHP_AUTOREG(s_MERSTexture);
SAMPLER2D_HIGHP_AUTOREG(s_NormalTexture);
SAMPLER2D_HIGHP_AUTOREG(s_PreviousFrameAverageLuminance);

#include "./lib/materials.glsl"
#include "./lib/shadow.glsl"
#include "./lib/bsdf.glsl"
#include "./lib/ibl.glsl"
#include "./lib/volumetrics.glsl"
#endif

void main() {
    vec4 albedo = texture2D(s_ParticleTexture, v_texcoord0);
#if ALPHA_TEST_PASS
    if (albedo.a < 0.5) discard;
    albedo.a = 1.0;
#endif
    albedo *= v_color0;

#if FORWARD_PBR_TRANSPARENT_PASS
    //materials setup
    albedo.rgb = toLinear(albedo.rgb) * 0.5;

    int pbrTextureFlags = int(PBRTextureFlags.r);

    vec4 mers = MERSUniforms;
    if ((pbrTextureFlags & kPBRTextureDataFlagHasMaterialTexture) == kPBRTextureDataFlagHasMaterialTexture) {
        vec4 mersTex = texture2D(s_MERSTexture, v_texcoord0);
        mers.rgb = mersTex.rgb;
        if ((pbrTextureFlags & kPBRTextureDataFlagHasSubsurfaceChannel) == kPBRTextureDataFlagHasSubsurfaceChannel) mers.a = mersTex.a;
    }

    vec3 normal = ((pbrTextureFlags & kPBRTextureDataFlagHasNormalTexture) == kPBRTextureDataFlagHasNormalTexture) ? mul(u_model[0], vec4(texture2D(s_NormalTexture, v_texcoord0).rgb * 2.0 - 1.0, 0.0)).xyz : vec3_splat(0.0);
    vec3 f0 = mix(vec3_splat(0.02), albedo.rgb, mers.r);

    //ambient lighting
    vec3 blockAmbient = v_coloredLighting;
    if ((blockAmbient.r + blockAmbient.g + blockAmbient.b) <= 0.0 && v_vanillaLighting.r > 0.0) {
        float blm = v_vanillaLighting.r * v_vanillaLighting.r;
        blockAmbient = saturate(vec3(blm, blm * ((blm * 0.6 + 0.4) * 0.6 + 0.4), blm * ((blm * blm * 0.6) + 0.4)));
    }

    float skylmContrib = mix(pow(v_vanillaLighting.g, 3.0), pow(v_vanillaLighting.g, 5.0), CameraLightIntensity.g);
    if (int(DimensionID.r) == 1) skylmContrib = 0.05;
    if (int(DimensionID.r) == 2) skylmContrib = 0.02;
    vec3 skyAmbient = (v_scatterColor + v_absorbColor / SUN_MAX_ILLUMINANCE) * skylmContrib * SKY_AMBIENT_INTENSITY;

    vec3 ambientLight = max(blockAmbient + skyAmbient, vec3_splat(MIN_AMBIENT_LIGHT));
    vec3 outColor = ambientLight * albedo.rgb * (1.0 - mers.r);

    //directional lighting
    vec3 shadowMap = calcShadowMap(v_worldPos, normal).rgr;

#ifdef VOLUMETRIC_CLOUDS_ENABLED
    vec3 position = v_worldPos - WorldOrigin.xyz;
    CloudSetup cloudSetup = calcCloudSetup(DirectionalLightSourceWorldSpaceDirection.y, position.y);
    float cloudShadow = calcCloudShadow(position, DirectionalLightSourceWorldSpaceDirection.xyz, 2.0, cloudSetup);
    shadowMap.rg = min(shadowMap.rg, vec2_splat(cloudShadow * CLOUD_SHADOW_CONTRIBUTION + (1.0 - CLOUD_SHADOW_CONTRIBUTION)));
    shadowMap.b = min(shadowMap.b, cloudShadow); //used for specular
#endif

    vec3 worldDir = normalize(v_worldPos);
    vec3 bsdf = BSDF(normal, DirectionalLightSourceWorldSpaceDirection.xyz, -worldDir, f0, albedo.rgb, shadowMap, mers.r, mers.b, mers.a);
    outColor += bsdf * v_absorbColor;

    //always lit
    outColor += albedo.rgb * mers.g * EMISSIVE_MATERIAL_INTENSITY;

    float worldDist = length(v_worldPos);

    bool isWaterBody = CausticsParameters.a > 0.0;

    if (int(DimensionID.r) == 0) {
        //reflections
        outColor += indirectSpecular(f0, worldDir, normal, blockAmbient, mers.b, mers.r, v_vanillaLighting.g, !isWaterBody);

#ifdef VOLUMETRIC_CLOUDS_ENABLED
        float dither = texelFetch(s_CausticsTexture, ivec3(ivec2(gl_FragCoord.xy) % 256, 1), 0).r;
        applyCumulusClouds(outColor, v_absorbColor, worldDir, worldDist, dither, true);
#endif

        //underwater extinction and scattering
        if (isWaterBody) {
            outColor *= exp(-WATER_EXTINCTION_COEFFICIENTS * worldDist);
            vec3 wscattering = exp(-WATER_EXTINCTION_COEFFICIENTS * 10.0) * luminance(v_absorbColor) * CameraLightIntensity.y;
            outColor = mix(outColor, wscattering, 0.01);
        }

        vec3 projPos = v_clipPos.xyz / v_clipPos.w;
        applyVolumetricFog(outColor, projPos);
    } else {
        float wDistNorm = worldDist / FogAndDistanceControl.z;
        float borderFog = saturate((wDistNorm + RenderChunkFogAlpha.x - FogAndDistanceControl.x) * FogAndDistanceControl.y);
        vec3 linFogColor = toLinear(FogColor.rgb);
        outColor = mix(outColor, linFogColor, borderFog);
    }

    outColor = preExposeLighting(outColor, texture2D(s_PreviousFrameAverageLuminance, vec2_splat(0.5)).r);

    gl_FragColor = vec4(outColor, albedo.a);
#else
    gl_FragColor = albedo;
#endif //FORWARD_PBR_TRANSPARENT_PASS
}

#endif //BGFX_SHADER_TYPE_FRAGMENT
