using System.Collections;
using UnityEngine;

/// <summary>
/// Quest 3 プレイヤーコントローラー。
/// HMD 向き基準の移動・スナップターン・物理歩行追跡・足元コライダー同期。
/// </summary>
public class QuestPlayerController : MonoBehaviour
{
    [Header("Movement")]
    [SerializeField] private float moveSpeed = 3f;
    [SerializeField] private float sprintMultiplier = 2f;
    [SerializeField] private float gravity = -9.81f;

    [Header("References")]
    [SerializeField] private Transform cameraRig;
    [SerializeField] private CharacterController characterController;

    [Header("Network Sync")]
    [SerializeField] private float syncIntervalSeconds = 0.05f;

    public Transform CameraRig => cameraRig;
    public bool IsRoomscaleBlocked => _roomscaleBlocked;
    public Vector3 StableBodyPosition => _stableBodyPosition;

    private Vector3 _velocity;
    private float _syncTimer;
    private Vector3 _lastSyncPosition;
    private Quaternion _lastSyncRotation;
    private Transform _hmdTransform;
    private float _worldYaw;
    private bool _snapTurnLock;
    private Transform _trackingSpace;
    private Vector3 _resolvedHmdLocalXZ;
    private bool _hmdTrackingInitialized;
    private bool _roomscaleBlocked;
    private Vector3 _stableBodyPosition;
    private bool _stableBodyInitialized;

    void Start()
    {
        ConfigureFloorLevelTracking();

        if (cameraRig != null)
        {
            var ovr = cameraRig.GetComponent<OVRCameraRig>();
            _hmdTransform = ovr != null ? ovr.centerEyeAnchor : Camera.main?.transform;
            _trackingSpace = ovr?.trackingSpace;
        }
        if (_hmdTransform == null)
            _hmdTransform = Camera.main?.transform ?? transform;

        StartCoroutine(InitWorldYawFromHMD());
    }

    void ConfigureFloorLevelTracking()
    {
        var manager = FindObjectOfType<OVRManager>();
        if (manager != null)
            manager.trackingOriginType = OVRManager.TrackingOrigin.FloorLevel;
    }

    IEnumerator InitWorldYawFromHMD()
    {
        yield return null;

        if (_hmdTransform != null)
        {
            Vector3 fwd = _hmdTransform.forward;
            fwd.y = 0f;
            if (fwd.sqrMagnitude > 0.001f)
                _worldYaw = Quaternion.LookRotation(fwd.normalized).eulerAngles.y;
        }

        ApplyCameraRigPosition();
        _resolvedHmdLocalXZ = GetHmdTrackingXZ();
        _hmdTrackingInitialized = true;
        _stableBodyPosition = transform.position;
        _stableBodyInitialized = true;
    }

    Vector3 GetHmdTrackingXZ()
    {
        if (_hmdTransform == null || _trackingSpace == null) return Vector3.zero;
        Vector3 localPosition = _trackingSpace.InverseTransformPoint(_hmdTransform.position);
        localPosition.y = 0f;
        return localPosition;
    }

    void ApplyCameraRigPosition()
    {
        if (cameraRig == null) return;

        Vector3 resolvedWorldOffset = Quaternion.Euler(0f, _worldYaw, 0f) * _resolvedHmdLocalXZ;
        cameraRig.position = new Vector3(
            transform.position.x - resolvedWorldOffset.x,
            transform.position.y,
            transform.position.z - resolvedWorldOffset.z);
        cameraRig.rotation = Quaternion.Euler(0f, _worldYaw, 0f);
    }

    void Update()
    {
        HandleSnapTurn();
        HandleMovement();
        HandleSync();
    }

    void HandleSnapTurn()
    {
        Vector2 axis = OVRInput.Get(OVRInput.Axis2D.PrimaryThumbstick, OVRInput.Controller.RTouch);

        if (!_snapTurnLock && Mathf.Abs(axis.x) > 0.7f)
        {
            _worldYaw += axis.x > 0f ? 30f : -30f;
            _snapTurnLock = true;
            if (cameraRig != null)
                cameraRig.rotation = Quaternion.Euler(0f, _worldYaw, 0f);
        }
        else if (Mathf.Abs(axis.x) < 0.3f)
        {
            _snapTurnLock = false;
        }
    }

    void HandleMovement()
    {
        _roomscaleBlocked = false;
        if (!_stableBodyInitialized)
        {
            _stableBodyPosition = transform.position;
            _stableBodyInitialized = true;
        }

        Vector2 leftAxis = OVRInput.Get(OVRInput.Axis2D.PrimaryThumbstick, OVRInput.Controller.LTouch);
        Vector3 forward = _hmdTransform.forward; forward.y = 0f; forward.Normalize();
        Vector3 right = _hmdTransform.right; right.y = 0f; right.Normalize();

        bool sprint = OVRInput.Get(OVRInput.Button.PrimaryThumbstick, OVRInput.Controller.LTouch);
        float speed = moveSpeed * (sprint ? sprintMultiplier : 1f);
        Vector3 moveDir = (forward * leftAxis.y + right * leftAxis.x) * speed;

        if (characterController.isGrounded) _velocity.y = -2f;
        else _velocity.y += gravity * Time.deltaTime;

        CollisionFlags locomotionFlags = characterController.Move((moveDir + _velocity) * Time.deltaTime);
        if ((locomotionFlags & CollisionFlags.Sides) == 0)
            _stableBodyPosition = transform.position;

        if (_hmdTrackingInitialized && _trackingSpace != null)
        {
            Vector3 currentXZ = GetHmdTrackingXZ();
            Vector3 requestedLocalDelta = currentXZ - _resolvedHmdLocalXZ;
            if (requestedLocalDelta.sqrMagnitude > 0.000001f)
            {
                Quaternion yawRotation = Quaternion.Euler(0f, _worldYaw, 0f);
                Vector3 desiredWorldDelta = yawRotation * requestedLocalDelta;
                Vector3 beforeMove = transform.position;
                characterController.Move(desiredWorldDelta);
                Vector3 actualWorldDelta = transform.position - beforeMove;
                Vector3 actualLocalDelta = Quaternion.Inverse(yawRotation) * actualWorldDelta;
                actualLocalDelta.y = 0f;
                _resolvedHmdLocalXZ += actualLocalDelta;

                Vector3 blockedLocalDelta = requestedLocalDelta - actualLocalDelta;
                blockedLocalDelta.y = 0f;
                _roomscaleBlocked = blockedLocalDelta.sqrMagnitude > 0.000001f;
                if (!_roomscaleBlocked)
                    _stableBodyPosition = transform.position;
            }
        }

        ApplyCameraRigPosition();
    }

    void HandleSync()
    {
        _syncTimer += Time.deltaTime;
        if (_syncTimer < syncIntervalSeconds) return;
        _syncTimer = 0f;

        var position = transform.position;
        var rotation = cameraRig != null ? cameraRig.rotation : transform.rotation;
        if (Vector3.Distance(position, _lastSyncPosition) > 0.001f ||
            Quaternion.Angle(rotation, _lastSyncRotation) > 0.5f)
        {
            VrexClient.Instance?.SendMove(position, rotation);
            _lastSyncPosition = position;
            _lastSyncRotation = rotation;
        }
    }

    public void TryTeleport(Vector3 targetPosition)
    {
        characterController.enabled = false;
        transform.position = targetPosition;
        characterController.enabled = true;
    }
}
