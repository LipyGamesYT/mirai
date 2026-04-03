#include "./lib/common.glsl"
#include "./lib/actor_util.glsl"
#include "./lib/taau_util.glsl"
#include "./lib/atmosphere.glsl"


///////////////////////////////////////////////////////////
// VERTEX SHADER
///////////////////////////////////////////////////////////
#if BGFX_SHADER_TYPE_VERTEX
uniform vec4 UVAnimation;
uniform mat4 Bones[8];
uniform vec4 SunDir;
uniform vec4 MoonDir;
uniform vec4 DimensionID;

#ifdef MATERIAL_ACTOR_BANNER_FORWARD_PBR
uniform vec4 BannerColors[7];
uniform vec4 BannerUVOffsetsAndScales[7];
#endif

#if defined(MATERIAL_ACTOR_GLINT_FORWARD_PBR) || defined(MATERIAL_ACTOR_PATTERN_GLINT_FORWARD_PBR)
uniform vec4 UVScale;
#endif

void main() {
    mat4 model = mul(u_model[0], Bones[int(a_indices)]);
#if INSTANCING__ON
    vec3 worldPos = mul(mtxFromCols(i_data1, i_data2, i_data3, vec4(0.0, 0.0, 0.0, 1.0)), vec4(a_position, 1.0)).xyz;
#else
    vec3 worldPos = mul(model, vec4(a_position, 1.0)).xyz;
#endif

    v_texcoord0 = applyUvAnimation(a_texcoord0, UVAnimation);

#if !DEPTH_ONLY_PASS && !DEPTH_ONLY_OPAQUE_PASS
    v_color0 = a_color0;
    v_worldPos = worldPos;
    v_clipPos = mul(u_viewProj, vec4(worldPos, 1.0));

    v_normal = mul(model, vec4(a_normal.xyz, 0.0)).xyz;
    v_tangent = mul(model, vec4(a_tangent.xyz, 0.0)).xyz;
    v_bitangent = mul(model, vec4(cross(a_normal.xyz, a_tangent.xyz) * a_tangent.w, 0.0)).xyz;

#ifdef MATERIAL_ACTOR_BANNER_FORWARD_PBR
    int frameIndex = int(a_color0.a * 255.0);
    v_texcoords.xy = (BannerUVOffsetsAndScales[frameIndex].zw * a_texcoord0) + BannerUVOffsetsAndScales[frameIndex].xy;
    v_texcoords.zw = (BannerUVOffsetsAndScales[0].zw * a_texcoord0) + BannerUVOffsetsAndScales[0].xy;
#if TINTING__ENABLED
    v_color0 = BannerColors[frameIndex];
    v_color0.a = frameIndex > 0 ? 0.0 : 1.0;
#endif
#endif //MATERIAL_ACTOR_BANNER_FORWARD_PBR

#if defined(MATERIAL_ACTOR_GLINT_FORWARD_PBR) || defined(MATERIAL_ACTOR_PATTERN_GLINT_FORWARD_PBR)
    v_texcoord0 = a_texcoord0;
    v_layerUV.xy = calculateLayerUV(a_texcoord0, UVAnimation.x, UVAnimation.z, UVScale.xy);
    v_layerUV.zw = calculateLayerUV(a_texcoord0, UVAnimation.y, UVAnimation.w, UVScale.xy);
#endif

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
#endif

    gl_Position = jitterVertexPosition(worldPos);
}

#endif //BGFX_SHADER_TYPE_VERTEX




///////////////////////////////////////////////////////////
// FRAGMENT/PIXEL SHADER
///////////////////////////////////////////////////////////
#if BGFX_SHADER_TYPE_FRAGMENT
uniform highp vec4 ActorFPEpsilon;
uniform highp vec4 ChangeColor;
uniform highp vec4 ColorBased;
uniform highp vec4 MatColor;
uniform highp vec4 MultiplicativeTintColor;
uniform highp vec4 OverlayColor;
uniform highp vec4 TintedAlphaTestEnabled;
uniform highp vec4 UseAlphaRewrite;

#if defined(MATERIAL_ACTOR_BANNER_FORWARD_PBR) || \
defined(MATERIAL_ACTOR_PATTERN_FORWARD_PBR) || \
defined(MATERIAL_ACTOR_PATTERN_GLINT_FORWARD_PBR)

uniform highp vec4 HudOpacity;
#endif

#if defined(MATERIAL_ACTOR_GLINT_FORWARD_PBR) || defined(MATERIAL_ACTOR_PATTERN_GLINT_FORWARD_PBR)
uniform highp vec4 GlintColor;
#endif

SAMPLER2D_HIGHP_AUTOREG(s_MatTexture);
SAMPLER2D_HIGHP_AUTOREG(s_MatTexture1);

#if defined(MATERIAL_ACTOR_MULTI_TEXTURE_FORWARD_PBR) || \
defined(MATERIAL_ACTOR_PATTERN_FORWARD_PBR) || \
defined(MATERIAL_ACTOR_PATTERN_GLINT_FORWARD_PBR)

SAMPLER2D_HIGHP_AUTOREG(s_MatTexture2);
#endif

#ifdef MATERIAL_ACTOR_PATTERN_GLINT_FORWARD_PBR
uniform highp vec4 PatternCount;
uniform highp vec4 PatternColors[7];
uniform highp vec4 PatternUVOffsetsAndScales[7];

vec4 getPatternAlbedo(int layer, vec2 texcoord) {
    vec2 tex = (PatternUVOffsetsAndScales[layer].zw * texcoord) + PatternUVOffsetsAndScales[layer].xy;
    vec4 color = PatternColors[layer];
    return texture2D(s_MatTexture2, tex) * color;
}
#endif

#if !DEPTH_ONLY_PASS && !DEPTH_ONLY_OPAQUE_PASS
uniform highp vec4 DirectionalLightSourceWorldSpaceDirection;
uniform highp vec4 TileLightIntensity;
uniform highp vec4 BlockLightColor;
uniform highp vec4 CameraLightIntensity;
uniform highp vec4 SunDir;
uniform highp vec4 MoonDir;
uniform highp vec4 CameraIsUnderwater;
uniform highp vec4 CausticsParameters;
uniform highp vec4 DimensionID;
uniform highp vec4 WorldOrigin;
uniform highp vec4 Time;
uniform highp vec4 FogAndDistanceControl;
uniform highp vec4 RenderChunkFogAlpha;
uniform highp vec4 FogColor;

SAMPLER2D_HIGHP_AUTOREG(s_PreviousFrameAverageLuminance);

#include "./lib/materials.glsl"
#include "./lib/shadow.glsl"
#include "./lib/bsdf.glsl"
#include "./lib/ibl.glsl"
#include "./lib/volumetrics.glsl"
#endif

void main() {
#if DEPTH_ONLY_PASS
    vec4 albedo = getActorAlbedoNoColorChange(MatColor, s_MatTexture, s_MatTexture1, v_texcoord0);
    float alpha = mix(albedo.a, albedo.a * OverlayColor.a, TintedAlphaTestEnabled.x);
    if (shouldDiscard(albedo.rgb, alpha, ActorFPEpsilon.x)) discard;
    gl_FragData[0] = vec4_splat(0.0);
#elif DEPTH_ONLY_OPAQUE_PASS
    gl_FragData[0] = vec4_splat(1.0);
#elif defined(MATERIAL_ACTOR_PATTERN_FORWARD_PBR) && (FORWARD_PBR_ALPHA_TEST_PASS || FORWARD_PBR_TRANSPARENT_PASS)
    vec3 outColor = preExposeLighting(vec3_splat(1.0), texture2D(s_PreviousFrameAverageLuminance, vec2_splat(0.5)).r);
    gl_FragData[0] = vec4(outColor, 1.0);
#else


    //PBR materials setup
    vec4 mers = vec4(0.0, 0.0, 1.0, 0.0);

#ifdef MATERIAL_ACTOR_BANNER_FORWARD_PBR
    vec4 albedo = getBannerAlbedo(v_color0, s_MatTexture, v_texcoords.zw, v_texcoords.xy);
    albedo.a *= HudOpacity.r;

    vec3 normal = gl_FrontFacing ? -v_normal : v_normal;
    normal = normalize(normal);
    getTexturePBRMaterials(s_MatTexture, v_texcoords.zw, v_tangent, v_bitangent, normal, mers);
#else
    vec3 normal = normalize(v_normal);
    getTexturePBRMaterials(v_texcoord0, v_tangent, v_bitangent, normal, mers);
#endif


#if defined(MATERIAL_ACTOR_MULTI_TEXTURE_FORWARD_PBR) || defined(MATERIAL_ACTOR_TINT_FORWARD_PBR)
    vec4 albedo = getActorAlbedoNoColorChange(MatColor, s_MatTexture, s_MatTexture1, v_texcoord0);
    albedo = applyChangeColor(albedo, ChangeColor, MultiplicativeTintColor.rgb, 0.0);

    float alpha = 0.0;
#ifdef MATERIAL_ACTOR_TINT_FORWARD_PBR
    albedo = applySecondColorTint(albedo, MultiplicativeTintColor.rgb, s_MatTexture1, v_texcoord0, alpha);
#else
    albedo = applyMultitextureAlbedo(albedo, ChangeColor, s_MatTexture1, s_MatTexture2, v_texcoord0, ActorFPEpsilon.x, alpha);
#endif
    albedo.rgb *= mix(vec3_splat(1.0), v_color0.rgb, ColorBased.x);
    albedo.rgb = mix(albedo.rgb, OverlayColor.rgb, OverlayColor.a);

#if FORWARD_PBR_ALPHA_TEST_PASS
    if (albedo.a < 0.5 && alpha < ActorFPEpsilon.x) discard;
#endif
#endif


#if defined(MATERIAL_ACTOR_FORWARD_PBR) || \
defined(MATERIAL_ACTOR_GLINT_FORWARD_PBR) || \
(defined(MATERIAL_ACTOR_PATTERN_FORWARD_PBR) && FORWARD_PBR_OPAQUE_PASS) || \
defined(MATERIAL_ACTOR_PATTERN_GLINT_FORWARD_PBR)

    vec4 albedo = getActorAlbedoNoColorChange(MatColor, s_MatTexture, s_MatTexture1, v_texcoord0);

#if FORWARD_PBR_ALPHA_TEST_PASS || (defined(MATERIAL_ACTOR_PATTERN_FORWARD_PBR) && FORWARD_PBR_OPAQUE_PASS)
    float alpha = albedo.a;
    alpha = mix(alpha, alpha * OverlayColor.a, TintedAlphaTestEnabled.r);
    if (shouldDiscard(albedo.rgb, alpha, ActorFPEpsilon.r)) discard;
#endif

    albedo = applyChangeColor(albedo, ChangeColor, MultiplicativeTintColor.rgb, UseAlphaRewrite.r);
    albedo.rgb *= mix(vec3_splat(1.0), v_color0.rgb, ColorBased.r);
    albedo.rgb = mix(albedo.rgb, OverlayColor.rgb, OverlayColor.a);
#endif

#ifdef MATERIAL_ACTOR_PATTERN_GLINT_FORWARD_PBR
    LOOP
    for (int i = 0; i < int(PatternCount.x); i++) {
        vec4 pattern = getPatternAlbedo(i, v_texcoord0);
        albedo = mix(albedo, pattern, pattern.a);
    }
    albedo.a = 1.0;
#endif

#if defined(MATERIAL_ACTOR_GLINT_FORWARD_PBR) || defined(MATERIAL_ACTOR_PATTERN_GLINT_FORWARD_PBR)
    albedo.rgb = applyGlint(albedo.rgb, v_layerUV, s_MatTexture1, GlintColor);
#endif

    albedo.rgb = toLinear(albedo.rgb) * 0.5;
    vec3 f0 = mix(vec3_splat(0.02), albedo.rgb, mers.r);


    //ambient lighting
    vec3 blockAmbient = BlockLightColor.rgb;
    if ((blockAmbient.r + blockAmbient.g + blockAmbient.b) <= 0.0 && TileLightIntensity.r > 0.0) {
        float blm = TileLightIntensity.r * TileLightIntensity.r;
        blockAmbient = saturate(vec3(blm, blm * ((blm * 0.6 + 0.4) * 0.6 + 0.4), blm * ((blm * blm * 0.6) + 0.4)));
    }

    float skylmContrib = mix(pow(TileLightIntensity.g, 3.0), pow(TileLightIntensity.g, 5.0), CameraLightIntensity.g);
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
        outColor += indirectSpecular(f0, worldDir, normal, blockAmbient, mers.b, mers.r, TileLightIntensity.g, !isWaterBody);

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

    gl_FragData[0] = vec4(outColor, albedo.a);
#endif
}

#endif //BGFX_SHADER_TYPE_FRAGMENT
