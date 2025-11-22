#define PI 3.1415926535
//Fresnel 菲涅尔项
float3 fresnelSchlick(float cosTheta, float3 F0)
{
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}
//法线分布函数（高光）
float DistributionGGX(float3 N,float3 H,float roughness)
{
    
    float a = roughness*roughness;
    a = lerp(0.002,1.0,a);
    float a2 = a*a;
    float NdotH = max(dot(N,H),0.000001);
    float NdotH2 = NdotH*NdotH;

    float num = a2;
    float denom = (NdotH2*(a2-1.0)+1.0);
    denom = PI*denom*denom;
    return num/denom;
}
//Geometry 几何函数（其一）
float GeometrySchlickGGX(float NdotV, float roughness)
{
    float r = (roughness + 1.0);
    float k = (r*r) / 8.0;

    float num   = NdotV;
    float denom = NdotV * (1.0 - k) + k;

    return num / denom;
}
//Geometry 几何函数（其二）
float GeometrySmith(float3 N, float3 V, float3 L, float roughness)
{
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx2  = GeometrySchlickGGX(NdotV, roughness);
    float ggx1  = GeometrySchlickGGX(NdotL, roughness);
    return ggx1 * ggx2;
}
//间接光照镜面反射用函数
float3 fresnelSchlickRoughness(float cosTheta, float3 F0, float roughness)
{
	return F0 + (max(float3(1.0 - roughness, 1.0 - roughness, 1.0 - roughness), F0) - F0) * pow(1.0 - cosTheta, 5.0);
}

//八面体映射压缩法线，解决法线精度问题
half3 EyPackNormal(half3 n)
{
    float2 octNormalWS = PackNormalOctQuadEncode(n);                  // values between [-1, +1], must use fp32 on some platforms.
    float2 remappedOctNormalWS = saturate(octNormalWS * 0.5 + 0.5);   // values between [ 0, +1]
    return half3(PackFloat2To888(remappedOctNormalWS));               // values between [ 0, +1]
}
//解码八面体映射的法线
half3 EyUnpackNormal(half3 pn)
{
    half2 remappedOctNormalWS = half2(Unpack888ToFloat2(pn));          // values between [ 0, +1]
    half2 octNormalWS = remappedOctNormalWS.xy * half(2.0) - half(1.0);// values between [-1, +1]
    return half3(UnpackNormalOctQuadEncode(octNormalWS));              // values between [-1, +1]
}
//一个人为调整后的sigmoid函数，拟合函数用于模拟Ramp图，center：偏移距离，过度的阈值，sharp，过度的软硬(在其他地方也有用途的重要函数)
float sigmoid(float x, float center, float sharp)
{
    float s;
    s = 1 / (1 + pow(100000, (-3 * sharp * (x - center))));
    return s;
}
//真正的sigmoid函数
float sigmoidTrue(float x, float center, float sharp)
{
    float s;
    s = 1 / (1 + exp(-(x-center)/sharp));
    return s;
}
//TBN矩阵解码法线贴图（只用法线贴图RG通道）
float3 TBNNormal(float2 NormalMapRG,float3 tDirWS,float3 bDirWS,float3 nDirWS)
{
    NormalMapRG = NormalMapRG*2-1;
    float3 nDirTS = float3(NormalMapRG,sqrt(1-NormalMapRG.r*NormalMapRG.r-NormalMapRG.g*NormalMapRG.g));
    float3x3 TBN = float3x3(tDirWS,bDirWS,nDirWS);
    float3 normal = normalize(mul(nDirTS,TBN));
    return normal;
}

//动态透视矫正
float3 CameraOffest(float3 posOS,float cameraFov,float offsetRange)
{
    //拿数据
    float3 cameraPosWS = GetCameraPositionWS();
    float3 posWS = TransformObjectToWorld(posOS);
    float3 ActorPosWS = TransformObjectToWorld(float3(0,0,0));     //取数据
    //float3 cameraDirWS = -UNITY_MATRIX_V[2];
    float3 cameraDirWS = TransformViewToWorldDir(float3(0,0,1));
    float3 vDirWS = posWS-cameraPosWS;
    float3 vDirWS_Actor = ActorPosWS-cameraPosWS;
    float CameraFov = cameraFov;

    //像素到摄象机方向的投影
    float3 q = dot(vDirWS,cameraDirWS)*cameraDirWS;
    q = (q-vDirWS)*(1-CameraFov);
    float3 p = dot(vDirWS_Actor,cameraDirWS)*cameraDirWS;                 //像素位置在摄象机方向的投影
    p = (p-vDirWS_Actor)*(1-CameraFov);
    float3 PixvToCameraProjection = q-p;

    //视角补偿
    float3 PosOffset = posWS+PixvToCameraProjection;
    PosOffset = vDirWS_Actor-PosOffset;
    PosOffset = PosOffset*(1-(1/CameraFov))+PixvToCameraProjection;
    float3 PosOffset2 = PosOffset;
    PosOffset2 = normalize(cameraPosWS-( PosOffset2+posWS));
    PosOffset = PosOffset+PosOffset2;
    PosOffset = TransformWorldToObject(PosOffset)*offsetRange*0.1;
    return PosOffset;
}