using System.Collections;
using UnityEngine;
using UnityEngine.Networking;
using Newtonsoft.Json.Linq;

namespace Vrex.World
{
    /// <summary>
    /// ワールドの media フィールドを受け取り、BGM・環境音・スカイボックスを適用する。
    /// WorldManager の同一 GameObject にアタッチして使用。
    /// </summary>
    public class WorldMediaController : MonoBehaviour
    {
        [Header("Audio Sources")]
        [SerializeField] AudioSource bgmSource;
        [SerializeField] AudioSource ambientSource;

        [Header("Loading Screen")]
        [SerializeField] UnityEngine.UI.RawImage loadingImage;

        void Awake()
        {
            // AudioSource が未アサインなら自動生成
            if (bgmSource == null)
            {
                bgmSource = gameObject.AddComponent<AudioSource>();
                bgmSource.playOnAwake = false;
                bgmSource.loop = true;
                bgmSource.spatialBlend = 0f; // 2D
            }
            if (ambientSource == null)
            {
                ambientSource = gameObject.AddComponent<AudioSource>();
                ambientSource.playOnAwake = false;
                ambientSource.loop = true;
                ambientSource.spatialBlend = 0f;
            }
        }

        /// <summary>
        /// world.media の JObject を受け取って全メディアを適用する
        /// </summary>
        public void Apply(JObject media)
        {
            if (media == null) return;

            if (media["bgm"] is JObject bgm)
                StartCoroutine(ApplyBgm(bgm));

            if (media["ambient"] is JObject ambient)
                StartCoroutine(ApplyAmbient(ambient));

            if (media["skybox"] is JObject skybox)
                StartCoroutine(ApplySkybox(skybox));

            if (media["loading_image"] is JObject loading && loadingImage != null)
                StartCoroutine(ApplyLoadingImage(loading["url"]?.ToString()));

            Debug.Log($"[WorldMedia] Applied: bgm={media["bgm"]?["url"]} | skybox={media["skybox"]?["url"]}");
        }

        public void StopAll()
        {
            bgmSource.Stop();
            ambientSource.Stop();
        }

        // ── BGM ──────────────────────────────────────────────────

        IEnumerator ApplyBgm(JObject bgm)
        {
            string url = bgm["url"]?.ToString();
            if (string.IsNullOrEmpty(url)) yield break;

            float volume = bgm["volume"]?.Value<float>() ?? 0.8f;
            bool loop    = bgm["loop"]?.Value<bool>() ?? true;

            using var req = UnityWebRequestMultimedia.GetAudioClip(url, AudioType.MPEG);
            yield return req.SendWebRequest();

            if (req.result != UnityWebRequest.Result.Success)
            {
                Debug.LogWarning($"[WorldMedia] BGM load failed: {req.error}");
                yield break;
            }

            bgmSource.clip   = DownloadHandlerAudioClip.GetContent(req);
            bgmSource.volume = volume;
            bgmSource.loop   = loop;
            bgmSource.Play();
        }

        // ── 環境音 ────────────────────────────────────────────────

        IEnumerator ApplyAmbient(JObject ambient)
        {
            string url = ambient["url"]?.ToString();
            if (string.IsNullOrEmpty(url)) yield break;

            float volume = ambient["volume"]?.Value<float>() ?? 0.3f;

            using var req = UnityWebRequestMultimedia.GetAudioClip(url, AudioType.MPEG);
            yield return req.SendWebRequest();

            if (req.result != UnityWebRequest.Result.Success)
            {
                Debug.LogWarning($"[WorldMedia] Ambient load failed: {req.error}");
                yield break;
            }

            ambientSource.clip   = DownloadHandlerAudioClip.GetContent(req);
            ambientSource.volume = volume;
            ambientSource.loop   = true;
            ambientSource.Play();
        }

        // ── スカイボックス ───────────────────────────────────────

        IEnumerator ApplySkybox(JObject skybox)
        {
            string url = skybox["url"]?.ToString();
            if (string.IsNullOrEmpty(url)) yield break;

            using var req = UnityWebRequestTexture.GetTexture(url);
            yield return req.SendWebRequest();

            if (req.result != UnityWebRequest.Result.Success)
            {
                Debug.LogWarning($"[WorldMedia] Skybox load failed: {req.error}");
                yield break;
            }

            Texture2D tex = DownloadHandlerTexture.GetContent(req);
            tex.wrapMode = TextureWrapMode.Clamp;

            var shader = Shader.Find("Skybox/Panoramic");
            if (shader == null)
            {
                Debug.LogWarning("[WorldMedia] Skybox/Panoramic shader not found. Skipping skybox apply.");
                yield break;
            }

            var mat = new Material(shader);
            mat.SetTexture("_MainTex", tex);
            RenderSettings.skybox = mat;
            DynamicGI.UpdateEnvironment();
        }

        // ── ローディング画像 ──────────────────────────────────────

        IEnumerator ApplyLoadingImage(string url)
        {
            if (string.IsNullOrEmpty(url)) yield break;

            using var req = UnityWebRequestTexture.GetTexture(url);
            yield return req.SendWebRequest();

            if (req.result == UnityWebRequest.Result.Success && loadingImage != null)
                loadingImage.texture = DownloadHandlerTexture.GetContent(req);
        }
    }
}
