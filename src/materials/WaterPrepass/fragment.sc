$input v_tangent
$input v_bitangent
$input v_normal
$input v_clipPos
$input v_worldPos
$input v_lightColor
$input v_lightmapUV

#include "bgfx_shader.sh"
#if BGFX_SHADER_LANGUAGE_GLSL
precision highp int;
#endif
#include "water_prepass.glsl"
