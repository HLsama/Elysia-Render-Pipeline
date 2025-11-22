#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Assets/Library/FxLibrary.hlsl"
CBUFFER_START(UnityPerMaterial)
float _OutlineClampScale;
float _OutlineWidth;
float3 _StrokeColor;
float3 _ShadowStrokeColor;
CBUFFER_END

struct a2v
{
    float4 vertex : POSITION;
    float4 uv : TEXCOORD0;
	float4 uv1 : TEXCOORD1;
    float3 normal : NORMAL;
    float4 tangent : TANGENT;
	float4 color : COLOR;
};
struct v2f
{
    float4 posCS : SV_POSITION;
    float2 uv : TEXCOORD;
    float4 scrPos : TEXCOORD1;
    float3 posWS : TEXCOORD2;
    float3 nDirWS : TEXCOORD3;
    float3 tDirWS : TEXCOORD4;
    float3 bDirWS :TEXCOORD5;
	float2 uv1 : TEXCOORD6;
    DECLARE_LIGHTMAP_OR_SH(staticLightmapUV, vertexSH, 7);
};
//将Gubffer打包成结构体输出
struct DeferredOutPut{
    float4 gBuffer0 : SV_TARGET0;
    float4 gBuffer1 : SV_TARGET1;
    float4 gBuffer2 : SV_TARGET2;
    float4 gBuffer3 : SV_TARGET3;
};

//描边的顶点着色器
v2f Strokevert(a2v v)
{
	v2f o;
	//在NDC空间计算法线外扩
	//#if _USESTROKE_ON 
	//v.vertex.xyz = v.vertex.xyz+v.normal.xyz*0.02;
	//#endif
	o.posCS = TransformObjectToHClip(v.vertex);
	o.nDirWS = TransformObjectToWorldNormal(v.normal.xyz) ;
	o.tDirWS = real3(TransformObjectToWorldDir(v.tangent.xyz));
	o.bDirWS = cross(o.nDirWS,o.tDirWS)*v.tangent.w*GetOddNegativeScale();
	float3 tangentOS = v.tangent.xyz;
	float3 normalOS = v.normal.xyz;
	float3 biTangentOS = cross(normalOS, tangentOS) * v.tangent.w * GetOddNegativeScale();
	#if _USESTROKE_ON
	float3 normal;
	normal = v.normal;
	#if _USESMOOTHNORMAL_ON
	float3 nDirTS;
	nDirTS.rgb = v.color.rgb*2-1;
	float3x3 TBN = float3x3(tangentOS, biTangentOS, normalOS);
	normal = normalize(mul(nDirTS,TBN));
	#endif
	float4 scaledScreenParams = GetScaledScreenParams();
	float ScaleX = abs(scaledScreenParams.x / scaledScreenParams.y);
	
	float3 nDirCS = TransformObjectToHClip(normal);
	float2 extend = normalize(nDirCS).xy * (_OutlineWidth*0.01);
	extend.x /= ScaleX;
	float ctrl = clamp(1/(o.posCS.w + _OutlineClampScale),0,1);
	o.posCS.xy +=extend.xy* o.posCS.w*ctrl;
	#endif
	return o;
}

//描边的片源着色器
DeferredOutPut Strokefrag(v2f i) : SV_Target
{
    DeferredOutPut g;
    //准备数据
	float3 lDirWS =  normalize(_MainLightPosition.xyz);
	float3 nDirWS = normalize(i.nDirWS);
	float3 tDirWS = normalize(i.tDirWS);
	float3 bDirWS = normalize(i.bDirWS);
	#if _USENORMALMAP_ON
	float4 ver_NormalMap = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, i.uv);
	ver_NormalMap = normalize(ver_NormalMap*2-1);
	float3x3 TBN = float3x3(tDirWS,bDirWS,nDirWS);
	nDirWS = normalize(mul(ver_NormalMap,TBN));
	#endif
	float nDotL = max(0,dot(nDirWS,lDirWS));
	float3 rgb = lerp(_StrokeColor* _MainLightColor,_ShadowStrokeColor,nDotL);

    //输出倒Gbuffer
    g.gBuffer0 = float4(rgb,1);//RGB：基础色 A:粗糙度
    g.gBuffer1 = float4(0,0,0,1);//RGB ：F0项，A：映射ID
    g.gBuffer2 = float4(0,0,0,1);//RGB:法线 A暂无
	g.gBuffer3 = float4(0,0,0,1);
	return g;
}

