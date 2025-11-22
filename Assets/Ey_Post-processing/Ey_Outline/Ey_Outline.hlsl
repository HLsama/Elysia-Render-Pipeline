//Include
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
//引用关于BitTex相关的库，来拿到摄象机传来的图
#include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
#include "Assets/Library/FxLibrary.hlsl"

//Texture& Samplers
float4 _BlitTexture_TexelSize;
float4 _CameraNormalsTexture_TexelSize;
float4 _CameraDepthTexture_TexelSize;
TEXTURE2D_X_FLOAT(_CameraDepthTexture);
TEXTURE2D_X_FLOAT(_CameraNormalsTexture);
SAMPLER(sampler_CameraNormalsTexture);
SAMPLER(sampler_CameraDepthTexture);

//渲染相关参数
float _OutlineDepthThreshold;
float _OutlineNormalThreshold;

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

//获取源图
float4 GetSource(float2 uv)
{
    float4 col = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv);
    return col;
}
//深度图
float SampleSceneDepth(float2 uv)
{
    float Depth = SAMPLE_TEXTURE2D_X(_CameraDepthTexture,sampler_CameraDepthTexture,uv).r;
    return Depth;
}

float DepthCompare(float A ,float B,float T)
{
    return abs(A-B)>T?0:1;
}
float NormalCompare(float3 A ,float3 B,float T)
{
    return dot(A,B)<T?0:1;
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
//深度描边用片元着色器
float4 frag (v2f i) : SV_Target
{
    //采样数据
    float2 uv = UnityStereoTransformScreenSpaceTex(i.uv);
    float Depth = SampleSceneDepth(uv);
    Depth = LinearEyeDepth(Depth,_ZBufferParams);
    float4 nDirWS = SAMPLE_TEXTURE2D_X(_CameraNormalsTexture,sampler_CameraNormalsTexture,uv);
    nDirWS.rgb = EyUnpackNormal(nDirWS.rgb);
    float3 src = GetSource(uv);
    
    //深度边缘检测
    //采样周围深度
    float Depth1 = SAMPLE_TEXTURE2D_X(_CameraDepthTexture,sampler_CameraDepthTexture,uv+float2(_CameraNormalsTexture_TexelSize.x,0)).r;
    float Depth2 = SAMPLE_TEXTURE2D_X(_CameraDepthTexture,sampler_CameraDepthTexture,uv+float2(0,_CameraNormalsTexture_TexelSize.y)).r;
    float Depth3 = SAMPLE_TEXTURE2D_X(_CameraDepthTexture,sampler_CameraDepthTexture,uv+float2(-_CameraNormalsTexture_TexelSize.x,0)).r;
    float Depth4 = SAMPLE_TEXTURE2D_X(_CameraDepthTexture,sampler_CameraDepthTexture,uv+float2(0,-_CameraNormalsTexture_TexelSize.y)).r;
    Depth1 = LinearEyeDepth(Depth1,_ZBufferParams);
    Depth2 = LinearEyeDepth(Depth2,_ZBufferParams);
    Depth3 = LinearEyeDepth(Depth3,_ZBufferParams);
    Depth4 = LinearEyeDepth(Depth4,_ZBufferParams);
    float DepthOutline = DepthCompare(Depth,Depth1,_OutlineDepthThreshold)*DepthCompare(Depth,Depth2,_OutlineDepthThreshold)*DepthCompare(Depth,Depth3,_OutlineDepthThreshold)*DepthCompare(Depth,Depth4,_OutlineDepthThreshold);

    //法线边缘检测
    float4 nDirWS1 = SAMPLE_TEXTURE2D_X(_CameraNormalsTexture,sampler_CameraNormalsTexture,uv+float2(_CameraNormalsTexture_TexelSize.x,0));
    nDirWS1.rgb = EyUnpackNormal(nDirWS1.rgb);
    float4 nDirWS2 = SAMPLE_TEXTURE2D_X(_CameraNormalsTexture,sampler_CameraNormalsTexture,uv+float2(0,_CameraNormalsTexture_TexelSize.y));
    nDirWS2.rgb = EyUnpackNormal(nDirWS2.rgb);
    float4 nDirWS3 = SAMPLE_TEXTURE2D_X(_CameraNormalsTexture,sampler_CameraNormalsTexture,uv+float2(-_CameraNormalsTexture_TexelSize.x,0));
    nDirWS3.rgb = EyUnpackNormal(nDirWS3.rgb);
    float4 nDirWS4 = SAMPLE_TEXTURE2D_X(_CameraNormalsTexture,sampler_CameraNormalsTexture,uv+float2(0,-_CameraNormalsTexture_TexelSize.y));
    nDirWS4.rgb = EyUnpackNormal(nDirWS4.rgb);
    float NormalOutline = NormalCompare(nDirWS.rgb,nDirWS1.rgb,_OutlineNormalThreshold)*NormalCompare(nDirWS.rgb,nDirWS2.rgb,_OutlineNormalThreshold)*NormalCompare(nDirWS.rgb,nDirWS3.rgb,_OutlineNormalThreshold)*NormalCompare(nDirWS.rgb,nDirWS4.rgb,_OutlineNormalThreshold);
    

    
    float3 Outline = NormalOutline*DepthOutline;
    float3 RGB = Outline*src;
    return float4(NormalOutline,NormalOutline,NormalOutline,1);
}



