#ifndef WATER_WAVE_INCLUDE
#define WATER_WAVE_INCLUDE

// gertsner inpired wave
// https://www.shadertoy.com/view/MdXyzX

vec2 wavedx(vec2 pos, vec2 dir, float speed, float freq, float time) {
    float x = dot(dir, pos) * freq - time * speed;
    float wave = exp(sin(x) - 1.0);
    return vec2(wave, -wave * cos(x));
}

float getWaves(vec2 pos, float time) {
    float angle = 0.0;
    float freq = 1.0;
    float speed = 2.0;
    float weight = 1.0;
    float w = 0.0;
    float ws = 0.0;

    pos *= vec2(2.0, 3.5);
    pos.y += time * 2.0;

    for (int i = 0; i < 10; i++) {
        vec2 dir = vec2(sin(angle), cos(angle));
        vec2 res = wavedx(pos, dir, speed, freq, time);
        pos += dir * res.y * weight * 0.1;
        w += res.x * weight;
        ws += weight;
        angle += 1.1;
        weight *= 0.8;
        freq *= 1.12;
        speed *= 1.05;
    }

    return w / ws;
}

float getWaves2(vec2 pos, float time) {
    float angle = 0.0;
    float freq = 1.0;
    float speed = 2.0;
    float weight = 1.0;
    float w = 0.0;
    float ws = 0.0;

    pos *= vec2(2.0, 3.5);
    pos.y += time * 2.0;

    for (int i = 0; i < 10; i++) {
        vec2 dir = vec2(sin(angle), cos(angle));
        vec2 res = wavedx(pos, dir, speed, freq, time);
        pos += dir * res.y * weight;
        w += res.x * weight;
        ws += weight;
        angle += 1.1;
        weight *= 0.9;
        freq *= 1.12;
        speed *= 1.05;
    }

    return smoothstep(0.2, 1.0, w / ws);
}

// central difference water normal
vec3 getWaterNormal(vec2 pos, float time) {

    float hL = getWaves(pos - vec2(0.05, 0.0), time);
    float hR = getWaves(pos + vec2(0.05, 0.0), time);
    float hD = getWaves(pos - vec2(0.0, 0.05), time);
    float hU = getWaves(pos + vec2(0.0, 0.05), time);

    return normalize(vec3(hL - hR, hD - hU, 1.0));
}

// just use heightmap
float calcCaustic(vec3 position, vec3 lightDir, float time) {
    vec3 rL = refract(-lightDir, vec3(0.0, 1.0, 0.0), 0.75);
    vec3 pL = rL * position.y / rL.y;
    vec3 ppos = position - pL;
    return getWaves2(ppos.xz, time) * 2.0;
}

#endif
