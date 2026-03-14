Shader "Ey_Post-processing/Ey_SSR"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" }
        Cull Off ZWrite Off ZTest Always
        
        //0-HiZ 用于提供Mip的深度图
        Pass
        {
            Name "HiZ"
            ZTest Always
            ZWrite Off
            Cull Off

            HLSLPROGRAM
                #pragma vertex vert
                #pragma fragment HiZfrag
                #include "Ey_SSR.hlsl"
                
            ENDHLSL
        }
        //进行屏幕空间的光线追踪 
        Pass
        {
            Name "SSR"
            ZTest Always
            ZWrite Off
            Cull Off
            
            HLSLPROGRAM
                #pragma vertex vert
                #pragma fragment HiZSSRfrag
                #include "Ey_SSR.hlsl"
            ENDHLSL
        }
        //横向的高斯模糊
        Pass
        {
            Name "GaussBlurHorizontal"
            ZTest Always
            ZWrite Off
            Cull Off
            
            HLSLPROGRAM
                #pragma vertex vert
                #pragma fragment GaussBlurHorizontalfrag
                #include "Ey_SSR.hlsl"
            ENDHLSL
        }
        //纵向的高斯模糊
        Pass
        {
            Name "GaussBlurVertical"
            ZTest Always
            ZWrite Off
            Cull Off
            
            HLSLPROGRAM
                #pragma vertex vert
                #pragma fragment GaussBlurVerticalfrag
                #include "Ey_SSR.hlsl"
            ENDHLSL
        }

    }
}