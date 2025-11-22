Shader "NPRLashesGufffer"
{
    Properties
    {
        [FoldoutBegin(_FoldoutTexEnd)]_FoldoutTex("基础色", Float) = 0
        _MainTex ("基础贴图",2D) = "white"{}
    	_MatCap("MatCap",2D)= "white"{}
    	_MatCapAlpha("MatCap强度",Range(0,1))=0
    	_Sequence("序列帧",2D)= "white"{}
    	_NormalMap("法线贴图",2D)="white"{}
        [HDR]_MainColor("基础颜色",Color)=(1,1,1)
        _OffestSize("偏移程度",Range(0,1))=1
        _ParallaxMaskEdge("MaskEdge", Range(0, 1))= 0.8
        _ParallaxMaskEdgeOffset("MaskEdgeOffset", Range(0, 1))= 0.2
    	_Speed ("序列帧播放", Range(0,16)) = 8
    	_SequenceAlpha("序列帧透明度",Range(0,1))=0
        [FoldoutEnd]_FoldoutTexEnd("_FoldoutEnd", Float) = 0
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
            Name "NPREye"
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
		        Comp Always
		        Pass Replace
		        Fail Keep
		        ZFail Keep
		    }
            HLSLPROGRAM
            
            #pragma vertex Basevert
            #pragma fragment Eyesfrag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Assets/Library/FxLibrary.hlsl"
            //#include "Assets/NPR/NPR.hlsl"

            CBUFFER_START(UnityPerMaterial)
			float4 _MainTex_ST;
            float3 _MainColor;
			float _OffestSize;
			float _ParallaxMaskEdge;
			float _ParallaxMaskEdgeOffset;
            float _Speed;
            float _SequenceAlpha;
            float _MatCapAlpha;

			CBUFFER_END
			TEXTURE2D(_MainTex);//在CG中会写成sampler2D _MainTex;
			SAMPLER(sampler_MainTex);
            TEXTURE2D(_MatCap);//在CG中会写成sampler2D _MainTex;
			SAMPLER(sampler_MatCap);
            TEXTURE2D(_NormalMap);//在CG中会写成sampler2D _MainTex;
			SAMPLER(sampler_NormalMap);
            TEXTURE2D(_Sequence);//在CG中会写成sampler2D _MainTex;
			SAMPLER(sampler_Sequence);
           

            struct a2v
            {
                float4 vertex : POSITION;
                float4 uv : TEXCOORD0;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
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
                o.scrPos = ComputeScreenPos(vertexInput.positionCS);
                return o;
            }

            DeferredOutPut Eyesfrag(v2f i) : SV_Target
			{
				DeferredOutPut g;
				//取样数据
				float2 uv = i.uv;
				float3 vDirWS = normalize(GetCameraPositionWS() - i.posWS);
				float3 nDirWS = normalize(i.nDirWS);
				float3 nDirVS = normalize(TransformWorldToObjectDir(nDirWS));
				
				//视差眼睛
				float3 vDirOS = normalize(TransformWorldToObjectDir(vDirWS)) ;
				float2 offset = vDirOS.xy;
				offset.y *= -1;
				uv +=  offset*_OffestSize;
				//视差遮罩
				float2 centerVec = i.uv - float2(0.5, 0.5);
				half centerDist = dot(centerVec, centerVec);
				half parallaxMask = smoothstep(_ParallaxMaskEdge, _ParallaxMaskEdge + _ParallaxMaskEdgeOffset, 1 - centerDist);
			    //贴图采样
			    float3 ver_MainTex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, lerp(i.uv, uv, parallaxMask)).rgb*_MainColor;
				//ver_MainTex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv).rgb*_MainColor;


				
				//环境光项（这里用Matcap）
				float2 matcapUV = saturate(nDirVS.xy * 0.5 + 0.5);
				float3 ver_NormalMap = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, matcapUV);
				nDirWS = normalize(ver_NormalMap * 2.0 - 1.0);
				nDirVS = normalize(TransformWorldToObjectDir(nDirWS));
				float3 NormalBlend_MatcapUV_Detail = nDirVS.rgb * float3(-1,-1,1);
				float3 NormalBlend_MatcapUV_Base = (mul( UNITY_MATRIX_V, float4(vDirWS,0)).rgb*float3(-1,-1,1)) + float3(0,0,1);
				float3 noSknewViewNormal = NormalBlend_MatcapUV_Base*dot(NormalBlend_MatcapUV_Base, NormalBlend_MatcapUV_Detail)/NormalBlend_MatcapUV_Base.b - NormalBlend_MatcapUV_Detail;                
				float2 ViewNormalAsMatCapUV = noSknewViewNormal.rg * 0.5 + 0.5;
				float3 MatCap = SAMPLE_TEXTURE2D(_MatCap, sampler_MatCap,ViewNormalAsMatCapUV )*_MatCapAlpha;

				//序列帧动画
				// 计算当前帧索引
				uv= i.uv;
                float time = _Time.y;
				
                int frameIndex  = floor(time* _Speed);//第几帧

				float stepU = 1.0 / 4;               //行步长
				float stepV = 1.0 / 4; 

                int idV = floor(frameIndex / 4);     //第几行
				int idU = fmod(frameIndex , 4);

				//【设定其实位置，左上角】
				 uv *= float2(stepU , stepV);      //uv缩放,当前定位：左下角
				 uv += float2(0.0 , 1 - stepV);                //uv向上偏移，当前定位: 左上角
				 //【uv滚动】
				 uv += float2(stepU * idU , -stepV * idV);     //uv从左上角到右下角运动

                float3 Sequence = SAMPLE_TEXTURE2D(_Sequence, sampler_Sequence,uv )*_SequenceAlpha;

				//混合
				float3 RGB= ver_MainTex*_MainColor+Sequence+MatCap;

				
			    //输出倒Gbuffer
			    g.gBuffer0 = float4(RGB,0.25);//RGB：基础色 A:粗糙度
			    g.gBuffer1 = float4(0,0,0,1);//RGB ：F0项，A：映射ID
			    g.gBuffer2 = float4(0,0,0,0);//RGB:法线 A暂无
				g.gBuffer3 = float4(0,0,0,1);
				return g;
			}
            ENDHLSL
        }
    }
    CustomEditor "UnityEditor.DanbaidongGUI.DanbaidongGUI"
}
