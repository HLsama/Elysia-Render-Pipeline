Shader "Ey_Outline"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" }
        Cull Off ZWrite Off ZTest Always
        //深度描边
        Pass
        {
            Name "Outline"
            ZTest Always
            ZWrite Off
            Cull Off

            HLSLPROGRAM
                #pragma vertex vert
                #pragma fragment frag
                #include "Ey_Outline.hlsl"
            ENDHLSL
        }
    }
}