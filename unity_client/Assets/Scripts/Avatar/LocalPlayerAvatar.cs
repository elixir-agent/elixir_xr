using UnityEngine;

/// <summary>
/// ローカルプレイヤーのアバター root / head と、コントローラ proxy を管理する。
/// 腕は肩を支点にした二関節IKで解き、肘は左右それぞれ体の外側へ曲がるように安定化する。
/// </summary>
[DefaultExecutionOrder(10000)]
public class LocalPlayerAvatar : MonoBehaviour
{
    [Header("VRM Loader")]
    [SerializeField] private VrmAvatarLoader _loader;

    [Header("Proxy Hands")]
    [SerializeField] private GameObject _leftHandProxy;
    [SerializeField] private GameObject _rightHandProxy;

    private Transform _hmdAnchor;
    private Transform _trackingSpace;
    private Vector3 _stableBodyXZ;
    private bool _stableBodyInitialized;
    private bool _armRestPoseInitialized;
    private Quaternion _rightShoulderLocalRotation;
    private Quaternion _rightUpperArmLocalRotation;
    private Quaternion _rightLowerArmLocalRotation;
    private Quaternion _rightHandLocalRotation;
    private Quaternion _leftShoulderLocalRotation;
    private Quaternion _leftUpperArmLocalRotation;
    private Quaternion _leftLowerArmLocalRotation;
    private Quaternion _leftHandLocalRotation;

    private struct ArmBones
    {
        public Transform Shoulder;
        public Transform UpperArm;
        public Transform LowerArm;
        public Transform Hand;
        public bool IsValid =>
            Shoulder != null && UpperArm != null && LowerArm != null && Hand != null;
    }

    void Start()
    {
        EnsureAvatarProxies();

        var ovrRig = FindObjectOfType<OVRCameraRig>();
        _hmdAnchor = ovrRig != null ? ovrRig.centerEyeAnchor : Camera.main?.transform;
        _trackingSpace = ovrRig?.trackingSpace;
        if (_hmdAnchor == null)
            _hmdAnchor = Camera.main?.transform ?? transform;
    }

    void LateUpdate()
    {
        GetControllerPose(OVRInput.Controller.RTouch, out Vector3 rPos, out Quaternion rRot);
        GetControllerPose(OVRInput.Controller.LTouch, out Vector3 lPos, out Quaternion lRot);

        UpdateProxy(_rightHandProxy, rPos, rRot);
        UpdateProxy(_leftHandProxy, lPos, lRot);

        var avatar = _loader?.LoadedAvatar;
        if (avatar == null || _hmdAnchor == null) return;

        var anim = avatar.GetComponent<Animator>();
        if (anim == null || !anim.isHuman) return;

        var playerController = GetComponent<QuestPlayerController>();
        Vector3 stableBodyPosition = playerController != null ? playerController.StableBodyPosition : transform.position;

        Vector3 camFwd = _hmdAnchor.forward;
        camFwd.y = 0f;
        if (camFwd.sqrMagnitude > 0.001f)
            avatar.transform.rotation = Quaternion.LookRotation(camFwd.normalized, Vector3.up);

        var headBone = anim.GetBoneTransform(HumanBodyBones.Head);
        if (headBone != null)
            headBone.rotation = _hmdAnchor.rotation;

        if (!_stableBodyInitialized)
        {
            _stableBodyXZ = new Vector3(stableBodyPosition.x, 0f, stableBodyPosition.z);
            _stableBodyInitialized = true;
        }
        _stableBodyXZ = new Vector3(stableBodyPosition.x, 0f, stableBodyPosition.z);

        Vector3 candidateRoot = avatar.transform.position;
        if (headBone != null)
        {
            candidateRoot += new Vector3(
                _stableBodyXZ.x - headBone.position.x,
                _hmdAnchor.position.y - headBone.position.y,
                _stableBodyXZ.z - headBone.position.z);
        }
        else
        {
            candidateRoot = new Vector3(_stableBodyXZ.x, _hmdAnchor.position.y, _stableBodyXZ.z);
        }

        candidateRoot.y = Mathf.Max(candidateRoot.y, transform.position.y);
        avatar.transform.position = candidateRoot;

        EnsureArmRestPose(anim);

        ApplyControllerArmIK(anim, HumanBodyBones.RightShoulder, HumanBodyBones.RightUpperArm,
            HumanBodyBones.RightLowerArm, HumanBodyBones.RightHand, rPos, rRot, true, avatar.transform);
        ApplyControllerArmIK(anim, HumanBodyBones.LeftShoulder, HumanBodyBones.LeftUpperArm,
            HumanBodyBones.LeftLowerArm, HumanBodyBones.LeftHand, lPos, lRot, false, avatar.transform);
    }

    void EnsureAvatarProxies()
    {
        if (_leftHandProxy == null)
            _leftHandProxy = CreateHandProxy("LeftHandProxy", new Color(0.2f, 0.8f, 1f, 0.9f));

        if (_rightHandProxy == null)
            _rightHandProxy = CreateHandProxy("RightHandProxy", new Color(1f, 0.7f, 0.2f, 0.9f));
    }

    GameObject CreateHandProxy(string proxyName, Color color)
    {
        var proxy = GameObject.CreatePrimitive(PrimitiveType.Sphere);
        proxy.name = proxyName;
        proxy.transform.SetParent(transform, false);
        proxy.transform.localScale = Vector3.one * 0.06f;
        var collider = proxy.GetComponent<Collider>();
        if (collider != null) Destroy(collider);
        ApplyProxyMaterial(proxy, color);
        return proxy;
    }

    void ApplyProxyMaterial(GameObject proxy, Color color)
    {
        var renderer = proxy.GetComponent<Renderer>();
        if (renderer == null) return;
        var shader = Shader.Find("Unlit/Color") ?? Shader.Find("Universal Render Pipeline/Unlit") ?? Shader.Find("Standard");
        if (shader == null) return;
        var mat = new Material(shader);
        if (mat.HasProperty("_Color")) mat.color = color;
        renderer.material = mat;
    }

    void GetControllerPose(OVRInput.Controller controller, out Vector3 pos, out Quaternion rot)
    {
        Transform ts = _trackingSpace ?? transform;
        Vector3 lp = OVRInput.GetLocalControllerPosition(controller);
        Quaternion lr = OVRInput.GetLocalControllerRotation(controller);
        pos = ts.TransformPoint(lp);
        rot = ts.rotation * lr;
    }

    static void UpdateProxy(GameObject proxy, Vector3 pos, Quaternion rot)
    {
        if (proxy == null) return;
        proxy.transform.position = pos;
        proxy.transform.rotation = rot;
    }

    public async void LoadAvatarFromUrl(string url, string avatarId)
    {
        if (_loader == null)
        {
            Debug.LogWarning("[LocalAvatar] Loader is not assigned.");
            return;
        }

        Debug.Log($"[LocalAvatar] Loading avatar_id={avatarId} url={url}");
        bool ok = await _loader.LoadFromUrl(url, avatarId);
        Debug.Log(ok
            ? $"[LocalAvatar] Avatar loaded: {avatarId}"
            : $"[LocalAvatar] Avatar load failed: {avatarId}");
    }

    void ApplyControllerArmIK(
        Animator animator,
        HumanBodyBones shoulderBone,
        HumanBodyBones upperArmBone,
        HumanBodyBones lowerArmBone,
        HumanBodyBones handBone,
        Vector3 controllerPosition,
        Quaternion controllerRotation,
        bool isRight,
        Transform avatarRoot)
    {
        var bones = new ArmBones
        {
            Shoulder = animator.GetBoneTransform(shoulderBone),
            UpperArm = animator.GetBoneTransform(upperArmBone),
            LowerArm = animator.GetBoneTransform(lowerArmBone),
            Hand = animator.GetBoneTransform(handBone),
        };
        if (!bones.IsValid) return;

        RestoreArmRestPose(bones, isRight);

        Vector3 shoulderPos = bones.Shoulder.position;
        Vector3 upperPos = bones.UpperArm.position;
        float upperLength = Vector3.Distance(bones.UpperArm.position, bones.LowerArm.position);
        float lowerLength = Vector3.Distance(bones.LowerArm.position, bones.Hand.position);
        if (upperLength < 0.0001f || lowerLength < 0.0001f) return;

        Vector3 toController = controllerPosition - upperPos;
        float maxReach = Mathf.Max(upperLength + lowerLength - 0.002f, upperLength);
        Vector3 targetPos = upperPos + Vector3.ClampMagnitude(toController, maxReach);

        SolveArmTwoBoneIK(bones, targetPos, controllerRotation, isRight, avatarRoot);
    }

    void SolveArmTwoBoneIK(ArmBones bones, Vector3 targetPos, Quaternion targetRot, bool isRight, Transform avatarRoot)
    {
        Vector3 upperPos = bones.UpperArm.position;
        Vector3 lowerPos = bones.LowerArm.position;
        Vector3 handPos = bones.Hand.position;

        float upperLength = Vector3.Distance(upperPos, lowerPos);
        float lowerLength = Vector3.Distance(lowerPos, handPos);
        Vector3 upperToTarget = targetPos - upperPos;
        if (upperToTarget.sqrMagnitude < 0.000001f) return;

        Vector3 targetDir = upperToTarget.normalized;
        float clampedDistance = Mathf.Clamp(upperToTarget.magnitude, Mathf.Abs(upperLength - lowerLength) + 0.0005f, upperLength + lowerLength - 0.0005f);

        Vector3 outwardAxis = avatarRoot.right * (isRight ? 1f : -1f);
        Vector3 bendDir = Vector3.ProjectOnPlane(outwardAxis, targetDir);
        if (bendDir.sqrMagnitude < 0.0001f)
            bendDir = Vector3.ProjectOnPlane(-avatarRoot.forward, targetDir);
        if (bendDir.sqrMagnitude < 0.0001f)
            bendDir = Vector3.ProjectOnPlane(avatarRoot.up, targetDir);
        if (bendDir.sqrMagnitude < 0.0001f)
            return;
        bendDir.Normalize();

        float shoulderAlong = Mathf.Clamp(
            (upperLength * upperLength + clampedDistance * clampedDistance - lowerLength * lowerLength) /
            (2f * clampedDistance),
            0f, upperLength);
        float elbowHeight = Mathf.Sqrt(Mathf.Max(upperLength * upperLength - shoulderAlong * shoulderAlong, 0f));
        Vector3 elbowPos = upperPos + targetDir * shoulderAlong + bendDir * elbowHeight;

        Vector3 currentUpperDir = (lowerPos - upperPos).normalized;
        Vector3 desiredUpperDir = (elbowPos - upperPos).normalized;
        if (desiredUpperDir.sqrMagnitude > 0.0001f)
            bones.UpperArm.rotation = Quaternion.FromToRotation(currentUpperDir, desiredUpperDir) * bones.UpperArm.rotation;

        lowerPos = bones.LowerArm.position;
        handPos = bones.Hand.position;
        Vector3 currentLowerDir = (handPos - lowerPos).normalized;
        Vector3 desiredLowerDir = (targetPos - lowerPos).normalized;
        if (desiredLowerDir.sqrMagnitude > 0.0001f)
            bones.LowerArm.rotation = Quaternion.FromToRotation(currentLowerDir, desiredLowerDir) * bones.LowerArm.rotation;

        bones.Hand.rotation = targetRot;
    }

    void EnsureArmRestPose(Animator animator)
    {
        if (_armRestPoseInitialized) return;

        CacheArmRestPose(animator, true,
            ref _rightShoulderLocalRotation,
            ref _rightUpperArmLocalRotation,
            ref _rightLowerArmLocalRotation,
            ref _rightHandLocalRotation);
        CacheArmRestPose(animator, false,
            ref _leftShoulderLocalRotation,
            ref _leftUpperArmLocalRotation,
            ref _leftLowerArmLocalRotation,
            ref _leftHandLocalRotation);

        _armRestPoseInitialized = true;
    }

    void CacheArmRestPose(Animator animator, bool isRight,
        ref Quaternion shoulderRot, ref Quaternion upperRot, ref Quaternion lowerRot, ref Quaternion handRot)
    {
        shoulderRot = animator.GetBoneTransform(isRight ? HumanBodyBones.RightShoulder : HumanBodyBones.LeftShoulder)?.localRotation ?? Quaternion.identity;
        upperRot = animator.GetBoneTransform(isRight ? HumanBodyBones.RightUpperArm : HumanBodyBones.LeftUpperArm)?.localRotation ?? Quaternion.identity;
        lowerRot = animator.GetBoneTransform(isRight ? HumanBodyBones.RightLowerArm : HumanBodyBones.LeftLowerArm)?.localRotation ?? Quaternion.identity;
        handRot = animator.GetBoneTransform(isRight ? HumanBodyBones.RightHand : HumanBodyBones.LeftHand)?.localRotation ?? Quaternion.identity;
    }

    void RestoreArmRestPose(ArmBones bones, bool isRight)
    {
        if (!_armRestPoseInitialized) return;

        if (isRight)
        {
            bones.Shoulder.localRotation = _rightShoulderLocalRotation;
            bones.UpperArm.localRotation = _rightUpperArmLocalRotation;
            bones.LowerArm.localRotation = _rightLowerArmLocalRotation;
            bones.Hand.localRotation = _rightHandLocalRotation;
        }
        else
        {
            bones.Shoulder.localRotation = _leftShoulderLocalRotation;
            bones.UpperArm.localRotation = _leftUpperArmLocalRotation;
            bones.LowerArm.localRotation = _leftLowerArmLocalRotation;
            bones.Hand.localRotation = _leftHandLocalRotation;
        }
    }
}
