using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

[DisallowMultipleRendererFeature("Ey_SSR")]//此标签用于防止这个renderfeature被重复添加多次
public class Ey_SSR : ScriptableRendererFeature
{
    //[SerializeField] private Ey_SSRSettings Ey_Settings = new Ey_SSRSettings();
    private Shader Ey_Shader;
    private const string Ey_ShaderName = "Ey_SSR";
    private Material Ey_Material;
    private Ey_SSR_RenderPass Ey_RenderPass;
    private HizRenderPass Hiz_RenderPass;


    //初始化
    public override void Create()
    {
        if (Hiz_RenderPass == null)
        {
            Hiz_RenderPass = new HizRenderPass();
            Hiz_RenderPass.renderPassEvent = RenderPassEvent.AfterRenderingDeferredLights;//改到光照计算之前，方便混合
        }
        if (Ey_RenderPass == null)//没有Pass就自己new个pass(别总想着改渲染时机了，这样写最稳健，bit也不会出问题)
        {
            Ey_RenderPass = new Ey_SSR_RenderPass();
            Ey_RenderPass.renderPassEvent = RenderPassEvent.AfterRenderingDeferredLights;
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

            bool shouldAddHiz = Hiz_RenderPass.Setup(ref Ey_Material);
            if (shouldAddHiz)
            {
                renderer.EnqueuePass(Hiz_RenderPass);
            }
            bool shouldAdd = Ey_RenderPass.Setup(ref Ey_Material);
            if (shouldAdd)
            {
                renderer.EnqueuePass(Ey_RenderPass);
            }
            
        }
    }

    //释放内存
    protected override void Dispose(bool disposing)
    {
        CoreUtils.Destroy(Ey_Material);
        Hiz_RenderPass?.Dispose();
        Hiz_RenderPass = null;
        Ey_RenderPass?.Dispose();
        Ey_RenderPass = null;
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

    class Ey_SSR_RenderPass : ScriptableRenderPass
    {
        private Ey_SSRVolumeCompact ey_SSRVolumeCompact;

        private Material EyMaterial;

        //设置RT格式（分辨率，通道等）
        private RenderTextureDescriptor EySSRDescriptor;

        //SSRTexture 0,1用于传递中间纹理
        private RTHandle srcTexture;
        private RTHandle dstTexture;
        private RTHandle SSRTexture0;
        private RTHandle SSRTexture1;

        private const string SSRTexture0Name = "_SSRTexture0",
            SSRTexture1Name = "_SSRTexture1";

        //传入ID
        private static readonly int mCameraViewTopLeftCornerID = Shader.PropertyToID("_CameraViewTopLeftCorner");
        private static readonly int mCameraViewXExtentID = Shader.PropertyToID("_CameraViewXExtent");
        private static readonly int mCameraViewYExtentID = Shader.PropertyToID("_CameraViewYExtent");
        private static readonly int mProjectionParams2ID = Shader.PropertyToID("_ProjectionParams2");
        private static readonly int mStrideID = Shader.PropertyToID("_Stride");
        private static readonly int mThicknessID = Shader.PropertyToID("_Thickness");
        private static readonly int mStepCountID = Shader.PropertyToID("_StepCount");
        private static readonly int mMaxDistanceID = Shader.PropertyToID("_MaxDistance");
        private static readonly int mSourceSizeID = Shader.PropertyToID("_SourceSize");
        private static readonly int SrcTextureID = Shader.PropertyToID("_SrcTexture");
        //Pass名称
        private ProfilingSampler mProfilingSampler = new ProfilingSampler("Ey_SSR");
        
        
        internal Ey_SSR_RenderPass()
        {
            ey_SSRVolumeCompact = VolumeManager.instance.stack.GetComponent<Ey_SSRVolumeCompact>();
        }

        internal bool Setup(ref Material material)
        {
            EyMaterial = material;
            ConfigureInput(ScriptableRenderPassInput.Normal);
            return EyMaterial != null;
        }



        // This method is called before executing the render pass.
        // It can be used to configure render targets and their clear state. Also to create temporary render target textures.
        // When empty this render pass will render to the active camera render target.
        // You should never call CommandBuffer.SetRenderTarget. Instead call <c>ConfigureTarget</c> and <c>ConfigureClear</c>.
        // The render pipeline will ensure target setup and clearing happens in a performant manner.
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var renderer = renderingData.cameraData.renderer;
            //深度图重构世界坐标
            //取数据
            Matrix4x4 view = renderingData.cameraData.GetViewMatrix();
            Matrix4x4 proj = renderingData.cameraData.GetProjectionMatrix();
            Matrix4x4 vp = proj * view;
            float near = renderingData.cameraData.camera.nearClipPlane;

            //将v矩阵的平移设置为0
            Matrix4x4 cview = view;
            cview.SetColumn(3,new Vector4(0,0,0,1));
            Matrix4x4 cviewproj = proj * cview;

            //计算vp逆矩阵
            Matrix4x4 cviewprojInv = cviewproj.inverse;

            //求世界空间下近平面的四个角的坐标（这里直接用逆矩阵变回去的，也可以用入门精要的方法计算）
            Vector4 topLeftCorner = cviewprojInv.MultiplyPoint(new Vector4(-1.0f, 1.0f, -1.0f, 1.0f));
            Vector4 topRightCorner = cviewprojInv.MultiplyPoint(new Vector4(1.0f, 1.0f, -1.0f, 1.0f));
            Vector4 bottomLeftCorner = cviewprojInv.MultiplyPoint(new Vector4(-1.0f, -1.0f, -1.0f, 1.0f));
            //相机近平面上的方向向量
            Vector4 cameraXExtent = topRightCorner - topLeftCorner;
            Vector4 cameraYExtent = bottomLeftCorner - topLeftCorner;

            //发送参数
            EyMaterial.SetVector(mCameraViewTopLeftCornerID, topLeftCorner);
            EyMaterial.SetVector(mCameraViewXExtentID, cameraXExtent);
            EyMaterial.SetVector(mCameraViewYExtentID, cameraYExtent);
            EyMaterial.SetVector(mProjectionParams2ID, new Vector4(1.0f / near, renderingData.cameraData.worldSpaceCameraPos.x, renderingData.cameraData.worldSpaceCameraPos.y, renderingData.cameraData.worldSpaceCameraPos.z));

            //发送SSR相关设置
            EyMaterial.SetFloat(mStrideID, ey_SSRVolumeCompact.Stride.value);
            EyMaterial.SetFloat(mThicknessID, ey_SSRVolumeCompact.Thickness.value);
            EyMaterial.SetFloat(mStepCountID, ey_SSRVolumeCompact.StepCount.value);
            EyMaterial.SetFloat(mMaxDistanceID, ey_SSRVolumeCompact.MaxDistance.value);
            EyMaterial.SetVector(mSourceSizeID, new Vector4(EySSRDescriptor.width, EySSRDescriptor.height, 1.0f / EySSRDescriptor.width, 1.0f / EySSRDescriptor.height));


            EySSRDescriptor = renderingData.cameraData.cameraTargetDescriptor;
            EySSRDescriptor.msaaSamples = 1;
            EySSRDescriptor.depthBufferBits = 0;
            RenderingUtils.ReAllocateIfNeeded(ref SSRTexture0, EySSRDescriptor, name: SSRTexture0Name);
            RenderingUtils.ReAllocateIfNeeded(ref SSRTexture1, EySSRDescriptor, name: SSRTexture1Name);

            // 配置目标和清除
            ConfigureTarget(renderer.cameraColorTargetHandle);
            ConfigureClear(ClearFlag.None, Color.white);
        }

        // Here you can implement the rendering logic.
        // Use <c>ScriptableRenderContext</c> to issue drawing commands or execute command buffers
        // https://docs.unity3d.com/ScriptReference/Rendering.ScriptableRenderContext.html
        // You don't have to call ScriptableRenderContext.submit, the render pipeline will call it at specific points in the pipeline.
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
            //ref CameraData cameraData = ref renderingData.cameraData;
            //这里ProfilingScope其实是性能分析工具，将渲染逻辑放进这里可以顺便分析性能
            using (new ProfilingScope(cmd, mProfilingSampler))
            {
                Blitter.BlitCameraTexture(cmd, srcTexture, SSRTexture0, EyMaterial,1);
                Blitter.BlitCameraTexture(cmd, SSRTexture0, SSRTexture1, EyMaterial,2);
                Blitter.BlitCameraTexture(cmd, SSRTexture1, SSRTexture0, EyMaterial,3);
                EyMaterial.SetTexture(SrcTextureID, srcTexture);
                Blitter.BlitCameraTexture(cmd, SSRTexture0, dstTexture);
            }
            context.ExecuteCommandBuffer(cmd);
            //cmd.Clear();
            CommandBufferPool.Release(cmd);
        }

        // Cleanup any allocated resources that were created during the execution of this render pass.
        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            srcTexture = null;
            dstTexture = null;
        }
        //释放函数
        public void Dispose()
        {
            // 释放RTHandle
            SSRTexture0?.Release();
            SSRTexture1?.Release();
            //mSSRTexture1?.Release();
        }
    }
}


