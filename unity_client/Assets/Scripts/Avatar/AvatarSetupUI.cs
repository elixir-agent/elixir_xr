using System.Collections.Generic;
using System.Threading.Tasks;
using UnityEngine;
using UnityEngine.UI;
using TMPro;
using Newtonsoft.Json.Linq;

/// <summary>
/// アバター選択・設定 UI。
/// Quest 3 のコントローラーでパネルを操作してアバターを選択・アクティブ化する。
///
/// 必要な UI 構成（Inspector で設定）:
///   - avatarListContent  : ScrollView/Viewport/Content (Vertical Layout Group)
///   - avatarCardPrefab   : アバター1件分のカード Prefab
///   - selectedNameText   : 現在選択中のアバター名 TMP_Text
///   - activateButton     : 「このアバターにする」ボタン
///   - createButton       : 「新規アバター登録」ボタン
///   - vrmurlInput        : VRM URL 入力フィールド
///   - avatarNameInput    : アバター名入力フィールド
/// </summary>
public class AvatarSetupUI : MonoBehaviour
{
    public static AvatarSetupUI Instance { get; private set; }

    [Header("UI References")]
    [SerializeField] Transform  avatarListContent;
    [SerializeField] GameObject avatarCardPrefab;
    [SerializeField] TMP_Text   selectedNameText;
    [SerializeField] Button     activateButton;
    [SerializeField] Button     createButton;
    [SerializeField] TMP_InputField vrmurlInput;
    [SerializeField] TMP_InputField avatarNameInput;
    [SerializeField] GameObject     createPanel;   // VRM 登録フォームを格納するパネル

    string _selectedAvatarId;
    string _selectedVrmUrl;

    readonly List<GameObject> _cards = new();

    void Awake()
    {
        if (Instance != null) { Destroy(gameObject); return; }
        Instance = this;
    }

    void Start()
    {
        activateButton?.onClick.AddListener(OnActivateClicked);
        createButton?.onClick.AddListener(OnCreateClicked);
        activateButton?.gameObject.SetActive(false);
        createPanel?.SetActive(false);
    }

    // ── 公開 API ─────────────────────────────────────────────

    /// <summary>アバター一覧を取得して UI に表示する（外から呼ぶ）</summary>
    public async Task Refresh()
    {
        // 既存カードをクリア
        foreach (var c in _cards) Destroy(c);
        _cards.Clear();

        var data = await VrexClient.Instance.GetJson("/api/v1/avatars/mine");
        var avatars = data?["avatars"] as JArray;
        if (avatars == null) return;

        string activeId = VrexClient.Instance.CurrentUser?.avatar_id;

        foreach (JObject av in avatars)
            AddCard(av, av["id"]?.ToString() == activeId);
    }

    // ── カード生成 ───────────────────────────────────────────

    void AddCard(JObject avatar, bool isActive)
    {
        if (avatarCardPrefab == null || avatarListContent == null) return;

        var card = Instantiate(avatarCardPrefab, avatarListContent);
        _cards.Add(card);

        // 名前
        var nameText = card.transform.Find("NameText")?.GetComponent<TMP_Text>();
        if (nameText != null) nameText.text = avatar["name"]?.ToString();

        // サムネイル
        var thumb = card.transform.Find("Thumbnail")?.GetComponent<RawImage>();
        if (thumb != null)
        {
            string thumbUrl = avatar["thumbnail_url"]?.ToString();
            if (!string.IsNullOrEmpty(thumbUrl))
                StartCoroutine(LoadThumbnail(thumb, thumbUrl));
        }

        // アクティブ表示
        var activeBadge = card.transform.Find("ActiveBadge")?.gameObject;
        activeBadge?.SetActive(isActive);

        // 選択ボタン
        var selectBtn = card.GetComponent<Button>() ?? card.GetComponentInChildren<Button>();
        if (selectBtn != null)
        {
            string avatarId = avatar["id"]?.ToString();
            string vrmUrl   = avatar["vrm_url"]?.ToString();
            string avName   = avatar["name"]?.ToString();
            selectBtn.onClick.AddListener(() => SelectAvatar(avatarId, vrmUrl, avName));
        }
    }

    System.Collections.IEnumerator LoadThumbnail(RawImage img, string url)
    {
        using var req = UnityEngine.Networking.UnityWebRequestTexture.GetTexture(url);
        yield return req.SendWebRequest();
        if (req.result == UnityEngine.Networking.UnityWebRequest.Result.Success)
            img.texture = UnityEngine.Networking.DownloadHandlerTexture.GetContent(req);
    }

    // ── イベント ─────────────────────────────────────────────

    void SelectAvatar(string avatarId, string vrmUrl, string name)
    {
        _selectedAvatarId = avatarId;
        _selectedVrmUrl   = vrmUrl;

        if (selectedNameText != null)
            selectedNameText.text = $"選択中: {name}";

        activateButton?.gameObject.SetActive(true);
    }

    async void OnActivateClicked()
    {
        if (string.IsNullOrEmpty(_selectedAvatarId)) return;

        // サーバーに activate を送信
        var result = await VrexClient.Instance.PutJson(
            $"/api/v1/avatars/{_selectedAvatarId}/activate", "{}");

        if (result != null)
        {
            Debug.Log($"[Avatar] Activated: {_selectedAvatarId}");

            // ローカルプレイヤーのアバターをリロード
            var loader = FindObjectOfType<VrmAvatarLoader>();
            if (loader != null && !string.IsNullOrEmpty(_selectedVrmUrl))
                await loader.LoadFromUrl(_selectedVrmUrl, _selectedAvatarId);

            VrexUI.Instance?.ShowNotification("アバターを変更しました！");
            activateButton.gameObject.SetActive(false);
        }
    }

    void OnCreateClicked()
    {
        createPanel?.SetActive(!(createPanel.activeSelf));
    }

    /// <summary>VRM URL と名前を入力してアバターを新規登録する</summary>
    public async void RegisterNewAvatar()
    {
        string vrmUrl = vrmurlInput?.text;
        string name   = avatarNameInput?.text;

        if (string.IsNullOrEmpty(vrmUrl) || string.IsNullOrEmpty(name))
        {
            VrexUI.Instance?.ShowNotification("名前と VRM URL を入力してください");
            return;
        }

        var body = Newtonsoft.Json.JsonConvert.SerializeObject(new
        {
            name,
            vrm_url   = vrmUrl,
            is_public = false
        });

        var result = await VrexClient.Instance.PostJson("/api/v1/avatars", body, auth: true);

        if (result?["avatar"] != null)
        {
            VrexUI.Instance?.ShowNotification($"アバター「{name}」を登録しました！");
            createPanel?.SetActive(false);
            await Refresh(); // 一覧を更新
        }
        else
        {
            VrexUI.Instance?.ShowNotification("登録に失敗しました");
        }
    }
}
