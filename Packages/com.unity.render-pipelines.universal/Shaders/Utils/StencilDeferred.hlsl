#ifndef UNIVERSAL_STENCIL_DEFERRED
#define UNIVERSAL_STENCIL_DEFERRED

    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
    #include "Packages/com.unity.render-pipelines.universal/Shaders/Utils/Deferred.hlsl"
    #include "Assets/Library/FxLibrary.hlsl"
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
    #include_with_pragmas "Packages/com.unity.render-pipelines.core/ShaderLibrary/FoveatedRenderingKeywords.hlsl"
    #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/FoveatedRendering.hlsl"


    struct Attributes
    {
        float4 positionOS : POSITION;
        uint vertexID : SV_VertexID;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    struct Varyings
    {
        float4 positionCS : SV_POSITION;
        float3 screenUV : TEXCOORD1;
        UNITY_VERTEX_INPUT_INSTANCE_ID
        UNITY_VERTEX_OUTPUT_STEREO
    };

    #if defined(_SPOT)
    float4 _SpotLightScale;
    float4 _SpotLightBias;
    float4 _SpotLightGuard;
    #endif

    Varyings Vertex(Attributes input)
    {
        Varyings output = (Varyings)0;

        UNITY_SETUP_INSTANCE_ID(input);
        UNITY_TRANSFER_INSTANCE_ID(input, output);
        UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

        float3 positionOS = input.positionOS.xyz;

        #if defined(_SPOT)
        // Spot lights have an outer angle than can be up to 180 degrees, in which case the shape
        // becomes a capped hemisphere. There is no affine transforms to handle the particular cone shape,
        // so instead we will adjust the vertices positions in the vertex shader to get the tighest fit.
        [flatten] if (any(positionOS.xyz))
        {
            // The hemisphere becomes the rounded cap of the cone.
            positionOS.xyz = _SpotLightBias.xyz + _SpotLightScale.xyz * positionOS.xyz;
            positionOS.xyz = normalize(positionOS.xyz) * _SpotLightScale.w;
            // Slightly inflate the geometry to fit the analytic cone shape.
            // We want the outer rim to be expanded along xy axis only, while the rounded cap is extended along all axis.
            positionOS.xyz = (positionOS.xyz - float3(0, 0, _SpotLightGuard.w)) * _SpotLightGuard.xyz + float3(0, 0, _SpotLightGuard.w);
        }
        #endif

        #if defined(_DIRECTIONAL) || defined(_FOG) || defined(_CLEAR_STENCIL_PARTIAL) || (defined(_SSAO_ONLY) && defined(_SCREEN_SPACE_OCCLUSION))
            // Full screen render using a large triangle.
            output.positionCS = float4(positionOS.xy, UNITY_RAW_FAR_CLIP_VALUE, 1.0); // Force triangle to be on zfar
        #elif defined(_SSAO_ONLY) && !defined(_SCREEN_SPACE_OCCLUSION)
            // Deferred renderer does not know whether there is a SSAO feature or not at the C# scripting level.
            // However, this is known at the shader level because of the shader keyword SSAO feature enables.
            // If the keyword was not enabled, discard the SSAO_only pass by rendering the geometry outside the screen.
            output.positionCS = float4(positionOS.xy, -2, 1.0); // Force triangle to be discarded
        #else
            // Light shape geometry is projected as normal.
            VertexPositionInputs vertexInput = GetVertexPositionInputs(positionOS.xyz);
            output.positionCS = vertexInput.positionCS;
        #endif

        output.screenUV = output.positionCS.xyw;
        #if UNITY_UV_STARTS_AT_TOP
        output.screenUV.xy = output.screenUV.xy * float2(0.5, -0.5) + 0.5 * output.screenUV.z;
        #else
        output.screenUV.xy = output.screenUV.xy * 0.5 + 0.5 * output.screenUV.z;
        #endif

        return output;
    }

    TEXTURE2D_X(_CameraDepthTexture);
    TEXTURE2D_X_FLOAT(_GBuffer0);
    TEXTURE2D_X_FLOAT(_GBuffer1);
    TEXTURE2D_X_FLOAT(_GBuffer2);

#if _RENDER_PASS_ENABLED

    #define GBUFFER0 0
    #define GBUFFER1 1
    #define GBUFFER2 2
    #define GBUFFER3 3

    FRAMEBUFFER_INPUT_HALF(GBUFFER0);
    FRAMEBUFFER_INPUT_HALF(GBUFFER1);
    FRAMEBUFFER_INPUT_HALF(GBUFFER2);
    FRAMEBUFFER_INPUT_FLOAT(GBUFFER3);
    #if OUTPUT_SHADOWMASK
    #define GBUFFER4 4
    FRAMEBUFFER_INPUT_HALF(GBUFFER4);
    #endif
#else
    #ifdef GBUFFER_OPTIONAL_SLOT_1
    TEXTURE2D_X_HALF(_GBuffer4);
    #endif
#endif

    #if defined(GBUFFER_OPTIONAL_SLOT_2) && _RENDER_PASS_ENABLED
    TEXTURE2D_X_HALF(_GBuffer5);
    #elif defined(GBUFFER_OPTIONAL_SLOT_2)
    TEXTURE2D_X(_GBuffer5);
    #endif
    #ifdef GBUFFER_OPTIONAL_SLOT_3
    TEXTURE2D_X(_GBuffer6);
    #endif

    float4x4 _ScreenToWorld[2];
    SamplerState my_point_clamp_sampler;

    float3 _LightPosWS;
    half3 _LightColor;
    half4 _LightAttenuation; // .xy are used by DistanceAttenuation - .zw are used by AngleAttenuation *for SpotLights)
    half3 _LightDirection;   // directional/spotLights support
    half4 _LightOcclusionProbInfo;
    int _LightFlags;
    int _ShadowLightIndex;
    uint _LightLayerMask;
    int _CookieLightIndex;

    half4 FragWhite(Varyings input) : SV_Target
    {
        return half4(1.0, 1.0, 1.0, 1.0);
    }

    Light GetStencilLight(float3 posWS, float2 screen_uv, half4 shadowMask, uint materialFlags)
    {
        Light unityLight;

        bool materialReceiveShadowsOff = (materialFlags & kMaterialFlagReceiveShadowsOff) != 0;

        uint lightLayerMask =_LightLayerMask;

        #if defined(_DIRECTIONAL)
            #if defined(_DEFERRED_MAIN_LIGHT)
                unityLight = GetMainLight();
                // unity_LightData.z is set per mesh for forward renderer, we cannot cull lights in this fashion with deferred renderer.
                unityLight.distanceAttenuation = 1.0;

                if (!materialReceiveShadowsOff)
                {
                    #if defined(_MAIN_LIGHT_SHADOWS_SCREEN) && !defined(_SURFACE_TYPE_TRANSPARENT)
                        float4 shadowCoord = float4(screen_uv, 0.0, 1.0);
                    #elif defined(MAIN_LIGHT_CALCULATE_SHADOWS)
                        float4 shadowCoord = TransformWorldToShadowCoord(posWS.xyz);
                    #else
                        float4 shadowCoord = float4(0, 0, 0, 0);
                    #endif
                    unityLight.shadowAttenuation = MainLightShadow(shadowCoord, posWS.xyz, shadowMask, _MainLightOcclusionProbes);
                }

                #if defined(_LIGHT_COOKIES)
                    real3 cookieColor = SampleMainLightCookie(posWS);
                    unityLight.color *= half3(cookieColor);
                #endif
            #else
                unityLight.direction = _LightDirection;
                unityLight.distanceAttenuation = 1.0;
                unityLight.shadowAttenuation = 1.0;
                unityLight.color = _LightColor.rgb;
                unityLight.layerMask = lightLayerMask;

                if (!materialReceiveShadowsOff)
                {
                    #if defined(_ADDITIONAL_LIGHT_SHADOWS)
                        unityLight.shadowAttenuation = AdditionalLightShadow(_ShadowLightIndex, posWS.xyz, _LightDirection, shadowMask, _LightOcclusionProbInfo);
                    #endif
                }
            #endif
        #else
            PunctualLightData light;
            light.posWS = _LightPosWS;
            light.radius2 = 0.0; //  only used by tile-lights.
            light.color = float4(_LightColor, 0.0);
            light.attenuation = _LightAttenuation;
            light.spotDirection = _LightDirection;
            light.occlusionProbeInfo = _LightOcclusionProbInfo;
            light.flags = _LightFlags;
            light.layerMask = lightLayerMask;
            unityLight = UnityLightFromPunctualLightDataAndWorldSpacePosition(light, posWS.xyz, shadowMask, _ShadowLightIndex, materialReceiveShadowsOff);

            #ifdef _LIGHT_COOKIES
                // Enable/disable is done toggling the keyword _LIGHT_COOKIES, but we could do a "static if" instead if required.
                // if(_CookieLightIndex >= 0)
                {
                    float4 cookieUvRect = GetLightCookieAtlasUVRect(_CookieLightIndex);
                    float4x4 worldToLight = GetLightCookieWorldToLightMatrix(_CookieLightIndex);
                    float2 cookieUv = float2(0,0);
                    #if defined(_SPOT)
                        cookieUv = ComputeLightCookieUVSpot(worldToLight, posWS, cookieUvRect);
                    #endif
                    #if defined(_POINT)
                        cookieUv = ComputeLightCookieUVPoint(worldToLight, posWS, cookieUvRect);
                    #endif
                    half4 cookieColor = SampleAdditionalLightsCookieAtlasTexture(cookieUv);
                    cookieColor = half4(IsAdditionalLightsCookieAtlasTextureRGBFormat() ? cookieColor.rgb
                                        : IsAdditionalLightsCookieAtlasTextureAlphaFormat() ? cookieColor.aaa
                                        : cookieColor.rrr, 1);
                    unityLight.color *= cookieColor;
                }
            #endif
        #endif
        return unityLight;
    }

    half4 DeferredShading(Varyings input) : SV_Target
    {
        //优化宏
        UNITY_SETUP_INSTANCE_ID(input);
        UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

        //屏幕uv
        float2 screen_uv = (input.screenUV.xy / input.screenUV.z);
        //阴影遮罩
        half4 shadowMask = 1.0;
        
        float d        = SAMPLE_TEXTURE2D_X_LOD(_CameraDepthTexture, my_point_clamp_sampler, screen_uv, 0).x; // raw depth value has UNITY_REVERSED_Z applied on most platforms.
        half4 gbuffer0 = SAMPLE_TEXTURE2D_X_LOD(_GBuffer0, my_point_clamp_sampler, screen_uv, 0);
        half4 gbuffer1 = SAMPLE_TEXTURE2D_X_LOD(_GBuffer1, my_point_clamp_sampler, screen_uv, 0);
        half4 gbuffer2 = SAMPLE_TEXTURE2D_X_LOD(_GBuffer2, my_point_clamp_sampler, screen_uv, 0);

        
        //拿各种数据
        float3 diffuse = gbuffer0.rgb;
        float3 F0 = gbuffer1.rgb;
        float3 nDirWS = EyUnpackNormal(gbuffer2.rgb);
        float Roughness = gbuffer1.a;
        //深度图重构世界坐标，其中的0是照着unity抄的
        float4 posWS = mul(_ScreenToWorld[0], float4(input.positionCS.xy, d, 1.0));
        posWS.xyz *= rcp(posWS.w);
        float3 vDirWS = normalize(GetCameraPositionWS() - posWS);
        float3 nDirVS = normalize(mul(UNITY_MATRIX_V,nDirWS));
        //先写好最终输出
        float3 color = float3(0,0,0);
        half alpha = 1.0;

        //用宏来判断是否启用混合光照来判断阴影遮罩的写法
        #if defined(_DEFERRED_MIXED_LIGHTING)
        // If both lights and geometry are static, then no realtime lighting to perform for this combination.
        [branch] if ((_LightFlags & materialFlags) == kMaterialFlagSubtractiveMixedLighting)
            return half4(color, alpha); // Cannot discard because stencil must be updated.
        #endif

        //光照分支
        #if defined(_DIRECTIONAL)//平行光
        //准备一些数据
        float3 lDirWS = normalize( _MainLightPosition.xyz);
        float3 lightColor = _MainLightColor.rgb;
        float distanceAttenuation = 1.0;//衰减
        float3 hDirWS = normalize(vDirWS+lDirWS);
        float3 lDirVS = TransformWorldToViewDir(lDirWS);
        //镜面反射
        //法线分布函数：
        float D= DistributionGGX(nDirWS,hDirWS,Roughness);
        //菲涅尔项
        float3 F = fresnelSchlick(max(dot(hDirWS,vDirWS),0.00001),F0);
        //Geometry 几何函数
        float G = GeometrySmith(nDirWS, vDirWS, lDirWS, Roughness);
        float3 nominator    = D*F*G;
        float denominator = 4.0 * max(dot(nDirWS, vDirWS), 0.0) * max(dot(nDirWS, lDirWS), 0.0) + 0.001;
        float3 Specular     = nominator / denominator;
        Specular = Specular*lightColor.rgb*PI*max(0,dot(nDirWS,lDirWS));
        //边缘光项
        //边缘光的改良
        //筛选边缘(重点在于偏移UV的改良）
        float normalExtendLeftOffset = nDirVS.x > 0 ? 1.0 : -1.0;//通过视空间法线来判断描边的“左右”
        normalExtendLeftOffset *= 3 * 0.0044;//这里的3实际上是描边的宽度，这里我暂时设置为3
        float2 extendUV = screen_uv;
        float linear01EyeOffecDepth = LinearEyeDepth(d, _ZBufferParams);
        extendUV.x += normalExtendLeftOffset / (linear01EyeOffecDepth + 3.0);
        float trueDepth = SAMPLE_TEXTURE2D_X_LOD(_CameraDepthTexture, my_point_clamp_sampler, extendUV, 0).x;
        float linear01EyeTrueDepth = LinearEyeDepth(trueDepth, _ZBufferParams);
        float depthDiffer = linear01EyeTrueDepth - linear01EyeOffecDepth;
        float rimArea = saturate(depthDiffer * 4);
        rimArea = rimArea>0.8?1:0;
        //边缘光颜色
        float NdotLVS = dot(nDirVS,lDirVS);
        float frontRim = max(NdotLVS, 0);//筛选出正面和背面
        float backRim = max(-NdotLVS, 0);
        float3 frontRimColor = frontRim * lightColor.rgb;
        float3 backRimColor = backRim * lightColor.rgb*0.5;
        float3 albedoRimColor = saturate(diffuse + 0.3);
        float3 rimColor = (frontRimColor + backRimColor) *albedoRimColor ;
        
        //color = float3(0,0,0);
        color = (diffuse+Specular+rimColor*rimArea) *distanceAttenuation*(1-gbuffer2.a);
        
        #else//其他光照
        //准备数据
        float3 lightPosWS = _LightPosWS;
        float3 lightColor = _LightColor.rgb;
        //计算光照方向
        float3 lightVector = lightPosWS - posWS.xyz;
        float distanceSqr = max(dot(lightVector, lightVector), HALF_MIN);//防止取0
        float3 lDirWS = normalize(lightVector);
        float3 lDirVS = TransformWorldToViewDir(lDirWS);
        float3 hDirWS = normalize(vDirWS+lDirWS);

        
        //BRDF
        //镜面反射项
        float D= DistributionGGX(nDirWS,hDirWS,Roughness);
        //菲涅尔项
        float3 F = fresnelSchlick(max(dot(hDirWS,vDirWS),0.00001),F0);
        //Geometry 几何函数
        float G = GeometrySmith(nDirWS, vDirWS, lDirWS, Roughness);
        float3 nominator    = D*F*G;
        float denominator = 4.0 * max(dot(nDirWS, vDirWS), 0.0) * max(dot(nDirWS, lDirWS), 0.0) + 0.001;
        float3 Specular     = nominator / denominator;
        Specular = Specular*lightColor.rgb*PI*max(0,dot(nDirWS,lDirWS));

        
        //边缘光项
        //边缘光的改良
        //筛选边缘(重点在于偏移UV的改良）
        float2 normalExtendDirVS = normalize(lDirVS.xy);
        normalExtendDirVS *= 3 * 0.0044;//这里的3实际上是描边的宽度，这里我暂时设置为3
        float2 extendUV = screen_uv;
        float linear01EyeOffecDepth = LinearEyeDepth(d, _ZBufferParams);
        extendUV.x += normalExtendDirVS / (linear01EyeOffecDepth + 3.0);
        float trueDepth = SAMPLE_TEXTURE2D_X_LOD(_CameraDepthTexture, my_point_clamp_sampler, extendUV, 0).x;
        float linear01EyeTrueDepth = LinearEyeDepth(trueDepth, _ZBufferParams);
        float depthDiffer = linear01EyeTrueDepth - linear01EyeOffecDepth;
        float rimArea = saturate(depthDiffer * 1);
        rimArea = rimArea>0.8?1:0;
        //边缘光颜色
        float NdotLVS = dot(nDirVS,lDirVS);
        float frontRim = max(NdotLVS, 0);//筛选出正面和背面
        float backRim = max(-NdotLVS, 0);
        float3 frontRimColor = frontRim * lightColor.rgb;
        float3 backRimColor = backRim * lightColor.rgb*0.5;
        float3 albedoRimColor = saturate(diffuse + 0.3);
        float3 rimColor = (frontRimColor + backRimColor) *albedoRimColor;

        //光照衰减
        float4 attenuation = _LightAttenuation;//神秘的什么东西
        float lightAtten = rcp(distanceSqr);
        float2 distanceAttenuationFloat = float2(attenuation.xy);
        half factor = half(distanceSqr * distanceAttenuationFloat.x);
        half smoothFactor = saturate(half(1.0) - factor * factor);
        smoothFactor = smoothFactor * smoothFactor;
        float distanceAttenuation = lightAtten * smoothFactor;

        //输出准备
        color = (Specular+diffuse)*lightColor*distanceAttenuation*gbuffer2.a+rimColor*rimArea*2*(1-gbuffer2.a);
        #endif
        
        // #if defined(_LIT)
        // color = float3(1,0,0);
        // #elif defined(_SIMPLELIT)
        // color = float3(0,1,0);
        // #elif defined(_EYEBLEND)
        // color = float3(0,0,1);
        // #endif
        return half4(color,alpha);
    }

    half4 FragFog(Varyings input) : SV_Target
    {
        UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

        #if _RENDER_PASS_ENABLED
            float d = LOAD_FRAMEBUFFER_INPUT(GBUFFER3, input.positionCS.xy).x;
        #else
            float d = LOAD_TEXTURE2D_X(_CameraDepthTexture, input.positionCS.xy).x;
        #endif
        float eye_z = LinearEyeDepth(d, _ZBufferParams);
        float clip_z = UNITY_MATRIX_P[2][2] * -eye_z + UNITY_MATRIX_P[2][3];
        half fogFactor = ComputeFogFactor(clip_z);
        half fogIntensity = ComputeFogIntensity(fogFactor);
        return half4(unity_FogColor.rgb, fogIntensity);
    }

    half4 FragSSAOOnly(Varyings input) : SV_Target
    {
        UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

        float2 screen_uv = (input.screenUV.xy / input.screenUV.z);
        AmbientOcclusionFactor aoFactor = GetScreenSpaceAmbientOcclusion(screen_uv);
        half surfaceDataOcclusion = SAMPLE_TEXTURE2D_X_LOD(_GBuffer1, my_point_clamp_sampler, screen_uv, 0).a;
        // What we want is really to apply the mininum occlusion value between the baked occlusion from surfaceDataOcclusion and real-time occlusion from SSAO.
        // But we already applied the baked occlusion during gbuffer pass, so we have to cancel it out here.
        // We must also avoid divide-by-0 that the reciprocal can generate.
        half occlusion = aoFactor.indirectAmbientOcclusion < surfaceDataOcclusion ? aoFactor.indirectAmbientOcclusion * rcp(surfaceDataOcclusion) : 1.0;
        return half4(0.0, 0.0, 0.0, occlusion);
    }

#endif //UNIVERSAL_STENCIL_DEFERRED
