///////////////////////////////////////////////////////////
// VERTEX SHADER
///////////////////////////////////////////////////////////
#if BGFX_SHADER_TYPE_VERTEX
void main() {
    v_texcoord0 = a_texcoord0;
    gl_Position = vec4(a_position.xy * 2.0 - 1.0, 0.0, 1.0);
}
#endif




///////////////////////////////////////////////////////////
// FRAGMENT/PIXEL SHADER
///////////////////////////////////////////////////////////
#if BGFX_SHADER_TYPE_FRAGMENT
uniform highp vec4 TonemapParams0;
uniform highp vec4 ExposureCompensation;
uniform highp vec4 LuminanceMinMaxAndWhitePointAndMinWhitePoint;

SAMPLER2D_HIGHP_AUTOREG(s_ColorTexture);
SAMPLER2D_HIGHP_AUTOREG(s_PreExposureLuminance);
SAMPLER2D_HIGHP_AUTOREG(s_AverageLuminance);
SAMPLER2D_HIGHP_AUTOREG(s_CustomExposureCompensation);
SAMPLER2D_HIGHP_AUTOREG(s_RasterizedColor);

#include "./lib/common.glsl"

// Minimal AgX approximation
// https://iolite-engine.com/blog_posts/minimal_agx_implementation

// Mean error^2: 1.85907662e-06
vec3 agxDefaultContrastApprox(vec3 x) {
    vec3 x2 = x * x;
    vec3 x4 = x2 * x2;
    vec3 x6 = x4 * x2;

    return - 17.86  * x6 * x
           + 78.01  * x6
           - 126.7  * x4 * x
           + 92.06  * x4
           - 28.72  * x2 * x
           + 4.361  * x2
           - 0.1718 * x
           + 0.002857;
}

vec3 agx(vec3 val) {
    mat3 agx_mat = mtxFromCols(
        vec3(0.842479062253094, 0.0423282422610123, 0.0423756549057051),
        vec3(0.0784335999999992,  0.878468636469772,  0.0784336),
        vec3(0.0792237451477643, 0.0791661274605434, 0.879142973793104)
    );

    CONST(float) min_ev = -12.47393f;
    CONST(float) max_ev = 4.026069f;

    // Input transform (inset)
    val = mul(agx_mat, val);

    // Log2 space encoding
    val = clamp(log2(val), min_ev, max_ev);
    val = (val - min_ev) / (max_ev - min_ev);

    // Apply sigmoid function approximation
    val = agxDefaultContrastApprox(val);
    return val;
}

vec3 agxEotf(vec3 val) {
    mat3 agx_mat_inv = mtxFromCols(
        vec3(1.19687900512017, -0.0528968517574562, -0.0529716355144438),
        vec3(-0.0980208811401368, 1.15190312990417, -0.0980434501171241),
        vec3(-0.0990297440797205, -0.0989611768448433, 1.15107367264116)
    );

    // Inverse input transform (outset)
    val = mul(agx_mat_inv, val);

    // sRGB IEC 61966-2-1 2.2 Exponent Reference EOTF Display
    // NOTE: We're linearizing the output here. Comment/adjust when
    // *not* using a sRGB render target
    // val = pow(val, vec3(2.2));
    return val;
}

vec3 agxLook(vec3 val) {
    vec3 offset = vec3_splat(0.0);
    vec3 slope = vec3_splat(1.0);
    vec3 power = vec3_splat(1.3);
    float sat = 1.05;

    // ASC CDL
    val = pow(val * slope + offset, power);
    float luma = dot(val, vec3(0.2126, 0.7152, 0.0722));
    return luma + sat * (val - luma);
}

void main() {
    vec3 inputColor = texture2D(s_ColorTexture, v_texcoord0).rgb;
    inputColor = max(inputColor, vec3_splat(0.0));

    // deobfuscated from vanilla material
    if (TonemapParams0.b > 0.0) {
        float preExposureLum = texture2D(s_PreExposureLuminance, vec2_splat(0.5)).r;
        inputColor = inputColor / vec3_splat((MIDDLE_GRAY / preExposureLum) + EPSILON);
    }

    float refLuminance = MIDDLE_GRAY;
    if (ExposureCompensation.b > 0.5) {
        float avgLum = texture2D(s_AverageLuminance, vec2_splat(0.5)).r;
        refLuminance = clamp(avgLum, LuminanceMinMaxAndWhitePointAndMinWhitePoint.r, LuminanceMinMaxAndWhitePointAndMinWhitePoint.g);
    }

    int exposureMode = int(ExposureCompensation.r);
    float exposureValue = ExposureCompensation.g; //manual
    if (exposureMode > 0 && exposureMode < 2) {
        //automatic
        exposureValue = 1.03 - (2.0 / ((0.43429 * log(refLuminance + 1.0)) + 2.0));
    } else if (exposureMode > 1) {
        //custom
        float lumMin = LuminanceMinMaxAndWhitePointAndMinWhitePoint.r;
        float lumMax = LuminanceMinMaxAndWhitePointAndMinWhitePoint.g;
        float t = (lumMin == lumMax) ? 0.5 : ((log2(refLuminance) + 3.0) - (log2(lumMin) + 3.0)) / ((log2(lumMax) + 3.0) - (log2(lumMin) + 3.0));
        exposureValue = texture2D(s_CustomExposureCompensation, vec2(t, 0.5)).r;
    }
    float exposure = (MIDDLE_GRAY / refLuminance) * exposureValue;

    vec3 outColor = inputColor * exposure;
    vec4 rasterColor = texture2D(s_RasterizedColor, v_texcoord0);
    outColor = mix(outColor, rasterColor.rgb, rasterColor.a);

    outColor *= 2.0; //extra exposure

    outColor = agx(outColor);
    outColor = agxLook(outColor);
    outColor = agxEotf(outColor);

    outColor = saturate(outColor);

    gl_FragColor = vec4(outColor, 1.0);
}
#endif //BGFX_SHADER_TYPE_FRAGMENT
