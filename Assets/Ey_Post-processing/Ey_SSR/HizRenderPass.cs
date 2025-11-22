using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;


class HizRenderPass : ScriptableRenderPass
{
    private Ey_SSRVolumeCompact ey_SSRVolumeCompact;
    private Material EyMaterial;
    private ProfilingSampler mProfilingSampler = new ProfilingSampler("HiZ");

    private RenderTextureDescriptor HiZBufferDescriptor;
    private RenderTextureDescriptor[] HiZBufferDescriptors;

    private RTHandle mHiZBufferTexture;
    private RTHandle mCameraColorTexture;
    private RTHandle mCameraDepthTexture;
    private RTHandle mDestinationTexture;
    
    private RTHandle[] mHiZBufferTextures;

    private const string mHiZBufferTextureName = "_HiZBufferTexture";

    private static readonly int mSourceSizeID = Shader.PropertyToID("_SourceSize");
    private static readonly int mHiZBufferFromMiplevelID = Shader.PropertyToID("_HierarchicalZBufferTextureFromMipLevel");
    private static readonly int mHiZBufferToMiplevelID = Shader.PropertyToID("_HierarchicalZBufferTextureToMipLevel");
    private static readonly int mHiZBufferTextureID = Shader.PropertyToID("_HierarchicalZBufferTexture");
    private static readonly int mMaxHiZBufferTextureipLevelID = Shader.PropertyToID("_MaxHierarchicalZBufferTextureMipLevel");

    
    internal HizRenderPass()
    {
        ey_SSRVolumeCompact = VolumeManager.instance.stack.GetComponent<Ey_SSRVolumeCompact>();
        mHiZBufferTextures = new RTHandle[ey_SSRVolumeCompact.MipCount.value];
    }
    internal bool Setup(ref Material material)
    {
        EyMaterial = material;
        ConfigureInput(ScriptableRenderPassInput.Normal);
        return EyMaterial != null;

    }

    public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
    {
        var renderer = renderingData.cameraData.renderer;
        //设置渲染RT
        RenderTextureDescriptor desc = renderingData.cameraData.cameraTargetDescriptor;
        //把高和宽变换为2的整次幂 然后除以2
        int width = Math.Max((int)Math.Ceiling(Mathf.Log(desc.width, 2) - 1.0f), 1);
        int height = Math.Max((int)Math.Ceiling(Mathf.Log(desc.height, 2) - 1.0f), 1);
        width = 1 << width;
        height = 1 << height;
        //设置要mip的ZbufferRT
        HiZBufferDescriptor = new RenderTextureDescriptor(width, height, RenderTextureFormat.RFloat, 0, ey_SSRVolumeCompact.MipCount.value);
        HiZBufferDescriptor.msaaSamples = 1;
        HiZBufferDescriptor.useMipMap = true;
        HiZBufferDescriptor.sRGB = false;// linear
        RenderingUtils.ReAllocateIfNeeded(ref mHiZBufferTexture, HiZBufferDescriptor, FilterMode.Bilinear, TextureWrapMode.Clamp, name: mHiZBufferTextureName);
        //逐级生成RT组，每次宽高为原先的一半
        HiZBufferDescriptors = new RenderTextureDescriptor[ey_SSRVolumeCompact.MipCount.value];
        
        for (int i = 0; i < ey_SSRVolumeCompact.MipCount.value; i++)
        {
            HiZBufferDescriptors[i] = new RenderTextureDescriptor(width, height, RenderTextureFormat.RFloat, 0, 1);
            HiZBufferDescriptors[i].msaaSamples = 1;
            HiZBufferDescriptors[i].useMipMap = false;
            HiZBufferDescriptors[i].sRGB = false;// linear
            //RenderingUtils.ReAllocateIfNeeded可以根据RenderTextureDescriptor自动销毁旧的RT创建新的RT
            RenderingUtils.ReAllocateIfNeeded(ref mHiZBufferTextures[i], HiZBufferDescriptors[i], FilterMode.Bilinear, TextureWrapMode.Clamp, name: mHiZBufferTextureName + i);
            width = Math.Max(width / 2, 1);
            height = Math.Max(height / 2, 1);
        }
        
        //配置目标和清除
        ConfigureTarget(renderer.cameraColorTargetHandle);
        ConfigureClear(ClearFlag.None, Color.white);
    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        
        if (EyMaterial == null)
        {
            Debug.LogErrorFormat("{0}.Execute(): Missing material. ScreenSpaceAmbientOcclusion pass will not execute. Check for missing reference in the renderer resources.", GetType().Name);
            return;
        }
        var cmd = CommandBufferPool.Get();
        context.ExecuteCommandBuffer(cmd);
        cmd.Clear();

        mCameraColorTexture = renderingData.cameraData.renderer.cameraColorTargetHandle;
        mCameraDepthTexture = renderingData.cameraData.renderer.cameraDepthTargetHandle;
        mDestinationTexture = renderingData.cameraData.renderer.cameraColorTargetHandle;

        using (new ProfilingScope(cmd, mProfilingSampler))
        {
            // mip 0
            Blitter.BlitCameraTexture(cmd, mCameraDepthTexture, mHiZBufferTextures[0]);
            cmd.CopyTexture(mHiZBufferTextures[0], 0, 0, mHiZBufferTexture, 0, 0);
            //mip
            
            for (int i = 1; i < ey_SSRVolumeCompact.MipCount.value; i++)
            {
                cmd.SetGlobalFloat(mHiZBufferFromMiplevelID, i - 1);
                cmd.SetGlobalFloat(mHiZBufferToMiplevelID, i);
                cmd.SetGlobalVector(mSourceSizeID, new Vector4(HiZBufferDescriptors[i - 1].width, HiZBufferDescriptors[i - 1].height, 1.0f / HiZBufferDescriptors[i - 1].width, 1.0f / HiZBufferDescriptors[i - 1].height));
                Blitter.BlitCameraTexture(cmd, mHiZBufferTextures[i - 1], mHiZBufferTextures[i], EyMaterial, 0);
                cmd.CopyTexture(mHiZBufferTextures[i], 0, 0, mHiZBufferTexture, 0, i);
            }
            cmd.SetGlobalFloat(mMaxHiZBufferTextureipLevelID, ey_SSRVolumeCompact.MipCount.value - 1);
            cmd.SetGlobalTexture(mHiZBufferTextureID, mHiZBufferTexture);
        }
        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }
    public override void OnCameraCleanup(CommandBuffer cmd)
    {
        
    }
    public void Dispose()
    {
        foreach (var tempRT in mHiZBufferTextures)
        {
            tempRT?.Release();
        }
    }
}