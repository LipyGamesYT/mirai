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
#define CIRRUS_HEIGHT (CLOUD_HEIGHT + CLOUD_THICKNESS + 200.0)

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
        if (direction > 0.0) {
            setup.isValidCloud = false;
            return setup;
        }
        setup.tMin = tTopPlane;
        setup.tMax = tBottomPlane;
    } else if (camAltitude < CLOUD_HEIGHT) {
        //camera is below the clouds
        if (direction < 0.0) {
            setup.isValidCloud = false;
            return setup;
        }
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

    base = linearstep(pow8(heightFraction), 1.0, base); //top sculpting
    base = linearstep(exp(-heightFraction * 25.0), 1.0, base); //bottom sculpting

    //worley sculpting for billow shape
    float wsculpting = worley3d(pos * 0.15 + windDir.xxy * 0.05);
    base = linearstep(wsculpting * heightFraction, 1.0, base);
    return base;
}

float calcDirectScattering(vec3 samplePos, vec3 lightDir, float extinction, float costh) {
    //fixed params self shadow
    float shadow = 0.0;
    float stepSpace = CLOUD_THICKNESS / max(lightDir.y, 0.01) * 0.25;
    stepSpace = min(stepSpace, CLOUD_THICKNESS);

    UNROLL
    for (int i = 0; i < 4; i++) {
        samplePos += lightDir * stepSpace * 0.1;
        shadow += calcCumulusModel(samplePos);
    }

    float lighting = 0.0;
    float lMod = saturate(lightDir.y);
    float g = 1.0; //anisotropy factor
    float b = 1.0 + lMod * 0.5; //brightness
    float a = 1.0; //shadow

    UNROLL
    for (int j = 0; j < 4; j++) {
        float fphase = PhaseHG(costh, 0.7 * g);
        float bphase = PhaseHG(costh, -0.1 * g);
        float dphase = mix(fphase, bphase, 0.4);

        lighting += b * dphase * exp(-shadow * stepSpace * a);
        a = a * (0.25 + lMod * 0.15);
        g *= 0.5;
        b *= 0.75;
    }

    //volume extinction is used for powder offect
    float powder = 1.0 - exp(-extinction * CLOUD_VOLUME_STEP_SPACE * 3.0);
    lighting *= mix(pow5(powder) * 5.0, 1.0, costh * 0.5 + 0.5);

    return lighting;
}

vec3 calcCloud(vec3 worldDir, vec3 lightDir, float worldDist, float dither, bool isTerrain, CloudSetup setup) {
    if (!setup.isValidCloud) return vec3(0.0, 0.0, 1.0);

    vec3 rayOrigin = -WorldOrigin.xyz;
    vec3 rayDir = worldDir;

    float costh = dot(worldDir, lightDir);

    float lighting = 0.0;
    float wdepth = 0.0; //weighted depth, used for atmosphere contribution
    float tweight = 0.0;
    float transmittance = 1.0;

    if (isTerrain) setup.tMax = min(setup.tMax, worldDist);

    LOOP
    for (int i = 0; i < setup.stepCounts; i++) {
        vec3 samplePos = rayOrigin + rayDir * (setup.tMin + dither * CLOUD_VOLUME_STEP_SPACE);
        float extinction = calcCumulusModel(samplePos);

        if (extinction > 0.0) {
            float dscattering = calcDirectScattering(samplePos, lightDir, extinction, costh) * extinction;
            float stepTransmittance = exp(-extinction * CLOUD_VOLUME_STEP_SPACE);

            //https://www.shadertoy.com/view/XlBSRz
            float scatterInt = (dscattering - dscattering * stepTransmittance) / max(extinction, EPSILON);

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
    return vec3(lighting, wdepth, transmittance);
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
        float extinction = calcCumulusModel(samplePos);
        if (extinction > 0.0) transmittance *= exp(-extinction * CLOUD_VOLUME_STEP_SPACE);
        if (transmittance < EPSILON) break;

        setup.tMin += CLOUD_VOLUME_STEP_SPACE;
        if (setup.tMin > setup.tMax) break;
    }

    return transmittance;
}

float calcCloudShadow(vec3 position, vec3 lightDir, float hardness, CloudSetup setup) {
    if (!setup.isValidCloud) return 1.0;

    float transmittance = 1.0;

    LOOP
    for (int i = 0; i < setup.stepCounts; i++) {
        vec3 samplePos = position + setup.tMin * lightDir;
        float extinction = calcCumulusModel(samplePos);
        if (extinction > 0.0) transmittance *= exp(-extinction * CLOUD_VOLUME_STEP_SPACE * hardness);
        if (transmittance < EPSILON) break;

        setup.tMin += CLOUD_VOLUME_STEP_SPACE;
        if (setup.tMin > setup.tMax) break;
    }

    return transmittance;
}

// just weird shape cirrus but i like it
float calcCirrusModel(vec2 pos) {
    float tdensity = 0.0;
    float amplitude = 1.0;

    pos.y *= 0.3;
    pos.y += Time.x * 0.001;
    pos.x += sin(pos.y * 3.0) * 0.2;

    UNROLL
    for (int i = 0; i < 4; i++) {
        float dens = valueNoise(pos) * amplitude;
        tdensity += dens;
        pos *= 3.0;
        pos.y += dens * pos.y * 0.2 + Time.x * 0.005;
        amplitude *= 0.5;
    }

    return saturate(tdensity * 0.533333 - 0.2);
}

void applyCirrusClouds(inout vec3 outColor, vec3 worldDir, vec3 lightDir, vec3 absorbColor, bool isTerrain) {
    float camAltitude = -WorldOrigin.y;
    float dirY = worldDir.y;
    float tPlane = (CIRRUS_HEIGHT - camAltitude) / dirY;
    if (tPlane < 0.0 || (dirY < 0.0 && camAltitude < CIRRUS_HEIGHT) || (dirY > 0.0 && camAltitude > CIRRUS_HEIGHT)) return;

    vec3 rayOrigin = -WorldOrigin.xyz;
    vec3 samplePos  = rayOrigin + worldDir * tPlane;
    float extinction = isTerrain ? 0.0 : calcCirrusModel(samplePos.xz * 0.005);
    extinction *= smoothstep(0.0, 0.4, dirY); //distance fade

    //height fade, make the clouds dissapear when camera near them
    extinction *= smoothstep(0.0, 180.0, CIRRUS_HEIGHT - camAltitude);

    float transmittance = exp(-extinction);
    float costh = dot(worldDir, lightDir);
    float phase  = PhaseR(costh);
    outColor = outColor * transmittance + absorbColor * phase * (1.0 - transmittance);
}

#endif
