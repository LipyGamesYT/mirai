#include "./lib/common.glsl"
#include "./lib/actor_util.glsl"
#include "./lib/taau_util.glsl"



///////////////////////////////////////////////////////////
// VERTEX SHADER
///////////////////////////////////////////////////////////
#if BGFX_SHADER_TYPE_VERTEX
uniform vec4 UVAnimation;
uniform mat4 Bones[8];
uniform mat4 PrevBones[8];
uniform mat4 PrevWorld;

#ifdef MATERIAL_ACTOR_BANNER_PREPASS
uniform vec4 BannerColors[7];
uniform vec4 BannerUVOffsetsAndScales[7];
#endif

#if defined(MATERIAL_ACTOR_GLINT_PREPASS) || defined(MATERIAL_ACTOR_PATTERN_GLINT_PREPASS)
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
    v_prevWorldPos = mul(mul(PrevWorld, PrevBones[int(a_indices)]), vec4(a_position, 1.0)).xyz;

    v_normal = mul(model, vec4(a_normal.xyz, 0.0)).xyz;
    v_tangent = mul(model, vec4(a_tangent.xyz, 0.0)).xyz;
    v_bitangent = mul(model, vec4(cross(a_normal.xyz, a_tangent.xyz) * a_tangent.w, 0.0)).xyz;

#ifdef MATERIAL_ACTOR_BANNER_PREPASS
    int frameIndex = int(a_color0.a * 255.0);
    v_texcoords.xy = (BannerUVOffsetsAndScales[frameIndex].zw * a_texcoord0) + BannerUVOffsetsAndScales[frameIndex].xy;
    v_texcoords.zw = (BannerUVOffsetsAndScales[0].zw * a_texcoord0) + BannerUVOffsetsAndScales[0].xy;
#if TINTING__ENABLED
    v_color0 = BannerColors[frameIndex];
    v_color0.a = frameIndex > 0 ? 0.0 : 1.0;
#endif
#endif //MATERIAL_ACTOR_BANNER_PREPASS

#if defined(MATERIAL_ACTOR_GLINT_PREPASS) || defined(MATERIAL_ACTOR_PATTERN_GLINT_PREPASS)
    v_texcoord0 = a_texcoord0;
    v_layerUV.xy = calculateLayerUV(a_texcoord0, UVAnimation.x, UVAnimation.z, UVScale.xy);
    v_layerUV.zw = calculateLayerUV(a_texcoord0, UVAnimation.y, UVAnimation.w, UVScale.xy);
#endif
#endif //!DEPTH_ONLY_PASS && !DEPTH_ONLY_OPAQUE_PASS

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

#if defined(MATERIAL_ACTOR_BANNER_PREPASS) || \
defined(MATERIAL_ACTOR_PATTERN_PREPASS) || \
defined(MATERIAL_ACTOR_PATTERN_GLINT_PREPASS)

uniform highp vec4 HudOpacity;
#endif

#if defined(MATERIAL_ACTOR_GLINT_PREPASS) || defined(MATERIAL_ACTOR_PATTERN_GLINT_PREPASS)
uniform highp vec4 GlintColor;
#endif

SAMPLER2D_HIGHP_AUTOREG(s_MatTexture);
SAMPLER2D_HIGHP_AUTOREG(s_MatTexture1);

#if defined(MATERIAL_ACTOR_MULTI_TEXTURE_PREPASS) || \
defined(MATERIAL_ACTOR_PATTERN_PREPASS) || \
defined(MATERIAL_ACTOR_PATTERN_GLINT_PREPASS)

SAMPLER2D_HIGHP_AUTOREG(s_MatTexture2);
#endif

#ifdef MATERIAL_ACTOR_PATTERN_GLINT_PREPASS
uniform highp vec4 PatternCount;
uniform highp vec4 PatternColors[7];
uniform highp vec4 PatternUVOffsetsAndScales[7];

vec4 getPatternAlbedo(int layer, vec2 texcoord) {
    vec2 tex = (PatternUVOffsetsAndScales[layer].zw * texcoord) + PatternUVOffsetsAndScales[layer].xy;
    vec4 color = PatternColors[layer];
    return texture2D(s_MatTexture2, tex) * color;
}
#endif

#if DEPTH_ONLY_PASS
void main() {
    vec4 albedo = getActorAlbedoNoColorChange(MatColor, s_MatTexture, s_MatTexture1, v_texcoord0);
    float alpha = mix(albedo.a, albedo.a * OverlayColor.a, TintedAlphaTestEnabled.x);
    if (shouldDiscard(albedo.rgb, alpha, ActorFPEpsilon.x)) discard;
    gl_FragColor = vec4_splat(1.0);
}
#elif DEPTH_ONLY_OPAQUE_PASS
void main() {
    gl_FragColor = vec4_splat(1.0);
}
#else

uniform highp vec4 BlockLightColor;
uniform highp vec4 TileLightIntensity;

#include "./lib/materials.glsl"

void main() {
    vec4 mers = vec4(0.0, 0.0, 1.0, 0.0);

#ifdef MATERIAL_ACTOR_BANNER_PREPASS
    vec4 albedo = getBannerAlbedo(v_color0, s_MatTexture, v_texcoords.zw, v_texcoords.xy);
    albedo.a *= HudOpacity.r;

    vec3 normal = gl_FrontFacing ? -v_normal : v_normal;
    normal = normalize(normal);
    getTexturePBRMaterials(s_MatTexture, v_texcoords.zw, v_tangent, v_bitangent, normal, mers);
#else
    vec3 normal = normalize(v_normal);
    getTexturePBRMaterials(v_texcoord0, v_tangent, v_bitangent, normal, mers);
#endif


#if defined(MATERIAL_ACTOR_MULTI_TEXTURE_PREPASS) || defined(MATERIAL_ACTOR_TINT_PREPASS)
    vec4 albedo = getActorAlbedoNoColorChange(MatColor, s_MatTexture, s_MatTexture1, v_texcoord0);
    albedo = applyChangeColor(albedo, ChangeColor, MultiplicativeTintColor.rgb, 0.0);

    float alpha = 0.0;
#ifdef MATERIAL_ACTOR_TINT_PREPASS
    albedo = applySecondColorTint(albedo, MultiplicativeTintColor.rgb, s_MatTexture1, v_texcoord0, alpha);
#else
    albedo = applyMultitextureAlbedo(albedo, ChangeColor, s_MatTexture1, s_MatTexture2, v_texcoord0, ActorFPEpsilon.x, alpha);
#endif
    albedo.rgb *= mix(vec3_splat(1.0), v_color0.rgb, ColorBased.x);
    albedo.rgb = mix(albedo.rgb, OverlayColor.rgb, OverlayColor.a);

#if GEOMETRY_PREPASS_ALPHA_TEST_PASS
    if (albedo.a < 0.5 && alpha < ActorFPEpsilon.x) discard;
#endif
#endif


#if defined(MATERIAL_ACTOR_PREPASS) || \
defined(MATERIAL_ACTOR_GLINT_PREPASS) || \
defined(MATERIAL_ACTOR_PATTERN_PREPASS) || \
defined(MATERIAL_ACTOR_PATTERN_GLINT_PREPASS)

    vec4 albedo = getActorAlbedoNoColorChange(MatColor, s_MatTexture, s_MatTexture1, v_texcoord0);

#if GEOMETRY_PREPASS_ALPHA_TEST_PASS || (defined(MATERIAL_ACTOR_PATTERN_PREPASS) && GEOMETRY_PREPASS_OPAQUE_PASS)
    float alpha = albedo.a;
    alpha = mix(alpha, alpha * OverlayColor.a, TintedAlphaTestEnabled.r);
    if (shouldDiscard(albedo.rgb, alpha, ActorFPEpsilon.r)) discard;
#endif

    albedo = applyChangeColor(albedo, ChangeColor, MultiplicativeTintColor.rgb, UseAlphaRewrite.r);
    albedo.rgb *= mix(vec3_splat(1.0), v_color0.rgb, ColorBased.r);
    albedo.rgb = mix(albedo.rgb, OverlayColor.rgb, OverlayColor.a);
#endif

#ifdef MATERIAL_ACTOR_PATTERN_GLINT_PREPASS
    LOOP
    for (int i = 0; i < int(PatternCount.x); i++) {
        vec4 pattern = getPatternAlbedo(i, v_texcoord0);
        albedo = mix(albedo, pattern, pattern.a);
    }
    albedo.a = 1.0;
#endif

#if defined(MATERIAL_ACTOR_GLINT_PREPASS) || defined(MATERIAL_ACTOR_PATTERN_GLINT_PREPASS)
    albedo.rgb = applyGlint(albedo.rgb, v_layerUV, s_MatTexture1, GlintColor);
#endif

    albedo.rgb *= 0.5; //decrease albedo brightness to match terrain

    vec3 lightColor = BlockLightColor.rgb;
    if ((lightColor.r + lightColor.g + lightColor.b) <= 0.0 && TileLightIntensity.x > 0.0) {
        float blm = TileLightIntensity.x * TileLightIntensity.x;
        lightColor = saturate(vec3(blm, blm * ((blm * 0.6 + 0.4) * 0.6 + 0.4), blm * ((blm * blm * 0.6) + 0.4)));
    }
    lightColor /= 6.0;
    float maxVal = ceil(saturate(max(max(lightColor.r, lightColor.g), lightColor.b)) * 255.0) / 255.0;
    lightColor /= maxVal;

    gl_FragData[0] = uvec4(pack2x8(mers.bg), pack2x8(lightColor.rg), pack2x8(vec2(lightColor.b, maxVal)), pack2x8(vec2(1.0, TileLightIntensity.y)));
    gl_FragData[1] = vec4(albedo.rgb, packMetalnessSubsurface(mers.r, mers.a));
    gl_FragData[2].xy = ndirToOctSnorm(normal);
    gl_FragData[2].zw = calculateMotionVector(v_worldPos, v_prevWorldPos - u_prevWorldPosOffset.xyz);
}
#endif //DEPTH_ONLY_OPAQUE_PASS

#endif //BGFX_SHADER_TYPE_FRAGMENT
