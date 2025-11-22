using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

public class Ey_BloomVolumeCompact : VolumeComponent
{
    [Header("Mip次数")]
    public ClampedIntParameter MipCount = new ClampedIntParameter(6, 4, 6, true);
    [Header("亮度筛选阈值")]
    public FloatParameter LuminanceThreshole = new FloatParameter(0.8f,true);
    [Header("亮度")]
    public ClampedFloatParameter BloomIntensity = new ClampedFloatParameter(1,0,2, true);
}
