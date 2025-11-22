Shader "NPRFringeGbuffer"
{
    Properties
    {
        [FoldoutBegin(_FoldoutTexEnd)]_FoldoutTex("基础色", Float) = 0
        _MainTex ("基础贴图",2D) = "white"{}
        [HDR]_MainColor("基础颜色",Color)=(1,1,1)
        _HairMaskTex("头发遮罩贴图",2D)="white"{}
    	[Toggle(_USEUV1TOMASK)]_USEUV1TOMASK("使用uv1采样遮罩", Float)= 0
	    _AnisotropicSlide ("各向异性缩放", Range(-0.5, 0.5))  = 0.3
	    _AnisotropicOffset ("各向异性偏移", Range(-1.0, 1.0)) = 0.0
    	_BlinnPhongPow("高光Pow", Range(1, 50))= 5
    	_SpecMinimum("最暗高光强度", Range(0, 0.5))= 0.1
    	[HDR]_SpecColor("高光颜色",Color)=(0.5,0.5,0.5)
    	_ShadowOffset("阴影偏移", Range(-1, 1)) = 0.5
	    _ShadowSmoothNdotL("阴影软硬", Range(0, 1)) = 0.25
        [FoldoutEnd]_FoldoutTexEnd("_FoldoutEnd", Float) = 0
        
        [FoldoutBegin(_FoldoutEnd2, _USENORMALMAP_ON)]_FoldoutWithKey("法线开关", float) = 0
        [HideInInspector]_USENORMALMAP_ON("_USENORMALMAP_ON", float) = 0
        _NormalMap("法线贴图",2D)="white"{}
        [FoldoutEnd]_FoldoutEnd2("FoldoutEnd2", float) = 0
        
        
        [FoldoutBegin(_FoldoutEnd3, _USESTROKE_ON)]_FoldoutWithKey2("描边开关", float) = 0
        [HideInInspector]_USESTROKE_ON("_USESTROKE_ON", float) = 0
        [Toggle(_USESMOOTHNORMAL_ON)]_SmoothNormal("使用平滑法线", Float)= 0
        [HDR]_StrokeColor("描边颜色",Color)=(0,0,0)
        [HDR]_ShadowStrokeColor("描边暗部颜色",Color)=(0,0,0)
        _OutlineWidth("描边宽度",Range(0,10))=2
        _OutlineClampScale("描边偏移",Range(0,4))=0
        [FoldoutEnd]_FoldoutEnd3("FoldoutEnd3", float) = 0
        
        // Ramp
        [FoldoutBegin(_FoldoutShadowRampEnd, _SHADOW_RAMP)]_FoldoutShadowRamp("ShadowRamp", Float) = 0
        [HideInInspector]_SHADOW_RAMP("_SHADOW_RAMP", Float) = 0
        [Ramp]_ShadowRampTex("ShadowRampTex", 2D)= "white" { }
        [FoldoutEnd]_FoldoutShadowRampEnd("_FoldoutEnd", Float) = 0
        _HiarAlpha("刘海厚度",Range(0,1))=1
    	[Header(Blend Mode)]
        [Enum(UnityEngine.Rendering.BlendMode)]
        _BlendSrc("Blend src", int) = 5
        [Enum(UnityEngine.Rendering.BlendMode)]
        _BlendDst("Blend dst", int) = 1
        [Enum(UnityEngine.Rendering.BlendOp)]
        _BlendOp("BlendOp", int) = 21
        [Enum(Off, 0, On, 1)]
        _ZWrite ("ZWrite", float) = 0
    }
    SubShader
    {
        Tags 
        {
            "RenderType"="Opaque"
        }
        //渲染的pass
        Pass
        {
            Name "HiarAlpha"
            Tags 
            {
                "LightMode"="UniversalGBuffer"
            }
            Stencil//untiy 正常该有的模板测试
		    {
//				Ref 32
//		        ReadMask 0
//		        WriteMask 96
//		        Comp Always
//		        Pass Replace
//		        Fail Keep
//		        ZFail Keep
		    	Ref 40
		        //ReadMask 0
		        //WriteMask 96
		        Comp Equal
		        Pass Replace
		        Fail Keep
		        ZFail Keep
		    }
            BlendOp [_BlendOp]
            Blend [_BlendSrc] [_BlendDst]
            ZWrite [_ZWrite]
            HLSLPROGRAM
            
            #pragma vertex Basevert
            #pragma fragment Hairfrag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Assets/Library/FxLibrary.hlsl"
            #pragma multi_compile _ _USENORMALMAP_ON
            #pragma multi_compile _ _SHADOW_RAMP
            #pragma multi_compile _ _USEUV1TOMASK

            CBUFFER_START(UnityPerMaterial)
			float4 _MainTex_ST;
            float3 _MainColor;
            float3 _SpecColor;

            float _AnisotropicSlide;              
            float _AnisotropicOffset;
            float _BlinnPhongPow;
            float _SpecMinimum;
            float _ShadowOffset;
            float _ShadowSmoothNdotL;
            float _HiarAlpha;

			

			CBUFFER_END
			TEXTURE2D(_MainTex);//基础色
			SAMPLER(sampler_MainTex);
            TEXTURE2D(_HairMaskTex);//头发遮罩
			SAMPLER(sampler_HairMaskTex);
            TEXTURE2D(_NormalMap);//法线贴图
			SAMPLER(sampler_NormalMap);
            TEXTURE2D(_ShadowRampTex);//Ramp图
			SAMPLER(sampler_ShadowRampTex);

            struct a2v
            {
                float4 vertex : POSITION;
                float4 uv : TEXCOORD0;
	            float4 uv1 : TEXCOORD1;
                float3 normal : NORMAL;
            	float4 tangent : TANGENT;
            };
            struct v2f
            {
                float4 posCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            	float2 uv1 : TEXCOORD1;
                float3 posWS : TEXCOORD2;
                float3 nDirWS : TEXCOORD3;
            	float3 tDirWS : TEXCOORD4;
                float3 bDirWS :TEXCOORD5;
                DECLARE_LIGHTMAP_OR_SH(staticLightmapUV, vertexSH, 7);
            };
            //将Gubffer打包成结构体输出
            struct DeferredOutPut{
                float4 gBuffer0 : SV_TARGET0;
                float4 gBuffer1 : SV_TARGET1;
                float4 gBuffer2 : SV_TARGET2;
                float4 gBuffer3 : SV_TARGET3;
            };

            v2f Basevert(a2v v)
            {
                v2f o;
                VertexPositionInputs vertexInput = GetVertexPositionInputs(v.vertex.xyz);
                o.posCS = vertexInput.positionCS;
                o.posWS = vertexInput.positionWS;
                o.nDirWS = TransformObjectToWorldNormal(v.normal.xyz) ;
            	o.tDirWS = real3(TransformObjectToWorldDir(v.tangent.xyz));
                o.bDirWS = cross(o.nDirWS,o.tDirWS)*v.tangent.w*GetOddNegativeScale();
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
	            o.uv1 = v.uv1;
                return o;
            }
             DeferredOutPut Hairfrag(v2f i) : SV_Target
			{
				DeferredOutPut g;
				//贴图采样
			    float3 ver_MainTex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);

			    //拿数据
				float3 lDirWS =  normalize(_MainLightPosition.xyz);
				float3 vDirWS = normalize(GetCurrentViewPosition() - i.posWS);
				float3 hDirWS = normalize(vDirWS+lDirWS);
			    float3 nDirWS = normalize(i.nDirWS);
				float3 tDirWS = normalize(i.tDirWS);
				float3 bDirWS = normalize(i.bDirWS);
			    //如果法线贴图开关开启就TBN矩阵
				#if _USENORMALMAP_ON
				float4 ver_NormalMap = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, i.uv);
				nDirWS = TBNNormal(ver_NormalMap.rg,tDirWS,bDirWS,nDirWS);
			    #endif

				//中间向量
				float NdotH = saturate(dot(nDirWS,hDirWS));
				
				//头发漫反射
				float halfLambert = dot(nDirWS,lDirWS);
				halfLambert = sigmoidTrue(halfLambert,_ShadowOffset,_ShadowSmoothNdotL);
				float3 diffuse = 1;
				#if _SHADOW_RAMP
				float3 RampTex = SAMPLE_TEXTURE2D(_ShadowRampTex, sampler_ShadowRampTex, float2(halfLambert,0.125));
				diffuse = RampTex*ver_MainTex*_MainColor;
				#else
				diffuse = halfLambert*ver_MainTex;
			    #endif

				//头发镜面反射(风格化的各向异性高光)
				//采样遮罩
				float Mask = 0;
				float anisotropicOffsetV = - vDirWS.y *_AnisotropicSlide + _AnisotropicOffset;
				#if _USEUV1TOMASK
				Mask = SAMPLE_TEXTURE2D(_HairMaskTex,sampler_HairMaskTex,float2(i.uv1.x,i.uv1.y+anisotropicOffsetV)).g;
				#else
				Mask = SAMPLE_TEXTURE2D(_HairMaskTex,sampler_HairMaskTex,float2(i.uv.x,i.uv.y+anisotropicOffsetV)).g;
				#endif
				float hairSpecStrength = _SpecMinimum + pow(NdotH, _BlinnPhongPow);
				float3 hairSpecColor = Mask * _SpecColor * hairSpecStrength;

				
				//输出
				float3 RGB = diffuse+hairSpecColor;
			    nDirWS = EyPackNormal(nDirWS);
			    //输出倒Gbuffer
			    g.gBuffer0 = float4(RGB,_HiarAlpha);//RGB：基础色 A:粗糙度
			    g.gBuffer1 = float4(0,0,0,1);//RGB ：F0项，A：映射ID
			    g.gBuffer2 = float4(nDirWS,0);//RGB:法线 A暂无
				g.gBuffer3 = float4(0,0,0,1);
				return g;
			}
            ENDHLSL
        }
		Pass
        {
            Name "Hiar"
            Tags 
            {
                "LightMode"="EyNPRHairGBuffer"
            }
            Stencil//untiy 正常该有的模板测试
		    {
//				Ref 32
//		        ReadMask 0
//		        WriteMask 96
//		        Comp Always
//		        Pass Replace
//		        Fail Keep
//		        ZFail Keep
		    	Ref 32
		        //ReadMask 0
		        //WriteMask 96
		        Comp GEqual
		        Pass Replace
		        Fail Keep
		        ZFail Keep
		    }
            HLSLPROGRAM
            
            #pragma vertex Basevert
            #pragma fragment Hairfrag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Assets/Library/FxLibrary.hlsl"
            #pragma multi_compile _ _USENORMALMAP_ON
            #pragma multi_compile _ _SHADOW_RAMP
            #pragma multi_compile _ _USEUV1TOMASK

            CBUFFER_START(UnityPerMaterial)
			float4 _MainTex_ST;
            float3 _MainColor;
            float3 _SpecColor;

            float _AnisotropicSlide;              
            float _AnisotropicOffset;
            float _BlinnPhongPow;
            float _SpecMinimum;
            float _ShadowOffset;
            float _ShadowSmoothNdotL;

			

			CBUFFER_END
			TEXTURE2D(_MainTex);//基础色
			SAMPLER(sampler_MainTex);
            TEXTURE2D(_HairMaskTex);//头发遮罩
			SAMPLER(sampler_HairMaskTex);
            TEXTURE2D(_NormalMap);//法线贴图
			SAMPLER(sampler_NormalMap);
            TEXTURE2D(_ShadowRampTex);//Ramp图
			SAMPLER(sampler_ShadowRampTex);

            struct a2v
            {
                float4 vertex : POSITION;
                float4 uv : TEXCOORD0;
	            float4 uv1 : TEXCOORD1;
                float3 normal : NORMAL;
            	float4 tangent : TANGENT;
            };
            struct v2f
            {
                float4 posCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            	float2 uv1 : TEXCOORD1;
                float3 posWS : TEXCOORD2;
                float3 nDirWS : TEXCOORD3;
            	float3 tDirWS : TEXCOORD4;
                float3 bDirWS :TEXCOORD5;
                DECLARE_LIGHTMAP_OR_SH(staticLightmapUV, vertexSH, 7);
            };
            //将Gubffer打包成结构体输出
            struct DeferredOutPut{
                float4 gBuffer0 : SV_TARGET0;
                float4 gBuffer1 : SV_TARGET1;
                float4 gBuffer2 : SV_TARGET2;
                float4 gBuffer3 : SV_TARGET3;
            };

            v2f Basevert(a2v v)
            {
                v2f o;
                VertexPositionInputs vertexInput = GetVertexPositionInputs(v.vertex.xyz);
                o.posCS = vertexInput.positionCS;
                o.posWS = vertexInput.positionWS;
                o.nDirWS = TransformObjectToWorldNormal(v.normal.xyz) ;
            	o.tDirWS = real3(TransformObjectToWorldDir(v.tangent.xyz));
                o.bDirWS = cross(o.nDirWS,o.tDirWS)*v.tangent.w*GetOddNegativeScale();
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
	            o.uv1 = v.uv1;
                return o;
            }
             DeferredOutPut Hairfrag(v2f i) : SV_Target
			{
				DeferredOutPut g;
				//贴图采样
			    float3 ver_MainTex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);

			    //拿数据
				float3 lDirWS =  normalize(_MainLightPosition.xyz);
				float3 vDirWS = normalize(GetCurrentViewPosition() - i.posWS);
				float3 hDirWS = normalize(vDirWS+lDirWS);
			    float3 nDirWS = normalize(i.nDirWS);
				float3 tDirWS = normalize(i.tDirWS);
				float3 bDirWS = normalize(i.bDirWS);
			    //如果法线贴图开关开启就TBN矩阵
				#if _USENORMALMAP_ON
				float4 ver_NormalMap = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, i.uv);
				nDirWS = TBNNormal(ver_NormalMap.rg,tDirWS,bDirWS,nDirWS);
			    #endif

				//中间向量
				float NdotH = saturate(dot(nDirWS,hDirWS));
				
				//头发漫反射
				float halfLambert = dot(nDirWS,lDirWS);
				halfLambert = sigmoidTrue(halfLambert,_ShadowOffset,_ShadowSmoothNdotL);
				float3 diffuse = 1;
				#if _SHADOW_RAMP
				float3 RampTex = SAMPLE_TEXTURE2D(_ShadowRampTex, sampler_ShadowRampTex, float2(halfLambert,0.125));
				diffuse = RampTex*ver_MainTex*_MainColor;
				#else
				diffuse = halfLambert*ver_MainTex*_MainColor;
			    #endif

				//头发镜面反射(风格化的各向异性高光)
				//采样遮罩
				float Mask = 0;
				float anisotropicOffsetV = - vDirWS.y *_AnisotropicSlide + _AnisotropicOffset;
				#if _USEUV1TOMASK
				Mask = SAMPLE_TEXTURE2D(_HairMaskTex,sampler_HairMaskTex,float2(i.uv1.x,i.uv1.y+anisotropicOffsetV)).g;
				#else
				Mask = SAMPLE_TEXTURE2D(_HairMaskTex,sampler_HairMaskTex,float2(i.uv.x,i.uv.y+anisotropicOffsetV)).g;
				#endif
				float hairSpecStrength = _SpecMinimum + pow(NdotH, _BlinnPhongPow);
				float3 hairSpecColor = Mask * _SpecColor * hairSpecStrength;

				
				//输出
				float3 RGB = diffuse+hairSpecColor;
			    nDirWS = EyPackNormal(nDirWS);
			    //输出倒Gbuffer
			    g.gBuffer0 = float4(RGB,1.0);//RGB：基础色 A:粗糙度
			    g.gBuffer1 = float4(0,0,0,1);//RGB ：F0项，A：映射ID
			    g.gBuffer2 = float4(nDirWS,0);//RGB:法线 A暂无
				g.gBuffer3 = float4(0,0,0,1);
				return g;
			}
            ENDHLSL
        }
		Pass
        {
            Name "NPRStroke"
            Tags 
            {
                "LightMode"="EyNPRStrokeGBuffer"
            }
            Cull Front
            Stencil//untiy 正常该有的模板测试
		    {
		        Ref 32
		        ReadMask 0
		        WriteMask 96
		        Comp Always
		        Pass Replace
		        Fail Keep
		        ZFail Keep
		    }
            HLSLPROGRAM
                #pragma vertex Strokevert
                #pragma fragment Strokefrag
                #include "Assets/NPR/NPR.hlsl"
                #pragma multi_compile _ _USESTROKE_ON
                #pragma multi_compile _ _USESMOOTHNORMAL_ON
            ENDHLSL
        }
    }
    CustomEditor "UnityEditor.DanbaidongGUI.DanbaidongGUI"
}
