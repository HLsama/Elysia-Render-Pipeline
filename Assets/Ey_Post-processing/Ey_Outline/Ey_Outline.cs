using System.Threading;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

[DisallowMultipleRendererFeature("Ey_Outline")]//此标签用于防止这个renderfeature被重复添加多次

public class Ey_Outline : ScriptableRendererFeature
{
    private Shader Ey_Shader;
    private const string Ey_ShaderName = "Ey_Post-processing/Ey_Outline";
    private Material Ey_Material;
    private Ey_OutlineRenderPass ey_OutlineRenderPass;


    //初始化
    public override void Create()
    {
        if (ey_OutlineRenderPass == null)
        {
            ey_OutlineRenderPass = new Ey_OutlineRenderPass();
            ey_OutlineRenderPass.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
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
            bool shouldAdd = ey_OutlineRenderPass.Setup(ref Ey_Material);
            if (shouldAdd)
            {
                renderer.EnqueuePass(ey_OutlineRenderPass);
            }

        }
    }
    //释放内存
    protected override void Dispose(bool disposing)
    {
        CoreUtils.Destroy(Ey_Material);
        ey_OutlineRenderPass?.Dispose();
        ey_OutlineRenderPass = null;
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
    class Ey_OutlineRenderPass : ScriptableRenderPass
    {
        private Ey_OutlineVolumeCompact ey_OutlineVolumeCompact;
        private Material EyMaterial;
        //Pass名称
        private ProfilingSampler mProfilingSampler = new ProfilingSampler("Ey_Outline");
        //设置RT格式
        private RenderTextureDescriptor EyOutlineDescriptor;

        //源纹理
        private RTHandle srcTexture;
        //创建中间纹理
        private RTHandle OutlineTexture;

        //shader相关参数
        private static readonly int OutlineDepthThresholdID = Shader.PropertyToID("_OutlineDepthThreshold");
        private static readonly int OutlineNormalThresholdID = Shader.PropertyToID("_OutlineNormalThreshold");


        internal Ey_OutlineRenderPass()
        {
            ey_OutlineVolumeCompact = VolumeManager.instance.stack.GetComponent<Ey_OutlineVolumeCompact>();
        }
        internal bool Setup(ref Material material)
        {
            EyMaterial = material;
            return EyMaterial != null;
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var renderer = renderingData.cameraData.renderer;
            EyOutlineDescriptor = renderingData.cameraData.cameraTargetDescriptor;
            EyOutlineDescriptor.msaaSamples = 1;
            EyOutlineDescriptor.depthBufferBits = 0;
            RenderingUtils.ReAllocateIfNeeded(ref OutlineTexture, EyOutlineDescriptor);
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
            //配置源纹理
            srcTexture = renderingData.cameraData.renderer.cameraColorTargetHandle;
            //执行渲染逻辑
            using (new ProfilingScope(cmd, mProfilingSampler))
            {
                cmd.SetGlobalFloat(OutlineDepthThresholdID, ey_OutlineVolumeCompact.OutlineDepthThreshold.value);
                cmd.SetGlobalFloat(OutlineNormalThresholdID, ey_OutlineVolumeCompact.OutlineNormalThreshold.value);
                Blitter.BlitCameraTexture(cmd, srcTexture, OutlineTexture, EyMaterial, 0);
                Blitter.BlitCameraTexture(cmd, OutlineTexture, srcTexture);
            }
            context.ExecuteCommandBuffer(cmd);
            //cmd.Clear();
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            srcTexture = null;
        }

        public void Dispose()
        {
            //释放中间纹理
            OutlineTexture?.Release();
        }
    }
}


