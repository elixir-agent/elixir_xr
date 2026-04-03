using System.Collections.Generic;
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

    [Header("Hand Rotation Offsets")]
    [SerializeField] private Vector3 _leftHandRotationOffsetEuler = new Vector3(0f, 0f, -90f);
    [SerializeField] private Vector3 _rightHandRotationOffsetEuler = new Vector3(0f, 0f, 90f);
    [SerializeField] private Vector3 _handFacingCorrectionEuler = new Vector3(90f, 0f, 0f);

    [Header("Hand Pose")]
    [SerializeField] private float _fingerProximalCurlAngle = 55f;
    [SerializeField] private float _fingerIntermediateCurlAngle = 72f;
    [SerializeField] private float _fingerDistalCurlAngle = 48f;
    [SerializeField] private float _indexPinchBias = 0.85f;
    [SerializeField] private float _thumbOppositionAngle = 28f;
    [SerializeField] private float _thumbCurlAngle = 36f;
    [SerializeField] private float _thumbTipCurlAngle = 18f;

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
    private readonly Dictionary<HumanBodyBones, Quaternion> _fingerRestLocalRotations = new();
    private Quaternion _rightHandBasisLocalRotation = Quaternion.identity;
    private Quaternion _leftHandBasisLocalRotation = Quaternion.identity;

    private struct ArmBones
    {
        public Transform Shoulder;
        public Transform UpperArm;
        public Transform LowerArm;
        public Transform Hand;
        public bool IsValid =>
            Shoulder != null && UpperArm != null && LowerArm != null && Hand != null;
    }

    private readonly struct FingerCurlSegment
    {
        public FingerCurlSegment(HumanBodyBones bone, Vector3 axis, float angleScale, Vector3? secondaryAxis = null, float secondaryScale = 0f)
        {
            Bone = bone;
            Axis = axis;
            AngleScale = angleScale;
            SecondaryAxis = secondaryAxis ?? Vector3.zero;
            SecondaryScale = secondaryScale;
        }

        public HumanBodyBones Bone { get; }
        public Vector3 Axis { get; }
        public float AngleScale { get; }
        public Vector3 SecondaryAxis { get; }
        public float SecondaryScale { get; }
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
        float rightGrip = GetHandPoseStrength(OVRInput.Controller.RTouch, true);
        float leftGrip = GetHandPoseStrength(OVRInput.Controller.LTouch, false);

        UpdateProxy(_rightHandProxy, rPos, rRot);
        UpdateProxy(_leftHandProxy, lPos, lRot);

        var avatar = _loader?.LoadedAvatar;
        UpdateProxyVisibility(avatar == null);
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
        ApplyHandPose(anim, true, rightGrip);
        ApplyHandPose(anim, false, leftGrip);
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

    float GetHandPoseStrength(OVRInput.Controller controller, bool isRight)
    {
        OVRInput.Axis1D gripAxis = isRight
            ? OVRInput.Axis1D.SecondaryHandTrigger
            : OVRInput.Axis1D.PrimaryHandTrigger;
        OVRInput.Axis1D indexAxis = isRight
            ? OVRInput.Axis1D.SecondaryIndexTrigger
            : OVRInput.Axis1D.PrimaryIndexTrigger;

        float grip = OVRInput.Get(gripAxis, controller);
        float index = OVRInput.Get(indexAxis, controller);
        return Mathf.Clamp01(Mathf.Max(grip, index));
    }

    static void UpdateProxy(GameObject proxy, Vector3 pos, Quaternion rot)
    {
        if (proxy == null) return;
        proxy.transform.position = pos;
        proxy.transform.rotation = rot;
    }

    void UpdateProxyVisibility(bool visible)
    {
        if (_leftHandProxy != null && _leftHandProxy.activeSelf != visible)
            _leftHandProxy.SetActive(visible);

        if (_rightHandProxy != null && _rightHandProxy.activeSelf != visible)
            _rightHandProxy.SetActive(visible);
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

        SolveArmTwoBoneIK(animator, bones, targetPos, controllerRotation, isRight, avatarRoot);
    }

    void SolveArmTwoBoneIK(Animator animator, ArmBones bones, Vector3 targetPos, Quaternion targetRot, bool isRight, Transform avatarRoot)
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

        bones.Hand.rotation = GetHandTargetRotation(animator, bones.Hand, targetRot, isRight, avatarRoot);
    }

    Quaternion GetHandTargetRotation(Animator animator, Transform hand, Quaternion controllerRotation, bool isRight, Transform avatarRoot)
    {
        if (!TryGetHandBasisLocalRotation(animator, hand, isRight, out Quaternion handBasisLocalRotation))
        {
            Vector3 offsetEuler = isRight ? _rightHandRotationOffsetEuler : _leftHandRotationOffsetEuler;
            return controllerRotation
                * Quaternion.Euler(offsetEuler)
                * Quaternion.Euler(_handFacingCorrectionEuler);
        }

        Vector3 desiredFingerDir = controllerRotation * Vector3.forward;
        Vector3 desiredPalmDir = controllerRotation * (isRight ? Vector3.left : Vector3.right);
        Quaternion basisWorldRotation = hand.rotation * handBasisLocalRotation;
        Vector3 currentFingerDir = basisWorldRotation * Vector3.forward;
        Vector3 currentPalmDir = basisWorldRotation * Vector3.up;

        Quaternion alignFinger = Quaternion.FromToRotation(currentFingerDir, desiredFingerDir);
        Vector3 desiredPalmOnPlane = Vector3.ProjectOnPlane(desiredPalmDir, desiredFingerDir).normalized;
        Vector3 currentPalmOnPlane = Vector3.ProjectOnPlane(alignFinger * currentPalmDir, desiredFingerDir).normalized;

        if (currentPalmOnPlane.sqrMagnitude < 0.0001f || desiredPalmOnPlane.sqrMagnitude < 0.0001f)
            return ApplyHandRollCorrection(alignFinger * hand.rotation, desiredFingerDir, isRight);

        float twistAngle = Vector3.SignedAngle(currentPalmOnPlane, desiredPalmOnPlane, desiredFingerDir);
        Quaternion twist = Quaternion.AngleAxis(twistAngle, desiredFingerDir);
        return ApplyHandRollCorrection(twist * alignFinger * hand.rotation, desiredFingerDir, isRight);
    }

    Quaternion ApplyHandRollCorrection(Quaternion rotation, Vector3 fingerAxis, bool isRight)
    {
        if (!isRight) return rotation;
        return Quaternion.AngleAxis(180f, fingerAxis) * rotation;
    }

    bool TryGetHandBasisLocalRotation(Animator animator, Transform hand, bool isRight, out Quaternion handBasisLocalRotation)
    {
        handBasisLocalRotation = isRight ? _rightHandBasisLocalRotation : _leftHandBasisLocalRotation;
        if (hand == null) return false;
        if (handBasisLocalRotation != Quaternion.identity) return true;

        var index = animator.GetBoneTransform(isRight ? HumanBodyBones.RightIndexProximal : HumanBodyBones.LeftIndexProximal);
        var middle = animator.GetBoneTransform(isRight ? HumanBodyBones.RightMiddleProximal : HumanBodyBones.LeftMiddleProximal);
        var ring = animator.GetBoneTransform(isRight ? HumanBodyBones.RightRingProximal : HumanBodyBones.LeftRingProximal);
        var little = animator.GetBoneTransform(isRight ? HumanBodyBones.RightLittleProximal : HumanBodyBones.LeftLittleProximal);
        if (index == null || middle == null || ring == null || little == null || hand == null) return false;

        Vector3 handPos = hand.position;
        Vector3 fingerDir = (
            (index.position - handPos) +
            (middle.position - handPos) +
            (ring.position - handPos) +
            (little.position - handPos)).normalized;
        if (fingerDir.sqrMagnitude < 0.0001f) return false;

        Vector3 acrossPalm = little.position - index.position;
        Vector3 palmDir = Vector3.Cross(fingerDir, acrossPalm).normalized;
        if (palmDir.sqrMagnitude < 0.0001f) return false;

        handBasisLocalRotation = Quaternion.Inverse(hand.rotation) * Quaternion.LookRotation(fingerDir, palmDir);
        if (isRight)
            _rightHandBasisLocalRotation = handBasisLocalRotation;
        else
            _leftHandBasisLocalRotation = handBasisLocalRotation;
        return true;
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
        CacheFingerRestPose(animator);
        CacheHandBasis(animator, true);
        CacheHandBasis(animator, false);

        _armRestPoseInitialized = true;
    }

    void CacheHandBasis(Animator animator, bool isRight)
    {
        var hand = animator.GetBoneTransform(isRight ? HumanBodyBones.RightHand : HumanBodyBones.LeftHand);
        if (hand == null) return;
        if (TryGetHandBasisLocalRotation(animator, hand, isRight, out Quaternion basis))
        {
            if (isRight)
                _rightHandBasisLocalRotation = basis;
            else
                _leftHandBasisLocalRotation = basis;
        }
    }

    void CacheFingerRestPose(Animator animator)
    {
        _fingerRestLocalRotations.Clear();
        foreach (var bone in FingerBones)
        {
            var t = animator.GetBoneTransform(bone);
            if (t != null)
                _fingerRestLocalRotations[bone] = t.localRotation;
        }
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

    void ApplyHandPose(Animator animator, bool isRight, float curlStrength)
    {
        if (!_armRestPoseInitialized) return;
        float mirroredSide = isRight ? 1f : -1f;

        ApplyFingerCurl(animator, isRight ? RightThumbCurl : LeftThumbCurl, curlStrength, mirroredSide);
        ApplyFingerCurl(animator, isRight ? RightIndexCurl : LeftIndexCurl, curlStrength * _indexPinchBias, mirroredSide);
        ApplyFingerCurl(animator, isRight ? RightMiddleCurl : LeftMiddleCurl, curlStrength, mirroredSide);
        ApplyFingerCurl(animator, isRight ? RightRingCurl : LeftRingCurl, curlStrength, mirroredSide);
        ApplyFingerCurl(animator, isRight ? RightLittleCurl : LeftLittleCurl, curlStrength, mirroredSide);
    }

    void ApplyFingerCurl(Animator animator, FingerCurlSegment[] segments, float curlStrength, float mirroredSide)
    {
        foreach (var segment in segments)
        {
            var finger = animator.GetBoneTransform(segment.Bone);
            if (finger == null || !_fingerRestLocalRotations.TryGetValue(segment.Bone, out Quaternion rest)) continue;

            Quaternion curlRotation = Quaternion.AngleAxis(segment.AngleScale * curlStrength, segment.Axis);
            Quaternion secondaryRotation = segment.SecondaryScale == 0f
                ? Quaternion.identity
                : Quaternion.AngleAxis(segment.SecondaryScale * curlStrength * mirroredSide, segment.SecondaryAxis);
            finger.localRotation = rest * secondaryRotation * curlRotation;
        }
    }

    static readonly HumanBodyBones[] FingerBones =
    {
        HumanBodyBones.LeftThumbProximal,
        HumanBodyBones.LeftThumbIntermediate,
        HumanBodyBones.LeftThumbDistal,
        HumanBodyBones.LeftIndexProximal,
        HumanBodyBones.LeftIndexIntermediate,
        HumanBodyBones.LeftIndexDistal,
        HumanBodyBones.LeftMiddleProximal,
        HumanBodyBones.LeftMiddleIntermediate,
        HumanBodyBones.LeftMiddleDistal,
        HumanBodyBones.LeftRingProximal,
        HumanBodyBones.LeftRingIntermediate,
        HumanBodyBones.LeftRingDistal,
        HumanBodyBones.LeftLittleProximal,
        HumanBodyBones.LeftLittleIntermediate,
        HumanBodyBones.LeftLittleDistal,
        HumanBodyBones.RightThumbProximal,
        HumanBodyBones.RightThumbIntermediate,
        HumanBodyBones.RightThumbDistal,
        HumanBodyBones.RightIndexProximal,
        HumanBodyBones.RightIndexIntermediate,
        HumanBodyBones.RightIndexDistal,
        HumanBodyBones.RightMiddleProximal,
        HumanBodyBones.RightMiddleIntermediate,
        HumanBodyBones.RightMiddleDistal,
        HumanBodyBones.RightRingProximal,
        HumanBodyBones.RightRingIntermediate,
        HumanBodyBones.RightRingDistal,
        HumanBodyBones.RightLittleProximal,
        HumanBodyBones.RightLittleIntermediate,
        HumanBodyBones.RightLittleDistal
    };

    FingerCurlSegment[] LeftThumbCurl => new[]
    {
        new FingerCurlSegment(HumanBodyBones.LeftThumbProximal, Vector3.right, _thumbCurlAngle, Vector3.up, _thumbOppositionAngle),
        new FingerCurlSegment(HumanBodyBones.LeftThumbIntermediate, Vector3.right, _thumbCurlAngle * 0.8f, Vector3.up, _thumbOppositionAngle * 0.45f),
        new FingerCurlSegment(HumanBodyBones.LeftThumbDistal, Vector3.right, _thumbTipCurlAngle)
    };

    FingerCurlSegment[] RightThumbCurl => new[]
    {
        new FingerCurlSegment(HumanBodyBones.RightThumbProximal, Vector3.right, _thumbCurlAngle, Vector3.up, _thumbOppositionAngle),
        new FingerCurlSegment(HumanBodyBones.RightThumbIntermediate, Vector3.right, _thumbCurlAngle * 0.8f, Vector3.up, _thumbOppositionAngle * 0.45f),
        new FingerCurlSegment(HumanBodyBones.RightThumbDistal, Vector3.right, _thumbTipCurlAngle)
    };

    FingerCurlSegment[] LeftIndexCurl => CreateFingerCurlChain(
        HumanBodyBones.LeftIndexProximal,
        HumanBodyBones.LeftIndexIntermediate,
        HumanBodyBones.LeftIndexDistal,
        -8f);

    FingerCurlSegment[] RightIndexCurl => CreateFingerCurlChain(
        HumanBodyBones.RightIndexProximal,
        HumanBodyBones.RightIndexIntermediate,
        HumanBodyBones.RightIndexDistal,
        -8f);

    FingerCurlSegment[] LeftMiddleCurl => CreateFingerCurlChain(
        HumanBodyBones.LeftMiddleProximal,
        HumanBodyBones.LeftMiddleIntermediate,
        HumanBodyBones.LeftMiddleDistal,
        -3f);

    FingerCurlSegment[] RightMiddleCurl => CreateFingerCurlChain(
        HumanBodyBones.RightMiddleProximal,
        HumanBodyBones.RightMiddleIntermediate,
        HumanBodyBones.RightMiddleDistal,
        -3f);

    FingerCurlSegment[] LeftRingCurl => CreateFingerCurlChain(
        HumanBodyBones.LeftRingProximal,
        HumanBodyBones.LeftRingIntermediate,
        HumanBodyBones.LeftRingDistal,
        5f);

    FingerCurlSegment[] RightRingCurl => CreateFingerCurlChain(
        HumanBodyBones.RightRingProximal,
        HumanBodyBones.RightRingIntermediate,
        HumanBodyBones.RightRingDistal,
        5f);

    FingerCurlSegment[] LeftLittleCurl => CreateFingerCurlChain(
        HumanBodyBones.LeftLittleProximal,
        HumanBodyBones.LeftLittleIntermediate,
        HumanBodyBones.LeftLittleDistal,
        11f);

    FingerCurlSegment[] RightLittleCurl => CreateFingerCurlChain(
        HumanBodyBones.RightLittleProximal,
        HumanBodyBones.RightLittleIntermediate,
        HumanBodyBones.RightLittleDistal,
        11f);

    FingerCurlSegment[] CreateFingerCurlChain(
        HumanBodyBones proximal,
        HumanBodyBones intermediate,
        HumanBodyBones distal,
        float splayAngle)
    {
        return new[]
        {
            new FingerCurlSegment(proximal, Vector3.right, _fingerProximalCurlAngle, Vector3.up, splayAngle),
            new FingerCurlSegment(intermediate, Vector3.right, _fingerIntermediateCurlAngle),
            new FingerCurlSegment(distal, Vector3.right, _fingerDistalCurlAngle)
        };
    }
}
