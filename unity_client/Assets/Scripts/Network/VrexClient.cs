using System;
using System.Collections;
using System.Collections.Generic;
using System.Threading.Tasks;
using UnityEngine;
using UnityEngine.Networking;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

/// <summary>
/// Vrex サーバーとの通信を管理するメインクライアント。
/// Phoenix Channels (WebSocket) + REST API を統合。
/// </summary>
public class VrexClient : MonoBehaviour
{
    public static VrexClient Instance { get; private set; }

    [Header("Server Settings")]
    [SerializeField] private string serverUrl = "http://192.168.1.10:4000";
    [SerializeField] private string wsUrl = "ws://192.168.1.10:4000/socket/websocket";

    [Header("State")]
    public string AuthToken { get; private set; }
    public UserData CurrentUser { get; private set; }
    public bool IsConnected => _channel?.IsConnected ?? false;

    private PhoenixChannel _channel;
    private string _currentRoomId;

    // Events
    public event Action<PlayerData> OnPlayerJoined;
    public event Action<string> OnPlayerLeft;
    public event Action<PlayerMoveData> OnPlayerMoved;
    public event Action<AvatarStateData> OnAvatarStateChanged;
    public event Action<ChatMessage> OnChatReceived;
    public event Action<ItemInteractData> OnItemInteracted;
    public event Action<JObject> OnVoiceSignal;
    public event Action<RoomStateData> OnRoomState;

    void Awake()
    {
        if (Instance != null) { Destroy(gameObject); return; }
        Instance = this;
        DontDestroyOnLoad(gameObject);
    }

    // NativeWebSocket は Quest (非WebGL) でメインスレッドへのディスパッチが必要
    void Update()
    {
        _channel?.DispatchToMainThread();
    }

    // ─── 認証 ────────────────────────────────────────────────

    public async Task<bool> Register(string username, string email, string password)
    {
        var body = JsonConvert.SerializeObject(new { username, email, password });
        var result = await PostJson("/api/v1/auth/register", body);
        if (result == null) return false;

        AuthToken = result["token"]?.ToString();
        CurrentUser = result["user"]?.ToObject<UserData>();
        return AuthToken != null;
    }

    public async Task<bool> Login(string email, string password)
    {
        var body = JsonConvert.SerializeObject(new { email, password });
        var result = await PostJson("/api/v1/auth/login", body);
        if (result == null) return false;

        AuthToken = result["token"]?.ToString();
        CurrentUser = result["user"]?.ToObject<UserData>();
        return AuthToken != null;
    }

    // ─── ルーム接続 ──────────────────────────────────────────

    public async Task<bool> JoinRoom(string roomId, string avatarId = null)
    {
        if (AuthToken == null)
        {
            Debug.LogError("[Vrex] ログインしてください");
            return false;
        }

        Debug.Log($"[Vrex] JoinRoom start. room_id={roomId} avatar_id={avatarId ?? "(none)"}");

        _channel = new PhoenixChannel(wsUrl, AuthToken);
        Debug.Log($"[Vrex] Connecting websocket: {wsUrl}");
        var connectTask = _channel.Connect();
        var connectCompleted = await Task.WhenAny(connectTask, Task.Delay(3000));
        if (connectCompleted != connectTask)
        {
            Debug.LogError("[Vrex] WebSocket connect timed out after 3s");
            return false;
        }
        await connectTask;
        Debug.Log("[Vrex] WebSocket connect completed");

        var joinPayload = new JObject();
        if (avatarId != null) joinPayload["avatar_id"] = avatarId;

        Debug.Log($"[Vrex] Joining Phoenix channel room:{roomId}");
        bool joined = await _channel.JoinChannel($"room:{roomId}", joinPayload, OnChannelMessage);
        Debug.Log($"[Vrex] JoinRoom result: {joined}");
        if (joined) _currentRoomId = roomId;
        return joined;
    }

    public async Task LeaveRoom()
    {
        if (_channel != null)
        {
            await _channel.LeaveChannel();
            _channel.Disconnect();
            _currentRoomId = null;
        }
    }

    // ─── 送信 ────────────────────────────────────────────────

    public void SendMove(Vector3 position, Quaternion rotation)
    {
        _channel?.Push("move", new JObject
        {
            ["position"] = new JObject { ["x"] = position.x, ["y"] = position.y, ["z"] = position.z },
            ["rotation"] = new JObject { ["x"] = rotation.x, ["y"] = rotation.y, ["z"] = rotation.z, ["w"] = rotation.w }
        });
    }

    public void SendAvatarState(Dictionary<string, float> blendShapes, string animation = null)
    {
        var payload = new JObject();
        if (blendShapes != null)
        {
            var bs = new JObject();
            foreach (var kv in blendShapes) bs[kv.Key] = kv.Value;
            payload["blend_shapes"] = bs;
        }
        if (animation != null) payload["animation"] = animation;

        _channel?.Push("avatar_state", payload);
    }

    public void SendChat(string message)
    {
        _channel?.Push("chat", new JObject { ["message"] = message });
    }

    public async Task<JObject> InteractItem(string itemId, JObject data = null)
    {
        var payload = new JObject { ["item_id"] = itemId };
        if (data != null) payload["data"] = data;
        if (_channel == null) return null;
        return await _channel.Push("interact", payload, waitReply: true);
    }

    public void SendVoiceSignal(string targetId, JObject signal)
    {
        signal["target_id"] = targetId;
        _channel?.Push("voice_signal", signal);
    }

    // ─── 受信ハンドラ ────────────────────────────────────────

    private void OnChannelMessage(string eventName, JObject payload)
    {
        switch (eventName)
        {
            case "room_state":
                OnRoomState?.Invoke(payload.ToObject<RoomStateData>());
                break;
            case "player_joined":
                OnPlayerJoined?.Invoke(payload.ToObject<PlayerData>());
                break;
            case "player_left":
                OnPlayerLeft?.Invoke(payload["user_id"]?.ToString());
                break;
            case "player_moved":
                OnPlayerMoved?.Invoke(payload.ToObject<PlayerMoveData>());
                break;
            case "avatar_state":
                OnAvatarStateChanged?.Invoke(payload.ToObject<AvatarStateData>());
                break;
            case "chat_message":
                OnChatReceived?.Invoke(payload.ToObject<ChatMessage>());
                break;
            case "item_interacted":
                OnItemInteracted?.Invoke(payload.ToObject<ItemInteractData>());
                break;
            case "voice_signal":
                OnVoiceSignal?.Invoke(payload);
                break;
        }
    }

    // ─── REST ヘルパー ───────────────────────────────────────

    public async Task<JObject> PostJson(string path, string json, bool auth = false)
    {
        using var req = new UnityWebRequest(serverUrl + path, "POST");
        req.uploadHandler = new UploadHandlerRaw(System.Text.Encoding.UTF8.GetBytes(json));
        req.downloadHandler = new DownloadHandlerBuffer();
        req.SetRequestHeader("Content-Type", "application/json");
        if (auth && AuthToken != null) req.SetRequestHeader("Authorization", $"Bearer {AuthToken}");

        var op = req.SendWebRequest();
        while (!op.isDone) await Task.Yield();

        if (req.result != UnityWebRequest.Result.Success)
        {
            Debug.LogError($"[Vrex] POST {path} failed: {req.error}");
            return null;
        }
        return JObject.Parse(req.downloadHandler.text);
    }

    public async Task<JObject> PutJson(string path, string json)
    {
        using var req = new UnityWebRequest(serverUrl + path, "PUT");
        req.uploadHandler   = new UploadHandlerRaw(System.Text.Encoding.UTF8.GetBytes(json));
        req.downloadHandler = new DownloadHandlerBuffer();
        req.SetRequestHeader("Content-Type", "application/json");
        if (AuthToken != null) req.SetRequestHeader("Authorization", $"Bearer {AuthToken}");

        var op = req.SendWebRequest();
        while (!op.isDone) await Task.Yield();

        if (req.result != UnityWebRequest.Result.Success)
        {
            Debug.LogError($"[Vrex] PUT {path} failed: {req.error}");
            return null;
        }
        return JObject.Parse(req.downloadHandler.text);
    }

    public async Task<JObject> GetJson(string path)
    {
        using var req = UnityWebRequest.Get(serverUrl + path);
        if (AuthToken != null) req.SetRequestHeader("Authorization", $"Bearer {AuthToken}");

        var op = req.SendWebRequest();
        while (!op.isDone) await Task.Yield();

        if (req.result != UnityWebRequest.Result.Success)
        {
            Debug.LogError($"[Vrex] GET {path} failed: {req.error}");
            return null;
        }
        return JObject.Parse(req.downloadHandler.text);
    }
}

// ─── データ型 ──────────────────────────────────────────────

[Serializable]
public class UserData
{
    public string id, username, email, display_name, avatar_id;
    public bool is_admin;
}

[Serializable]
public class PlayerData
{
    public string user_id, username, display_name, avatar_id;
}

[Serializable]
public class PlayerMoveData
{
    public string user_id;
    public VrexVector3 position;
    public VrexQuaternion rotation;
}

[Serializable]
public class AvatarStateData
{
    public string user_id, animation;
    public Dictionary<string, float> blend_shapes;
}

[Serializable]
public class ChatMessage
{
    public string user_id, username, display_name, message;
}

[Serializable]
public class ItemInteractData
{
    public string item_id, user_id;
    public JObject response;
}

[Serializable]
public class RoomStateData
{
    public string world_id;
    public List<PlayerFullData> players;
}

[Serializable]
public class PlayerFullData : PlayerData
{
    public VrexVector3 position;
    public VrexQuaternion rotation;
}

[Serializable]
public class VrexVector3
{
    public float x, y, z;
    public Vector3 ToUnity() => new Vector3(x, y, z);
}

[Serializable]
public class VrexQuaternion
{
    public float x, y, z, w;
    public Quaternion ToUnity() => new Quaternion(x, y, z, w);
}
