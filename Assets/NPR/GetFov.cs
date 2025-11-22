namespace UnityEngine.Rendering.Universal
{
    [ExecuteAlways]
    [AddComponentMenu("Rendering/GetFov")]
    public class GetFov : MonoBehaviour
    {
        public Material[] faceMaterial;
        [Range(0, 1)] public float CameraOffset = 0;
        void Update()
        {
            float fov = Camera.main.fieldOfView;
            if (faceMaterial.Length > 0)
            {
                foreach (Material mat in faceMaterial)
                {
                    mat.SetFloat(ShaderConstants._CameraFov,fov);
                    mat.SetFloat(ShaderConstants._CameraOffset,CameraOffset);
                }
            }
        }

        static class ShaderConstants
        {
            public static readonly int _CameraFov = Shader.PropertyToID("_CameraFov");
            public static readonly int _CameraOffset = Shader.PropertyToID("_CameraOffset");
        }
    }
}