using System;
using System.Reflection;
using UnityEngine;

/// <summary>
/// Meta XR SDK の body / humanoid retargeting をローカル VRM に接続する。
/// 腕・手の解決は Meta 側に任せ、自前 IK は使わない。
/// </summary>
[DisallowMultipleComponent]
public class MetaControllerDrivenHumanoidRetargeting : MonoBehaviour
{
    [SerializeField] private OVRBody _body;
    [SerializeField] private VrexHumanoidRetargeter _retargeter;

    private bool _subscribed;

    public static void AttachTo(GameObject target)
    {
        if (target == null) return;
        var bridge = target.GetComponent<MetaControllerDrivenHumanoidRetargeting>();
        if (bridge == null)
            bridge = target.AddComponent<MetaControllerDrivenHumanoidRetargeting>();
        bridge.Initialize();
    }

    void OnEnable()
    {
        SubscribePermissionCallback();
        Initialize();
    }

    void OnDisable()
    {
        UnsubscribePermissionCallback();
    }

    public void Initialize()
    {
        ConfigureManager();
        EnsureComponents();

        OVRBody.SetRequestedJointSet(OVRPlugin.BodyJointSet.UpperBody);
        Debug.Log("[MetaRetarget] Initialize: UpperBody requested, controller-driven hands = Natural");

        if (OVRPermissionsRequester.IsPermissionGranted(OVRPermissionsRequester.Permission.BodyTracking))
        {
            Debug.Log("[MetaRetarget] Body tracking permission already granted.");
            EnableRetargeting();
        }
        else
        {
            Debug.Log("[MetaRetarget] Requesting body tracking permission.");
            DisableRetargeting();
            OVRPermissionsRequester.Request(new[] { OVRPermissionsRequester.Permission.BodyTracking });
        }
    }

    private void EnsureComponents()
    {
        if (_body == null)
            _body = gameObject.GetComponent<OVRBody>() ?? gameObject.AddComponent<OVRBody>();

        if (_retargeter == null)
            _retargeter = gameObject.GetComponent<VrexHumanoidRetargeter>() ?? gameObject.AddComponent<VrexHumanoidRetargeter>();

        _body.ProvidedSkeletonType = OVRPlugin.BodyJointSet.UpperBody;
        _retargeter.ConfigureForControllerDrivenHands();
        Debug.Log("[MetaRetarget] Components ready: OVRBody + VrexHumanoidRetargeter");
    }

    private void ConfigureManager()
    {
        var manager = FindObjectOfType<OVRManager>();
        if (manager == null) return;

        manager.controllerDrivenHandPosesType = OVRManager.ControllerDrivenHandPosesType.Natural;
        manager.SimultaneousHandsAndControllersEnabled = false;
        manager.wideMotionModeHandPosesEnabled = false;

        var permissionField = typeof(OVRManager).GetField(
            "requestBodyTrackingPermissionOnStartup",
            BindingFlags.Instance | BindingFlags.NonPublic);
        permissionField?.SetValue(manager, true);
        Debug.Log("[MetaRetarget] OVRManager configured for body tracking + controller-driven hands.");
    }

    private void EnableRetargeting()
    {
        if (_body != null) _body.enabled = true;
        if (_retargeter != null) _retargeter.enabled = true;
        Debug.Log("[MetaRetarget] Retargeting enabled.");
    }

    private void DisableRetargeting()
    {
        if (_retargeter != null) _retargeter.enabled = false;
        if (_body != null) _body.enabled = false;
        Debug.Log("[MetaRetarget] Retargeting disabled.");
    }

    private void SubscribePermissionCallback()
    {
        if (_subscribed) return;
        OVRPermissionsRequester.PermissionGranted += HandlePermissionGranted;
        _subscribed = true;
    }

    private void UnsubscribePermissionCallback()
    {
        if (!_subscribed) return;
        OVRPermissionsRequester.PermissionGranted -= HandlePermissionGranted;
        _subscribed = false;
    }

    private void HandlePermissionGranted(string permissionId)
    {
        if (permissionId != OVRPermissionsRequester.BodyTrackingPermission) return;
        Debug.Log("[MetaRetarget] Body tracking permission granted callback received.");
        EnableRetargeting();
    }
}

/// <summary>
/// Meta の humanoid retargeter を VRM の腕・手用途に絞り込む。
/// head / torso / hips は既存ローカル制御を維持する。
/// </summary>
public class VrexHumanoidRetargeter : OVRUnityHumanoidSkeletonRetargeter
{
    private static readonly OVRHumanBodyBonesMappings.BodySection[] ArmSections =
    {
        OVRHumanBodyBonesMappings.BodySection.LeftArm,
        OVRHumanBodyBonesMappings.BodySection.RightArm,
        OVRHumanBodyBonesMappings.BodySection.LeftHand,
        OVRHumanBodyBonesMappings.BodySection.RightHand,
    };

    public void ConfigureForControllerDrivenHands()
    {
        _adjustments = Array.Empty<JointAdjustment>();
        _bodySectionsToAlign = ArmSections;
        _bodySectionToPosition = ArmSections;
        _fullBodySectionsToAlign = ArmSections;
        _fullBodySectionToPosition = ArmSections;
        _updateType = UpdateType.UpdateOnly;
    }

    void Awake()
    {
        ConfigureForControllerDrivenHands();
    }

    protected override void Start()
    {
        ConfigureForControllerDrivenHands();
        base.Start();
    }
}
