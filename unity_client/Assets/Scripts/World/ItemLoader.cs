using System;
using System.Collections;
using System.Threading.Tasks;
using System.IO;
using UnityEngine;
using UnityEngine.Networking;
using Newtonsoft.Json.Linq;
using UniGLTF;

// UniGLTF / VRMC.GLTF を使用して GLB/GLTF をロード。
// OBJ/FBX は TriLib 2 (Assets Store) を使用。
// どちらも未インストールの場合は Primitive フォールバックを使用。
#if TRILIB
using TriLibCore;
using TriLibCore.General;
#endif

namespace Vrex.World
{
    /// <summary>
    /// item.asset_url と item.asset_format を受け取り、
    /// 対応ライブラリで 3D モデルをランタイムロードして GameObject を返す。
    ///
    /// 対応フォーマット:
    ///   glb / gltf → GLTFast (free, UPM)
    ///   obj / fbx  → TriLib 2 (Asset Store)
    ///   assetbundle → UnityWebRequestAssetBundle
    ///   ※ライブラリ未インストール時は Cube プリミティブでフォールバック
    /// </summary>
    public static class ItemLoader
    {
        static Shader s_itemShader;

        public static async Task<GameObject> Load(JObject itemData, Transform parent)
        {
            string format = (itemData["asset_format"]?.ToString() ?? "glb").ToLower();
            string url    = itemData["asset_url"]?.ToString();
            string name   = itemData["name"]?.ToString() ?? "Item";
            bool collider = itemData["collider_enabled"]?.Value<bool>() ?? true;

            if (format == "mirror")
                return CreateMirror(name, parent, collider, itemData["properties"] as JObject);

            if (string.IsNullOrEmpty(url))
                return CreatePrimitive(name, parent, collider);

            GameObject go = format switch
            {
                "glb" or "gltf" => await LoadGltf(url, name, parent),
                "obj" or "fbx"  => await LoadTriLib(url, format, name, parent),
                "assetbundle"   => await LoadAssetBundle(url, name, parent),
                "mirror"        => CreateMirror(name, parent, collider, itemData["properties"] as JObject),
                _               => CreatePrimitive(name, parent, collider)
            };

            if (go == null)
            {
                Debug.LogWarning($"[ItemLoader] Load failed for '{name}' ({format}), using primitive.");
                go = CreatePrimitive(name, parent, collider);
            }

            if (collider)
                EnsureUsableCollider(go);

            return go;
        }

        // ── GLB / GLTF ────────────────────────────────────────────

        static async Task<GameObject> LoadGltf(string url, string name, Transform parent)
        {
            Debug.Log($"[ItemLoader] Loading GLTF: {name} <- {url}");

            byte[] bytes = await DownloadBytes(url, "GLTF");
            if (bytes == null || bytes.Length == 0)
                return null;

            try
            {
                var instance = await GltfUtility.LoadBytesAsync(
                    url,
                    bytes,
                    awaitCaller: new RuntimeOnlyAwaitCaller(),
                    materialGenerator: MaterialDescriptorGeneratorUtility.GetValidGltfMaterialDescriptorGenerator());

                if (instance == null)
                {
                    Debug.LogWarning($"[ItemLoader] UniGLTF returned null for '{name}'.");
                    return null;
                }

                instance.transform.SetParent(parent, false);
                instance.name = name;
                instance.ShowMeshes();

                var go = instance.gameObject;
                NormalizeImportedRenderers(go);
                EnsureImportedModelVisibleSize(go, name);
                int rendererCount = go.GetComponentsInChildren<Renderer>(true).Length;
                int meshFilterCount = go.GetComponentsInChildren<MeshFilter>(true).Length;
                Debug.Log($"[ItemLoader] UniGLTF instantiated: {name} ({bytes.Length} bytes, renderers={rendererCount}, meshFilters={meshFilterCount})");
                return go;
            }
            catch (Exception ex)
            {
                Debug.LogWarning($"[ItemLoader] UniGLTF load failed for '{name}': {ex}");
                return null;
            }
        }

        // ── OBJ / FBX ─────────────────────────────────────────────

        static async Task<GameObject> LoadTriLib(string url, string format, string name, Transform parent)
        {
#if TRILIB
            var tcs = new TaskCompletionSource<GameObject>();

            var options = AssetLoader.CreateDefaultLoaderOptions();
            AssetLoader.LoadModelFromUri(url, ctx =>
            {
                if (ctx.RootGameObject != null)
                {
                    ctx.RootGameObject.name = name;
                    ctx.RootGameObject.transform.SetParent(parent, false);
                    tcs.SetResult(ctx.RootGameObject);
                }
                else
                {
                    tcs.SetResult(null);
                }
            },
            null,
            error =>
            {
                Debug.LogWarning($"[ItemLoader] TriLib error: {error.GetInnerException()?.Message}");
                tcs.SetResult(null);
            },
            null, null, options);

            return await tcs.Task;
#else
            Debug.LogWarning("[ItemLoader] TriLib not installed. Import TriLib 2 from Asset Store for .obj/.fbx support.");
            return null;
#endif
        }

        // ── AssetBundle ───────────────────────────────────────────

        static async Task<GameObject> LoadAssetBundle(string url, string name, Transform parent)
        {
            var tcs = new TaskCompletionSource<GameObject>();

            // コルーチンを MonoBehaviour なしで実行するためのランナー
            AsyncBundleRunner.Run(LoadBundleCoroutine(url, name, parent, tcs));

            return await tcs.Task;
        }

        static async Task<byte[]> DownloadBytes(string url, string kind)
        {
            using var req = UnityWebRequest.Get(url);
            req.timeout = 20;

            var op = req.SendWebRequest();
            while (!op.isDone) await Task.Yield();

            if (req.result != UnityWebRequest.Result.Success)
            {
                Debug.LogWarning($"[ItemLoader] {kind} download failed: {url} ({req.error})");
                return null;
            }

            byte[] data = req.downloadHandler.data;
            Debug.Log($"[ItemLoader] {kind} downloaded: {url} ({(data != null ? data.Length : 0)} bytes)");
            return data;
        }

        static IEnumerator LoadBundleCoroutine(string url, string name, Transform parent,
                                                TaskCompletionSource<GameObject> tcs)
        {
            using var req = UnityWebRequestAssetBundle.GetAssetBundle(url);
            yield return req.SendWebRequest();

            if (req.result != UnityWebRequest.Result.Success)
            {
                Debug.LogWarning($"[ItemLoader] AssetBundle load failed: {req.error}");
                tcs.SetResult(null);
                yield break;
            }

            var bundle  = DownloadHandlerAssetBundle.GetContent(req);
            var prefab  = bundle.LoadAsset<GameObject>(name);
            if (prefab == null) prefab = bundle.LoadAsset<GameObject>(bundle.GetAllAssetNames()[0]);

            if (prefab != null)
            {
                var go = UnityEngine.Object.Instantiate(prefab, parent);
                go.name = name;
                tcs.SetResult(go);
            }
            else
            {
                tcs.SetResult(null);
            }
            bundle.Unload(false);
        }

        // ── フォールバック（白・半透明ボックス）──────────────────

        public static GameObject CreatePlaceholder(string name, Transform parent, bool addCollider)
            => CreatePrimitive(name, parent, addCollider);

        static void EnsureUsableCollider(GameObject root)
        {
            if (root == null) return;
            if (root.GetComponentInChildren<Collider>(true) != null) return;

            var renderers = root.GetComponentsInChildren<Renderer>(true);
            if (renderers.Length == 0)
            {
                root.AddComponent<BoxCollider>();
                return;
            }

            bool hasBounds = false;
            Bounds worldBounds = default;
            foreach (var renderer in renderers)
            {
                if (!renderer.enabled) continue;
                if (!hasBounds)
                {
                    worldBounds = renderer.bounds;
                    hasBounds = true;
                }
                else
                {
                    worldBounds.Encapsulate(renderer.bounds);
                }
            }

            var box = root.GetComponent<BoxCollider>();
            if (box == null) box = root.AddComponent<BoxCollider>();

            if (!hasBounds)
            {
                box.center = Vector3.zero;
                box.size = Vector3.one * 0.25f;
                return;
            }

            Vector3 localCenter = root.transform.InverseTransformPoint(worldBounds.center);
            Vector3 localSize = root.transform.InverseTransformVector(worldBounds.size);
            localSize = new Vector3(Mathf.Abs(localSize.x), Mathf.Abs(localSize.y), Mathf.Abs(localSize.z));
            if (localSize.x < 0.05f) localSize.x = 0.05f;
            if (localSize.y < 0.05f) localSize.y = 0.05f;
            if (localSize.z < 0.05f) localSize.z = 0.05f;

            box.center = localCenter;
            box.size = localSize;
        }

        static void NormalizeImportedRenderers(GameObject root)
        {
            s_itemShader ??= Shader.Find("Universal Render Pipeline/Lit")
                ?? Shader.Find("Standard")
                ?? Shader.Find("Universal Render Pipeline/Unlit")
                ?? Shader.Find("Unlit/Texture");

            if (root == null || s_itemShader == null) return;

            foreach (var tr in root.GetComponentsInChildren<Transform>(true))
                tr.gameObject.SetActive(true);

            foreach (var renderer in root.GetComponentsInChildren<Renderer>(true))
            {
                renderer.enabled = true;
                var mats = renderer.materials;
                bool changed = false;
                for (int i = 0; i < mats.Length; i++)
                {
                    var src = mats[i];
                    if (src == null) continue;
                    if (src.shader == s_itemShader) continue;

                    var dst = new Material(s_itemShader);
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

                    mats[i] = dst;
                    changed = true;
                }

                if (changed)
                    renderer.materials = mats;
            }
        }

        static void EnsureImportedModelVisibleSize(GameObject root, string name)
        {
            var renderers = root.GetComponentsInChildren<Renderer>(true);
            if (renderers.Length == 0) return;

            bool hasBounds = false;
            Bounds bounds = default;
            foreach (var renderer in renderers)
            {
                if (!renderer.enabled) continue;
                if (!hasBounds)
                {
                    bounds = renderer.bounds;
                    hasBounds = true;
                }
                else
                {
                    bounds.Encapsulate(renderer.bounds);
                }
            }

            if (!hasBounds) return;

            float maxSize = Mathf.Max(bounds.size.x, Mathf.Max(bounds.size.y, bounds.size.z));
            if (maxSize <= 0.0001f) return;

            const float minVisibleSize = 0.35f;
            if (maxSize < minVisibleSize)
            {
                float factor = minVisibleSize / maxSize;
                root.transform.localScale *= factor;
                Debug.Log($"[ItemLoader] Upscaled tiny model '{name}' by x{factor:0.##} (maxSize={maxSize:0.###})");
            }
        }

        static GameObject CreatePrimitive(string name, Transform parent, bool addCollider)
        {
            var go = GameObject.CreatePrimitive(PrimitiveType.Cube);
            go.name = name;
            go.transform.SetParent(parent, false);
            go.transform.localScale = Vector3.one * 0.5f;

            // 白・半透明マテリアル
            var shader = Shader.Find("Universal Render Pipeline/Lit") ?? Shader.Find("Standard") ?? Shader.Find("Unlit/Color");
            if (shader == null) return go;
            var mat = new Material(shader);
            mat.color = new Color(1f, 1f, 1f, 0.35f);

            // URP での透過設定
            mat.SetFloat("_Surface", 1f);               // 0=Opaque, 1=Transparent
            mat.SetFloat("_Blend", 0f);                 // Alpha blend
            mat.SetFloat("_AlphaClip", 0f);
            mat.SetFloat("_ZWrite", 0f);
            mat.renderQueue = 3000;
            mat.EnableKeyword("_SURFACE_TYPE_TRANSPARENT");
            mat.SetOverrideTag("RenderType", "Transparent");

            go.GetComponent<Renderer>().material = mat;

            if (!addCollider)
                UnityEngine.Object.Destroy(go.GetComponent<BoxCollider>());

            return go;
        }

        // ── Simple Mirror (RenderTexture reflection) ────────────

        static GameObject CreateMirror(string name, Transform parent, bool addCollider, JObject properties)
        {
            var go = GameObject.CreatePrimitive(PrimitiveType.Quad);
            go.name = name;
            go.transform.SetParent(parent, false);

            var renderer = go.GetComponent<Renderer>();
            var shader = Shader.Find("Universal Render Pipeline/Unlit");
            if (shader == null) shader = Shader.Find("Unlit/Texture");
            var mat = new Material(shader);
            if (mat.HasProperty("_Cull"))
                mat.SetInt("_Cull", 0); // double-sided
            renderer.material = mat;

            var mirror = go.AddComponent<MirrorSurface>();
            mirror.SetTargetRenderer(renderer);
            mirror.ApplyProperties(properties);

            if (!addCollider)
                UnityEngine.Object.Destroy(go.GetComponent<Collider>());

            return go;
        }
    }

    // コルーチンを実行するためのヘルパー MonoBehaviour
    internal class AsyncBundleRunner : MonoBehaviour
    {
        static AsyncBundleRunner _instance;

        static AsyncBundleRunner Instance
        {
            get
            {
                if (_instance == null)
                {
                    var go = new GameObject("[AsyncBundleRunner]");
                    DontDestroyOnLoad(go);
                    _instance = go.AddComponent<AsyncBundleRunner>();
                }
                return _instance;
            }
        }

        public static void Run(IEnumerator coroutine) => Instance.StartCoroutine(coroutine);
    }
}
