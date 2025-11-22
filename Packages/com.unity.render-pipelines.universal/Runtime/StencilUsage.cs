namespace UnityEngine.Rendering.Universal.Internal
{
    // Stencil usage for deferred renderer.
    enum StencilUsage
    {
        // Bits [0,3] are reserved for users
        UserMask = 0b_0000_1111,

        // Bit [4] is used for stenciling light shapes.
        StencilLight = 0b_0001_0000,

        // Bits [5,6] are used for material types.
        MaterialMask = 0b_0110_0011,//开放Bits [0,1] 两位用于新增光照模型，这样总共可以有16种足够用了（跟别人学的，原值为0b_0110_0000）爱莉
        MaterialUnlit = 0b_0000_0000,
        MaterialLit = 0b_0010_0000,
        MaterialSimpleLit = 0b_0100_0000,
        MaterialEyeBlend = 0b_0000_0001//新增用于眼睛混合的Stencil

        // Bit [7] is reserved.
    }
}
