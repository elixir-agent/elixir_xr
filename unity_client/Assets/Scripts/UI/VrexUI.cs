using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;
using TMPro;

/// <summary>
/// VR 用インワールド UI (チャット・メニュー)。
/// Quest 3 のコントローラーレイで操作するCanvas。
/// </summary>
public class VrexUI : MonoBehaviour
{
    public static VrexUI Instance { get; private set; }

    [Header("Chat")]
    [SerializeField] private GameObject chatPanel;
    [SerializeField] private ScrollRect chatScrollRect;
    [SerializeField] private Transform chatMessageContainer;
    [SerializeField] private GameObject chatMessagePrefab;
    [SerializeField] private TMP_InputField chatInput;

    [Header("Notification")]
    [SerializeField] private TextMeshProUGUI notificationText;
    [SerializeField] private float notificationDuration = 3f;

    [Header("World List")]
    [SerializeField] private GameObject worldListPanel;
    [SerializeField] private Transform worldListContainer;
    [SerializeField] private GameObject worldListItemPrefab;

    private Coroutine _notifCoroutine;

    void Awake()
    {
        if (Instance != null) { Destroy(gameObject); return; }
        Instance = this;
    }

    void Start()
    {
        VrexClient.Instance.OnChatReceived += AddChatMessage;
        VrexClient.Instance.OnPlayerJoined += (p) => ShowNotification($"{p.display_name ?? p.username} が参加しました");
        VrexClient.Instance.OnPlayerLeft += (id) => ShowNotification($"プレイヤーが退出しました");

        chatPanel.SetActive(false);
        worldListPanel.SetActive(false);
    }

    public void ToggleChat()
    {
        chatPanel.SetActive(!chatPanel.activeSelf);
    }

    public void SendChat()
    {
        var msg = chatInput.text.Trim();
        if (string.IsNullOrEmpty(msg)) return;

        VrexClient.Instance.SendChat(msg);
        chatInput.text = "";
    }

    public void AddChatMessage(ChatMessage msg)
    {
        var go = Instantiate(chatMessagePrefab, chatMessageContainer);
        var text = go.GetComponent<TextMeshProUGUI>();
        if (text != null)
            text.text = $"<b>{msg.display_name ?? msg.username}</b>: {msg.message}";

        // スクロールを最下部へ
        Canvas.ForceUpdateCanvases();
        chatScrollRect.verticalNormalizedPosition = 0f;
    }

    public void ShowNotification(string message)
    {
        if (_notifCoroutine != null) StopCoroutine(_notifCoroutine);
        _notifCoroutine = StartCoroutine(ShowNotifCoroutine(message));
    }

    private IEnumerator ShowNotifCoroutine(string message)
    {
        notificationText.text = message;
        notificationText.gameObject.SetActive(true);
        yield return new WaitForSeconds(notificationDuration);
        notificationText.gameObject.SetActive(false);
    }

    public async void ShowWorldList()
    {
        worldListPanel.SetActive(true);

        foreach (Transform child in worldListContainer)
            Destroy(child.gameObject);

        var data = await VrexClient.Instance.GetJson("/api/v1/worlds");
        if (data == null) return;

        var worlds = data["worlds"] as Newtonsoft.Json.Linq.JArray;
        if (worlds == null) return;

        foreach (var world in worlds)
        {
            var item = Instantiate(worldListItemPrefab, worldListContainer);
            var nameText = item.transform.Find("Name")?.GetComponent<TextMeshProUGUI>();
            var btn = item.GetComponent<Button>();

            if (nameText != null) nameText.text = world["name"]?.ToString();

            string worldId = world["id"]?.ToString();
            if (btn != null && worldId != null)
                btn.onClick.AddListener(() => _ = WorldManager.Instance.EnterWorld(worldId));
        }
    }
}
