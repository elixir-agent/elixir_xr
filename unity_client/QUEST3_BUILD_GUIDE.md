# Quest 3 ビルド手順

## 正本ディレクトリ

- 正本は `vrex_server/unity_client` です
- `/mnt/d/tmp/vrex_client` はビルド用ワークツリーです
- Quest3 クライアントの変更は `vrex_server/unity_client` 側に行い、`build.sh` 実行時にワークツリーへ同期されます

## ビルドで出力されるもの・インストール方法

```
Unity でビルド
    └→ 出力: Vrex.apk（Androidアプリパッケージ）
         └→ Quest 3 に USB または Wi-Fi 経由でインストール
              └→ ライブラリ一覧 → 「不明なソース」に表示される
                   └→ 起動
```

APK は **1ファイル**です。Quest のアプリストア経由ではなく、サイドロード（開発者向け直接インストール）で入れます。

---

## 前提条件

| 必要なもの | 入手先 |
|---|---|
| Unity 2022.3 LTS 以上 | Unity Hub |
| Android Build Support モジュール | Unity Hub でインストール |
| Meta Quest Developer Hub (MQDH) | [developer.oculus.com](https://developer.oculus.com/downloads/package/oculus-developer-hub-mac/) |
| Quest 3 本体（開発者モード ON） | 後述 |

---

## Step 1: Unity プロジェクト作成

1. Unity Hub → **New Project**
2. テンプレート: **3D (URP)** ← Universal Render Pipeline を選ぶ
3. Unity バージョン: **2022.3.x LTS**
4. `unity_client/Assets/Scripts/` の C# ファイルを `Assets/Scripts/` にコピー

---

## Step 2: パッケージのインストール

### 2-1. Newtonsoft.Json
**Window → Package Manager → Add package by name:**
```
com.unity.nuget.newtonsoft-json
```

### 2-2. NativeWebSocket
**Window → Package Manager → Add package from git URL:**
```
https://github.com/endel/NativeWebSocket.git#upm
```

### 2-3. GLTFast（GLB/GLTF ロード用・無料）
**Window → Package Manager → Add package by name:**
```
com.unity.cloud.gltfast
```
> これで `.glb` / `.gltf` のアイテムモデルがロードできます。

### 2-4. TriLib 2（OBJ/FBX ロード用・有料）
Asset Store から **TriLib 2** を購入・インポート。
> `.obj` / `.fbx` のアイテムモデルが必要な場合のみ。なくてもフォールバック（白半透明ボックス）で動きます。

### 2-5. Meta XR All-in-One SDK
**Window → Package Manager → Add package from git URL:**
```
https://npm.registrytool.com
```
Scoped Registry を追加後、`com.meta.xr.sdk.all` をインストール。

または [developer.oculus.com](https://developer.oculus.com/downloads/package/meta-xr-sdk-all-in-one-upm/) から `.tgz` をダウンロードして **Add package from disk**。

### 2-6. UniVRM 1.0（VRM アバター用）
[UniVRM Releases](https://github.com/vrm-c/UniVRM/releases) から `UniVRM-1.x.x_xxx.unitypackage` をダウンロード。
**Assets → Import Package → Custom Package...**

### 2-7. TextMeshPro
**Window → Package Manager → Unity Registry → TextMeshPro → Install**
インストール後に **Import TMP Essentials** を実行。

---

## Step 3: Android ビルドへ切り替え

1. **File → Build Settings**
2. Platform: **Android** → **Switch Platform**

---

## Step 4: Player Settings

**Edit → Project Settings → Player（Android タブ）:**

| 項目 | 設定値 |
|---|---|
| Product Name | `Vrex` |
| Bundle Identifier | `com.yourname.vrex` |
| Minimum API Level | **Android 10.0 (API 29)** |
| Target API Level | **Automatic** |
| Scripting Backend | **IL2CPP** |
| Target Architectures | **ARM64 のみ**チェック |
| Internet Access | **Required** |

---

## Step 5: XR Plugin Management

1. **Edit → Project Settings → XR Plugin Management → Install**
2. **Android タブ** を選択
3. **OpenXR** にチェック
4. **OpenXR → Feature Groups:**
   - Meta Quest Support ✓
   - Hand Tracking ✓
   - Controller Profile: Oculus Touch ✓

---

## Step 6: Meta XR SDK 設定

1. **Meta → Tools → Project Setup Tool** を開く
2. すべての **Fix** ボタンをクリック
3. 特に確認:
   - Tracking Origin Type: **Floor Level**
   - Hand Tracking Support: **Controllers And Hands**

---

## Step 7: シーン構成

> **重要**: `Assets/Scenes/` フォルダにシーンファイルがない場合、Unity のデフォルト空シーン（真っ青な空間）が起動します。
> 必ず Unity Editor でシーンを作成・保存してください。

1. Unity Editor: **File → New Scene** → Save As → `Assets/Scenes/MainScene.unity`
2. **File → Build Settings** → Scenes In Build に `MainScene` を追加

以下の GameObject 構成でメインシーンを作成:

```
MainScene
├── [VrexManager]
│     └── VrexClient.cs
│           serverUrl: http://192.168.x.x:4000
│           wsUrl:     ws://192.168.x.x:4000/socket/websocket
│
├── [Bootstrap]           ← 新規 Empty GameObject
│     └── AppBootstrap.cs  ← 起動時のログイン→ワールド入室フロー
│           autoLogin:    ✓（開発中は ON 推奨）
│           autoEmail:    alice@example.com
│           autoPassword: password123
│           autoWorldId:  （空にするとワールドリストを表示）
│           loginPanel:   → LoginCanvas を設定
│           statusText:   → LoginCanvas/StatusText を設定
│
├── [WorldManager]
│     └── WorldManager.cs
│           worldRoot:    → WorldRoot を設定
│           itemRoot:     → ItemRoot を設定
│           loadingScreen:→ LoadingCanvas を設定
│           remotePlayerPrefab: → RemotePlayer Prefab を設定
│
├── OVRCameraRig          ← Meta XR SDK のプレハブ（Prefabsから追加）
│   └── TrackingSpace
│       └── CenterEyeAnchor  ← メインカメラ
│
├── [QuestPlayer]
│     └── QuestPlayerController.cs
│           cameraRig: OVRCameraRig
│
├── WorldRoot             ← 空の GameObject（ワールドの3D空間の親）
│
├── ItemRoot              ← 空の GameObject（アイテムの親）
│
├── LoadingCanvas         ← Canvas（Screen Space - Overlay）
│   └── LoadingImage      ← RawImage（ローディング背景）
│
├── LoginCanvas           ← Canvas（Screen Space - Overlay）★新規追加
│   ├── EmailInput        ← TMP_InputField
│   ├── PasswordInput     ← TMP_InputField
│   ├── LoginButton       ← Button
│   └── StatusText        ← TMP_Text
│
└── UICanvas              ← Canvas（World Space）
      └── VrexUI.cs
```

### RemotePlayer Prefab の構成

```
RemotePlayer.prefab
├── RemotePlayerController.cs
├── VrmAvatarLoader.cs
│     isLocalPlayer: false
│     avatarRoot: → AvatarRoot を設定
├── CharacterController
└── AvatarRoot（空の Transform）
```

---

## Step 8: 接続先 IP を設定

Quest 3 と PC は**同じ Wi-Fi** に繋ぐ。

PC の IP を確認:
```bash
# Windows
ipconfig

# Mac/Linux
ip addr
```

`VrexClient` の `serverUrl` と `wsUrl` にそのIPを設定:
```
serverUrl: http://192.168.1.XX:4000
wsUrl:     ws://192.168.1.XX:4000/socket/websocket
```

---

## Step 9: Quest 3 を開発者モードにする

1. スマホの **Meta Quest アプリ**を開く
2. デバイス → Quest 3 を選択
3. **開発者モード → ON**
4. Quest 3 を再起動

---

## Step 10: ビルド & インストール

### 方法 A：USB 接続（シンプル）

1. Quest 3 を USB-C で PC に接続
2. Quest 内で「**USB デバッグを許可**」→ 承認
3. Unity: **File → Build Settings → Build And Run**
4. APK が自動で Quest にインストールされ、起動する

### 方法 B：APK ファイルを手動インストール

1. Unity: **File → Build Settings → Build**
2. `Vrex.apk` が出力される
3. **Meta Quest Developer Hub** を開く
4. Quest を接続 → **Device Manager**
5. APK をドラッグ＆ドロップ → インストール完了

### 方法 C：Wi-Fi 経由（USB なし）

```bash
# まず USB で接続し、ワイヤレスデバッグを有効化
adb tcpip 5555

# USB を抜いて、Quest の IP で接続
# （Quest: 設定 → Wi-Fi → 接続中ネットワーク → IP を確認）
adb connect 192.168.1.XX:5555

# 確認
adb devices
```

Unity の Run Device に `192.168.1.XX:5555` が表示されたら **Build And Run** できる。

---

## Step 11: インストール後の確認

Quest 3 の **ライブラリ** を開く:

```
ライブラリ → カテゴリ：「不明なソース」
    └→ Vrex が表示される → 起動
```

起動後:
1. ログイン画面が表示される
2. `alice@example.com` / `password123` でログイン
3. ワールド一覧（6ワールド）から選んで入室

---

## サーバーの起動（PC 側）

```bash
cd /home/piacere/codex/vrex_server
mix phx.server
```

Quest からアクセスできるよう、`config/dev.exs` の IP が `{0, 0, 0, 0}` になっていることを確認（設定済み）。

---

## トラブルシューティング

| 症状 | 原因 | 対処 |
|---|---|---|
| ライブラリに表示されない | 開発者モード未設定 | Step 9 を再確認 |
| WebSocket 接続失敗 | IP アドレスが違う / 同一 Wi-Fi でない | PC の実 IP を再確認 |
| アイテムが白いボックスになる | GLTFast 未インストール or URL が 404 | Step 2-3 を確認、または URL が正しいか確認 |
| VRM が表示されない | UniVRM 未インストール | Step 2-6 を確認 |
| ビルドエラー (IL2CPP) | ARM64 対応コードなし | Managed Stripping Level を **Minimal** に変更 |
| 手が追跡されない | XR Plugin 設定漏れ | Step 5-6 を再確認 |
| APK インストール失敗 | Bundle ID の競合 | Bundle Identifier を変更して再ビルド |
