Shader "Ey_Bloom"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" }
        Cull Off ZWrite Off ZTest Always
        
        //0-Prefilter亮部筛选
        Pass
        {
            Name "Prefilter"
            ZTest Always
            ZWrite Off
            Cull Off

            HLSLPROGRAM
                #pragma vertex vert
                #pragma fragment eyPrefilterfrag
                #include "Ey_Bloom.hlsl"
            ENDHLSL
        }
        //1—GaussBlurHorizontal 用于下采样的高斯模糊横向
        Pass
        {
            Name "GaussBlurHorizontal"
            ZTest Always
            ZWrite Off
            Cull Off

            HLSLPROGRAM
                #pragma vertex vert
                #pragma fragment eyGaussBlurfragHUnity
                #include "Ey_Bloom.hlsl"
            ENDHLSL
        }
        //2—GaussBlurVertical 用于下采样的高斯模糊纵向
        Pass
        {
            Name "GaussBlurVertical"
            ZTest Always
            ZWrite Off
            Cull Off

            HLSLPROGRAM
                #pragma vertex vert
                #pragma fragment eyGaussBlurfragVUnity
                #include "Ey_Bloom.hlsl"
            ENDHLSL
        }
        //3—MipUp 用于上采样
        Pass
        {
            Name "MipUp"
            ZTest Always
            ZWrite Off
            Cull Off

            HLSLPROGRAM
                #pragma vertex vert
                #pragma fragment eyMipUpfrag
                #include "Ey_Bloom.hlsl"
            ENDHLSL
        }
        //4—Blend 合成原图像
        Pass
        {
            Name "Blend"
            ZTest Always
            ZWrite Off
            Cull Off

            HLSLPROGRAM
                #pragma vertex vert
                #pragma fragment eyBlendfrag
                #include "Ey_Bloom.hlsl"
            ENDHLSL
        }
        //5—FirstDown 用于下采样之前，抗闪烁
        Pass
        {
            Name "FirstDown"
            ZTest Always
            ZWrite Off
            Cull Off

            HLSLPROGRAM
                #pragma vertex vert
                #pragma fragment eyFirstDownfrag
                #include "Ey_Bloom.hlsl"
            ENDHLSL
        }
    }
}