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
    vec4 transmittance;
    vec3 atmContrib = GetAtmosphere(worldDir, clouds.b, 100.0, SunDir.xyz, vec3_splat(1.0), transmittance) * SUN_MAX_ILLUMINANCE;
    atmContrib += GetAtmosphere(worldDir, clouds.b, 50.0, MoonDir.xyz, vec3_splat(1.0)) * MOON_MAX_ILLUMINANCE;

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
