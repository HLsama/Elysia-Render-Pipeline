using System.Collections;
using System.Collections.Generic;
using System.Data.Common;
using UnityEngine;
using UnityEngine.Rendering;

public class Ey_OutlineVolumeCompact : VolumeComponent
{
    [Header("描边颜色")]
    public ColorParameter MipCount = new ColorParameter(Color.black,true);
    [Header("描边宽度")]
    public FloatParameter OutlineWitch = new FloatParameter(1.0f, true);
    [Header("描边深度阈值")]
    public FloatParameter OutlineDepthThreshold = new FloatParameter(1.0f, true);
    [Header("描边法线阈值")]
    public FloatParameter OutlineNormalThreshold = new FloatParameter(1.0f, true);
}
