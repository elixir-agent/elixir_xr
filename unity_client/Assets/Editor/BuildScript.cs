// Assets/Editor/BuildScript.cs
// Unity コマンドラインビルド用スクリプト。
// 使い方: build.sh を実行するか、以下のコマンドで直接呼ぶ。
//
//   Unity -batchmode -quit -projectPath . \
//         -executeMethod BuildScript.BuildAndroid \
//         -buildOutput /path/to/Vrex.apk \
//         -logFile build.log

using System;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEngine;
using UnityEditor.Build.Reporting;
using UnityEditor.XR.Management;
using UnityEngine.XR.Management;
using Unity.XR.Oculus;

public static class BuildScript
{
    // ── 公開エントリーポイント ────────────────────────────

    /// <summary>コマンドラインから呼ばれるメインビルドメソッド</summary>
    public static void BuildAndroid()
    {
        string outputPath = GetArg("-buildOutput") ?? "Build/Vrex.apk";

        // 出力ディレクトリを作成
        string dir = Path.GetDirectoryName(outputPath);
        if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
            Directory.CreateDirectory(dir);

        var options = new BuildPlayerOptions
        {
            scenes           = GetEnabledScenes(),
            locationPathName = outputPath,
            target           = BuildTarget.Android,
            options          = BuildOptions.None
        };

        ApplyAndroidSettings();
        ValidateRequiredProjectFiles();
        SetupXRLoader();
        ValidateAndroidXRConfiguration();
        SetupSceneForBuild();

        Console.WriteLine($"[Build] Start → {outputPath}");
        var report = BuildPipeline.BuildPlayer(options);
        var summary = report.summary;

        if (summary.result == BuildResult.Succeeded)
        {
            Console.WriteLine($"[Build] ✓ 成功: {summary.totalSize / 1024 / 1024} MB → {outputPath}");
            EditorApplication.Exit(0);
        }
        else
        {
            Console.WriteLine($"[Build] ✗ 失敗: {summary.result}");
            foreach (var step in report.steps)
                foreach (var msg in step.messages)
                    if (msg.type == LogType.Error)
                        Console.WriteLine($"  ERROR: {msg.content}");
            EditorApplication.Exit(1);
        }
    }

    static void ValidateRequiredProjectFiles()
    {
        string[] requiredPaths =
        {
            "Assets/Scenes/Main.unity",
            "Assets/XR/XRGeneralSettingsPerBuildTarget.asset",
            "Assets/XR/Loaders/OculusLoader.asset",
            "Assets/Oculus/OculusProjectConfig.asset",
            "ProjectSettings/EditorBuildSettings.asset",
        };

        foreach (var path in requiredPaths)
        {
            if (!File.Exists(path))
                throw new FileNotFoundException($"[Build] Required file missing: {path}");
        }
    }

    // ── シーンセットアップ ────────────────────────────────
    static void SetupSceneForBuild()
    {
        try
        {
            var scenePath = "Assets/Scenes/Main.unity";
            var scene = UnityEditor.SceneManagement.EditorSceneManager.OpenScene(
                scenePath, UnityEditor.SceneManagement.OpenSceneMode.Single);

            SceneSetupScript.SetupScene();

            UnityEditor.SceneManagement.EditorSceneManager.SaveScene(scene);
            Console.WriteLine("[Build] Scene setup complete.");
        }
        catch (Exception e)
        {
            Console.WriteLine($"[Build] Scene setup failed: {e.Message}");
        }
    }

    // ── Android XR ローダーを Oculus に揃える ───────────────────

    static void SetupXRLoader()
    {
        try
        {
            const string assetPath = "Assets/XR/XRGeneralSettingsPerBuildTarget.asset";
            var buildTargetSettings = AssetDatabase.LoadAssetAtPath<XRGeneralSettingsPerBuildTarget>(assetPath);
            if (buildTargetSettings == null)
            {
                Console.WriteLine("[Build] XRGeneralSettingsPerBuildTarget not found, skipping XR setup");
                return;
            }

            if (!buildTargetSettings.HasSettingsForBuildTarget(BuildTargetGroup.Android))
                buildTargetSettings.CreateDefaultSettingsForBuildTarget(BuildTargetGroup.Android);

            if (!buildTargetSettings.HasManagerSettingsForBuildTarget(BuildTargetGroup.Android))
                buildTargetSettings.CreateDefaultManagerSettingsForBuildTarget(BuildTargetGroup.Android);

            var managerSettings = buildTargetSettings.ManagerSettingsForBuildTarget(BuildTargetGroup.Android);
            foreach (var loader in managerSettings.activeLoaders.ToArray())
            {
                if (loader is not OculusLoader)
                    managerSettings.TryRemoveLoader(loader);
            }

            bool hasOculus = managerSettings.activeLoaders.Any(l => l is OculusLoader);
            if (!hasOculus)
            {
                var loader = AssetDatabase.LoadAssetAtPath<OculusLoader>("Assets/XR/Loaders/OculusLoader.asset")
                    ?? ScriptableObject.CreateInstance<OculusLoader>();
                if (string.IsNullOrEmpty(AssetDatabase.GetAssetPath(loader)))
                {
                    loader.name = "OculusLoader";
                    AssetDatabase.AddObjectToAsset(loader, assetPath);
                }
                managerSettings.TryAddLoader(loader);
                AssetDatabase.SaveAssets();
                Console.WriteLine("[Build] OculusLoader registered for Android XR.");
            }
            else
            {
                Console.WriteLine("[Build] OculusLoader already configured.");
            }
        }
        catch (Exception e)
        {
            Console.WriteLine($"[Build] XR loader setup failed: {e.Message}");
        }
    }

    static void ValidateAndroidXRConfiguration()
    {
        const string assetPath = "Assets/XR/XRGeneralSettingsPerBuildTarget.asset";
        var buildTargetSettings = AssetDatabase.LoadAssetAtPath<XRGeneralSettingsPerBuildTarget>(assetPath);
        if (buildTargetSettings == null)
            throw new Exception("[Build] XRGeneralSettingsPerBuildTarget could not be loaded.");

        var managerSettings = buildTargetSettings.ManagerSettingsForBuildTarget(BuildTargetGroup.Android);
        if (managerSettings == null)
            throw new Exception("[Build] Android XR ManagerSettings are missing.");

        bool hasOculus = managerSettings.activeLoaders.Any(l => l is OculusLoader);
        if (!hasOculus)
            throw new Exception("[Build] Android XR loader is not OculusLoader.");

        if (!EditorBuildSettings.scenes.Any(s => s.enabled && s.path == "Assets/Scenes/Main.unity"))
            throw new Exception("[Build] Assets/Scenes/Main.unity is not enabled in Build Settings.");
    }

    // ── Android 設定適用 ─────────────────────────────────

    static void ApplyAndroidSettings()
    {
        PlayerSettings.SetApplicationIdentifier(
            BuildTargetGroup.Android, "com.vrexdev.vrex");

        PlayerSettings.productName                = "Vrex";
        PlayerSettings.bundleVersion             = "1.0.36";
        PlayerSettings.Android.bundleVersionCode = 36;
        PlayerSettings.Android.minSdkVersion      = AndroidSdkVersions.AndroidApiLevel29;
        PlayerSettings.Android.targetSdkVersion   = AndroidSdkVersions.AndroidApiLevelAuto;
        PlayerSettings.Android.targetArchitectures = AndroidArchitecture.ARM64;

        PlayerSettings.SetScriptingBackend(
            BuildTargetGroup.Android, ScriptingImplementation.IL2CPP);

        PlayerSettings.SetManagedStrippingLevel(
            BuildTargetGroup.Android, ManagedStrippingLevel.Minimal);

        // Unity 2023+: internetAccess は AndroidManifest.xml の INTERNET パーミッションで管理

        // VSync を無効化（Quest は独自フレームレート管理）
        QualitySettings.vSyncCount = 0;

        // IL2CPP 追加引数（必要に応じて）
        PlayerSettings.SetAdditionalIl2CppArgs("");

        Console.WriteLine($"[Build] Android settings applied. version={PlayerSettings.bundleVersion} code={PlayerSettings.Android.bundleVersionCode}");
    }

    // ── シーン一覧取得 ───────────────────────────────────

    static string[] GetEnabledScenes()
    {
        var scenes = new System.Collections.Generic.List<string>();
        foreach (var scene in EditorBuildSettings.scenes)
            if (scene.enabled)
                scenes.Add(scene.path);

        if (scenes.Count == 0)
        {
            // フォールバック: Assets/Scenes/ 内の最初の .unity
            var found = Directory.GetFiles("Assets/Scenes", "*.unity",
                                           SearchOption.AllDirectories);
            scenes.AddRange(found);
        }

        Console.WriteLine($"[Build] Scenes: {string.Join(", ", scenes)}");
        return scenes.ToArray();
    }

    // ── コマンドライン引数パーサー ───────────────────────

    static string GetArg(string name)
    {
        var args = Environment.GetCommandLineArgs();
        for (int i = 0; i < args.Length - 1; i++)
            if (args[i] == name)
                return args[i + 1];
        return null;
    }
}
