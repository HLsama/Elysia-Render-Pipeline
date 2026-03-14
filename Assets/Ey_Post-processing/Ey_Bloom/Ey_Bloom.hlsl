//Include
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
//引用关于BitTex相关的库，来拿到摄象机传来的图
#include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
#define EX 2.718281828459045

//Texture& Samplers
float4 _BlitTexture_TexelSize;
TEXTURE2D_X(_PrevMip);
SAMPLER(sampler_PrevMip);
TEXTURE2D_X(_BloomTex);
SAMPLER(sampler_BloomTex);
//传来参数
float _luminanceThreshole;
float _BloomIntensity;
//结构体
struct appdata
{
    uint vertexID : SV_VertexID;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct v2f
{
    float2 uv : TEXCOORD0;
    float4 vertex : SV_POSITION;
};

half3 DecodeHDR(half4 color)
{
    #if UNITY_COLORSPACE_GAMMA
    color.xyz *= color.xyz; // γ to linear
    #endif

    #if _USE_RGBM
    return DecodeRGBM(color);
    #else
    return color.xyz;
    #endif
}

half4 EncodeHDR(half3 color)
{
    #if _USE_RGBM
    half4 outColor = EncodeRGBM(color);
    #else
    half4 outColor = half4(color, 1.0);
    #endif

    #if UNITY_COLORSPACE_GAMMA
    return half4(sqrt(outColor.xyz), outColor.w); // linear to γ
    #else
    return outColor;
    #endif
}

//高斯函数一维
float GaussWeight1D(float x,float sigma)
{
    float sigma_2 = pow(sigma,2);
    float a = -(x*x)/(2.0*sigma_2);
    float Gauss = pow(EX,a)/sqrt(2.0*PI*sigma_2);
    return Gauss;
}
//高斯函数二维
float GaussWeight2D(float x, float y, float sigma)
{
    //float PI = 3.14159265358;
    float sigma_2 = pow(sigma, 2);

    float a = -(x*x + y*y) / (2.0 * sigma_2);
    return pow(EX, a) / (2.0 * 3.14159265358 * sigma_2);
}
//暂时不知道干什么的
float3 ACESToneMapping(float3 color, float adapted_lum)
{
    const float A = 2.51f;
    const float B = 0.03f;
    const float C = 2.43f;
    const float D = 0.59f;
    const float E = 0.14f;

    color *= adapted_lum;
    return (color * (A * color + B)) / (color * (C * color + D) + E);
}
//通用顶点着色器
v2f vert (appdata v)
{
    v2f o;
    o.vertex = GetFullScreenTriangleVertexPosition(v.vertexID);
    //参考了官方bloom的uv拿法
    float2 uv = GetFullScreenTriangleTexCoord(v.vertexID);
    o.uv= uv * _BlitScaleBias.xy + _BlitScaleBias.zw;
    return o;
}

//亮部筛选
float4 eyPrefilterfrag (v2f i) : SV_Target
{
    //采样数据
    float2 uv = UnityStereoTransformScreenSpaceTex(i.uv);
    float3 col = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv);
    float lum = dot(float3(0.2126, 0.7152, 0.0722), col.rgb);//筛选亮部
    float3 lumcol = lum>_luminanceThreshole?col:float3(0,0,0);
    //col = max(col-_luminanceThreshole,0);
    
    return EncodeHDR(lumcol);
}
//尝试用unity的，预计算的高斯算法（横向）
float4 eyGaussBlurfragHUnity (v2f i) : SV_Target
{
    float texelSize = _BlitTexture_TexelSize.x * 2.0;
    float2 uv = UnityStereoTransformScreenSpaceTex(i.uv);

    // 9-tap gaussian blur on the downsampled source
    half3 c0 = DecodeHDR(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv - float2(texelSize * 4.0, 0.0)));
    half3 c1 = DecodeHDR(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv - float2(texelSize * 3.0, 0.0)));
    half3 c2 = DecodeHDR(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv - float2(texelSize * 2.0, 0.0)));
    half3 c3 = DecodeHDR(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv - float2(texelSize * 1.0, 0.0)));
    half3 c4 = DecodeHDR(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv                               ));
    half3 c5 = DecodeHDR(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2(texelSize * 1.0, 0.0)));
    half3 c6 = DecodeHDR(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2(texelSize * 2.0, 0.0)));
    half3 c7 = DecodeHDR(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2(texelSize * 3.0, 0.0)));
    half3 c8 = DecodeHDR(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2(texelSize * 4.0, 0.0)));

    half3 color = c0 * 0.01621622 + c1 * 0.05405405 + c2 * 0.12162162 + c3 * 0.19459459
                + c4 * 0.22702703
                + c5 * 0.19459459 + c6 * 0.12162162 + c7 * 0.05405405 + c8 * 0.01621622;

    return EncodeHDR(color);
}

float4 eyGaussBlurfragVUnity (v2f i) : SV_Target
{
    float texelSize = _BlitTexture_TexelSize.y;
    float2 uv = UnityStereoTransformScreenSpaceTex(i.uv);

    // Optimized bilinear 5-tap gaussian on the same-sized source (9-tap equivalent)
    half3 c0 = DecodeHDR(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv - float2(0.0, texelSize * 3.23076923)));
    half3 c1 = DecodeHDR(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv - float2(0.0, texelSize * 1.38461538)));
    half3 c2 = DecodeHDR(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv                                      ));
    half3 c3 = DecodeHDR(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2(0.0, texelSize * 1.38461538)));
    half3 c4 = DecodeHDR(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2(0.0, texelSize * 3.23076923)));

    half3 color = c0 * 0.07027027 + c1 * 0.31621622
                + c2 * 0.22702703
                + c3 * 0.31621622 + c4 * 0.07027027;

    return EncodeHDR(color);
}
//直接用卷积核为4，西格玛值为1的高斯模糊做的上采样
float4 eyMipUpfrag (v2f i) : SV_Target
{
    float2 uv = UnityStereoTransformScreenSpaceTex(i.uv);
    float3 highMip = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv).rgb;
    float3 lowMip = SAMPLE_TEXTURE2D_X(_PrevMip,sampler_PrevMip,uv).rgb;
    float3 curr_mip = float3(0, 0, 0);
    float3 prev_mip = float3(0, 0, 0);
    int r = 4;
    float weight = 0.0;
    float weight2 = 0.0;
    float2 prev_stride = 0.5 * _BlitTexture_TexelSize.xy;   
    float2 curr_stride = 1.0 * _BlitTexture_TexelSize.xy; 
    for(int i=-r;i<=r;i++)
    {
        for(int j=-r; j<=r; j++)
        {
            float w = GaussWeight2D(i, j, 1);
            float2 texcoord = uv + float2(i,j)*curr_stride;
            curr_mip += SAMPLE_TEXTURE2D_X(_BlitTexture,sampler_LinearClamp,texcoord).rgb*w;
            weight +=w;
        }
    }
    curr_mip /= weight;

    for(int i=-r;i<=r;i++)
    {
        for(int j=-r; j<=r; j++)
        {
            float w = GaussWeight2D(i, j, 1);
            float2 texcoord = uv + float2(i,j)*prev_stride;
            prev_mip += SAMPLE_TEXTURE2D_X(_PrevMip,sampler_PrevMip,texcoord).rgb*w;
            weight2 +=w;
        }
    }
    prev_mip /= weight2;

    float3 color = prev_mip+curr_mip;

    return EncodeHDR(highMip+lowMip);
}
//混合原图
float4 eyBlendfrag (v2f i) : SV_Target
{
    //测试
    float2 uv = UnityStereoTransformScreenSpaceTex(i.uv);
    float3 BloomTex = SAMPLE_TEXTURE2D_X(_BloomTex, sampler_PointClamp, uv)*_BloomIntensity;
    float3 BlitTexture = SAMPLE_TEXTURE2D_X(_BlitTexture,sampler_LinearClamp,uv);//采样前屏幕纹理
    BloomTex = ACESToneMapping(BloomTex, 1.0);
    float g = 1.0 / 2.2;
    BloomTex = saturate(pow(BloomTex, float3(g, g, g)));
    BlitTexture.rgb += BloomTex;
    return float4(BlitTexture,1.0);
}
float4 eyFirstDownfrag (v2f i) : SV_Target
{
    //测试
    float2 uv = UnityStereoTransformScreenSpaceTex(i.uv);
    float3 color = float3(0,0,0);
    int r = 4;
    float weight = 0.0;
    float2 curr_stride = 1.0 * _BlitTexture_TexelSize.xy;

    for(int i=-r; i<=r; i++)
    {
        for(int j=-r; j<=r; j++)
        {
            float2 coord = uv + float2(i, j)*curr_stride;
            float3 c = SAMPLE_TEXTURE2D_X(_BlitTexture,sampler_LinearClamp,coord);
            float luma = dot(float3(0.2126, 0.7152, 0.0722), c);  // 亮度

            float w1 = GaussWeight2D(i, j, 1);
            float w2 = 1.0 / (1.0 + luma);
            float w = w1 * w2;

            color += c * w;
            weight += w;
        }
    }
    color /= weight;
    return float4(color,1.0);
}