#ifndef VOLUMETRICS_INCLUDE
#define VOLUMETRICS_INCLUDE

SAMPLER2DARRAY_AUTOREG(s_ScatteringBuffer);

#include "./froxel_util.glsl"
#include "./clouds.glsl"

void applyCumulusClouds(inout vec3 outColor, vec3 scatterColor, vec3 absorbColor, vec3 worldDir, float worldDist, float dither, bool isTerrain) {
    CloudSetup cloudSetup = calcCloudSetup(worldDir.y, -WorldOrigin.y);

    // vec4(direct light, indirect light, weighted depth, transmittance)
    vec4 clouds = calcCloud(worldDir, DirectionalLightSourceWorldSpaceDirection.xyz, worldDist, dither, isTerrain, cloudSetup);

    //get atmosphere again, but now with cloud depth and has more aerial intensity
    AtmosphereParams sunAtmParams;
    sunAtmParams.rayStart = vec3(0.0, 10.0, 0.0);
    sunAtmParams.rayDir = worldDir;
    sunAtmParams.lightDir = SunDir.xyz;
    sunAtmParams.rayLength = clouds.b;
    sunAtmParams.aerial = 100.0;
    sunAtmParams.occlusion = 1.0;
    sunAtmParams.mieMod = 1.0;

    AtmosphereParams moonAtmParams;
    moonAtmParams.rayStart = vec3(0.0, 10.0, 0.0);
    moonAtmParams.rayDir = worldDir;
    moonAtmParams.lightDir = MoonDir.xyz;
    moonAtmParams.rayLength = clouds.b;
    moonAtmParams.aerial = 40.0;
    moonAtmParams.occlusion = 1.0;
    moonAtmParams.mieMod = 1.0;

    vec4 transmittance;
    vec3 atmContrib = GetAtmosphere(sunAtmParams, transmittance) * SUN_MAX_ILLUMINANCE;
    atmContrib += GetAtmosphere(moonAtmParams) * MOON_MAX_ILLUMINANCE;

    if (MoonDir.y > 0.0) clouds.r *= 0.75;

    vec3 cloudsColor = (clouds.g * scatterColor + clouds.r * absorbColor) * transmittance.rgb;
    cloudsColor += atmContrib * (1.0 - clouds.a);
    outColor = clouds.a * outColor + cloudsColor;
}

void applyVolumetricFog(inout vec3 outColor, vec3 projPos) {
    vec3 uvw = ndcToVolume(projPos);
    vec4 volumetricFog = sampleVolume(s_ScatteringBuffer, uvw);
    if (VolumeScatteringEnabledAndPointLightVolumetricsEnabled.x > 0.0) outColor = outColor * volumetricFog.a + volumetricFog.rgb;
}

#endif
