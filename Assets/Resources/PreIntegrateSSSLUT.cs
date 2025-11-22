
using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
 
public class PreIntegrateSSSLUT : MonoBehaviour
{
    public int resolution = 1024;
    public RenderTexture SSSLUTRT;
    public Texture2D SSSLUT;
 
    void Start()
    {
        if (SSSLUTRT != null) RenderTexture.ReleaseTemporary(SSSLUTRT);
        if (SSSLUT != null) Texture2D.Destroy(SSSLUT);
        ComputeShader computeShader = Resources.Load<ComputeShader>("SSS/CS_PreIntegrateSSSLUT");
        if (computeShader == null)
        {
            Debug.LogError("PreIntegrateSSSLUT compute shader is missing");
        }
 
        SSSLUTRT = RenderTexture.GetTemporary(resolution, resolution, 0, RenderTextureFormat.ARGBHalf, RenderTextureReadWrite.Default);
        SSSLUTRT.enableRandomWrite = true;
        SSSLUT = new Texture2D(resolution, resolution, TextureFormat.RGB24, true, true);
 
        var kernelIndex = computeShader.FindKernel("PreIntegrateSSSLUT");
        computeShader.SetTexture(kernelIndex, "_RW_OutputTex", SSSLUTRT);
        computeShader.SetVector("_SSSLUTSize", new Vector4(resolution, resolution, 1f / resolution, 1f / resolution));
        computeShader.Dispatch(kernelIndex, resolution / 8, resolution / 8, 1);
 
        RenderTexture.active = SSSLUTRT;
        SSSLUT.ReadPixels(new Rect(0, 0, resolution, resolution), 0, 0);
        RenderTexture.active = null;
 
        System.IO.File.WriteAllBytes("Assets/Resources/Tex/SSSLut.jpg", SSSLUT.EncodeToJPG());
    }
 
    private void OnDestroy()
    {
        RenderTexture.ReleaseTemporary(SSSLUTRT);
        Texture2D.Destroy(SSSLUT);
    }
}