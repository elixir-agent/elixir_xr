using UnityEngine;

/// <summary>
/// VR レーザーポインター。
/// コントローラー先端から Ray を飛ばし、Trigger でインタラクト、Grip でグラブする。
/// </summary>
public class LaserPointerController : MonoBehaviour
{
    [Header("Controller")]
    [SerializeField] private bool isRightHand = true;

    [Header("Laser")]
    [SerializeField] private float maxDistance = 10f;
    [SerializeField] private Color laserColor = Color.cyan;
    [SerializeField] private LayerMask hitLayers = ~0;

    [Header("Grab")]
    [SerializeField] private float grabDistance = 0.35f;
    [SerializeField] private float grabMoveSpeed = 18f;
    [SerializeField] private float grabRotateSpeed = 18f;
    [SerializeField] private float grabSearchRadius = 0.25f;
    [SerializeField] private float grabbedLabelHeightOffset = 0.18f;
    [SerializeField] private float grabbedLabelReferenceDistance = 1.0f;
    [SerializeField] private float grabbedLabelBaseScale = 0.08f;
    [SerializeField] private float grabbedLabelMinScale = 0.05f;
    [SerializeField] private float grabbedLabelMaxScale = 0.16f;

    private OVRInput.Controller Controller =>
        isRightHand ? OVRInput.Controller.RTouch : OVRInput.Controller.LTouch;

    private OVRInput.Axis1D GripAxis =>
        isRightHand ? OVRInput.Axis1D.SecondaryHandTrigger : OVRInput.Axis1D.PrimaryHandTrigger;

    private OVRInput.Button TriggerButton =>
        isRightHand ? OVRInput.Button.SecondaryIndexTrigger : OVRInput.Button.PrimaryIndexTrigger;

    private OVRInput.Axis1D IndexTriggerAxis =>
        isRightHand ? OVRInput.Axis1D.SecondaryIndexTrigger : OVRInput.Axis1D.PrimaryIndexTrigger;

    private LineRenderer _lineRenderer;
    private GameObject _lineGO;
    private bool _laserVisible = true;

    private bool _wasGripPressed;
    private InteractableItem _pointedItem;
    private InteractableItem _grabbedItem;
    private Rigidbody _grabbedBody;
    private bool _grabbedBodyWasKinematic;
    private float _activeGrabDistance;
    private TextMesh _grabbedItemLabel;
    private Transform _hmdTransform;
    private OVRCameraRig _cameraRig;
    private Vector3 _grabLocalPositionOffset;
    private Quaternion _grabLocalRotationOffset;

    void Awake()
    {
        _lineGO = new GameObject(isRightHand ? "RightLaserLine" : "LeftLaserLine");
        _lineGO.transform.SetParent(transform);
        _lineRenderer = _lineGO.AddComponent<LineRenderer>();
        _lineRenderer.positionCount = 2;
        _lineRenderer.startWidth = 0.003f;
        _lineRenderer.endWidth = 0.001f;
        _lineRenderer.material = new Material(Shader.Find("Unlit/Color"));
        _lineRenderer.material.color = laserColor;
        _lineRenderer.useWorldSpace = true;
        _lineGO.SetActive(_laserVisible);
        _activeGrabDistance = grabDistance;
    }

    void Update()
    {
        EnsureRigReferences();

        if (OVRInput.GetDown(OVRInput.Button.One, Controller))
        {
            _laserVisible = !_laserVisible;
            _lineGO.SetActive(_laserVisible);
            if (!_laserVisible) HideGrabbedItemLabel();
        }

        var trackingSpace = _cameraRig != null ? _cameraRig.trackingSpace : transform;
        Vector3 localPosition = OVRInput.GetLocalControllerPosition(Controller);
        Quaternion localRotation = OVRInput.GetLocalControllerRotation(Controller);
        Vector3 controllerPos = trackingSpace.TransformPoint(localPosition);
        Quaternion controllerRot = trackingSpace.rotation * localRotation;

        Vector3 origin = GetControllerOrigin(controllerPos, controllerRot);
        Vector3 direction = controllerRot * Vector3.forward;
        float pointedDistance = maxDistance;

        _pointedItem = null;
        if (Physics.Raycast(origin, direction, out RaycastHit hit, maxDistance, hitLayers))
        {
            _pointedItem = hit.collider.GetComponentInParent<InteractableItem>();
            pointedDistance = hit.distance;

            if (_laserVisible)
            {
                _lineRenderer.SetPosition(0, origin);
                _lineRenderer.SetPosition(1, hit.point);
            }

            if (OVRInput.GetDown(TriggerButton, Controller))
                _pointedItem?.Interact();
        }
        else if (_laserVisible)
        {
            _lineRenderer.SetPosition(0, origin);
            _lineRenderer.SetPosition(1, origin + direction * maxDistance);
        }

        float gripValue = Mathf.Max(
            OVRInput.Get(GripAxis, Controller),
            OVRInput.Get(GripAxis, OVRInput.Controller.Touch),
            OVRInput.Get(IndexTriggerAxis, Controller));
        bool gripPressed = gripValue > 0.55f;
        if (gripPressed && !_wasGripPressed)
        {
            var candidate = _pointedItem
                ?? FindNearestItem(origin + direction * grabDistance)
                ?? FindNearestItem(origin);
            if (candidate != null)
            {
                Debug.Log($"[Grab] Candidate: {candidate.name} ({(isRightHand ? "R" : "L")})");
                BeginGrab(candidate, _pointedItem == candidate ? pointedDistance : grabDistance, origin, controllerRot);
            }
            else
            {
                Debug.Log($"[Grab] No candidate ({(isRightHand ? "R" : "L")})");
            }
        }
        else if (!gripPressed && _wasGripPressed && _grabbedItem != null)
        {
            EndGrab();
        }

        _wasGripPressed = gripPressed;

        if (_grabbedItem != null)
            UpdateGrab(origin, controllerRot);
        else
            HideGrabbedItemLabel();
    }

    void EnsureRigReferences()
    {
        if (_cameraRig == null)
            _cameraRig = FindObjectOfType<OVRCameraRig>();

        if (_hmdTransform == null && _cameraRig != null)
            _hmdTransform = _cameraRig.centerEyeAnchor;

        if (_hmdTransform == null)
            _hmdTransform = Camera.main != null ? Camera.main.transform : transform;
    }

    InteractableItem FindNearestItem(Vector3 center)
    {
        var hits = Physics.OverlapSphere(center, grabSearchRadius, hitLayers);
        InteractableItem best = null;
        float bestDistance = float.MaxValue;
        foreach (var hit in hits)
        {
            var item = hit.GetComponentInParent<InteractableItem>();
            if (item == null) continue;
            float distance = (hit.ClosestPoint(center) - center).sqrMagnitude;
            if (distance < bestDistance)
            {
                bestDistance = distance;
                best = item;
            }
        }
        return best;
    }

    void BeginGrab(InteractableItem item, float desiredDistance, Vector3 origin, Quaternion controllerRot)
    {
        _grabbedItem = item;
        _activeGrabDistance = Mathf.Clamp(desiredDistance, 0.15f, maxDistance);
        _grabbedBody = item.GetComponentInChildren<Rigidbody>();
        if (_grabbedBody != null)
        {
            _grabbedBodyWasKinematic = _grabbedBody.isKinematic;
            _grabbedBody.isKinematic = true;
        }

        Transform target = item.GrabTarget;
        _grabLocalPositionOffset = Quaternion.Inverse(controllerRot) * (target.position - origin);
        _grabLocalRotationOffset = Quaternion.Inverse(controllerRot) * target.rotation;
        Debug.Log($"[Grab] Begin: {item.name} ({(isRightHand ? "R" : "L")})");
    }

    void UpdateGrab(Vector3 origin, Quaternion controllerRot)
    {
        Transform target = _grabbedItem.GrabTarget;
        Vector3 targetPosition = origin + controllerRot * _grabLocalPositionOffset;
        Quaternion targetRotation = controllerRot * _grabLocalRotationOffset;
        target.position = Vector3.Lerp(target.position, targetPosition, Time.deltaTime * grabMoveSpeed);
        target.rotation = Quaternion.Slerp(target.rotation, targetRotation, Time.deltaTime * grabRotateSpeed);
        UpdateGrabbedItemLabel(target);
    }

    void EndGrab()
    {
        if (_grabbedBody != null)
            _grabbedBody.isKinematic = _grabbedBodyWasKinematic;

        Debug.Log($"[Grab] End: {_grabbedItem.name}");
        _grabbedBody = null;
        _grabbedItem = null;
        _activeGrabDistance = grabDistance;
        HideGrabbedItemLabel();
    }

    Vector3 GetControllerOrigin(Vector3 controllerPos, Quaternion controllerRot)
    {
        return controllerPos + controllerRot * new Vector3(0f, -0.01f, 0.09f);
    }

    void UpdateGrabbedItemLabel(Transform target)
    {
        if (target == null) return;
        EnsureGrabbedItemLabel();
        EnsureRigReferences();

        Vector3 euler = target.rotation.eulerAngles;
        _grabbedItemLabel.text =
            $"X:{target.position.x:0.00} Y:{target.position.y:0.00} Z:{target.position.z:0.00}\n" +
            $"R:{euler.x:0} P:{euler.y:0} Y:{euler.z:0}";

        Vector3 labelPos = target.position + Vector3.up * grabbedLabelHeightOffset;
        _grabbedItemLabel.transform.position = labelPos;

        if (_hmdTransform != null)
        {
            Vector3 toCamera = _hmdTransform.position - labelPos;
            if (toCamera.sqrMagnitude > 0.0001f)
            {
                _grabbedItemLabel.transform.rotation =
                    Quaternion.LookRotation(toCamera.normalized, Vector3.up) * Quaternion.Euler(0f, 180f, 0f);
                float distance = Vector3.Distance(_hmdTransform.position, labelPos);
                float scale = grabbedLabelBaseScale * (distance / grabbedLabelReferenceDistance);
                scale = Mathf.Clamp(scale, grabbedLabelMinScale, grabbedLabelMaxScale);
                _grabbedItemLabel.transform.localScale = Vector3.one * scale;
            }
        }

        _grabbedItemLabel.gameObject.SetActive(true);
    }

    void EnsureGrabbedItemLabel()
    {
        if (_grabbedItemLabel != null) return;

        var go = new GameObject(isRightHand ? "RightGrabbedItemLabel" : "LeftGrabbedItemLabel");
        _grabbedItemLabel = go.AddComponent<TextMesh>();
        _grabbedItemLabel.fontSize = 160;
        _grabbedItemLabel.characterSize = 0.05f;
        _grabbedItemLabel.anchor = TextAnchor.MiddleCenter;
        _grabbedItemLabel.alignment = TextAlignment.Center;
        _grabbedItemLabel.color = Color.white;
        _grabbedItemLabel.text = string.Empty;

        var renderer = go.GetComponent<MeshRenderer>();
        if (renderer != null)
        {
            var baseMat = renderer.sharedMaterial;
            if (baseMat != null)
            {
                var mat = new Material(baseMat);
                if (mat.HasProperty("_BaseColor")) mat.SetColor("_BaseColor", Color.white);
                if (mat.HasProperty("_Color")) mat.SetColor("_Color", Color.white);
                mat.renderQueue = 4000;
                renderer.material = mat;
            }
            renderer.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            renderer.receiveShadows = false;
        }

        go.SetActive(false);
    }

    void HideGrabbedItemLabel()
    {
        if (_grabbedItemLabel != null)
            _grabbedItemLabel.gameObject.SetActive(false);
    }
}
