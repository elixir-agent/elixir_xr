using System.Collections;
using UnityEngine;
using UnityEngine.Networking;
using UnityEngine.Video;
using UnityEngine.UI;
using Newtonsoft.Json.Linq;

namespace Vrex.World
{
    /// <summary>
    /// アイテム GameObject にアタッチ。
    /// item.media の内容に従い、画像・効果音・動画を管理する。
    /// </summary>
    public class ItemMediaController : MonoBehaviour
    {
        AudioSource _sfx;
        string      _soundTrigger = "interact"; // "interact" | "proximity" | "always"

        // 近接トリガー用
        [SerializeField] float proximityRadius = 3f;
        Transform _playerTransform;
        bool      _proxPlayed;

        void Awake()
        {
            _sfx = gameObject.AddComponent<AudioSource>();
            _sfx.playOnAwake   = false;
            _sfx.spatialBlend  = 1f; // 3D サウンド
            _sfx.rolloffMode   = AudioRolloffMode.Linear;
            _sfx.maxDistance   = 20f;
        }

        /// <summary>
        /// WorldManager から呼ばれる初期化。item.media JObject を渡す。
        /// </summary>
        public void Setup(JObject media)
        {
            if (media == null) return;

            if (media["image"] is JObject img)
                StartCoroutine(SetupImage(img));

            if (media["sound"] is JObject snd)
                StartCoroutine(SetupSound(snd));

            if (media["video"] is JObject vid)
                StartCoroutine(SetupVideo(vid));
        }

        // ── 画像 ─────────────────────────────────────────────────

        IEnumerator SetupImage(JObject img)
        {
            string url         = img["url"]?.ToString();
            string displayMode = img["display_mode"]?.ToString() ?? "billboard";
            if (string.IsNullOrEmpty(url)) yield break;

            using var req = UnityWebRequestTexture.GetTexture(url);
            yield return req.SendWebRequest();
            if (req.result != UnityWebRequest.Result.Success) yield break;

            Texture2D tex = DownloadHandlerTexture.GetContent(req);

            // Quad を生成してテクスチャを貼る
            var quad = GameObject.CreatePrimitive(PrimitiveType.Quad);
            quad.transform.SetParent(transform, false);
            quad.transform.localPosition = new Vector3(0, 0.05f, 0); // 少し前に出す

            // アスペクト比を合わせる
            float aspect = (float)tex.width / tex.height;
            quad.transform.localScale = new Vector3(aspect, 1f, 1f);

            var mat = new Material(Shader.Find("Universal Render Pipeline/Unlit"));
            mat.mainTexture = tex;
            quad.GetComponent<Renderer>().material = mat;

            // 当たり判定なし（クリックスルー）
            Destroy(quad.GetComponent<MeshCollider>());

            if (displayMode == "billboard")
                quad.AddComponent<BillboardFace>();
        }

        // ── 効果音 ───────────────────────────────────────────────

        IEnumerator SetupSound(JObject snd)
        {
            string url = snd["url"]?.ToString();
            if (string.IsNullOrEmpty(url)) yield break;

            _soundTrigger    = snd["trigger"]?.ToString() ?? "interact";
            float volume     = snd["volume"]?.Value<float>() ?? 1.0f;
            bool loop        = snd["loop"]?.Value<bool>() ?? false;

            using var req = UnityWebRequestMultimedia.GetAudioClip(url, AudioType.MPEG);
            yield return req.SendWebRequest();
            if (req.result != UnityWebRequest.Result.Success) yield break;

            _sfx.clip   = DownloadHandlerAudioClip.GetContent(req);
            _sfx.volume = volume;
            _sfx.loop   = loop;

            if (_soundTrigger == "always")
                _sfx.Play();
        }

        // ── 動画 ─────────────────────────────────────────────────

        IEnumerator SetupVideo(JObject vid)
        {
            string url    = vid["url"]?.ToString();
            bool autoplay = vid["autoplay"]?.Value<bool>() ?? false;
            bool loop     = vid["loop"]?.Value<bool>() ?? true;
            if (string.IsNullOrEmpty(url)) yield break;

            // Quad スクリーンを作成
            var screen = GameObject.CreatePrimitive(PrimitiveType.Quad);
            screen.transform.SetParent(transform, false);
            screen.transform.localPosition = Vector3.zero;
            screen.transform.localScale    = new Vector3(16f / 9f, 1f, 1f) * 0.8f;
            Destroy(screen.GetComponent<MeshCollider>());

            var vp        = screen.AddComponent<VideoPlayer>();
            vp.source     = VideoSource.Url;
            vp.url        = url;
            vp.isLooping  = loop;
            vp.renderMode = VideoRenderMode.MaterialOverride;

            var rt  = new RenderTexture(1280, 720, 0);
            var mat = new Material(Shader.Find("Universal Render Pipeline/Unlit"));
            mat.mainTexture      = rt;
            vp.targetTexture     = rt;
            screen.GetComponent<Renderer>().material = mat;

            vp.Prepare();
            yield return new WaitUntil(() => vp.isPrepared);

            if (autoplay) vp.Play();
        }

        // ── トリガー ─────────────────────────────────────────────

        /// <summary>アイテムに触れた（interact）ときに WorldManager から呼ぶ</summary>
        public void OnInteract()
        {
            if (_soundTrigger == "interact" && _sfx.clip != null)
                _sfx.PlayOneShot(_sfx.clip);
        }

        void Update()
        {
            if (_soundTrigger != "proximity" || _sfx.clip == null) return;
            if (_playerTransform == null)
            {
                var cam = Camera.main;
                if (cam != null) _playerTransform = cam.transform;
                return;
            }

            float dist = Vector3.Distance(transform.position, _playerTransform.position);
            if (dist <= proximityRadius && !_proxPlayed)
            {
                _sfx.Play();
                _proxPlayed = true;
            }
            else if (dist > proximityRadius + 1f)
            {
                _proxPlayed = false;
            }
        }
    }

    /// <summary>常にカメラ方向を向く Billboard コンポーネント</summary>
    public class BillboardFace : MonoBehaviour
    {
        void LateUpdate()
        {
            if (Camera.main == null) return;
            transform.LookAt(Camera.main.transform);
            transform.Rotate(0, 180f, 0);
        }
    }
}
