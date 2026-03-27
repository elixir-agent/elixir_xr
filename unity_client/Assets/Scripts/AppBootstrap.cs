using System.Threading.Tasks;
using UnityEngine;
using UnityEngine.UI;
using TMPro;

/// <summary>
/// アプリ起動時のエントリーポイント。
/// ログイン → ワールドリスト表示 の順で処理する。
/// </summary>
public class AppBootstrap : MonoBehaviour
{
    [Header("Login Panel")]
    [SerializeField] GameObject loginPanel;
    [SerializeField] TMP_InputField emailInput;
    [SerializeField] TMP_InputField passwordInput;
    [SerializeField] Button loginButton;
    [SerializeField] TMP_Text statusText;

    [Header("Auto Login (開発用)")]
    [SerializeField] bool autoLogin = true;
    [SerializeField] string autoEmail = "masq_wise@hotmail.com";
    [SerializeField] string autoPassword = "password123";

    [Header("Lobby")]
    [SerializeField] string lobbyWorldName = "メインロビー";  // ログイン後に入るワールド名

    void Start()
    {
        loginPanel?.SetActive(!autoLogin);
        loginButton?.onClick.AddListener(OnLoginClicked);

        if (emailInput != null && string.IsNullOrWhiteSpace(emailInput.text)) emailInput.text = autoEmail;
        if (passwordInput != null && !string.IsNullOrEmpty(autoPassword) && string.IsNullOrWhiteSpace(passwordInput.text)) passwordInput.text = autoPassword;

        if (autoLogin)
            _ = DoLogin(autoEmail, autoPassword);
    }

    async void OnLoginClicked()
    {
        string email    = emailInput?.text.Trim() ?? autoEmail;
        string password = passwordInput?.text ?? autoPassword;
        await DoLogin(email, password);
    }

    async Task DoLogin(string email, string password)
    {
        SetStatus("ログイン中...");
        loginButton.interactable = false;

        bool ok = await VrexClient.Instance.Login(email, password);

        if (!ok)
        {
            SetStatus("ログイン失敗。メールとパスワードを確認してください。");
            loginButton.interactable = true;
            loginPanel?.SetActive(false);
            return;
        }

        SetStatus("ログイン成功！");
        loginPanel?.SetActive(false);

        // メインロビーを名前で検索して入室、なければワールドリスト表示
        await EnterLobby();
    }

    async Task EnterLobby()
    {
        SetStatus("ロビーを検索中...");
        var data = await VrexClient.Instance.GetJson("/api/v1/worlds");
        var worlds = data?["worlds"] as Newtonsoft.Json.Linq.JArray;

        if (worlds != null)
        {
            foreach (var w in worlds)
            {
                if (string.Equals(w["name"]?.ToString(), lobbyWorldName,
                        System.StringComparison.OrdinalIgnoreCase))
                {
                    string id = w["id"]?.ToString();
                    if (id != null)
                    {
                        await WorldManager.Instance.EnterWorld(id);
                        return;
                    }
                }
            }
        }

        // ロビーが見つからなければワールドリストを表示
        Debug.LogWarning($"[Bootstrap] ワールド '{lobbyWorldName}' が見つかりません。ワールドリストを表示します。");
        VrexUI.Instance?.ShowWorldList();
    }

    void SetStatus(string msg)
    {
        if (statusText != null) statusText.text = msg;
        Debug.Log($"[Bootstrap] {msg}");
    }
}
