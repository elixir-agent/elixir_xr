using UnityEngine;

/// <summary>
/// 起動時に Canvas をカメラの正面 2m に配置する。
/// Quest でどの方向を向いていても UI が見えるようにする。
/// </summary>
public class VRCanvasPositioner : MonoBehaviour
{
    [SerializeField] private float distance = 2f;
    [SerializeField] private float heightOffset = 0f;

    void Start()
    {
        var cam = Camera.main;
        if (cam == null) cam = FindObjectOfType<Camera>();
        if (cam == null) return;

        // カメラの正面 distance m の位置に配置（高さオフセット付き）
        Vector3 forward = cam.transform.forward;
        forward.y = 0f;
        if (forward == Vector3.zero) forward = Vector3.forward;
        forward.Normalize();

        transform.position = cam.transform.position
            + forward * distance
            + Vector3.up * heightOffset;

        // Canvas がカメラの方を向く
        transform.rotation = Quaternion.LookRotation(
            transform.position - cam.transform.position);
    }
}
