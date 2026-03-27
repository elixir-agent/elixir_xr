using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using System.Text;
using UnityEngine;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using NativeWebSocket;

/// <summary>
/// Phoenix Channels v2 プロトコル実装。
/// WebSocket 上で Phoenix のメッセージプロトコルを処理する。
/// 依存: NativeWebSocket (https://github.com/endel/NativeWebSocket)
/// </summary>
public class PhoenixChannel
{
    public bool IsConnected => _ws?.State == WebSocketState.Open;

    private WebSocket _ws;
    private readonly string _wsUrl;
    private readonly string _token;
    private int _ref = 0;

    private string _topic;
    private Action<string, JObject> _messageHandler;
    private TaskCompletionSource<bool> _joinTcs;

    // Push の応答待ち: ref -> TCS
    private readonly Dictionary<string, TaskCompletionSource<JObject>> _pushCallbacks = new();

    public PhoenixChannel(string wsUrl, string token)
    {
        _wsUrl = $"{wsUrl}?token={Uri.EscapeDataString(token)}";
        _token = token;
    }

    public async Task Connect()
    {
        _ws = new WebSocket(_wsUrl);
        _ws.OnMessage += OnMessage;
        _ws.OnError += (e) => Debug.LogError($"[Phoenix] WebSocket error: {e}");
        _ws.OnClose += (code) => Debug.Log($"[Phoenix] WebSocket closed: {code}");

        await _ws.Connect();
        Debug.Log("[Phoenix] WebSocket connected");

        // ハートビートを送り続ける
        _ = HeartbeatLoop();
    }

    public void Disconnect()
    {
        _ = _ws?.Close();
    }

    public async Task<bool> JoinChannel(string topic, JObject payload, Action<string, JObject> handler)
    {
        _topic = topic;
        _messageHandler = handler;
        _joinTcs = new TaskCompletionSource<bool>();

        var msg = BuildMessage(topic, "phx_join", payload);
        await SendRaw(msg);

        // 5秒タイムアウト
        var timeout = Task.Delay(5000);
        var result = await Task.WhenAny(_joinTcs.Task, timeout);

        if (result == timeout)
        {
            Debug.LogError($"[Phoenix] Join {topic} timed out");
            return false;
        }
        return await _joinTcs.Task;
    }

    public async Task LeaveChannel()
    {
        if (_topic != null)
        {
            var msg = BuildMessage(_topic, "phx_leave", new JObject());
            await SendRaw(msg);
        }
    }

    public void Push(string eventName, JObject payload)
    {
        _ = SendRaw(BuildMessage(_topic, eventName, payload));
    }

    public async Task<JObject> Push(string eventName, JObject payload, bool waitReply)
    {
        if (!waitReply) { Push(eventName, payload); return null; }

        var refStr = NextRef().ToString();
        var tcs = new TaskCompletionSource<JObject>();
        _pushCallbacks[refStr] = tcs;

        var msgObj = new JObject
        {
            ["topic"] = _topic,
            ["event"] = eventName,
            ["payload"] = payload,
            ["ref"] = refStr,
            ["join_ref"] = null
        };
        await SendRaw(msgObj.ToString(Formatting.None));

        var timeout = Task.Delay(5000);
        var result = await Task.WhenAny(tcs.Task, timeout);
        _pushCallbacks.Remove(refStr);

        if (result == timeout) return null;
        return await tcs.Task;
    }

    public void DispatchToMainThread()
    {
        // NativeWebSocket requires this call every frame on non-WebGL platforms
        _ws?.DispatchMessageQueue();
    }

    private void OnMessage(byte[] bytes)
    {
        var raw = Encoding.UTF8.GetString(bytes);
        JObject msg;
        try { msg = JObject.Parse(raw); }
        catch { return; }

        var topic = msg["topic"]?.ToString();
        var eventName = msg["event"]?.ToString();
        var payload = msg["payload"] as JObject ?? new JObject();
        var refStr = msg["ref"]?.ToString();

        switch (eventName)
        {
            case "phx_reply":
                HandleReply(refStr, payload);
                break;
            case "phx_close":
            case "phx_error":
                Debug.LogWarning($"[Phoenix] Channel {topic} closed/error");
                break;
            default:
                if (topic == _topic)
                    _messageHandler?.Invoke(eventName, payload);
                break;
        }
    }

    private void HandleReply(string refStr, JObject payload)
    {
        // Join 応答
        if (_joinTcs != null && !_joinTcs.Task.IsCompleted)
        {
            bool ok = payload["status"]?.ToString() == "ok";
            _joinTcs.TrySetResult(ok);
        }

        // Push 応答
        if (refStr != null && _pushCallbacks.TryGetValue(refStr, out var tcs))
        {
            tcs.TrySetResult(payload["response"] as JObject ?? new JObject());
        }
    }

    private async Task HeartbeatLoop()
    {
        while (IsConnected)
        {
            await Task.Delay(30_000);
            if (IsConnected)
                await SendRaw(BuildMessage("phoenix", "heartbeat", new JObject()));
        }
    }

    private string BuildMessage(string topic, string eventName, JObject payload)
    {
        return new JObject
        {
            ["topic"] = topic,
            ["event"] = eventName,
            ["payload"] = payload,
            ["ref"] = NextRef().ToString(),
            ["join_ref"] = null
        }.ToString(Formatting.None);
    }

    private async Task SendRaw(string message)
    {
        if (!IsConnected)
        {
            Debug.LogWarning("[Phoenix] WebSocket not connected, dropping message");
            return;
        }
        await _ws.SendText(message);
    }

    private int NextRef() => ++_ref;
}
