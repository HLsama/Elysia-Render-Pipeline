using UnityEditor;
using UnityEngine;
using System.Collections.Generic;
using System.IO;


public enum WRITETYPE
{
    VertexColor = 0,
    Tangent = 1,
    uv3 = 2,
}
public class EySmoothNormalTools : EditorWindow
{

    public WRITETYPE wt;

    public Object SrcMesh;
    // public bool customMesh;

    [MenuItem("Tools/平滑法线工具")]
    public static void ShowWindow()
    {
        EditorWindow.GetWindow(typeof(EySmoothNormalTools));//显示现有窗口实例。如果没有，请创建一个。
    }


    void OnGUI()
    {
        SrcMesh = (Object)EditorGUILayout.ObjectField("源模型", SrcMesh, typeof(Object), false);
        wt = (WRITETYPE)EditorGUILayout.EnumPopup("写入目标", wt);
        switch (wt)
        {
            case WRITETYPE.Tangent://执行写入到 顶点切线
                GUILayout.Label("  将会把平滑后的法线写入到顶点切线中", EditorStyles.boldLabel);
                break;
            case WRITETYPE.VertexColor:// 写入到顶点色
                GUILayout.Label("  将会把平滑后的法线写入到顶点色的RGB中，A保持不变", EditorStyles.boldLabel);
                break;
            case WRITETYPE.uv3:// UV3中
                GUILayout.Label("  将会把平滑后的法线以切线空间写入到UV3中，需要自己解码法线", EditorStyles.boldLabel);
                break;
        }
        if (GUILayout.Button("导出模型"))
        {//执行平滑
            //SmoothNormalPrev(wt);
        }
        GUILayout.Label("  会将mesh保存到Assets/SmoothNormalTools/下", EditorStyles.boldLabel);
        GUILayout.Space(5);
    }
}