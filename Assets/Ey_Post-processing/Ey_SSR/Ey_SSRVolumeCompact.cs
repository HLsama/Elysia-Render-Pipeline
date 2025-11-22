using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

public class Ey_SSRVolumeCompact : VolumeComponent
{

    [Header("物体厚度")]
    public ClampedFloatParameter Thickness = new ClampedFloatParameter(0.75f, 0.1f, 1f,true);

    [Header("步进距离")]
    public ClampedIntParameter Stride = new ClampedIntParameter(4, 1, 8, true);

    [Header("最大迭代次数")]
    public ClampedIntParameter StepCount = new ClampedIntParameter(64, 16, 256, true);

    [Header("最长步进长度")]
    public ClampedFloatParameter MaxDistance = new ClampedFloatParameter(10f, 1f, 20f, true);

    [Header("MipZBuffer层级")]
    //在1080P以下最佳设置为3
    //在1080P左右最佳设置为4
    //在4K左右最佳设置为5
    public ClampedIntParameter MipCount = new ClampedIntParameter(4, 3, 6, true);

}
