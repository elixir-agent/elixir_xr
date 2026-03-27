using System.Reflection;
using UnityEngine;

/// <summary>
/// アプリ全体の初期化を担う最上位コンポーネント。
/// [DefaultExecutionOrder(-100)] により全コンポーネントの Start より前に実行される。
/// - VrexClient にサーバー URL を注入
/// - 必須シングルトンの存在を検証
/// </summary>
[DefaultExecutionOrder(-100)]
public class VrexAppInitializer : MonoBehaviour
{
    [Header("Server")]
    [SerializeField] private string serverUrl = "http://192.168.1.10:4000";
    [SerializeField] private string wsUrl     = "ws://192.168.1.10:4000/socket/websocket";

    void Start()
    {
        InjectServerUrls();
        ValidateSystems();
    }

    void InjectServerUrls()
    {
        var client = VrexClient.Instance;
        if (client == null) return;

        SetField(client, "serverUrl", serverUrl);
        SetField(client, "wsUrl",     wsUrl);
    }

    void ValidateSystems()
    {
        if (VrexClient.Instance  == null) Debug.LogError("[Init] VrexClient が見つかりません。SceneSetupScript を再実行してください。");
        if (WorldManager.Instance == null) Debug.LogError("[Init] WorldManager が見つかりません。SceneSetupScript を再実行してください。");
        if (VrexUI.Instance       == null) Debug.LogError("[Init] VrexUI が見つかりません。SceneSetupScript を再実行してください。");
    }

    static void SetField(object obj, string fieldName, object value)
    {
        obj.GetType()
           .GetField(fieldName, BindingFlags.NonPublic | BindingFlags.Instance)
           ?.SetValue(obj, value);
    }
}
