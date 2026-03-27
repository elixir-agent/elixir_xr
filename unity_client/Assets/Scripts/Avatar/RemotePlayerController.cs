using System.Collections;
using System.Collections.Generic;
using UnityEngine;

/// <summary>
/// リモートプレイヤーのアバター制御。
/// サーバーから受信した位置/回転を補間して滑らかに追従。
/// </summary>
[RequireComponent(typeof(VrmAvatarLoader))]
public class RemotePlayerController : MonoBehaviour
{
    public string UserId { get; private set; }
    public string Username { get; private set; }

    [Header("Interpolation")]
    [SerializeField] private float positionLerpSpeed = 10f;
    [SerializeField] private float rotationLerpSpeed = 10f;
    [SerializeField] private float positionThreshold = 0.01f;

    [Header("Nameplate")]
    [SerializeField] private float nameplateHeight = 1.8f;
    [SerializeField] private float nameplateCharacterSize = 0.02f;
    [SerializeField] private int nameplateFontSize = 64;
    [SerializeField] private Color nameplateColor = Color.white;

    private Vector3 _targetPosition;
    private Quaternion _targetRotation;
    private VrmAvatarLoader _avatarLoader;
    private float _lastUpdateTime;
    private const float TimeoutSeconds = 10f;
    private TextMesh _nameplateText;

    void Awake()
    {
        _avatarLoader = GetComponent<VrmAvatarLoader>();
        _targetPosition = transform.position;
        _targetRotation = transform.rotation;
    }

    void Update()
    {
        // 位置・回転を補間
        if (Vector3.Distance(transform.position, _targetPosition) > positionThreshold)
        {
            transform.position = Vector3.Lerp(transform.position, _targetPosition,
                                               Time.deltaTime * positionLerpSpeed);
        }
        transform.rotation = Quaternion.Lerp(transform.rotation, _targetRotation,
                                              Time.deltaTime * rotationLerpSpeed);
    }

    public void Initialize(string userId, string username, string displayName)
    {
        UserId = userId;
        Username = username;
        gameObject.name = $"Player_{username}";
        _lastUpdateTime = Time.time;
        EnsureNameplate(!string.IsNullOrWhiteSpace(displayName) ? displayName : username);
    }

    public async void SetAvatar(string avatarId, string vrmUrl)
    {
        if (string.IsNullOrEmpty(vrmUrl)) return;
        await _avatarLoader.LoadFromUrl(vrmUrl, avatarId);
    }

    public void UpdateTransform(VrexVector3 position, VrexQuaternion rotation)
    {
        _targetPosition = position.ToUnity();
        _targetRotation = rotation.ToUnity();
        _lastUpdateTime = Time.time;
    }

    public void UpdateAvatarState(AvatarStateData state)
    {
        if (state.blend_shapes != null)
            _avatarLoader.ApplyBlendShapes(state.blend_shapes);
    }

    public bool IsTimedOut() => Time.time - _lastUpdateTime > TimeoutSeconds;

    void EnsureNameplate(string label)
    {
        if (_nameplateText == null)
        {
            var go = new GameObject("Nameplate");
            go.transform.SetParent(transform, false);
            go.transform.localPosition = new Vector3(0f, nameplateHeight, 0f);

            _nameplateText = go.AddComponent<TextMesh>();
            _nameplateText.anchor = TextAnchor.LowerCenter;
            _nameplateText.alignment = TextAlignment.Center;
            _nameplateText.fontSize = nameplateFontSize;
            _nameplateText.characterSize = nameplateCharacterSize;
            _nameplateText.color = nameplateColor;

            go.AddComponent<NameplateBillboard>();
        }

        _nameplateText.text = label ?? "";
    }
}

public class NameplateBillboard : MonoBehaviour
{
    void LateUpdate()
    {
        if (Camera.main == null) return;
        transform.rotation = Quaternion.LookRotation(transform.position - Camera.main.transform.position);
    }
}
