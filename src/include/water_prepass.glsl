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

    uvec2 data16 = uvec2(a_texcoord1 * 65535.0);
    uvec2 highByte = (data16 >> 8) & 0xFFu;
    uvec2 lowByte = data16 & 0xFFu;
    uvec2 mHighByte = highByte & 0xFFu;
    float lintensity = a_normal.w * 0.5 + 0.5;
    v_lightColor = vec3(mHighByte.x, lowByte.x, mHighByte.y) / 255.0 * lintensity * 6.0;
    v_lightmapUV = vec2(uvec2(data16.y >> 4, data16.y) & 15u) / 15.0;

    v_normal = mul(u_model[0], vec4(a_normal.xyz, 0.0)).xyz;
    v_tangent = mul(u_model[0], vec4(a_tangent.xyz, 0.0)).xyz;
    v_bitangent = mul(u_model[0], vec4(cross(a_normal.xyz, a_tangent.xyz) * a_tangent.w, 0.0)).xyz;
    v_worldPos = worldPos;
    vec4 clipPos = mul(u_viewProj, vec4(worldPos, 1.0));
    v_clipPos = clipPos;

    gl_Position = clipPos;
}

#endif //BGFX_SHADER_TYPE_VERTEX




///////////////////////////////////////////////////////////
// FRAGMENT/PIXEL SHADER
///////////////////////////////////////////////////////////
#if BGFX_SHADER_TYPE_FRAGMENT
#if DEPTH_ONLY_PASS
void main() {
    gl_FragColor = vec4_splat(1.0);
}
#elif DEPTH_AND_NORMAL_PASS
#include "./lib/froxel_util.glsl"
void main() {
    vec3 projPos = v_clipPos.xyz / v_clipPos.w;
    vec3 uvw = ndcToVolume(projPos);
    gl_FragData[0] = vec4(uvw.z, abs(dot(v_normal, normalize(-v_worldPos))), 0.0, 1.0);
}
#else

uniform highp vec4 WorldOrigin;
uniform highp vec4 Time;

#include "./lib/common.glsl"
#include "./lib/materials.glsl"
#include "./lib/water_wave.glsl"
#include "./lib/taau_util.glsl"

void main() {
    vec3 normal = gl_FrontFacing ? -v_normal : v_normal;
    normal = normalize(normal);
    mat3 tbn = mtxFromCols(normalize(v_tangent), normalize(v_bitangent), normal);

    vec2 waterPos = v_worldPos.xz - WorldOrigin.xz;
    vec3 waterNormal = getWaterNormal(waterPos, Time.x);
    waterNormal = mul(tbn, waterNormal);
    waterNormal = mix(normal, waterNormal, saturate(exp(-length(v_worldPos.xz) * 0.01)));

    vec3 lightColor = v_lightColor;
    if ((lightColor.r + lightColor.g + lightColor.b) <= 0.0 && v_lightmapUV.x > 0.0) {
        float blm = v_lightmapUV.x * v_lightmapUV.x;
        lightColor = saturate(vec3(blm, blm * ((blm * 0.6 + 0.4) * 0.6 + 0.4), blm * ((blm * blm * 0.6) + 0.4)));
    }
    lightColor /= 6.0;
    float maxVal = ceil(saturate(max(max(lightColor.r, lightColor.g), lightColor.b)) * 255.0) / 255.0;
    lightColor /= maxVal;

    gl_FragData[0] = uvec4(0, pack2x8(lightColor.rg), pack2x8(vec2(lightColor.b, maxVal)), pack2x8(vec2(1.0, v_lightmapUV.y)));
    gl_FragData[1] = vec4_splat(0.0);
    gl_FragData[2].xy = ndirToOctSnorm(waterNormal);
    gl_FragData[2].zw = calculateMotionVector(v_worldPos, v_worldPos - u_prevWorldPosOffset.xyz);
}
#endif //!DEPTH_AND_NORMAL_PASS
#endif //BGFX_SHADER_TYPE_FRAGMENT
