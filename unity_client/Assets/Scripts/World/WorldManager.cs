using System;
using System.Collections;
using System.Collections.Generic;
using System.Threading.Tasks;
using UnityEngine;
using UnityEngine.Networking;
using Newtonsoft.Json.Linq;
using GLTFast;
using Vrex.World;

/// <summary>
/// ワールドの読み込み・切り替え・マルチプレイヤー管理。
/// </summary>
public class WorldManager : MonoBehaviour
{
    public static WorldManager Instance { get; private set; }

    [Header("World")]
    [SerializeField] Transform worldRoot;
    [SerializeField] GameObject loadingScreen;

    [Header("Player Prefab")]
    [SerializeField] GameObject remotePlayerPrefab;

    [Header("Item Root")]
    [SerializeField] Transform itemRoot; // アイテムを配置する親 Transform

    [Header("Debug HUD")]
    [SerializeField] bool showDebugHud = true;
    [SerializeField] float playerMovedWindowSeconds = 5f;

    readonly Dictionary<string, RemotePlayerController> _remotePlayers = new();
    readonly Dictionary<string, GameObject>             _spawnedItems  = new();
    readonly Queue<float> _playerMovedTimes = new();
    GameObject _fallbackWorldShell;

    string      _currentWorldId;
    string      _currentRoomId;
    AssetBundle _currentBundle;

    WorldMediaController _mediaController;

    void Awake()
    {
        if (Instance != null) { Destroy(gameObject); return; }
        Instance = this;

        if (worldRoot == null)
        {
            var existingWorldRoot = GameObject.Find("WorldRoot");
            worldRoot = existingWorldRoot != null ? existingWorldRoot.transform : new GameObject("WorldRoot").transform;
        }

        if (itemRoot == null)
        {
            var existingItemRoot = GameObject.Find("ItemRoot");
            itemRoot = existingItemRoot != null ? existingItemRoot.transform : new GameObject("ItemRoot").transform;
        }

        _mediaController = GetComponent<WorldMediaController>();
        if (_mediaController == null)
            _mediaController = gameObject.AddComponent<WorldMediaController>();
    }

    void Start()
    {
        var client = VrexClient.Instance;
        client.OnRoomState         += HandleRoomState;
        client.OnPlayerJoined      += HandlePlayerJoined;
        client.OnPlayerLeft        += HandlePlayerLeft;
        client.OnPlayerMoved       += HandlePlayerMoved;
        client.OnAvatarStateChanged += HandleAvatarState;
        client.OnItemInteracted    += HandleItemInteracted;
    }

    // ═══════════════════════════════════════════════════════════
    // 入室メインフロー
    // ═══════════════════════════════════════════════════════════

    public async Task EnterWorld(string worldId, string roomId = null)
    {
        Debug.Log($"[World] MEDIA_ONLY_MODE build={Application.version} tag=ray-grab-stable-head-v4");
        ShowLoading(true);

        // ── 1. ワールドデータ取得（world + items）────────────
        var data = await VrexClient.Instance.GetJson($"/api/v1/worlds/{worldId}");
        if (data == null)
        {
            Debug.LogError("[World] Failed to fetch world data");
            ShowLoading(false);
            return;
        }

        // ── 2. 前のワールドを破棄 ────────────────────────────
        UnloadCurrentWorld();

        var world = data["world"] as JObject ?? new JObject();
        var media = world["media"] as JObject ?? new JObject();
        var items = data["items"] as JArray ?? new JArray();

        // ── 3. admin/worlds の運用に合わせ、media + items を正とする ──
        // asset_bundle_url は現状のQuestクライアントでは使わない。
        await CreateMediaDrivenWorld(world, items);

        // ── 4. メディア適用（BGM・スカイボックス等）──────────
        _mediaController.Apply(media);

        // ── 5. まずスポーン地点に移動 ───────────────────────
        // アイテムロードが重くても、自分の入室とアバター表示を先に成立させる。

        // ── 5b. スポーン地点に移動 ───────────────────────────
        var spawnPoint = data["world"]?["spawn_point"] as JObject;
        if (spawnPoint != null)
        {
            var spawnPos = new Vector3(
                spawnPoint["x"]?.Value<float>() ?? 0f,
                spawnPoint["y"]?.Value<float>() ?? 0f,
                spawnPoint["z"]?.Value<float>() ?? 0f);
            MoveLocalPlayerToSpawn(spawnPos);
        }

        // ── 6. ルーム取得または作成 ──────────────────────────
        if (roomId == null)
        {
            var roomData = await VrexClient.Instance.GetJson($"/api/v1/rooms?world_id={worldId}");
            var rooms    = roomData?["rooms"] as JArray;

            roomId = (rooms != null && rooms.Count > 0)
                ? rooms[0]?["id"]?.ToString()
                : (await CreateRoom(worldId))?["room"]?["id"]?.ToString();
        }

        if (roomId == null)
        {
            Debug.LogError("[World] No room available");
            ShowLoading(false);
            return;
        }

        // ── 7. 表示系はルーム接続に依存させず先に進める ─────────
        string avatarId = VrexClient.Instance.CurrentUser?.avatar_id;
        _currentWorldId = worldId;
        _currentRoomId  = roomId;

        Debug.Log($"[World] Loading local avatar before room join. avatar_id={avatarId ?? "(none)"}");
        await LoadLocalAvatar(avatarId);

        Debug.Log($"[World] Preparing to spawn {items.Count} items before room join completes.");
        await SpawnWorldItems(items);

        Debug.Log($"[World] Joining room {roomId} with avatar_id={avatarId ?? "(none)"}");
        bool joined = await JoinRoomWithTimeout(roomId, avatarId, 3f);
        if (joined)
        {
            _playerMovedTimes.Clear();
            Debug.Log($"[World] Joined room {roomId} in world {worldId}");
        }
        else
        {
            Debug.LogWarning($"[World] Room join timed out or failed. Continuing in local-only mode for world {worldId}.");
        }

        ShowLoading(false);
    }

    // ═══════════════════════════════════════════════════════════
    // アイテムスポーン
    // ═══════════════════════════════════════════════════════════

    async Task SpawnWorldItems(JArray items)
    {
        // itemRoot が未設定なら worldRoot を使う
        Transform root = itemRoot != null ? itemRoot : worldRoot;

        foreach (JObject item in items)
        {
            string itemId = item["id"]?.ToString();
            if (string.IsNullOrEmpty(itemId)) continue;

            // ── 3D モデルロード ──────────────────────────────
            string itemName = item["name"]?.ToString() ?? itemId;
            Debug.Log($"[World] Spawning item {itemName} ({itemId})");
            GameObject go = await LoadItemWithTimeout(item, root, itemName, itemId);
            if (go == null)
            {
                Debug.LogWarning($"[World] Item load returned null even after fallback: {itemName} ({itemId})");
                continue;
            }

            go.name = item["name"]?.ToString() ?? "Item";

            // ── Transform 適用 ──────────────────────────────
            ApplyTransform(go, item);

            // ── メディア設定 ─────────────────────────────────
            var media = item["media"] as JObject ?? new JObject();
            var imc   = go.AddComponent<ItemMediaController>();
            imc.Setup(media);

            // ── インタラクション ─────────────────────────────
            var interactable = go.AddComponent<InteractableItem>();
            interactable.ItemId    = itemId;
            interactable.OnInteracted += () =>
            {
                imc.OnInteract();
                VrexClient.Instance.InteractItem(itemId);
            };

            _spawnedItems[itemId] = go;
        }

        Debug.Log($"[World] Spawned {_spawnedItems.Count} items.");
    }

    async Task<bool> JoinRoomWithTimeout(string roomId, string avatarId, float timeoutSeconds)
    {
        var joinTask = VrexClient.Instance.JoinRoom(roomId, avatarId);
        var completed = await Task.WhenAny(joinTask, Task.Delay(TimeSpan.FromSeconds(timeoutSeconds)));
        if (completed == joinTask)
        {
            return await joinTask;
        }

        Debug.LogWarning($"[World] JoinRoom timeout after {timeoutSeconds:0.#}s for room {roomId}");
        return false;
    }

    async Task<GameObject> LoadItemWithTimeout(JObject item, Transform root, string itemName, string itemId)
    {
        var loadTask = ItemLoader.Load(item, root);
        var completed = await Task.WhenAny(loadTask, Task.Delay(15000));
        if (completed == loadTask)
        {
            return await loadTask;
        }

        Debug.LogWarning($"[World] Item load timed out after 15s: {itemName} ({itemId}). Using placeholder.");
        bool collider = item["collider_enabled"]?.Value<bool>() ?? true;
        var placeholder = ItemLoader.CreatePlaceholder(itemName, root, collider);
        placeholder.name = itemName;
        return placeholder;
    }

    static void ApplyTransform(GameObject go, JObject item)
    {
        if (item["position"] is JObject pos)
            go.transform.localPosition = new Vector3(
                pos["x"]?.Value<float>() ?? 0f,
                pos["y"]?.Value<float>() ?? 0f,
                pos["z"]?.Value<float>() ?? 0f);

        if (item["rotation"] is JObject rot)
        {
            float rx = rot["x"]?.Value<float>() ?? 0f;
            float ry = rot["y"]?.Value<float>() ?? 0f;
            float rz = rot["z"]?.Value<float>() ?? 0f;
            float rw = rot["w"]?.Value<float>() ?? 1f;
            bool looksLikeEuler = Mathf.Abs(rx) > 1.01f || Mathf.Abs(ry) > 1.01f || Mathf.Abs(rz) > 1.01f;
            go.transform.localRotation = looksLikeEuler
                ? Quaternion.Euler(rx, ry, rz)
                : new Quaternion(rx, ry, rz, rw);
        }

        if (item["scale"] is JObject scl)
            go.transform.localScale = new Vector3(
                scl["x"]?.Value<float>() ?? 1f,
                scl["y"]?.Value<float>() ?? 1f,
                scl["z"]?.Value<float>() ?? 1f);
    }

    // ═══════════════════════════════════════════════════════════
    // ワールドのアンロード
    // ═══════════════════════════════════════════════════════════

    void UnloadCurrentWorld()
    {
        _mediaController?.StopAll();

        foreach (Transform child in worldRoot)
            Destroy(child.gameObject);

        if (itemRoot != null)
            foreach (Transform child in itemRoot)
                Destroy(child.gameObject);

        _spawnedItems.Clear();
        _remotePlayers.Clear();
        _fallbackWorldShell = null;

        if (_currentBundle != null)
        {
            _currentBundle.Unload(true);
            _currentBundle = null;
        }
    }

    // ═══════════════════════════════════════════════════════════
    // AssetBundle ロード
    // ═══════════════════════════════════════════════════════════

    async Task<bool> LoadWorldAssetBundle(string url)
    {
        Debug.Log($"[World] Loading AssetBundle: {url}");
        var req = UnityEngine.Networking.UnityWebRequestAssetBundle.GetAssetBundle(url);
        var op  = req.SendWebRequest();
        while (!op.isDone) await Task.Yield();

        if (req.result != UnityEngine.Networking.UnityWebRequest.Result.Success)
        {
            Debug.LogWarning($"[World] AssetBundle load failed: {req.error}");
            return false;
        }

        _currentBundle = UnityEngine.Networking.DownloadHandlerAssetBundle.GetContent(req);
        var scene = _currentBundle.LoadAsset<GameObject>("WorldScene");
        if (scene == null)
        {
            foreach (var assetName in _currentBundle.GetAllAssetNames())
            {
                scene = _currentBundle.LoadAsset<GameObject>(assetName);
                if (scene != null)
                {
                    Debug.Log($"[World] Using fallback bundle asset: {assetName}");
                    break;
                }
            }
        }

        if (scene != null)
        {
            Instantiate(scene, worldRoot);
            return true;
        }
        else
        {
            Debug.LogWarning("[World] AssetBundle loaded but no GameObject asset was found.");
            return false;
        }
    }

    async Task<bool> LoadWorldGltf(string url)
    {
        Debug.Log($"[World] Loading GLTF world: {url}");
        var gltf = new GltfImport();
        bool ok = await gltf.Load(url);
        if (!ok)
        {
            Debug.LogWarning($"[World] GLTF world load failed: {url}");
            return false;
        }

        var go = new GameObject("WorldScene");
        go.transform.SetParent(worldRoot, false);
        await gltf.InstantiateMainSceneAsync(go.transform);
        return true;
    }

    async Task CreateMediaDrivenWorld(JObject world, JArray items)
    {
        _fallbackWorldShell = new GameObject("FallbackWorld");
        _fallbackWorldShell.transform.SetParent(worldRoot, false);

        var floor = GameObject.CreatePrimitive(PrimitiveType.Plane);
        floor.name = "WorldFloor";
        floor.transform.SetParent(_fallbackWorldShell.transform, false);
        floor.transform.localPosition = Vector3.zero;

        float extent = CalculateWorldExtent(world, items);
        floor.transform.localScale = new Vector3(extent, 1f, extent);

        var renderer = floor.GetComponent<Renderer>();
        var shader = Shader.Find("Universal Render Pipeline/Lit") ?? Shader.Find("Standard");
        if (shader != null)
            renderer.material = new Material(shader);

        var floorMedia = world["media"]?["floor"] as JObject;
        string floorUrl = floorMedia?["url"]?.ToString();
        float tileScale = floorMedia?["tile_scale"]?.Value<float>() ?? 1f;
        await ApplyFloorTexture(renderer, floorUrl, tileScale);

        Debug.Log($"[World] Using media-driven fallback world. extent={extent:0.##}, floor={floorUrl ?? "(default)"}");
    }

    static float CalculateWorldExtent(JObject world, JArray items)
    {
        float maxAbs = 8f;

        if (world?["spawn_point"] is JObject spawn)
        {
            maxAbs = Mathf.Max(maxAbs,
                Mathf.Abs(spawn["x"]?.Value<float>() ?? 0f),
                Mathf.Abs(spawn["z"]?.Value<float>() ?? 0f));
        }

        foreach (var token in items)
        {
            if (token is not JObject item || item["position"] is not JObject pos) continue;
            maxAbs = Mathf.Max(maxAbs,
                Mathf.Abs(pos["x"]?.Value<float>() ?? 0f),
                Mathf.Abs(pos["z"]?.Value<float>() ?? 0f));
        }

        return Mathf.Clamp(maxAbs / 5f + 2f, 4f, 20f);
    }

    static async Task ApplyFloorTexture(Renderer renderer, string url, float tileScale)
    {
        if (renderer == null || renderer.material == null) return;

        if (string.IsNullOrEmpty(url))
        {
            renderer.material.color = new Color(0.82f, 0.82f, 0.82f, 1f);
            return;
        }

        using var req = UnityWebRequestTexture.GetTexture(url);
        var op = req.SendWebRequest();
        while (!op.isDone) await Task.Yield();

        if (req.result != UnityWebRequest.Result.Success)
        {
            Debug.LogWarning($"[World] Floor texture load failed: {req.error}");
            renderer.material.color = new Color(0.82f, 0.82f, 0.82f, 1f);
            return;
        }

        var tex = DownloadHandlerTexture.GetContent(req);
        tex.wrapMode = TextureWrapMode.Repeat;
        renderer.material.mainTexture = tex;
        renderer.material.mainTextureScale = Vector2.one * Mathf.Max(0.01f, 1f / tileScale);
        renderer.material.color = Color.white;
    }

    async Task<JObject> CreateRoom(string worldId)
    {
        var json = Newtonsoft.Json.JsonConvert.SerializeObject(new { world_id = worldId });
        return await VrexClient.Instance.PostJson("/api/v1/rooms", json);
    }

    // ═══════════════════════════════════════════════════════════
    // チャネルイベントハンドラ
    // ═══════════════════════════════════════════════════════════

    void HandleRoomState(RoomStateData state)
    {
        foreach (var player in state.players)
        {
            if (player.user_id == VrexClient.Instance.CurrentUser?.id) continue;
            SpawnRemotePlayer(player);
        }
    }

    void HandlePlayerJoined(PlayerData player)
    {
        if (player.user_id == VrexClient.Instance.CurrentUser?.id) return;
        SpawnRemotePlayer(new PlayerFullData
        {
            user_id      = player.user_id,
            username     = player.username,
            display_name = player.display_name,
            avatar_id    = player.avatar_id,
            position     = new VrexVector3 { x = 0, y = 0, z = 0 },
            rotation     = new VrexQuaternion { x = 0, y = 0, z = 0, w = 1 }
        });
    }

    void HandlePlayerLeft(string userId)
    {
        if (_remotePlayers.TryGetValue(userId, out var p))
        {
            Destroy(p.gameObject);
            _remotePlayers.Remove(userId);
        }
    }

    void HandlePlayerMoved(PlayerMoveData data)
    {
        if (_remotePlayers.TryGetValue(data.user_id, out var p))
            p.UpdateTransform(data.position, data.rotation);

        TrackPlayerMoved();
    }

    void HandleAvatarState(AvatarStateData data)
    {
        if (_remotePlayers.TryGetValue(data.user_id, out var p))
            p.UpdateAvatarState(data);
    }

    void HandleItemInteracted(ItemInteractData data)
    {
        // サーバーからのフィードバックを UI に表示
        var msg = data.response?["message"]?.ToString();
        if (!string.IsNullOrEmpty(msg))
            VrexUI.Instance?.ShowNotification(msg);
    }

    void SpawnRemotePlayer(PlayerFullData data)
    {
        if (_remotePlayers.ContainsKey(data.user_id)) return;

        var go         = Instantiate(remotePlayerPrefab, worldRoot);
        var controller = go.GetComponent<RemotePlayerController>();
        controller.Initialize(data.user_id, data.username, data.display_name);
        controller.UpdateTransform(data.position, data.rotation);

        if (!string.IsNullOrEmpty(data.avatar_id))
            _ = FetchAndSetAvatar(controller, data.avatar_id);

        _remotePlayers[data.user_id] = controller;
    }

    async Task LoadLocalAvatar(string avatarId)
    {
        Debug.Log($"[World] LoadLocalAvatar called. avatar_id={avatarId ?? "(none)"}");
        if (string.IsNullOrEmpty(avatarId))
        {
            Debug.LogWarning("[World] Local player has no avatar_id.");
            return;
        }

        var localAvatar = FindObjectOfType<LocalPlayerAvatar>();
        if (localAvatar == null)
        {
            Debug.LogWarning("[World] LocalPlayerAvatar not found.");
            return;
        }

        Debug.Log("[World] LocalPlayerAvatar found.");

        var data = await VrexClient.Instance.GetJson($"/api/v1/avatars/{avatarId}");
        string vrmUrl = data?["avatar"]?["vrm_url"]?.ToString();
        if (string.IsNullOrEmpty(vrmUrl))
        {
            Debug.LogWarning($"[World] Avatar URL not found for avatar {avatarId}.");
            return;
        }

        Debug.Log($"[World] Loading local avatar from {vrmUrl}");
        localAvatar.LoadAvatarFromUrl(vrmUrl, avatarId);
    }

    async Task FetchAndSetAvatar(RemotePlayerController controller, string avatarId)
    {
        var data = await VrexClient.Instance.GetJson($"/api/v1/avatars/{avatarId}");
        string vrmUrl = data?["avatar"]?["vrm_url"]?.ToString();
        if (!string.IsNullOrEmpty(vrmUrl))
            controller.SetAvatar(avatarId, vrmUrl);
    }

    // ═══════════════════════════════════════════════════════════
    // スポーン地点
    // ═══════════════════════════════════════════════════════════

    static void MoveLocalPlayerToSpawn(Vector3 pos)
    {
        var cc = FindObjectOfType<CharacterController>();
        if (cc == null) return;
        cc.enabled = false;
        cc.transform.position = pos;
        cc.enabled = true;
        Debug.Log($"[World] Moved local player to spawn: {pos}");
    }

    void ShowLoading(bool show)
    {
        if (loadingScreen != null) loadingScreen.SetActive(show);
    }

    void TrackPlayerMoved()
    {
        _playerMovedTimes.Enqueue(Time.time);
        PrunePlayerMovedTimes();
    }

    void PrunePlayerMovedTimes()
    {
        float cutoff = Time.time - playerMovedWindowSeconds;
        while (_playerMovedTimes.Count > 0 && _playerMovedTimes.Peek() < cutoff)
            _playerMovedTimes.Dequeue();
    }

    void OnGUI()
    {
        if (!showDebugHud) return;

        PrunePlayerMovedTimes();

        const float width = 320f;
        const float height = 90f;
        GUILayout.BeginArea(new Rect(10f, 10f, width, height), GUI.skin.box);
        GUILayout.Label($"Room: {_currentRoomId ?? "-"}");
        GUILayout.Label($"player_moved (last {playerMovedWindowSeconds:0.#}s): {_playerMovedTimes.Count}");
        var cam = Camera.main;
        if (cam != null)
            GUILayout.Label($"Spawn/Camera: {cam.transform.position:F2}");
        GUILayout.EndArea();
    }
}

// ─── アイテムのインタラクションコンポーネント ────────────────

/// <summary>
/// Quest 3 のコントローラーで触れたときに OnInteracted を発火する。
/// OVRGrabbable/XRGrabInteractable の代わりに使うシンプル実装。
/// </summary>
public class InteractableItem : MonoBehaviour
{
    public string    ItemId;
    public event Action OnInteracted;

    // Quest 3 コントローラーの Ray が当たってボタンを押した時
    public void Interact() => OnInteracted?.Invoke();

    public Transform GrabTarget => transform;

    // Trigger Collider でも発火（接触型）
    void OnTriggerEnter(Collider other)
    {
        if (other.CompareTag("PlayerHand"))
            OnInteracted?.Invoke();
    }
}
