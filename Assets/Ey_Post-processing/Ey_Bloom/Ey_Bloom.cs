using System;
using System.Threading;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;


[DisallowMultipleRendererFeature("Ey_Bloom")]//此标签用于防止这个renderfeature被重复添加多次
public class Ey_Bloom : ScriptableRendererFeature
{
    //[SerializeField] private Ey_SSRSettings Ey_Settings = new Ey_SSRSettings();
    private Shader Ey_Shader;
    private const string Ey_ShaderName = "Ey_Bloom";
    private Material Ey_Material;
    private Ey_BloomRenderPass ey_BloomRenderPass;
    //初始化
    public override void Create()
    {
        if (ey_BloomRenderPass == null)
        {
            ey_BloomRenderPass = new Ey_BloomRenderPass();
            ey_BloomRenderPass.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
        }
    }

    //添加pass
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (renderingData.cameraData.postProcessEnabled) //检测是否启用了摄象机的后处理
        {

            if (!GetMaterials())
            {
                Debug.LogErrorFormat("{0}.AddRenderPasses(): 没获取到材质球. {1} RenderPass添加失败.", GetType().Name, name);
                return;
            }
            bool shouldAdd = ey_BloomRenderPass.Setup(ref Ey_Material);
            if (shouldAdd)
            {
                renderer.EnqueuePass(ey_BloomRenderPass);
            }

        }
    }

    //释放内存
    protected override void Dispose(bool disposing)
    {
        CoreUtils.Destroy(Ey_Material);
        ey_BloomRenderPass?.Dispose();
        ey_BloomRenderPass = null;
    }

    //单独写个函数来获取材质球与shader，这样就不用手动塞入材质球了
    private bool GetMaterials()
    {
        if (Ey_Shader == null)
            Ey_Shader = Shader.Find(Ey_ShaderName);
        if (Ey_Material == null && Ey_Shader != null)
            Ey_Material = CoreUtils.CreateEngineMaterial(Ey_Shader);
        return Ey_Material != null;
    }

    class Ey_BloomRenderPass : ScriptableRenderPass
    {
        private Ey_BloomVolumeCompact ey_BloomVolumeCompact;
        private Material EyMaterial;
        //Pass名称
        private ProfilingSampler mProfilingSampler = new ProfilingSampler("Ey_Bloom");
        //设置RT格式（分辨率，通道等）
        private RenderTextureDescriptor EySSRDescriptor;
        private RenderTextureDescriptor[] MipDescriptors;

        private RTHandle srcTexture;
        private RTHandle dstTexture;
        private RTHandle MiddleTexture;
        private RTHandle SSRTexture0;
        private RTHandle[] DownTex;
        private RTHandle[] UpTex;

        private const string BloomMipDown = "_BloomMipDown";
        private const string UpMipDown = "_UpMipDown";
        private const string Middle = "Middle";
        private const string SSRTexture0Name = "_SSRTexture0";

        private static readonly int LuminanceThresholeID = Shader.PropertyToID("_luminanceThreshole");
        static readonly int PrevTexId = Shader.PropertyToID("_PrevMip");
        static readonly int BloomTexId = Shader.PropertyToID("_BloomTex");
        static readonly int BloomIntensity = Shader.PropertyToID("_BloomIntensity");

        internal Ey_BloomRenderPass()
        {
            ey_BloomVolumeCompact = VolumeManager.instance.stack.GetComponent<Ey_BloomVolumeCompact>();
            DownTex = new RTHandle[ey_BloomVolumeCompact.MipCount.value];
            UpTex = new RTHandle[ey_BloomVolumeCompact.MipCount.value];
        }

        internal bool Setup(ref Material material)
        {
            EyMaterial = material;
            return EyMaterial != null;
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var renderer = renderingData.cameraData.renderer;
            RenderTextureDescriptor desc = renderingData.cameraData.cameraTargetDescriptor;
            desc.msaaSamples = 1;
            desc.depthBufferBits = 0;
            int width = desc.width>>1;
            int height = desc.height>>1;
            MipDescriptors = new RenderTextureDescriptor[ey_BloomVolumeCompact.MipCount.value];
            RenderingUtils.ReAllocateIfNeeded(ref MiddleTexture, desc, name: Middle);
            for (int i = 0; i < ey_BloomVolumeCompact.MipCount.value; i++)
            {
                MipDescriptors[i] = new RenderTextureDescriptor(width, height,GraphicsFormat.R16G16B16A16_SFloat, 0);
                RenderingUtils.ReAllocateIfNeeded(ref DownTex[i], MipDescriptors[i], FilterMode.Bilinear, TextureWrapMode.Clamp, name: BloomMipDown+i);
                RenderingUtils.ReAllocateIfNeeded(ref UpTex[i], MipDescriptors[i], FilterMode.Bilinear, TextureWrapMode.Clamp, name: UpMipDown + i);
                //用右移运算符来表示除以2，可以减少部分异常
                width = Mathf.Max(1, width >> 1);
                height = Mathf.Max(1, height >> 1);
            }
            EySSRDescriptor = renderingData.cameraData.cameraTargetDescriptor;
            EySSRDescriptor.msaaSamples = 1;
            EySSRDescriptor.depthBufferBits = 0;
            RenderingUtils.ReAllocateIfNeeded(ref SSRTexture0, EySSRDescriptor, name: SSRTexture0Name);
            // 配置目标和清除
            ConfigureTarget(renderer.cameraColorTargetHandle);
            ConfigureClear(ClearFlag.None, Color.white);
        }
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (EyMaterial == null)
            {
                Debug.LogErrorFormat(
                    "{0}.Execute(): Missing material. ScreenSpaceAmbientOcclusion pass will not execute. Check for missing reference in the renderer resources.",
                    GetType().Name);
                return;
            }

            var cmd = CommandBufferPool.Get();
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();

            //源和目标Tex
            srcTexture = renderingData.cameraData.renderer.cameraColorTargetHandle;
            dstTexture = renderingData.cameraData.renderer.cameraColorTargetHandle;
            //这里ProfilingScope其实是性能分析工具，将渲染逻辑放进这里可以顺便分析性能
            using (new ProfilingScope(cmd, mProfilingSampler))
            {
                cmd.SetGlobalFloat(LuminanceThresholeID, ey_BloomVolumeCompact.LuminanceThreshole.value);
                Blitter.BlitCameraTexture(cmd, srcTexture, SSRTexture0, EyMaterial, 0);
                Blitter.BlitCameraTexture(cmd, SSRTexture0, DownTex[0], EyMaterial, 5);
                //在两个Pass中进行下采样（将一个二维高斯核拆解为两个一维高斯核）
                //（这里用上采样纹理只是拿来充当中间纹理）
                var lastDown = DownTex[0];
                for (int i=1;i<ey_BloomVolumeCompact.MipCount.value;i++)
                {
                    Blitter.BlitCameraTexture(cmd, lastDown, UpTex[i], RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store, EyMaterial, 1);
                    Blitter.BlitCameraTexture(cmd, UpTex[i], DownTex[i], RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store, EyMaterial, 2);
                    lastDown = DownTex[i];
                }
                //上采样
                for (int i = ey_BloomVolumeCompact.MipCount.value - 2; i >= 0; i--)
                {
                    var lowMip = (i == ey_BloomVolumeCompact.MipCount.value - 2) ? DownTex[i + 1] : UpTex[i + 1];
                    var highMip = DownTex[i];
                    cmd.SetGlobalTexture(PrevTexId, lowMip);
                    //合成
                    Blitter.BlitCameraTexture(cmd, highMip, UpTex[i], RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store, EyMaterial, 3);
                }
                cmd.SetGlobalFloat(BloomIntensity,ey_BloomVolumeCompact.BloomIntensity.value);
                cmd.SetGlobalTexture(BloomTexId, UpTex[0]);
                Blitter.BlitCameraTexture(cmd, srcTexture, MiddleTexture,EyMaterial,4);
                Blitter.BlitCameraTexture(cmd, MiddleTexture,dstTexture);
            }
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            srcTexture = null;
            dstTexture = null;
        }
        //释放函数
        public void Dispose()
        {
            SSRTexture0?.Release();
            MiddleTexture?.Release();
            foreach (var tempRT in DownTex)
            {
                tempRT?.Release();
            }
            foreach (var tempRT in UpTex)
            {
                tempRT?.Release();
            }
        }
    }
}


