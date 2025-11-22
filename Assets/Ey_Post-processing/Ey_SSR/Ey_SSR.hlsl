//Include
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
//引用关于BitTex相关的库，来拿到摄象机传来的图
#include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
#include "Assets/Library/FxLibrary.hlsl"

//Texture& Samplers
float4 _BlitTexture_TexelSize;
TEXTURE2D_X_FLOAT(_CameraDepthTexture);
TEXTURE2D_X_FLOAT(_CameraNormalsTexture);
TEXTURE2D_X_FLOAT(_GBuffer0);
TEXTURE2D_X_FLOAT(_GBuffer1);
TEXTURE2D_X_FLOAT(_GBuffer2);
TEXTURE2D_X_FLOAT(_SrcTexture);
SamplerState my_point_clamp_sampler;
SAMPLER(sampler_CameraNormalsTexture);
SAMPLER(sampler_CameraDepthTexture);
Texture2D _HierarchicalZBufferTexture;

// Params
//重构世界坐标相关参数
float4 _CameraViewTopLeftCorner;
float4 _CameraViewXExtent;
float4 _CameraViewYExtent;
float4 _ProjectionParams2;
//光线步进相关参数
float _Stride;//步幅
float _Thickness;//厚度
float _StepCount;//最大步进次数
float _MaxDistance;//最大步进长度
float4 _SourceSize;//原图尺寸
float _MipCount2;
//HiZ相关参数
float _HierarchicalZBufferTextureFromMipLevel;
float _HierarchicalZBufferTextureToMipLevel;
float _MaxHierarchicalZBufferTextureMipLevel;


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

//计算相对于摄象机的偏移值
float3 ReconstructViewPos(float2 uv,float Depth)
{
    uv.y = 1-uv.y;

    float zSize = Depth*_ProjectionParams2.x;
    float3 viewPos = _CameraViewTopLeftCorner.xyz+_CameraViewXExtent*uv.x+_CameraViewYExtent*uv.y;
    return zSize*viewPos;
}

//每步步进的uv与深度
void ReconstructUVAndDepth(float3 wpos, out float2 uv, out float depth)
{  
    float4 cpos = mul(UNITY_MATRIX_VP, wpos);  
    uv = float2(cpos.x, cpos.y * _ProjectionParams.x) / cpos.w * 0.5 + 0.5;  
    depth = cpos.w;  
}

//变换坐标到屏幕空间
float4 TransformViewToHScreen(float3 vpos, float2 screenSize)
{  
    float4 cpos = mul(UNITY_MATRIX_P, vpos);  
    cpos.xy = float2(cpos.x, cpos.y * _ProjectionParams.x) * 0.5 + 0.5 * cpos.w;  
    cpos.xy *= screenSize;  
    return cpos;  
}  
//交换数据
void swap(inout float v0, inout float v1)
{  
    float temp = v0;  
    v0 = v1;    
    v1 = temp;
}
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
float4 GetHiZSoure(float2 uv,float2 offset = 0,float mipLevel = 0)
{
    offset *= _SourceSize.zw;
    return SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearRepeat, uv + offset, mipLevel);
}
// jitter dither map
static float dither[16] = {
    0.0, 0.5, 0.125, 0.625,
    0.75, 0.25, 0.875, 0.375,
    0.187, 0.687, 0.0625, 0.562,
    0.937, 0.437, 0.812, 0.312
};
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

//SSR用片源着色器
float4 SSRfrag (v2f i) : SV_Target
{
    //采样数据
    float2 uv = UnityStereoTransformScreenSpaceTex(i.uv);
    float Depth = SAMPLE_TEXTURE2D_X(_CameraDepthTexture,sampler_CameraDepthTexture,uv).r;
    Depth = LinearEyeDepth(Depth,_ZBufferParams);
    float3 Normal = SAMPLE_TEXTURE2D_X(_CameraNormalsTexture,sampler_CameraNormalsTexture,uv);
    float4 col = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv);//采样前屏幕纹理
    //深度图还原世界坐标
    float3 viewPos = ReconstructViewPos(uv,Depth);
    float3 posWS = _WorldSpaceCameraPos+viewPos;
    //视空间反射方向
    float3 vDir = normalize(viewPos);
    float3 vrDir = TransformWorldToViewDir(normalize(reflect(vDir,Normal)));

    //视空间的光线步进
    /*UNITY_LOOP
    for(int i=0;i<100;i++)
    {
        float3 viewPos2 = viewPos+vrDir*i*_Stride;
        float2 uv2;  
        float stepDepth;  
        ReconstructUVAndDepth(viewPos2, uv2, stepDepth);
        float stepRawDepth = SAMPLE_TEXTURE2D_X(_CameraDepthTexture,sampler_CameraDepthTexture,uv2).r;  
        float stepSurfaceDepth = LinearEyeDepth(stepRawDepth, _ZBufferParams);  
        if (stepSurfaceDepth < stepDepth && stepDepth < stepSurfaceDepth + _Thickness)
            return SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv2);  
    }
    return float4(0,0,0,1);*/



    
    //屏幕空间的光线步进（DDA画线法）
    //首先规定最大步进长度（自定义最大步进终点，这样才能DDA画线）
    float magnitude = _MaxDistance;
    float3 startView = TransformWorldToView(posWS);//视空间起点
    float end = startView.z + vrDir.z * magnitude;
    if (end > -_ProjectionParams.y)
        magnitude = (-_ProjectionParams.y - startView.z) / vrDir.z;
    float3 endView = startView+vrDir*magnitude;//视空间终点
    float4 startHScreen = TransformViewToHScreen(startView, _SourceSize.xy);//屏幕空间起点
    float4 endHScreen = TransformViewToHScreen(endView, _SourceSize.xy);//屏幕空间终点
    //1/k
    float startK = 1.0/startHScreen.w;
    float endK = 1.0/endHScreen.w;
    //与之前的屏幕坐标有什么区别？？？
    float2 startScreen = startHScreen.xy*startK;
    float2 endScreen = endHScreen.xy * endK;

    //齐次除法视坐标？？？？
    float3 startQ = startView*startK;
    float3 endQ = endView*endK;
    //斜率切换xy
    float2 diff = endScreen-startScreen;
    bool permute = false;
    if(abs(diff.x)<abs(diff.y))
    {
        permute = true;
        diff = diff.yx;
        startScreen = startScreen.yx;
        endScreen = endScreen.yx;
    }
    //计算屏幕坐标，齐次坐标，inverse-w的线性增量
    float dir = sign(diff.x);
    float invdx = dir/diff.x;
    float2 dp = float2(dir,invdx*diff.y);//步进方向
    float3 dq = (endQ-startQ)*invdx;
    float dk = (endK-startK)*invdx;

    dp *=_Stride;//步进方向*距离
    dq *=_Stride;
    dk *=_Stride;
    //缓存当前深度和位置(为什么这些都是同一深度）
    float rayZMin = startView.z;  
    float rayZMax = startView.z;  
    float preZ = startView.z;

    float2 P = startScreen;
    float3 Q = startQ;
    float K = startK;
    
    end = endScreen.x * dir;
    //屏幕空间光线步进
    UNITY_LOOP
    for (int i =0;i<_StepCount&&P.x*dir<=end;i++)
    {
        //步进
        P +=dp;//屏幕空间步进一个像素
        Q.z +=dq.z;//深度步进
        K +=dk;//K值也跟着增加
        //步进前后两点的深度
        rayZMin = preZ;
        rayZMax = (dq.z*0.5+Q.z)/(dk*0.5+K);
        preZ = rayZMax;
        if(rayZMin>rayZMax)
        {
            swap(rayZMin, rayZMax);  
        }
        //得到交点UV
        float2 hitUV = permute?P.yx:P;
        hitUV *=_SourceSize.zw;
        if(any(hitUV<0.0)||any(hitUV>1.0))
        {
            return float4(col);
        }
        float surfaceDepth = -LinearEyeDepth(SampleSceneDepth(hitUV), _ZBufferParams);
        bool isBehind = (rayZMin + 0.1 <= surfaceDepth);//防止步进步数过小，自反射；
        bool intersecting = isBehind && (rayZMax >= surfaceDepth - _Thickness);
        if (intersecting)
        {
            return GetSource(hitUV)+col; 
        }
    }
    return float4(col);
}
//用HiZ优化的SSR
float4 HiZSSRfrag (v2f i) : SV_Target
{
    //采样数据
    float2 uv = UnityStereoTransformScreenSpaceTex(i.uv);
    float Depth = SAMPLE_TEXTURE2D_X(_CameraDepthTexture,sampler_CameraDepthTexture,uv).r;
    Depth = LinearEyeDepth(Depth,_ZBufferParams);
    float4 NormalTEX = SAMPLE_TEXTURE2D_X(_CameraNormalsTexture,sampler_CameraNormalsTexture,uv);
    float Mask= NormalTEX.a>0.9?1:0;//角色与场景的遮罩
    float3 Normal = EyUnpackNormal(NormalTEX.rgb);
    float4 col = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv);//采样前屏幕纹理
    //深度图还原世界坐标
    float3 viewPos = ReconstructViewPos(uv,Depth);
    float3 posWS = _WorldSpaceCameraPos+viewPos;
    //视空间反射方向
    float3 vDir = normalize(viewPos);
    float3 vrDir = TransformWorldToViewDir(normalize(reflect(vDir,Normal)));

    //视空间的光线步进
    /*UNITY_LOOP
    for(int i=0;i<100;i++)
    {
        float3 viewPos2 = viewPos+vrDir*i*_Stride;
        float2 uv2;  
        float stepDepth;  
        ReconstructUVAndDepth(viewPos2, uv2, stepDepth);
        float stepRawDepth = SAMPLE_TEXTURE2D_X(_CameraDepthTexture,sampler_CameraDepthTexture,uv2).r;  
        float stepSurfaceDepth = LinearEyeDepth(stepRawDepth, _ZBufferParams);  
        if (stepSurfaceDepth < stepDepth && stepDepth < stepSurfaceDepth + _Thickness)
            return SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv2);  
    }
    return float4(0,0,0,1);*/



    
    //屏幕空间的光线步进（DDA画线法）
    //首先规定最大步进长度（自定义最大步进终点，这样才能DDA画线）
    float magnitude = _MaxDistance;
    float3 startView = TransformWorldToView(posWS);//视空间起点
    float end = startView.z + vrDir.z * magnitude;
    if (end > -_ProjectionParams.y)
        magnitude = (-_ProjectionParams.y - startView.z) / vrDir.z;
    float3 endView = startView+vrDir*magnitude;//视空间终点
    float4 startHScreen = TransformViewToHScreen(startView, _SourceSize.xy);//屏幕空间起点
    float4 endHScreen = TransformViewToHScreen(endView, _SourceSize.xy);//屏幕空间终点
    //1/k
    float startK = 1.0/startHScreen.w;
    float endK = 1.0/endHScreen.w;
    //与之前的屏幕坐标有什么区别？？？
    float2 startScreen = startHScreen.xy*startK;
    float2 endScreen = endHScreen.xy * endK;

    //齐次除法视坐标？？？？
    float3 startQ = startView*startK;
    float3 endQ = endView*endK;
    //斜率切换xy
    float2 diff = endScreen-startScreen;
    bool permute = false;
    if(abs(diff.x)<abs(diff.y))
    {
        permute = true;
        diff = diff.yx;
        startScreen = startScreen.yx;
        endScreen = endScreen.yx;
    }
    //计算屏幕坐标，齐次坐标，inverse-w的线性增量
    float dir = sign(diff.x);
    float invdx = dir/diff.x;
    float2 dp = float2(dir,invdx*diff.y);//步进方向
    float3 dq = (endQ-startQ)*invdx;
    float dk = (endK-startK)*invdx;

    dp *=_Stride;//步进方向*距离
    dq *=_Stride;
    dk *=_Stride;
    //缓存当前深度和位置(为什么这些都是同一深度）
    float rayZMin = startView.z;  
    float rayZMax = startView.z;  
    float preZ = startView.z;

    int mipLevel = 0.0;
    //float2 hitUV = 0.0;

    float2 P = startScreen;
    float3 Q = startQ;
    float K = startK;
    /*// Binary抖动
    float2 ditherUV = fmod(P, 4);
    float jitter = lerp(1, dither[ditherUV.x * 3 + ditherUV.y],float3(0.2,0,1));
    P += dp * jitter;
    Q += dq * jitter;
    K += dk * jitter;*/

    //准备光线步进结果
    if(Mask>0)
    {
        //屏幕空间光线步进
        UNITY_LOOP
        for (int i =0;i<_StepCount;i++)
        {
            //步进
            P +=dp*exp2(mipLevel);//屏幕空间步进一个像素
            Q +=dq*exp2(mipLevel);//深度步进
            K +=dk*exp2(mipLevel);//K值也跟着增加
            //步进前后两点的深度
            rayZMin = preZ;
            rayZMax = (dq.z*exp2(mipLevel)*0.5+Q.z)/(dk*exp2(mipLevel)*0.5+K);
            preZ = rayZMax;
            if(rayZMin>rayZMax)
            {
                swap(rayZMin, rayZMax);  
            }
            //得到交点UV
            float2 hitUV = permute?P.yx:P;
            hitUV *=_SourceSize.zw;
            if(any(hitUV<0.0)||any(hitUV>1.0))
            {
                return float4(0,0,0,1);
            }
            float rawDepth = SAMPLE_TEXTURE2D_X_LOD(_HierarchicalZBufferTexture, sampler_PointClamp, hitUV, mipLevel).r;
            float surfaceDepth = -LinearEyeDepth(rawDepth, _ZBufferParams);
            bool isBehind = rayZMin+0.01 <= surfaceDepth;//防止步进步数过小，自反射；
            if (!isBehind)
            {
                mipLevel = min(mipLevel + 1, _MaxHierarchicalZBufferTextureMipLevel);
            }
            else
            {
                if (mipLevel == 0)
                {
                    if (abs(surfaceDepth - rayZMax) < _Thickness)
                    {
                        return (GetSource(hitUV)+col)/(i+1);
                    }
                }
                else
                {
                    P -= dp * exp2(mipLevel);
                    Q -= dq * exp2(mipLevel);
                    K -= dk * exp2(mipLevel);
                    preZ = Q.z / K;
                    mipLevel--;
                }
            }
        }
    }
    return float4(0,0,0,1);
}
//生成HiZ的深度图用片源着色器
float4 HiZfrag (v2f i) : SV_Target
{
    float2 uv = i.uv;

    float4 minDepth = float4(
        GetHiZSoure(uv, float2(-1, -1), _HierarchicalZBufferTextureFromMipLevel).r,
        GetHiZSoure(uv, float2(-1, 1), _HierarchicalZBufferTextureFromMipLevel).r,
        GetHiZSoure(uv, float2(1, -1), _HierarchicalZBufferTextureFromMipLevel).r,
        GetHiZSoure(uv, float2(1, 1), _HierarchicalZBufferTextureFromMipLevel).r
    );
    float MaxDepth = max(max(minDepth.r, minDepth.g), max(minDepth.b, minDepth.a));
    return MaxDepth;
}
//横向的高斯模糊
float4 GaussBlurHorizontalfrag (v2f i) : SV_Target
{
    float texelSize = _BlitTexture_TexelSize.x * 2.0;
    float2 uv = UnityStereoTransformScreenSpaceTex(i.uv);

    // 9-tap gaussian blur on the downsampled source
    float3 c0 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv - float2(texelSize * 4.0, 0.0));
    float3 c1 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv - float2(texelSize * 3.0, 0.0));
    float3 c2 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv - float2(texelSize * 2.0, 0.0));
    float3 c3 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv - float2(texelSize * 1.0, 0.0));
    float3 c4 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv                               );
    float3 c5 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2(texelSize * 1.0, 0.0));
    float3 c6 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2(texelSize * 2.0, 0.0));
    float3 c7 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2(texelSize * 3.0, 0.0));
    float3 c8 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2(texelSize * 4.0, 0.0));

    float3 color = c0 * 0.01621622 + c1 * 0.05405405 + c2 * 0.12162162 + c3 * 0.19459459
                + c4 * 0.22702703
                + c5 * 0.19459459 + c6 * 0.12162162 + c7 * 0.05405405 + c8 * 0.01621622;

    return float4(color,1.0);
}
//纵向的高斯模糊(在进行纵向的高斯模糊时，进行环境光的计算与叠加)
float4 GaussBlurVerticalfrag (v2f i) : SV_Target
{
    //纵向的高斯模糊
    float texelSize = _BlitTexture_TexelSize.y;
    float2 uv = UnityStereoTransformScreenSpaceTex(i.uv);

    // Optimized bilinear 5-tap gaussian on the same-sized source (9-tap equivalent)
    float3 c0 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv - float2(0.0, texelSize * 3.23076923));
    float3 c1 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv - float2(0.0, texelSize * 1.38461538));
    float3 c2 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv                                      );
    float3 c3 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2(0.0, texelSize * 1.38461538));
    float3 c4 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2(0.0, texelSize * 3.23076923));

    float3 color = c0 * 0.07027027 + c1 * 0.31621622
                + c2 * 0.22702703
                + c3 * 0.31621622 + c4 * 0.07027027;


    //源
    float3 src = SAMPLE_TEXTURE2D_X(_SrcTexture, sampler_LinearClamp, uv);

    //环境光的最终计算
    
    
    return float4(src+color,1.0);
}
