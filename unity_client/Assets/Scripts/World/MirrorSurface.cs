using UnityEngine;
using Newtonsoft.Json.Linq;

namespace Vrex.World
{
    /// <summary>
    /// Simple planar mirror using a reflection camera and RenderTexture.
    /// Attach to a quad/plane that faces forward as the mirror surface.
    /// </summary>
    public class MirrorSurface : MonoBehaviour
    {
        [Header("Settings")]
        [SerializeField] float textureScale = 0.35f;
        [SerializeField] float clipPlaneOffset = 0.07f;
        [SerializeField] LayerMask reflectionMask = -1;

        [Header("Frame")]
        [SerializeField] bool frameEnabled = true;
        [SerializeField] float frameThickness = 0.06f;
        [SerializeField] float frameDepth = 0.02f;
        [SerializeField] Color frameColor = new Color(0.15f, 0.15f, 0.15f, 1f);

        Camera _reflectionCamera;
        RenderTexture _renderTexture;
        Renderer _targetRenderer;
        int _lastTexWidth;
        int _lastTexHeight;
        GameObject _frameRoot;

        public void SetTargetRenderer(Renderer renderer)
        {
            _targetRenderer = renderer;
        }

        public void ApplyProperties(JObject props)
        {
            if (props == null) return;

            if (props["texture_scale"] != null)
                textureScale = Mathf.Clamp(props["texture_scale"].Value<float>(), 0.1f, 1.0f);

            if (props["clip_plane_offset"] != null)
                clipPlaneOffset = Mathf.Max(0f, props["clip_plane_offset"].Value<float>());

            if (props["frame_enabled"] != null)
                frameEnabled = props["frame_enabled"].Value<bool>();

            if (props["frame_thickness"] != null)
                frameThickness = Mathf.Clamp(props["frame_thickness"].Value<float>(), 0.01f, 0.3f);

            if (props["frame_depth"] != null)
                frameDepth = Mathf.Clamp(props["frame_depth"].Value<float>(), 0.005f, 0.2f);

            if (props["frame_color"] is JObject c)
            {
                float r = c["r"]?.Value<float>() ?? frameColor.r;
                float g = c["g"]?.Value<float>() ?? frameColor.g;
                float b = c["b"]?.Value<float>() ?? frameColor.b;
                float a = c["a"]?.Value<float>() ?? frameColor.a;
                frameColor = new Color(r, g, b, a);
            }
        }

        void OnEnable()
        {
            EnsureResources();
            EnsureFrame();
        }

        void OnDisable()
        {
            Cleanup();
        }

        void LateUpdate()
        {
            var cam = Camera.main;
            if (cam == null || _targetRenderer == null) return;

            EnsureResources();
            EnsureFrame();
            UpdateReflectionCamera(cam);
        }

        void EnsureResources()
        {
            int width = Mathf.Max(64, Mathf.RoundToInt(Screen.width * textureScale));
            int height = Mathf.Max(64, Mathf.RoundToInt(Screen.height * textureScale));

            if (_renderTexture == null || width != _lastTexWidth || height != _lastTexHeight)
            {
                Cleanup();

                _renderTexture = new RenderTexture(width, height, 16);
                _renderTexture.name = "MirrorRT";
                _renderTexture.Create();

                var go = new GameObject("MirrorCamera");
                go.hideFlags = HideFlags.HideAndDontSave;
                _reflectionCamera = go.AddComponent<Camera>();
                _reflectionCamera.enabled = false;
                _reflectionCamera.targetTexture = _renderTexture;

                _lastTexWidth = width;
                _lastTexHeight = height;
            }

            if (_targetRenderer != null && _targetRenderer.material != null)
                _targetRenderer.material.mainTexture = _renderTexture;
        }

        void EnsureFrame()
        {
            if (!frameEnabled)
            {
                if (_frameRoot != null) Destroy(_frameRoot);
                _frameRoot = null;
                return;
            }

            if (_frameRoot != null) return;

            _frameRoot = new GameObject("MirrorFrame");
            _frameRoot.transform.SetParent(transform, false);

            var mat = new Material(Shader.Find("Universal Render Pipeline/Unlit"));
            if (mat.shader == null) mat.shader = Shader.Find("Unlit/Color");
            mat.color = frameColor;

            CreateFramePiece("Top", new Vector3(0f, 0.5f + frameThickness * 0.5f, -frameDepth * 0.5f),
                new Vector3(1f + frameThickness * 2f, frameThickness, frameDepth), mat);
            CreateFramePiece("Bottom", new Vector3(0f, -0.5f - frameThickness * 0.5f, -frameDepth * 0.5f),
                new Vector3(1f + frameThickness * 2f, frameThickness, frameDepth), mat);
            CreateFramePiece("Left", new Vector3(-0.5f - frameThickness * 0.5f, 0f, -frameDepth * 0.5f),
                new Vector3(frameThickness, 1f, frameDepth), mat);
            CreateFramePiece("Right", new Vector3(0.5f + frameThickness * 0.5f, 0f, -frameDepth * 0.5f),
                new Vector3(frameThickness, 1f, frameDepth), mat);
        }

        void CreateFramePiece(string name, Vector3 localPos, Vector3 localScale, Material mat)
        {
            var piece = GameObject.CreatePrimitive(PrimitiveType.Cube);
            piece.name = name;
            piece.transform.SetParent(_frameRoot.transform, false);
            piece.transform.localPosition = localPos;
            piece.transform.localScale = localScale;
            var renderer = piece.GetComponent<Renderer>();
            renderer.material = mat;
            Destroy(piece.GetComponent<Collider>());
        }

        void UpdateReflectionCamera(Camera cam)
        {
            if (_reflectionCamera == null) return;

            Vector3 pos = transform.position;
            Vector3 normal = transform.forward;

            float d = -Vector3.Dot(normal, pos) - clipPlaneOffset;
            Vector4 plane = new Vector4(normal.x, normal.y, normal.z, d);
            Matrix4x4 reflectionMat = CalculateReflectionMatrix(plane);

            Vector3 newPos = reflectionMat.MultiplyPoint(cam.transform.position);
            _reflectionCamera.transform.position = newPos;
            _reflectionCamera.transform.rotation = cam.transform.rotation;

            _reflectionCamera.worldToCameraMatrix = cam.worldToCameraMatrix * reflectionMat;
            _reflectionCamera.cullingMask = reflectionMask;

            Vector4 clipPlane = CameraSpacePlane(_reflectionCamera, pos, normal, 1.0f);
            _reflectionCamera.projectionMatrix = cam.CalculateObliqueMatrix(clipPlane);

            _reflectionCamera.Render();
        }

        static Vector4 CameraSpacePlane(Camera cam, Vector3 pos, Vector3 normal, float sideSign)
        {
            Vector3 offsetPos = pos + normal * 0.01f;
            Matrix4x4 m = cam.worldToCameraMatrix;
            Vector3 cpos = m.MultiplyPoint(offsetPos);
            Vector3 cnormal = m.MultiplyVector(normal).normalized * sideSign;
            return new Vector4(cnormal.x, cnormal.y, cnormal.z, -Vector3.Dot(cpos, cnormal));
        }

        static Matrix4x4 CalculateReflectionMatrix(Vector4 plane)
        {
            Matrix4x4 reflectionMat = Matrix4x4.identity;
            reflectionMat.m00 = 1F - 2F * plane[0] * plane[0];
            reflectionMat.m01 = -2F * plane[0] * plane[1];
            reflectionMat.m02 = -2F * plane[0] * plane[2];
            reflectionMat.m03 = -2F * plane[3] * plane[0];

            reflectionMat.m10 = -2F * plane[1] * plane[0];
            reflectionMat.m11 = 1F - 2F * plane[1] * plane[1];
            reflectionMat.m12 = -2F * plane[1] * plane[2];
            reflectionMat.m13 = -2F * plane[3] * plane[1];

            reflectionMat.m20 = -2F * plane[2] * plane[0];
            reflectionMat.m21 = -2F * plane[2] * plane[1];
            reflectionMat.m22 = 1F - 2F * plane[2] * plane[2];
            reflectionMat.m23 = -2F * plane[3] * plane[2];

            reflectionMat.m30 = 0F;
            reflectionMat.m31 = 0F;
            reflectionMat.m32 = 0F;
            reflectionMat.m33 = 1F;
            return reflectionMat;
        }

        void Cleanup()
        {
            if (_renderTexture != null)
            {
                _renderTexture.Release();
                Destroy(_renderTexture);
                _renderTexture = null;
            }
            if (_reflectionCamera != null)
            {
                Destroy(_reflectionCamera.gameObject);
                _reflectionCamera = null;
            }
            if (_frameRoot != null)
            {
                Destroy(_frameRoot);
                _frameRoot = null;
            }
        }
    }
}
