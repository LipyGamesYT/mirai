#if BGFX_SHADER_TYPE_COMPUTE
uniform highp mat4 CascadesShadowInvProj[8];
uniform highp mat4 CascadesShadowProj[8];
uniform highp mat4 PlayerShadowProj;
uniform highp vec4 CameraUnderwaterAndWaterSurfaceBiasAndFalloff;
uniform highp vec4 CascadesParameters[8];
uniform highp vec4 CascadesPerSet;
uniform highp vec4 DimensionID;
uniform highp vec4 TimeOfDay;
uniform highp vec4 DirectionalLightSourceWorldSpaceDirection;
uniform highp vec4 FirstPersonPlayerShadowsEnabledAndResolutionAndFilterWidthAndTextureDimensions;
uniform highp vec4 FogAndDistanceControl;
uniform highp vec4 HeightFogScaleBias;
uniform highp vec4 JitterOffset;
uniform highp vec4 MoonDir;
uniform highp vec4 SunDir;
uniform highp vec4 TemporalSettings;

SAMPLER2DARRAY_AUTOREG(s_ShadowCascades);
SAMPLER2DARRAY_AUTOREG(s_PreviousLightingBuffer);
IMAGE2D_ARRAY_WR_AUTOREG(s_CurrentLightingBuffer, rgba16f);

#include "./lib/common.glsl"
#include "./lib/froxel_util.glsl"
#include "./lib/atmosphere.glsl"

float calcFPShadow(vec3 worldPos){
    vec3 projPos = mul(PlayerShadowProj, vec4(worldPos, 1.0)).xyz;
    projPos.z = min(projPos.z, 1.0);

#if BGFX_SHADER_LANGUAGE_GLSL
    vec2 uvShadow = projPos.xy * 0.5 + 0.5;
    float occluder = projPos.z * 0.5 + 0.5;
#else
    vec2 uvShadow = vec2(projPos.x, -projPos.y) * 0.5 + 0.5;
    float occluder = projPos.z;
#endif

    float shadowScale = FirstPersonPlayerShadowsEnabledAndResolutionAndFilterWidthAndTextureDimensions.y;
    uvShadow = uvShadow * shadowScale + vec2(0.0, 1.0 - shadowScale);
    if (!(uvShadow.x >= 0.0 && uvShadow.x < shadowScale && uvShadow.y >= (1.0 - shadowScale) && uvShadow.y < 1.0)) return 1.0;

    float cascade = dot(CascadesPerSet, vec4_splat(1.0)) + 1.0;
    return step(occluder, texture2DArrayLod(s_ShadowCascades, vec3(uvShadow, cascade), 0.0).r);
}

// get total 8 cascades, 4 day, 4 night
int getCascade(vec3 worldPos, out vec3 projPos) {
    int numShadow = 0;
    int numCascade = int(dot(clamp(CascadesPerSet, 0.0, 1.0), vec4_splat(1.0)));

    LOOP
    for (int i = 0; i < numCascade; i++) {
        int cascadePerSet = min(int(CascadesPerSet[i]), 8 - numShadow);
        LOOP
        for (int j = 0; j < cascadePerSet; j++) {
            int cascadeIdx = numShadow + j;
            projPos = mul(CascadesShadowProj[cascadeIdx], vec4(worldPos, 1.0)).xyz;
            if (all(lessThanEqual(abs(projPos), vec3_splat(1.0)))) return cascadeIdx;
        }
        numShadow += cascadePerSet;
    }
    return -1;
}

//no need filter and bias
float calcMainShadow(vec3 worldPos){
    vec3 projPos;
    int cascade = getCascade(worldPos, projPos);
    if (cascade < 0) return 1.0;

#if BGFX_SHADER_LANGUAGE_GLSL
    vec2 uvShadow = projPos.xy * 0.5 + 0.5;
    float occluder = projPos.z * 0.5 + 0.5;
#else
    vec2 uvShadow = vec2(projPos.x, -projPos.y) * 0.5 + 0.5;
    float occluder = projPos.z;
#endif

    float shadowScale = CascadesParameters[cascade].x;
    uvShadow = uvShadow * shadowScale + vec2(0.0, 1.0 - shadowScale);

    return step(occluder, texture2DArrayLod(s_ShadowCascades, vec3(uvShadow, cascade), 0.0).r);
}

#if THREAD_LIMIT__LIMITED_AT128
NUM_THREADS(8, 8, 2)
#elif THREAD_LIMIT__LIMITED_AT256
NUM_THREADS(8, 8, 4)
#else
NUM_THREADS(8, 8, 8)
#endif
void main() {
    ivec3 xyz = ivec3(gl_GlobalInvocationID.xyz);
    //just for overworld
    if (any(greaterThanEqual(xyz, ivec3(VolumeDimensions.xyz))) || int(DimensionID.r) != 0) return;

    vec3 uvw = (vec3(xyz) + JitterOffset.xyz + 0.5) / VolumeDimensions.xyz;
    vec3 worldPos = volumeToWorld(uvw);
    vec3 worldDir = normalize(worldPos);
    vec3 viewPos = mul(u_view, vec4(worldPos, 1.0)).xyz;
    float viewDist = length(viewPos);

    float shadowMap = calcMainShadow(worldPos);
    float fpShadow = calcFPShadow(worldPos);
    shadowMap = min(shadowMap, fpShadow);

    vec3 absorbColor = GetSunTransmittance(SunDir.xyz) * SUN_MAX_ILLUMINANCE;
    absorbColor += GetMoonTransmittance(MoonDir.xyz) * MOON_MAX_ILLUMINANCE;
    //night-sunrise sunset-night transition fade
    absorbColor *= smoothstep(0.0, 0.1, DirectionalLightSourceWorldSpaceDirection.y);

    // air scattering
    // aerial intensity is higher when sunrise
    float aerialModulator = 1.0 + smoothstep(0.5, 0.75, TimeOfDay.r) * smoothstep(0.85, 0.7, TimeOfDay.r) * 10.0;
    AtmosphereParams sunAtmParams;
    sunAtmParams.rayStart = vec3(0.0, 10.0, 0.0);
    sunAtmParams.rayDir = worldDir;
    sunAtmParams.lightDir = SunDir.xyz;
    sunAtmParams.rayLength = viewDist;
    sunAtmParams.aerial = aerialModulator;
    sunAtmParams.occlusion = shadowMap;
    sunAtmParams.mieMod = 1.0;

    AtmosphereParams moonAtmParams;
    moonAtmParams.rayStart = vec3(0.0, 10.0, 0.0);
    moonAtmParams.rayDir = worldDir;
    moonAtmParams.lightDir = MoonDir.xyz;
    moonAtmParams.rayLength = viewDist;
    moonAtmParams.aerial = aerialModulator;
    moonAtmParams.occlusion = shadowMap;
    moonAtmParams.mieMod = 1.0;

    vec4 transmittance;
    vec3 airScattering = GetAtmosphere(sunAtmParams, transmittance) * SUN_MAX_ILLUMINANCE;
    airScattering += GetAtmosphere(moonAtmParams) * MOON_MAX_ILLUMINANCE;

    float altitudeMod = clamp(HeightFogScaleBias.x * worldPos.y + HeightFogScaleBias.y, 0.0, 1.0);
    float tsmLum = saturate(luminance(transmittance.rgb));
    vec4 scatterExt = vec4(airScattering, 1.0 - tsmLum) * altitudeMod;

    // water scattering
    float cost = dot(worldDir, DirectionalLightSourceWorldSpaceDirection.xyz);
    vec3 waterScattering = exp(-WATER_EXTINCTION_COEFFICIENTS * 10.0) * PhaseHG(cost, 0.7) * shadowMap;
    if (CameraUnderwaterAndWaterSurfaceBiasAndFalloff.x > 0.0) {
        scatterExt = vec4(waterScattering * luminance(absorbColor) * 0.03, 0.0);
    }

    // cut scattering if out of render distance
    scatterExt = (viewDist / FogAndDistanceControl.z) < 1.0 ? scatterExt * 2.0 : vec4_splat(0.0);

    //temporal accumulation stuff
    vec3 uvwNoJitt = (vec3(xyz) + 0.5) / VolumeDimensions.xyz;
    vec3 worldPosNoJitt = volumeToWorld(uvwNoJitt);
    vec3 prevWorldPos = worldPosNoJitt - u_prevWorldPosOffset.xyz;
    vec3 prevUvw = worldToVolume(prevWorldPos);
    vec4 prevValue = sampleVolume(s_PreviousLightingBuffer, prevUvw);
    vec3 prevTexel = VolumeDimensions.xyz * prevUvw;
    vec3 prevTexelClamped = clamp(prevTexel, vec3_splat(0.0), VolumeDimensions.xyz);
    float distBoundary = distance(prevTexelClamped, prevTexel);
    float rejectH = clamp(distBoundary * TemporalSettings.y, 0.0, 1.0);
    float blendW = mix(TemporalSettings.z, 0.0, rejectH);

    if (TemporalSettings.x > 0.0) {
        imageStore(s_CurrentLightingBuffer, xyz, mix(scatterExt, prevValue, blendW));
    } else {
        imageStore(s_CurrentLightingBuffer, xyz, scatterExt);
    }
}

#endif
