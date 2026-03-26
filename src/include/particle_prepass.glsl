#include "./lib/taau_util.glsl"


///////////////////////////////////////////////////////////
// VERTEX SHADER
///////////////////////////////////////////////////////////
#if BGFX_SHADER_TYPE_VERTEX
void main() {
#if INSTANCING__ON
    vec3 worldPos = mul(mtxFromCols(i_data1, i_data2, i_data3, vec4(0.0, 0.0, 0.0, 1.0)), vec4(a_position, 1.0)).xyz;
#else
    vec3 worldPos = mul(u_model[0], vec4(a_position, 1.0)).xyz;
#endif

    v_color0 = a_color0;
    v_texcoord0 = a_texcoord0;

#if GEOMETRY_PREPASS_ALPHA_TEST_PASS
    //unpack block light color and lightmap
    uvec2 data16 = uvec2(a_texcoord1 * 65535.0) & 0xFFFFu;
    uint lowByte = data16.g & 0xFFu;
    v_coloredLighting = vec3(data16.r >> 8, data16.r & 0xFFu, data16.g >> 8) / 255.0;
    v_vanillaLighting = vec2(uvec2(lowByte >> 4, lowByte) & 15u) / 15.0;

    v_worldPos = worldPos;
    v_normal = a_normal.xyz;
    v_tangent = mul(u_model[0], vec4(a_tangent.xyz, 0.0)).xyz;
    v_bitangent = mul(u_model[0], vec4(cross(a_normal.xyz, a_tangent.xyz) * a_tangent.w, 0.0)).xyz;

    gl_Position = jitterVertexPosition(worldPos);
#else
    gl_Position = mul(u_viewProj, vec4(worldPos, 1.0));
#endif
}
#endif //BGFX_SHADER_TYPE_VERTEX




///////////////////////////////////////////////////////////
// FRAGMENT/PIXEL SHADER
///////////////////////////////////////////////////////////
#if BGFX_SHADER_TYPE_FRAGMENT
uniform highp vec4 MERSUniforms;
uniform highp vec4 PBRTextureFlags;

SAMPLER2D_HIGHP_AUTOREG(s_ParticleTexture);
SAMPLER2D_HIGHP_AUTOREG(s_MERSTexture);
SAMPLER2D_HIGHP_AUTOREG(s_NormalTexture);

#include "./lib/common.glsl"
#include "./lib/materials.glsl"

void main() {
    vec4 albedo = texture2D(s_ParticleTexture, v_texcoord0);
#if ALPHA_TEST_PASS || GEOMETRY_PREPASS_ALPHA_TEST_PASS
    if (albedo.a < 0.5) discard;
    albedo.a = 1.0;
#endif
    albedo *= v_color0;

#if GEOMETRY_PREPASS_ALPHA_TEST_PASS
    int pbrTextureFlags = int(PBRTextureFlags.r);

    vec4 mers = MERSUniforms;
    if ((pbrTextureFlags & kPBRTextureDataFlagHasMaterialTexture) == kPBRTextureDataFlagHasMaterialTexture) {
        vec4 mersTex = texture2D(s_MERSTexture, v_texcoord0);
        mers.rgb = mersTex.rgb;
        if ((pbrTextureFlags & kPBRTextureDataFlagHasSubsurfaceChannel) == kPBRTextureDataFlagHasSubsurfaceChannel) mers.a = mersTex.a;
    }

    vec3 normal = v_normal;
    if ((pbrTextureFlags & kPBRTextureDataFlagHasNormalTexture) == kPBRTextureDataFlagHasNormalTexture) {
        vec3 normalt = texture2D(s_NormalTexture, v_texcoord0).rgb * 2.0 - 1.0;
        mat3 tbn = mtxFromCols(normalize(v_tangent), normalize(v_bitangent), normal);
        normal = mul(tbn, normalt);
    }

    albedo.rgb *= 0.5; //decrease albedo brightness to match terrain

    vec3 lightColor = v_coloredLighting;
    if ((lightColor.r + lightColor.g + lightColor.b) <= 0.0 && v_vanillaLighting.x > 0.0) {
        float blm = v_vanillaLighting.x * v_vanillaLighting.x;
        lightColor = saturate(vec3(blm, blm * ((blm * 0.6 + 0.4) * 0.6 + 0.4), blm * ((blm * blm * 0.6) + 0.4)));
    }
    lightColor /= 6.0;
    float maxVal = ceil(saturate(max(max(lightColor.r, lightColor.g), lightColor.b)) * 255.0) / 255.0;
    lightColor /= maxVal;

    gl_FragData[0] = uvec4(pack2x8(mers.bg), pack2x8(lightColor.rg), pack2x8(vec2(lightColor.b, maxVal)), pack2x8(vec2(1.0, v_vanillaLighting.y)));
    gl_FragData[1] = vec4(albedo.rgb, packMetalnessSubsurface(mers.r, mers.a));
    gl_FragData[2].xy = ndirToOctSnorm(normal);
    gl_FragData[2].zw = calculateMotionVector(v_worldPos, v_worldPos - u_prevWorldPosOffset.xyz);
#else
    gl_FragData[0] = uvec4(0u, 0u, 0u, 0u);
    gl_FragData[1] = albedo;
    gl_FragData[2] = vec4_splat(0.0);
#endif
}

#endif //BGFX_SHADER_TYPE_FRAGMENT
