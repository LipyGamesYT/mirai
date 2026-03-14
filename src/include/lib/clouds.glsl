#ifndef CLOUDS_INCLUDE
#define CLOUDS_INCLUDE

// CLOUDS!
// https://www.guerrilla-games.com/read/the-real-time-volumetric-cloudscapes-of-horizon-zero-dawn
// https://www.guerrilla-games.com/read/nubis-realtime-volumetric-cloudscapes-in-a-nutshell
// https://media.contentapi.ea.com/content/dam/eacom/frostbite/files/s2016-pbs-frostbite-sky-clouds-new.pdf
// https://www.shadertoy.com/view/XlBSRz
// https://www.shadertoy.com/view/XslGRr

#define CLOUD_HEIGHT 180.0
#define CLOUD_THICKNESS 150.0
#define CLOUD_VOLUME_SSHADOW_STEPS 4
#define CLOUD_VOLUME_MAX_STEP_COUNTS 200
#define CLOUD_VOLUME_STEP_SPACE 10.0

//terrain
#define CLOUD_SHADOW_STEPS_COUNT 10
#define CLOUD_SHADOW_STEP_SPACE 30.0
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
    float heightFraction = saturate((pos.y - CLOUD_HEIGHT) / CLOUD_THICKNESS);
    vec2 windDir = vec2(0.0, Time.x);
    vec2 basePos = pos.xz * 0.005 + windDir * 0.0025;

    float base = valueNoise(basePos);
    base += valueNoise(basePos * 2.0) * 0.5;
    base += valueNoise(basePos * 4.0) * 0.25;
    base += valueNoise(basePos * 8.0) * 0.125;
    base = saturate(base * 0.533333 - 0.2);

    float topFade = exp(-(1.0 - heightFraction) * 20.0);
    base = linearstep(topFade, 1.0, base);

    float bottomFade = exp(-heightFraction * 25.0);
    base = linearstep(bottomFade, 1.0, base);

    //worley sculpting, exclude buttom layer
    float wsculpting = worley3d(pos * 0.15);
    base = linearstep(wsculpting * heightFraction * 0.75, 1.0, base);

    //perlin worley sculpting
    float pwsculpting = perlinWorley3d(pos * 0.2 + windDir.xxy * 0.5);
    base = linearstep(pwsculpting * heightFraction * 0.25, 1.0, base);
    return base;
}

float calcDirectScattering(vec3 samplePos, vec3 lightDir, float costh) {
    float shadow = 0.0;
    float stepSpace = CLOUD_THICKNESS / max(lightDir.y, 0.01) / float(CLOUD_VOLUME_SSHADOW_STEPS);
    stepSpace = min(stepSpace, CLOUD_THICKNESS);

    for (int i = 0; i < CLOUD_VOLUME_SSHADOW_STEPS; i++) {
        samplePos += lightDir * stepSpace * 0.1;
        shadow += calcCumulusModel(samplePos);
    }

    float powder = 1.0 - exp(-shadow);
    float lighting = 0.0;

    // https://x.com/FewesW/status/1364617191652524032
    float g = 1.0; //mie
    float b = 1.7; //exposure
    float a = 1.0; //shadow

    for (int j = 0; j < 4; j++) {
        float forward = PhaseHG(costh, 0.7 * g) * 0.5;
        float backward = PhaseHG(costh, -0.1 * g) * 0.5;
        lighting += b * (forward + backward) * exp(-shadow * stepSpace * a);

        a *= 0.25;
        g *= 0.5;
        b *= 0.5;
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

    for (int i = 0; i < setup.stepCounts; i++) {
        vec3 samplePos = rayOrigin + rayDir * (setup.tMin + dither * CLOUD_VOLUME_STEP_SPACE);
        float heightFraction = saturate((samplePos.y - CLOUD_HEIGHT) / CLOUD_THICKNESS);

        float density = calcCumulusModel(samplePos);

        if (density > 0.0) {
            //indirect scatter just use layer gradient
            float dscattering = calcDirectScattering(samplePos, lightDir, costh);
            vec2 lum = vec2(dscattering, heightFraction) * density;

            float stepTransmittance = exp(-density * CLOUD_VOLUME_STEP_SPACE);

            //hillaire sctter integration
            vec2 scatterInt = (lum - lum * stepTransmittance) / max(density, EPSILON);
            lighting += transmittance * scatterInt;

            wdepth += transmittance * setup.tMin;
            tweight += transmittance;
            transmittance *= stepTransmittance;
        }

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

    for (int i = 0; i < setup.stepCounts; i++) {
        vec3 samplePos = rayOrigin + rayDir * (setup.tMin + dither * CLOUD_VOLUME_STEP_SPACE);
        float density = calcCumulusModel(samplePos);
        if (density > 0.0) transmittance *= exp(-density * CLOUD_VOLUME_STEP_SPACE);

        setup.tMin += CLOUD_VOLUME_STEP_SPACE;
        if (setup.tMin > setup.tMax) break;
    }

    return transmittance;
}

float calcCloudShadow(vec3 position, vec3 lightDir, float hardness, CloudSetup setup) {
    if (!setup.isValidCloud) return 1.0;

    float shadowDensity = 0.0;

    for (int i = 0; i < CLOUD_SHADOW_STEPS_COUNT; i++) {
        vec3 samplePos = position + setup.tMin * lightDir;
        float density = calcCumulusModel(samplePos) * CLOUD_SHADOW_STEP_SPACE;
        if (density > 0.0) shadowDensity += density;

        setup.tMin += CLOUD_SHADOW_STEP_SPACE;
        if (setup.tMin > setup.tMax) break;
    }

    return exp(-shadowDensity * hardness);
}

// just weird shape cirrus but i kinda like it
float cirrusFbm(vec2 pos) {
    float tdensity = 0.0;
    float amplitude = 1.0;

    pos.y *= 0.3;
    pos.x += sin(pos.y * 3.0) * 0.2;
    vec2 wind = vec2(0.0, Time.x * 0.05);

    for (int i = 0; i < 4; i++) {
        float density = valueNoise(pos + wind) * amplitude;
        tdensity += density;
        pos *= 3.0;
        pos.y += density * 2.0;
        amplitude *= 0.5;
    }

    return saturate(tdensity * 0.533333 - 0.25);
}

void applyCirrusClouds(inout vec3 outColor, vec3 worldDir, vec3 lightDir, vec3 absorbColor, bool isTerrain) {
    vec2 cloudpos = worldDir.xz / worldDir.y * 2.5;
    float base = isTerrain ? 0.0 : cirrusFbm(cloudpos);

    //distance fade
    base *= smoothstep(0.0, 0.2, worldDir.y);

    //height fade, make the clouds dissapear when camera near them
    float cirrusHeight = CLOUD_HEIGHT + CLOUD_THICKNESS + 200.0;
    base *= smoothstep(0.0, 180.0, cirrusHeight + WorldOrigin.y);

    float transmittance = exp(-base * 0.1);

    float costh = dot(worldDir, lightDir);
    float forward = PhaseHG(costh, 0.8);

    outColor = outColor * transmittance + absorbColor * (1.0 + forward) * (1.0 - transmittance);
}

#endif
