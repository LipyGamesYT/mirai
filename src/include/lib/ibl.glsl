#ifndef IBL_INCLUDE
#define IBL_INCLUDE

// some functions are deobfuscated from vanilla materials

uniform highp vec4 ConvolutionType;
uniform highp vec4 IBLParameters;
uniform highp vec4 IBLSkyFadeParameters;
uniform highp vec4 LastSpecularIBLIdx;

SAMPLER2D_HIGHP_AUTOREG(s_BrdfLUT);
SAMPLERCUBEARRAY_AUTOREG(s_SpecularIBLRecords);

float getIBLMipLevel(float a) {
    float x = 1.0 - a;
    if (int(ConvolutionType.x) != 1) x = x * x * x * x;
    return (1.0 - x * x) * (IBLParameters.y - 1.0);
}

vec3 getProbeLighting(float a, vec3 rv) {
    float iblMipLevel = getIBLMipLevel(a);
    int curr = int(LastSpecularIBLIdx.x);
    int prev = (curr + 2) % 3;

    vec3 preFilteredColorCurrent = textureCubeArrayLod(s_SpecularIBLRecords, vec4(rv, curr), iblMipLevel).rgb;
    vec3 preFilteredColorPrevious = textureCubeArrayLod(s_SpecularIBLRecords, vec4(rv, prev), iblMipLevel).rgb;
    vec3 preFilteredColor = mix(preFilteredColorPrevious, preFilteredColorCurrent, IBLParameters.w);
    return preFilteredColor;
}

#if DO_INDIRECT_SPECULAR_SHADING_DUAL_TARGET_PASS || DO_INDIRECT_SPECULAR_SHADING_SINGLE_TARGET_PASS

uniform highp vec4 SSRParameters;
SAMPLER2D_HIGHP_AUTOREG(s_SSRTexture);

vec3 indirectSpecular(vec3 f0, vec3 worldDir, vec3 normal, vec3 blockAmbient, vec2 ssrUV, float roughness, float metalness, float skyLightmap, float exposure, bool isNeedSkyReflection) {
    vec3 ambientColor = mix(vec3_splat(MIN_AMBIENT_LIGHT), blockAmbient, luminance(blockAmbient)) * metalness;
    vec3 incomingLight = ambientColor;

    if (IBLParameters.r > 0.0) {
        vec3 reflectedDir = reflect(worldDir, normal);
        float reflIntensity = 1.0 - sqrt(roughness);
        vec3 skyProbe = getProbeLighting(roughness, reflectedDir);

        if (isNeedSkyReflection) {
            incomingLight = mix(incomingLight, skyProbe * pow(skyLightmap, 3.0) * reflIntensity, reflIntensity);
        }

        float iblLuminance = luminance(incomingLight);
        float ambientLuminance = luminance(ambientColor);
        if (iblLuminance < ambientLuminance) incomingLight = ambientColor;

        vec4 ssr = texture2D(s_SSRTexture, ssrUV);
        ssr.rgb = unExposeLighting(ssr.rgb, exposure);
        if (SSRParameters.r > 0.0 && isNeedSkyReflection) incomingLight = mix(incomingLight, ssr.rgb, ssr.a * SSRParameters.g);
    }

    float cost = saturate(dot(-worldDir, normal));
    vec2 envDFGUV = vec2(cost, 1.0 - roughness);
    vec2 envDFG = texture2D(s_BrdfLUT, envDFGUV).rg;

    return incomingLight * (f0 * envDFG.r + envDFG.g);
}

#else

vec3 indirectSpecular(vec3 f0, vec3 worldDir, vec3 normal, vec3 blockAmbient, float roughness, float metalness, float skyLightmap, bool isNeedSkyReflection) {
    vec3 ambientColor = mix(vec3_splat(MIN_AMBIENT_LIGHT), blockAmbient, luminance(blockAmbient)) * metalness;
    vec3 incomingLight = ambientColor;

    if (IBLParameters.r > 0.0) {
        vec3 reflectedDir = reflect(worldDir, normal);
        float reflIntensity = 1.0 - sqrt(roughness);
        vec3 skyProbe = getProbeLighting(roughness, reflectedDir);

        if (isNeedSkyReflection) {
            incomingLight = mix(incomingLight, skyProbe * pow(skyLightmap, 3.0) * reflIntensity, reflIntensity);
        }

        float iblLuminance = luminance(incomingLight);
        float ambientLuminance = luminance(ambientColor);
        if (iblLuminance < ambientLuminance) incomingLight = ambientColor;
    }

    float cost = saturate(dot(-worldDir, normal));
    vec2 envDFGUV = vec2(cost, 1.0 - roughness);
    vec2 envDFG = texture2D(s_BrdfLUT, envDFGUV).rg;

    return incomingLight * (f0 * envDFG.r + envDFG.g);
}

#endif
#endif //IBL_INCLUDE
