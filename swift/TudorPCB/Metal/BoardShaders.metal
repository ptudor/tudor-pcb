#include <metal_stdlib>
using namespace metal;

struct BoardVertex {
    float3 position;
    float3 normal;
    float2 uv;
    uint material;
    uint padding;
};

struct BoardUniforms {
    float4x4 model;
    float4x4 viewProjection;
    float4 lightDirection;
};

struct BoardVarying {
    float4 position [[position]];
    float3 normal;
    float2 uv;
    uint material [[flat]];
};

vertex BoardVarying board_vertex(
    uint vertexID [[vertex_id]],
    constant BoardVertex *vertices [[buffer(0)]],
    constant BoardUniforms &uniforms [[buffer(1)]]) {
    BoardVertex input = vertices[vertexID];
    float4 world = uniforms.model * float4(input.position, 1.0);
    BoardVarying out;
    out.position = uniforms.viewProjection * world;
    out.normal = normalize((uniforms.model * float4(input.normal, 0.0)).xyz);
    out.uv = input.uv;
    out.material = input.material;
    return out;
}

fragment float4 board_fragment(
    BoardVarying in [[stage_in]],
    texture2d<float> topTexture [[texture(0)]],
    texture2d<float> bottomTexture [[texture(1)]],
    texture2d<float> maskTexture [[texture(2)]],
    sampler textureSampler [[sampler(0)]],
    constant BoardUniforms &uniforms [[buffer(0)]]) {
    if (in.material == 2) {
        float3 edge = float3(0.18, 0.14, 0.075);
        float diffuse = 0.45 + 0.45 * max(0.0, dot(normalize(in.normal), normalize(uniforms.lightDirection.xyz)));
        return float4(edge * diffuse, 1.0);
    }

    float mask = maskTexture.sample(textureSampler, in.uv).a;
    if (mask < 0.08) discard_fragment();
    float4 surface = in.material == 0
        ? topTexture.sample(textureSampler, in.uv)
        : bottomTexture.sample(textureSampler, in.uv);
    if (surface.a < 0.08) discard_fragment();

    float3 normal = normalize(in.normal);
    float3 light = normalize(uniforms.lightDirection.xyz);
    float diffuse = max(0.0, dot(normal, light));
    float rim = pow(1.0 - abs(normal.z), 3.0) * 0.08;
    float lighting = 0.62 + diffuse * 0.42 + rim;
    return float4(surface.rgb * lighting, surface.a);
}
