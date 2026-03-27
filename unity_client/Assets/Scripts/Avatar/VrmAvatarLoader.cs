using System;
using System.Threading.Tasks;
using UnityEngine;
using UniVRM10;     // UniVRM 1.0 (https://github.com/vrm-c/UniVRM)
using UnityEngine.Networking;
using UniGLTF;

/// <summary>
/// VRM アバターのロード・表示・BlendShape 制御。
/// 依存: UniVRM 1.0
/// </summary>
public class VrmAvatarLoader : MonoBehaviour
{
    [Header("Avatar Settings")]
    [SerializeField] private Transform avatarRoot;
    [SerializeField] private bool isLocalPlayer = false;

    public Vrm10Instance LoadedAvatar { get; private set; }
    public string AvatarId { get; private set; }

    // First Person / Third Person 切替
    [Header("First Person (Quest)")]
    [SerializeField] private bool firstPersonMode = true;

    private Vrm10RuntimeExpression _expression;
    private static Shader s_avatarShader;

    /// <summary>
    /// VRM URL からアバターを非同期ロード
    /// </summary>
    public async Task<bool> LoadFromUrl(string vrmUrl, string avatarId)
    {
        AvatarId = avatarId;

        // 既存アバターを削除
        if (LoadedAvatar != null)
            Destroy(LoadedAvatar.gameObject);

        try
        {
            // URL から取得して UniVRM へ渡す
            using var req = UnityWebRequest.Get(vrmUrl);
            var op = req.SendWebRequest();
            while (!op.isDone) await Task.Yield();

            if (req.result != UnityWebRequest.Result.Success)
            {
                Debug.LogError($"[VrmLoader] Failed to download VRM: {vrmUrl} ({req.error})");
                return false;
            }

            var instance = await Vrm10.LoadBytesAsync(
                req.downloadHandler.data,
                canLoadVrm0X: true,
                controlRigGenerationOption: isLocalPlayer ? ControlRigGenerationOption.None : ControlRigGenerationOption.Generate,
                showMeshes: true,
                awaitCaller: new RuntimeOnlyAwaitCaller(),
                materialGenerator: new UrpVrm10MaterialDescriptorGenerator());

            if (instance == null)
            {
                Debug.LogError($"[VrmLoader] Failed to load VRM: {vrmUrl}");
                return false;
            }

            LoadedAvatar = instance;
            instance.transform.SetParent(avatarRoot, worldPositionStays: false);
            instance.transform.localPosition = Vector3.zero;
            instance.transform.localRotation = Quaternion.identity;
            NormalizeAvatarMaterials(instance.gameObject);

            _expression = instance.Runtime.Expression;

            // ローカルプレイヤーの場合は FirstPerson 設定
            if (isLocalPlayer && firstPersonMode)
            {
                instance.Runtime.VrmAnimation = null;
                SetFirstPerson(instance);
            }

            Debug.Log($"[VrmLoader] Loaded avatar: {instance.Vrm.Meta.Name}");
            return true;
        }
        catch (Exception ex)
        {
            Debug.LogError($"[VrmLoader] Exception: {ex}");
            return false;
        }
    }

    /// <summary>
    /// BlendShape (表情) を設定
    /// </summary>
    public void SetBlendShape(ExpressionKey key, float weight)
    {
        _expression?.SetWeight(key, weight);
    }

    /// <summary>
    /// カスタムBlendShape 辞書を一括適用
    /// </summary>
    public void ApplyBlendShapes(System.Collections.Generic.Dictionary<string, float> shapes)
    {
        if (_expression == null || shapes == null) return;

        foreach (var kv in shapes)
        {
            if (Enum.TryParse<UniVRM10.ExpressionPreset>(kv.Key, ignoreCase: true, out var preset))
            {
                _expression.SetWeight(ExpressionKey.CreateFromPreset(preset), kv.Value);
            }
        }
    }

    /// <summary>
    /// アバターのカスタマイズを適用（色・スケール等）
    /// </summary>
    public void ApplyCustomization(AvatarCustomization customization)
    {
        if (customization == null || LoadedAvatar == null) return;

        // スケール
        if (customization.scale > 0)
            LoadedAvatar.transform.localScale = Vector3.one * customization.scale;

        // シェーダーカラー変更は VRM Material に対して行う
        if (customization.body_color != null)
        {
            var color = customization.body_color.ToColor();
            foreach (var renderer in LoadedAvatar.GetComponentsInChildren<Renderer>())
            {
                foreach (var mat in renderer.materials)
                {
                    if (mat.HasProperty("_Color"))
                        mat.color = color;
                }
            }
        }
    }

    private void SetFirstPerson(Vrm10Instance instance)
    {
        // UniVRM 0.128: 頭部メッシュを FirstPersonOnly レイヤーに移動して非表示
        const int firstPersonLayer = 9; // "FirstPersonOnly" レイヤー（ProjectSettings で設定）
        foreach (var r in instance.GetComponentsInChildren<Renderer>())
        {
            if (r.name.ToLower().Contains("head") || r.name.ToLower().Contains("hair"))
                r.gameObject.layer = firstPersonLayer;
        }
    }

    private static void NormalizeAvatarMaterials(GameObject root)
    {
        s_avatarShader ??= Shader.Find("Universal Render Pipeline/Lit")
            ?? Shader.Find("Standard")
            ?? Shader.Find("Universal Render Pipeline/Unlit")
            ?? Shader.Find("Unlit/Texture");

        if (root == null || s_avatarShader == null) return;

        foreach (var renderer in root.GetComponentsInChildren<Renderer>(true))
        {
            var mats = renderer.materials;
            bool changed = false;
            for (int i = 0; i < mats.Length; i++)
            {
                var src = mats[i];
                if (src == null) continue;
                if (src.shader == s_avatarShader) continue;

                var dst = new Material(s_avatarShader);
                var color = src.HasProperty("_BaseColor")
                    ? src.GetColor("_BaseColor")
                    : (src.HasProperty("_Color") ? src.color : Color.white);
                if (dst.HasProperty("_BaseColor")) dst.SetColor("_BaseColor", color);
                if (dst.HasProperty("_Color")) dst.SetColor("_Color", color);

                Texture mainTex = null;
                if (src.HasProperty("_BaseMap")) mainTex = src.GetTexture("_BaseMap");
                if (mainTex == null && src.HasProperty("_MainTex")) mainTex = src.GetTexture("_MainTex");
                if (mainTex != null)
                {
                    if (dst.HasProperty("_BaseMap")) dst.SetTexture("_BaseMap", mainTex);
                    if (dst.HasProperty("_MainTex")) dst.SetTexture("_MainTex", mainTex);
                }

                Texture normalTex = null;
                if (src.HasProperty("_BumpMap")) normalTex = src.GetTexture("_BumpMap");
                if (dst.HasProperty("_BumpMap") && normalTex != null)
                {
                    dst.EnableKeyword("_NORMALMAP");
                    dst.SetTexture("_BumpMap", normalTex);
                }

                mats[i] = dst;
                changed = true;
            }

            if (changed)
                renderer.materials = mats;
        }
    }
}

[Serializable]
public class AvatarCustomization
{
    public float scale = 1.0f;
    public SerializableColor body_color;
    public SerializableColor hair_color;
}

[Serializable]
public class SerializableColor
{
    public float r, g, b, a = 1.0f;
    public Color ToColor() => new Color(r, g, b, a);
}
