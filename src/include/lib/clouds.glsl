#ifndef CLOUDS_INCLUDE
#define CLOUDS_INCLUDE

// CLOUDS!
// https://www.guerrilla-games.com/read/the-real-time-volumetric-cloudscapes-of-horizon-zero-dawn
// https://www.guerrilla-games.com/read/nubis-realtime-volumetric-cloudscapes-in-a-nutshell
// https://media.contentapi.ea.com/content/dam/eacom/frostbite/files/s2016-pbs-frostbite-sky-clouds-new.pdf

#define CLOUD_HEIGHT 180.0
#define CLOUD_THICKNESS 200.0
#define CLOUD_VOLUME_MAX_STEP_COUNTS 200
#define CLOUD_VOLUME_STEP_SPACE 10.0

//terrain
#define CLOUD_SHADOW_CONTRIBUTION 0.8

#include "./noises.glsl"


struct CloudSetup {
    float tMin;
    float tMax;
    int stepCounts;
    bool isValidCloud;
};

CloudSetup calcCloudSetup(float direction, float camAltitude) {
    CloudSetup setup;
    setup.tMin = 0.0;
    setup.tMax = 1e6;
    setup.stepCounts = CLOUD_VOLUME_MAX_STEP_COUNTS;
    setup.isValidCloud = true;

    float cloudMaxY = CLOUD_HEIGHT + CLOUD_THICKNESS;
    float tBottomPlane = (CLOUD_HEIGHT - camAltitude) / direction;
    float tTopPlane = (cloudMaxY - camAltitude) / direction;

    if (camAltitude > cloudMaxY) {
        //camera is above the clouds
        if (direction >= 0.0) { setup.isValidCloud = false; return setup; }

        //start marching at the top plane, stop at the bottom plane
        setup.tMin = tTopPlane;
        setup.tMax = tBottomPlane;
    } else if (camAltitude < CLOUD_HEIGHT) {
        //camera is below the clouds
        if (direction <= 0.0) { setup.isValidCloud = false; return setup; }

        //start marching at the bottom plane, stop at the top plane
        setup.tMin = tBottomPlane;
        setup.tMax = tTopPlane;
    } else {
        //camera inside cloud layer
        setup.tMin = 0.0;
        setup.tMax = direction > 0.0 ? tTopPlane : tBottomPlane;
    }

    float raySpan = (setup.tMax - setup.tMin) / CLOUD_VOLUME_STEP_SPACE;
    setup.stepCounts = min(setup.stepCounts, int(raySpan));

    return setup;
}

float calcCumulusModel(vec3 pos) {
    vec2 windDir = vec2(0.0, Time.x);
    vec2 basePos = (pos.xz + windDir) * 0.003;

    //base 2d value noise fbm
    float base = valueNoise(basePos);
    base += valueNoise(basePos * 2.0) * 0.5;
    base += valueNoise(basePos * 4.0) * 0.25;
    base += valueNoise(basePos * 8.0) * 0.125;
    base = saturate(base * 0.533333 - 0.25);

    float heightFraction = saturate((pos.y - CLOUD_HEIGHT) / CLOUD_THICKNESS);

    //top sculpting
    float topFade = pow(heightFraction, 6.0);
    base = linearstep(topFade, 1.0, base);

    //bottom sculpting
    float bottomFade = exp(-heightFraction * 20.0);
    base = linearstep(bottomFade, 1.0, base);

    //worley sculpting for billow shape
    float wsculpting = worley3d(pos * 0.15 + windDir.xxy * 0.05);
    base = linearstep(wsculpting * heightFraction, 1.0, base);
    return base;
}

float calcDirectScattering(vec3 samplePos, vec3 lightDir, float costh) {
    //fixed params self shadow
    float shadow = 0.0;
    float stepSpace = CLOUD_THICKNESS / max(lightDir.y, 0.01) * 0.25;
    stepSpace = min(stepSpace, CLOUD_THICKNESS);

    UNROLL
    for (int i = 0; i < 4; i++) {
        samplePos += lightDir * stepSpace * 0.1;
        shadow += calcCumulusModel(samplePos);
    }

    float powder = 1.0 - exp(-shadow * 2.0);
    float lighting = 0.0;

    float lMod = saturate(lightDir.y);
    float g = 1.0; //anisotropy factor
    float b = 0.75 + lMod * 0.5; //brightness
    float a = 1.0; //shadow

    UNROLL
    for (int j = 0; j < 4; j++) {
        float forward = PhaseHG(costh, 0.7 * g);
        float backward = PhaseHG(costh, -0.1 * g);
        float phase = mix(forward, backward, 0.2);
        lighting += b * phase * exp(-shadow * stepSpace * a);

        a = a * (0.25 + lMod * 0.2);
        g *= 0.5;
        b *= 0.75;
    }

    return powder * lighting + lighting;
}

vec4 calcCloud(vec3 worldDir, vec3 lightDir, float worldDist, float dither, bool isTerrain, CloudSetup setup) {
    if (!setup.isValidCloud) return vec4(0.0, 0.0, 0.0, 1.0);

    vec3 rayOrigin = -WorldOrigin.xyz;
    vec3 rayDir = worldDir;

    float costh = dot(worldDir, lightDir);

    vec2 lighting = vec2_splat(0.0);
    float wdepth = 0.0; //weighted depth, used for atmosphere contribution
    float tweight = 0.0;
    float transmittance = 1.0;

    if (isTerrain) setup.tMax = min(setup.tMax, worldDist);

    LOOP
    for (int i = 0; i < setup.stepCounts; i++) {
        vec3 samplePos = rayOrigin + rayDir * (setup.tMin + dither * CLOUD_VOLUME_STEP_SPACE);
        float heightFraction = saturate((samplePos.y - CLOUD_HEIGHT) / CLOUD_THICKNESS);

        float density = calcCumulusModel(samplePos);
        if (density > 0.0) {
            //indirect scatter just use layer gradient
            float iscattering = heightFraction * 0.1 + 0.1;
            float dscattering = calcDirectScattering(samplePos, lightDir, costh);
            vec2 lum = vec2(dscattering, iscattering) * density;

            float stepTransmittance = exp(-density * CLOUD_VOLUME_STEP_SPACE);

            //https://www.shadertoy.com/view/XlBSRz
            vec2 scatterInt = (lum - lum * stepTransmittance) / max(density, EPSILON);
            lighting += transmittance * scatterInt;

            wdepth += transmittance * setup.tMin;
            tweight += transmittance;
            transmittance *= stepTransmittance;
        }

        if (transmittance < EPSILON) break;

        setup.tMin += CLOUD_VOLUME_STEP_SPACE;
        if (setup.tMin > setup.tMax) break;
    }

    wdepth /= tweight;
    return vec4(lighting, wdepth, transmittance);
}

float calcCloudTransmittanceOnly(vec3 worldDir, float worldDist, float dither, bool isTerrain, CloudSetup setup) {
    if (!setup.isValidCloud) return 1.0;

    vec3 rayOrigin = -WorldOrigin.xyz;
    vec3 rayDir = worldDir;

    if (isTerrain) setup.tMax = min(setup.tMax, worldDist);

    float transmittance = 1.0;

    LOOP
    for (int i = 0; i < setup.stepCounts; i++) {
        vec3 samplePos = rayOrigin + rayDir * (setup.tMin + dither * CLOUD_VOLUME_STEP_SPACE);
        float density = calcCumulusModel(samplePos);
        if (density > 0.0) transmittance *= exp(-density * CLOUD_VOLUME_STEP_SPACE);
        if (transmittance < EPSILON) break;

        setup.tMin += CLOUD_VOLUME_STEP_SPACE;
        if (setup.tMin > setup.tMax) break;
    }

    return transmittance;
}

float calcCloudShadow(vec3 position, vec3 lightDir, float hardness, CloudSetup setup) {
    if (!setup.isValidCloud) return 1.0;

    float shadowDensity = 0.0;

    LOOP
    for (int i = 0; i < setup.stepCounts; i++) {
        vec3 samplePos = position + setup.tMin * lightDir;
        float density = calcCumulusModel(samplePos);
        if (density > 0.0) shadowDensity += density * CLOUD_VOLUME_STEP_SPACE;

        setup.tMin += CLOUD_VOLUME_STEP_SPACE;
        if (setup.tMin > setup.tMax) break;
    }

    return exp(-shadowDensity * hardness);
}

// just weird shape cirrus but i like it
float calcCirrusModel(vec2 pos) {
    float tdensity = 0.0;
    float amplitude = 1.0;

    pos.y *= 0.3;
    pos.x += sin(pos.y * 3.0) * 0.2;
    pos.y += Time.x * 0.005;

    UNROLL
    for (int i = 0; i < 4; i++) {
        float dens = valueNoise(pos) * amplitude;
        tdensity += dens;
        pos *= 3.0;
        pos.y += dens * 5.0 + Time.x * 0.01;
        amplitude *= 0.5;
    }

    return saturate(tdensity * 0.533333 - 0.25);
}

void applyCirrusClouds(inout vec3 outColor, vec3 worldDir, vec3 lightDir, vec3 absorbColor, bool isTerrain) {
    vec2 cloudpos = worldDir.xz / worldDir.y * 2.5;
    float base = isTerrain ? 0.0 : calcCirrusModel(cloudpos);

    //distance fade
    base *= smoothstep(0.0, 0.4, worldDir.y);

    //height fade, make the clouds dissapear when camera near them
    float cirrusHeight = CLOUD_HEIGHT + CLOUD_THICKNESS + 200.0;
    base *= smoothstep(0.0, 180.0, cirrusHeight + WorldOrigin.y);

    float transmittance = exp(-base * 0.07);

    float costh = dot(worldDir, lightDir);
    float phase = PhaseHG(costh, 0.8);

    outColor = outColor * transmittance + absorbColor * (1.0 + phase) * (1.0 - transmittance);
}

#endif
