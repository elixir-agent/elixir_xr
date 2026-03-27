#if UNITY_EDITOR
using System.Reflection;
using UnityEngine;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine.SceneManagement;
using UnityEngine.UI;
using TMPro;

/// <summary>
/// Unity シーンを自動構築する Editor スクリプト。
/// メニュー: Vrex / Setup Scene
/// </summary>
public static class SceneSetupScript
{
    [MenuItem("Vrex/Setup Scene")]
    public static void SetupScene()
    {
        // ─── シーンをクリア ───────────────────────────────
        foreach (var root in SceneManager.GetActiveScene().GetRootGameObjects())
        {
            if (root.name != "Directional Light")
                Object.DestroyImmediate(root);
        }

        // ─── OVRCameraRig ────────────────────────────────
        var ovrRigPrefab = AssetDatabase.LoadAssetAtPath<GameObject>(
            "Packages/com.meta.xr.sdk.core/Prefabs/OVRCameraRig.prefab");

        GameObject ovrGO;
        if (ovrRigPrefab != null)
        {
            ovrGO = (GameObject)PrefabUtility.InstantiatePrefab(ovrRigPrefab);
            ovrGO.name = "OVRCameraRig";
        }
        else
        {
            ovrGO = new GameObject("OVRCameraRig");
            var cam = new GameObject("CenterEyeAnchor");
            cam.transform.SetParent(ovrGO.transform);
            cam.AddComponent<Camera>().tag = "MainCamera";
        }
        ovrGO.transform.rotation = Quaternion.identity;

        var ovrManager = ovrGO.GetComponentInChildren<OVRManager>(true);
        if (ovrManager != null)
            ovrManager.trackingOriginType = OVRManager.TrackingOrigin.FloorLevel;

        // ─── VrexClient ──────────────────────────────────
        var vcGO = new GameObject("VrexClient");
        vcGO.AddComponent<VrexClient>();

        // ─── QuestPlayer ─────────────────────────────────
        var player = new GameObject("QuestPlayer");
        player.transform.position = Vector3.zero;

        var cc = player.AddComponent<CharacterController>();
        cc.height = 1.8f;
        cc.radius = 0.3f;
        cc.center = new Vector3(0f, 0.9f, 0f);
        cc.skinWidth = 0.02f;

        var qpc = player.AddComponent<QuestPlayerController>();
        SetPrivateField(qpc, "characterController", cc);
        SetPrivateField(qpc, "cameraRig", ovrGO.transform);

        // VrmAvatarLoader
        var loaderGO = new GameObject("AvatarLoader");
        loaderGO.transform.SetParent(player.transform);
        var loader = loaderGO.AddComponent<VrmAvatarLoader>();
        SetPrivateField(loader, "avatarRoot", loaderGO.transform);
        SetPrivateField(loader, "isLocalPlayer", true);

        // LocalPlayerAvatar
        var leftHandProxy = GameObject.CreatePrimitive(PrimitiveType.Sphere);
        leftHandProxy.name = "LeftHandProxy";
        leftHandProxy.transform.SetParent(player.transform, false);
        leftHandProxy.transform.localScale = Vector3.one * 0.06f;
        Object.DestroyImmediate(leftHandProxy.GetComponent<Collider>());
        leftHandProxy.GetComponent<Renderer>().sharedMaterial = CreateUnlitColorMaterial(new Color(0.2f, 0.8f, 1f, 0.9f));

        var rightHandProxy = GameObject.CreatePrimitive(PrimitiveType.Sphere);
        rightHandProxy.name = "RightHandProxy";
        rightHandProxy.transform.SetParent(player.transform, false);
        rightHandProxy.transform.localScale = Vector3.one * 0.06f;
        Object.DestroyImmediate(rightHandProxy.GetComponent<Collider>());
        rightHandProxy.GetComponent<Renderer>().sharedMaterial = CreateUnlitColorMaterial(new Color(1f, 0.7f, 0.2f, 0.9f));

        var lpa = player.AddComponent<LocalPlayerAvatar>();
        SetPrivateField(lpa, "_loader", loader);
        SetPrivateField(lpa, "_leftHandProxy", leftHandProxy);
        SetPrivateField(lpa, "_rightHandProxy", rightHandProxy);

        // LaserPointerController (右手・左手)
        var laserR = player.AddComponent<LaserPointerController>();
        SetPrivateField(laserR, "isRightHand", true);
        var laserL = player.AddComponent<LaserPointerController>();
        SetPrivateField(laserL, "isRightHand", false);

        // ─── WorldRoot / ItemRoot ─────────────────────────
        var worldRoot = new GameObject("WorldRoot");
        var itemRoot  = new GameObject("ItemRoot");

        // ─── WorldManager ────────────────────────────────
        var wmGO = new GameObject("WorldManager");
        var wm   = wmGO.AddComponent<WorldManager>();
        SetSerializedField(wm, "worldRoot", worldRoot.transform);
        SetSerializedField(wm, "itemRoot",  itemRoot.transform);

        // ─── Remote Player Prefab ─────────────────────────
        EnsureFolder("Assets/Prefabs");
        var remotePlayerPrefab = CreateRemotePlayerPrefab();
        SetSerializedField(wm, "remotePlayerPrefab", remotePlayerPrefab);

        // ─── VR Canvas ───────────────────────────────────
        var canvasGO = new GameObject("VRCanvas");
        var canvas   = canvasGO.AddComponent<Canvas>();
        canvas.renderMode = RenderMode.WorldSpace;
        canvasGO.AddComponent<CanvasScaler>();
        canvasGO.AddComponent<GraphicRaycaster>();
        canvasGO.AddComponent<VRCanvasPositioner>(); // 起動時にカメラ正面へ自動配置
        canvasGO.transform.position   = new Vector3(0f, 1.6f, 2f);
        canvasGO.transform.localScale = Vector3.one * 0.001f;
        var canvasRT = canvasGO.GetComponent<RectTransform>();
        canvasRT.sizeDelta = new Vector2(1200f, 800f);

        // ─── Login Panel ─────────────────────────────────
        var loginPanel = CreatePanel("LoginPanel", canvasGO.transform, new Vector2(600f, 500f), new Vector2(0f, 50f));

        var emailInput    = CreateInputField("EmailInput",    loginPanel.transform, "メールアドレス", new Vector2(0f, 130f));
        var passwordInput = CreateInputField("PasswordInput", loginPanel.transform, "パスワード",     new Vector2(0f, 50f));
        passwordInput.contentType = TMP_InputField.ContentType.Password;

        var loginButton = CreateButton("LoginButton", loginPanel.transform, "ログイン", new Vector2(0f, -40f));
        var statusText  = CreateText("StatusText",   loginPanel.transform, "",          new Vector2(0f, -110f), 18);

        // ─── VrexUI + Chat / Notification / WorldList ────
        var vrexUIGO = new GameObject("VrexUI");
        vrexUIGO.transform.SetParent(canvasGO.transform, false);
        var vrexUI = vrexUIGO.AddComponent<VrexUI>();

        // Chat Panel
        var chatPanel = CreatePanel("ChatPanel", canvasGO.transform, new Vector2(500f, 400f), new Vector2(-350f, -200f));
        var (chatScroll, msgContainer) = CreateScrollView("ChatScrollView", chatPanel.transform);
        var chatInput  = CreateInputField("ChatInput", chatPanel.transform, "メッセージ...", new Vector2(0f, -220f));

        // Notification Text
        var notifGO   = new GameObject("NotificationText");
        notifGO.transform.SetParent(canvasGO.transform, false);
        var notifRT   = notifGO.AddComponent<RectTransform>();
        notifRT.anchoredPosition = new Vector2(0f, 300f);
        notifRT.sizeDelta        = new Vector2(800f, 60f);
        var notifText = notifGO.AddComponent<TextMeshProUGUI>();
        notifText.alignment = TextAlignmentOptions.Center;
        notifText.fontSize  = 24;
        notifGO.SetActive(false);

        // World List Panel
        var worldListPanel = CreatePanel("WorldListPanel", canvasGO.transform, new Vector2(700f, 600f), new Vector2(0f, 0f));
        var worldListContainer = new GameObject("WorldListContainer");
        worldListContainer.transform.SetParent(worldListPanel.transform, false);
        var wlcRT = worldListContainer.AddComponent<RectTransform>();
        wlcRT.anchorMin = new Vector2(0f, 0f);
        wlcRT.anchorMax = new Vector2(1f, 1f);
        wlcRT.offsetMin = new Vector2(10f, 10f);
        wlcRT.offsetMax = new Vector2(-10f, -10f);
        var wlcVLG = worldListContainer.AddComponent<VerticalLayoutGroup>();
        wlcVLG.spacing = 10f;
        wlcVLG.childForceExpandWidth = true;

        // World List Item Prefab
        EnsureFolder("Assets/Prefabs");
        var wliPrefab = CreateWorldListItemPrefab();

        // Chat Message Prefab
        var chatMsgPrefabGO = new GameObject("ChatMessagePrefab");
        chatMsgPrefabGO.AddComponent<RectTransform>();
        var chatMsgText = chatMsgPrefabGO.AddComponent<TextMeshProUGUI>();
        chatMsgText.fontSize = 18;
        var chatMsgPrefab = PrefabUtility.SaveAsPrefabAsset(chatMsgPrefabGO,
            "Assets/Prefabs/ChatMessagePrefab.prefab");
        Object.DestroyImmediate(chatMsgPrefabGO);

        // VrexUI フィールド設定
        SetSerializedField(vrexUI, "chatPanel",            chatPanel);
        SetSerializedField(vrexUI, "chatScrollRect",       chatScroll);
        SetSerializedField(vrexUI, "chatMessageContainer", msgContainer);
        SetSerializedField(vrexUI, "chatMessagePrefab",    chatMsgPrefab);
        SetSerializedField(vrexUI, "chatInput",            chatInput);
        SetSerializedField(vrexUI, "notificationText",     notifText);
        SetSerializedField(vrexUI, "worldListPanel",       worldListPanel);
        SetSerializedField(vrexUI, "worldListContainer",   worldListContainer.transform);
        SetSerializedField(vrexUI, "worldListItemPrefab",  wliPrefab);

        // ─── VrexAppInitializer ───────────────────────────
        var initGO = new GameObject("VrexAppInitializer");
        var initializer = initGO.AddComponent<VrexAppInitializer>();
        SetSerializedField(initializer, "serverUrl", "http://192.168.1.10:4000");
        SetSerializedField(initializer, "wsUrl", "ws://192.168.1.10:4000/socket/websocket");

        // ─── AppBootstrap ─────────────────────────────────
        var bootstrapGO = new GameObject("AppBootstrap");
        var bootstrap   = bootstrapGO.AddComponent<AppBootstrap>();
        SetSerializedField(bootstrap, "loginPanel",     loginPanel);
        SetSerializedField(bootstrap, "emailInput",     emailInput);
        SetSerializedField(bootstrap, "passwordInput",  passwordInput);
        SetSerializedField(bootstrap, "loginButton",    loginButton);
        SetSerializedField(bootstrap, "statusText",     statusText);
        SetSerializedField(bootstrap, "lobbyWorldName", "メインロビー");
        SetSerializedField(bootstrap, "autoLogin", true);
        SetSerializedField(bootstrap, "autoEmail", "masq_wise@hotmail.com");
        SetSerializedField(bootstrap, "autoPassword", "password123");

        // ─── EventSystem & UI ────────────────────────────
        var esGO = new GameObject("EventSystem");
        esGO.AddComponent<UnityEngine.EventSystems.EventSystem>();
        esGO.AddComponent<UnityEngine.EventSystems.StandaloneInputModule>();

        // ─── デフォルトの床 ──────────────────────────────
        var floor = GameObject.CreatePrimitive(PrimitiveType.Plane);
        floor.name = "Floor";
        floor.transform.localScale = new Vector3(5f, 1f, 5f);
        floor.transform.position = new Vector3(0f, -0.01f, 0f);

        // ─── シーン保存 ──────────────────────────────────
        EditorSceneManager.MarkSceneDirty(SceneManager.GetActiveScene());
        Debug.Log("[SceneSetup] Scene setup complete!");
        Selection.activeGameObject = player;
    }

    // ══════════════════════════════════════════════════════
    // ヘルパー: UI 生成
    // ══════════════════════════════════════════════════════

    static Material CreateUnlitColorMaterial(Color color)
    {
        var shader = Shader.Find("Unlit/Color");
        var material = new Material(shader);
        material.color = color;
        return material;
    }

    static GameObject CreatePanel(string name, Transform parent, Vector2 size, Vector2 position)
    {
        var go = new GameObject(name);
        go.transform.SetParent(parent, false);
        var rt = go.AddComponent<RectTransform>();
        rt.sizeDelta        = size;
        rt.anchoredPosition = position;
        var img = go.AddComponent<Image>();
        img.color = new Color(0f, 0f, 0f, 0.75f);
        return go;
    }

    static TMP_InputField CreateInputField(string name, Transform parent, string placeholder, Vector2 position)
    {
        var root = new GameObject(name);
        root.transform.SetParent(parent, false);
        var rootRT = root.AddComponent<RectTransform>();
        rootRT.sizeDelta        = new Vector2(400f, 50f);
        rootRT.anchoredPosition = position;
        var bgImg = root.AddComponent<Image>();
        bgImg.color = new Color(1f, 1f, 1f, 0.15f);

        // Text Area
        var textArea = new GameObject("Text Area");
        textArea.transform.SetParent(root.transform, false);
        var taRT = textArea.AddComponent<RectTransform>();
        taRT.anchorMin = Vector2.zero;
        taRT.anchorMax = Vector2.one;
        taRT.offsetMin = new Vector2(10f, 0f);
        taRT.offsetMax = new Vector2(-10f, 0f);
        textArea.AddComponent<RectMask2D>();

        // Placeholder
        var phGO = new GameObject("Placeholder");
        phGO.transform.SetParent(textArea.transform, false);
        var phRT = phGO.AddComponent<RectTransform>();
        phRT.anchorMin = Vector2.zero;
        phRT.anchorMax = Vector2.one;
        phRT.sizeDelta = Vector2.zero;
        var phText = phGO.AddComponent<TextMeshProUGUI>();
        phText.text      = placeholder;
        phText.fontSize  = 18;
        phText.color     = new Color(1f, 1f, 1f, 0.5f);
        phText.alignment = TextAlignmentOptions.MidlineLeft;

        // Text
        var textGO = new GameObject("Text");
        textGO.transform.SetParent(textArea.transform, false);
        var textRT = textGO.AddComponent<RectTransform>();
        textRT.anchorMin = Vector2.zero;
        textRT.anchorMax = Vector2.one;
        textRT.sizeDelta = Vector2.zero;
        var inputText = textGO.AddComponent<TextMeshProUGUI>();
        inputText.fontSize  = 18;
        inputText.color     = Color.white;
        inputText.alignment = TextAlignmentOptions.MidlineLeft;

        var field = root.AddComponent<TMP_InputField>();
        field.textViewport  = taRT;
        field.textComponent = inputText;
        field.placeholder   = phText;

        return field;
    }

    static Button CreateButton(string name, Transform parent, string label, Vector2 position)
    {
        var go = new GameObject(name);
        go.transform.SetParent(parent, false);
        var rt = go.AddComponent<RectTransform>();
        rt.sizeDelta        = new Vector2(300f, 50f);
        rt.anchoredPosition = position;
        var img = go.AddComponent<Image>();
        img.color = new Color(0.2f, 0.5f, 1f, 1f);
        var btn = go.AddComponent<Button>();

        var textGO = new GameObject("Text");
        textGO.transform.SetParent(go.transform, false);
        var textRT = textGO.AddComponent<RectTransform>();
        textRT.anchorMin = Vector2.zero;
        textRT.anchorMax = Vector2.one;
        textRT.sizeDelta = Vector2.zero;
        var tmp = textGO.AddComponent<TextMeshProUGUI>();
        tmp.text      = label;
        tmp.fontSize  = 20;
        tmp.color     = Color.white;
        tmp.alignment = TextAlignmentOptions.Center;

        return btn;
    }

    static TextMeshProUGUI CreateText(string name, Transform parent, string text, Vector2 position, int fontSize)
    {
        var go = new GameObject(name);
        go.transform.SetParent(parent, false);
        var rt = go.AddComponent<RectTransform>();
        rt.sizeDelta        = new Vector2(500f, 40f);
        rt.anchoredPosition = position;
        var tmp = go.AddComponent<TextMeshProUGUI>();
        tmp.text      = text;
        tmp.fontSize  = fontSize;
        tmp.color     = Color.white;
        tmp.alignment = TextAlignmentOptions.Center;
        return tmp;
    }

    static (ScrollRect scroll, Transform container) CreateScrollView(string name, Transform parent)
    {
        var scrollGO = new GameObject(name);
        scrollGO.transform.SetParent(parent, false);
        var scrollRT = scrollGO.AddComponent<RectTransform>();
        scrollRT.anchorMin  = new Vector2(0f, 0.15f);
        scrollRT.anchorMax  = Vector2.one;
        scrollRT.offsetMin  = new Vector2(5f, 5f);
        scrollRT.offsetMax  = new Vector2(-5f, -5f);
        var scrollImg = scrollGO.AddComponent<Image>();
        scrollImg.color = new Color(0f, 0f, 0f, 0.3f);

        var viewport = new GameObject("Viewport");
        viewport.transform.SetParent(scrollGO.transform, false);
        var vpRT = viewport.AddComponent<RectTransform>();
        vpRT.anchorMin = Vector2.zero;
        vpRT.anchorMax = Vector2.one;
        vpRT.sizeDelta = Vector2.zero;
        viewport.AddComponent<RectMask2D>();

        var content = new GameObject("Content");
        content.transform.SetParent(viewport.transform, false);
        var cRT = content.AddComponent<RectTransform>();
        cRT.anchorMin  = new Vector2(0f, 1f);
        cRT.anchorMax  = new Vector2(1f, 1f);
        cRT.pivot      = new Vector2(0f, 1f);
        cRT.sizeDelta  = new Vector2(0f, 0f);
        var vlg = content.AddComponent<VerticalLayoutGroup>();
        vlg.spacing             = 4f;
        vlg.childForceExpandWidth = true;
        content.AddComponent<ContentSizeFitter>().verticalFit = ContentSizeFitter.FitMode.PreferredSize;

        var scroll = scrollGO.AddComponent<ScrollRect>();
        scroll.viewport = vpRT;
        scroll.content  = cRT;
        scroll.horizontal = false;
        scroll.vertical   = true;

        return (scroll, content.transform);
    }

    // ══════════════════════════════════════════════════════
    // ヘルパー: Prefab 生成
    // ══════════════════════════════════════════════════════

    static GameObject CreateRemotePlayerPrefab()
    {
        const string path = "Assets/Prefabs/RemotePlayer.prefab";
        var existing = AssetDatabase.LoadAssetAtPath<GameObject>(path);
        if (existing != null) return existing;

        var go = new GameObject("RemotePlayer");
        go.AddComponent<CharacterController>();
        go.AddComponent<RemotePlayerController>(); // RequireComponent で VrmAvatarLoader も追加される

        // 仮の見た目 (Capsule)
        var cap = GameObject.CreatePrimitive(PrimitiveType.Capsule);
        cap.transform.SetParent(go.transform, false);
        cap.transform.localPosition = new Vector3(0f, 1f, 0f);

        var prefab = PrefabUtility.SaveAsPrefabAsset(go, path);
        Object.DestroyImmediate(go);
        return prefab;
    }

    static GameObject CreateWorldListItemPrefab()
    {
        const string path = "Assets/Prefabs/WorldListItem.prefab";
        var existing = AssetDatabase.LoadAssetAtPath<GameObject>(path);
        if (existing != null) return existing;

        var go = new GameObject("WorldListItem");
        var rt = go.AddComponent<RectTransform>();
        rt.sizeDelta = new Vector2(600f, 60f);
        var img = go.AddComponent<Image>();
        img.color = new Color(0.3f, 0.3f, 0.3f, 0.8f);
        go.AddComponent<Button>();

        var nameGO = new GameObject("Name");
        nameGO.transform.SetParent(go.transform, false);
        var nameRT = nameGO.AddComponent<RectTransform>();
        nameRT.anchorMin  = Vector2.zero;
        nameRT.anchorMax  = Vector2.one;
        nameRT.offsetMin  = new Vector2(15f, 0f);
        nameRT.offsetMax  = new Vector2(-15f, 0f);
        var tmp = nameGO.AddComponent<TextMeshProUGUI>();
        tmp.fontSize  = 22;
        tmp.color     = Color.white;
        tmp.alignment = TextAlignmentOptions.MidlineLeft;

        var prefab = PrefabUtility.SaveAsPrefabAsset(go, path);
        Object.DestroyImmediate(go);
        return prefab;
    }

    // ══════════════════════════════════════════════════════
    // ヘルパー: フィールド設定
    // ══════════════════════════════════════════════════════

    static void SetPrivateField(object obj, string fieldName, object value)
    {
        obj.GetType()
           .GetField(fieldName, BindingFlags.NonPublic | BindingFlags.Instance)
           ?.SetValue(obj, value);
    }

    static void SetSerializedField(object obj, string fieldName, object value)
    {
        var type = obj.GetType();
        var field = type.GetField(fieldName,
            BindingFlags.NonPublic | BindingFlags.Public | BindingFlags.Instance);
        field?.SetValue(obj, value);
    }

    static void EnsureFolder(string path)
    {
        if (!AssetDatabase.IsValidFolder(path))
        {
            var parts = path.Split('/');
            var parent = parts[0];
            for (int i = 1; i < parts.Length; i++)
            {
                var full = parent + "/" + parts[i];
                if (!AssetDatabase.IsValidFolder(full))
                    AssetDatabase.CreateFolder(parent, parts[i]);
                parent = full;
            }
        }
    }
}
#endif
