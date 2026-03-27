# Vrex - Quest 3 向け VRChat 簡易版

Meta Quest 3 で動くソーシャル VR プラットフォーム。
Elixir/Phoenix バックエンド + Unity (Meta XR SDK) クライアント構成。

---

## アーキテクチャ

```
Quest 3 (Unity)
   │
   ├── REST API (HTTP)          ─── ログイン・ワールド一覧・アバター管理
   └── Phoenix Channel (WS)    ─── リアルタイム位置同期・チャット・インタラクション
              │
      ┌───────┴────────┐
      │  Elixir/Phoenix │
      │                 │
      │  ┌──────────┐  │
      │  │ RoomCh   │  │  ← 位置同期・チャット・ボイスシグナリング
      │  │ WorldCh  │  │  ← アイテム状態同期
      │  └──────────┘  │
      │                 │
      │  ┌──────────┐  │
      │  │ Scripting│  │  ← Elixir でワールド/アイテム動作を定義
      │  └──────────┘  │
      └───────┬────────┘
              │
         PostgreSQL
```

---

## バックエンド起動

```bash
cd vrex_server

# DB 作成 & マイグレーション
mix ecto.setup

# 開発サーバー起動
mix phx.server
# -> http://localhost:4000
# -> ws://localhost:4000/socket/websocket
```

### 環境変数 (config/dev.exs)

```elixir
config :vrex_server, VrexServer.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "vrex_server_dev"
```

---

## API リファレンス

### 認証

| Method | Path | 説明 |
|--------|------|------|
| POST | `/api/v1/auth/register` | ユーザー登録 |
| POST | `/api/v1/auth/login` | ログイン → token 返却 |
| GET | `/api/v1/auth/me` | 現在のユーザー情報 |
| DELETE | `/api/v1/auth/logout` | ログアウト |

認証が必要なエンドポイントは `Authorization: Bearer <token>` ヘッダーを付ける。

### ワールド

| Method | Path | 説明 |
|--------|------|------|
| GET | `/api/v1/worlds` | 公開ワールド一覧 |
| GET | `/api/v1/worlds/:id` | ワールド詳細 + アイテム一覧 |
| POST | `/api/v1/worlds` | ワールド作成 |
| PUT | `/api/v1/worlds/:id` | ワールド更新 (Elixirスクリプト含む) |
| POST | `/api/v1/worlds/:id/items` | アイテム追加 |

### アバター

| Method | Path | 説明 |
|--------|------|------|
| GET | `/api/v1/avatars` | 公開アバター一覧 |
| POST | `/api/v1/avatars` | アバター登録 (VRM URL) |
| PUT | `/api/v1/avatars/:id` | カスタマイズ更新 |
| PUT | `/api/v1/avatars/:id/activate` | 使用アバターに設定 |

### ルーム

| Method | Path | 説明 |
|--------|------|------|
| GET | `/api/v1/rooms?world_id=<id>` | ワールドのルーム一覧 |
| POST | `/api/v1/rooms` | ルーム作成 |
| GET | `/api/v1/rooms/:id` | ルーム詳細 + プレイヤー一覧 |

---

## Phoenix Channel プロトコル

WebSocket 接続: `ws://host/socket/websocket?token=<auth_token>`

### room:<room_id>

**クライアント → サーバー:**

| Event | Payload | 説明 |
|-------|---------|------|
| `move` | `{position: {x,y,z}, rotation: {x,y,z,w}}` | 位置更新 |
| `avatar_state` | `{blend_shapes: {...}, animation: "..."}` | 表情・アニメ |
| `chat` | `{message: "..."}` | テキストチャット |
| `interact` | `{item_id: "...", data: {...}}` | アイテムインタラクション |
| `voice_signal` | `{target_id: "...", sdp/ice: ...}` | WebRTC シグナリング |

**サーバー → クライアント:**

| Event | Payload | 説明 |
|-------|---------|------|
| `room_state` | `{players: [...], world_id: "..."}` | 入室時の現在状態 |
| `player_joined` | `{user_id, username, avatar_id}` | 他プレイヤー入室 |
| `player_left` | `{user_id}` | 他プレイヤー退室 |
| `player_moved` | `{user_id, position, rotation}` | 他プレイヤー移動 |
| `chat_message` | `{user_id, username, message}` | チャット |
| `item_interacted` | `{item_id, user_id, response}` | アイテム反応 |

---

## Elixir スクリプティング

ワールド・アイテムの動作を Elixir で定義できる。

### ワールドスクリプト例

```elixir
defmodule MyWorld do
  use VrexServer.Scripting.WorldScript

  def on_player_join(ctx) do
    broadcast(ctx.room_id, "welcome", %{
      message: "ようこそ！"
    })
  end
end
```

### アイテムスクリプト例

```elixir
defmodule MusicBox do
  use VrexServer.Scripting.ItemScript

  def on_interact(_ctx) do
    %{sound: "music_box_01", animation: "open"}
  end
end
```

スクリプトは PUT `/api/v1/worlds/:id` の `script` フィールドで登録し、
`script_enabled: true` にすることで有効化される。

---

## Unity セットアップ

### 必要パッケージ

```
- Meta XR All-in-One SDK
- UniVRM 1.0 (VRM アバター)
- NativeWebSocket (Phoenix Channel 通信)
- Newtonsoft.Json (com.unity.nuget.newtonsoft-json)
```

### スクリプト配置

```
Assets/Scripts/
  Network/
    VrexClient.cs       ← メインクライアント
    PhoenixChannel.cs   ← WebSocket プロトコル
  Avatar/
    VrmAvatarLoader.cs  ← VRM 読み込み・表情制御
    RemotePlayerController.cs
  VR/
    QuestPlayerController.cs  ← Quest 3 移動
  World/
    WorldManager.cs     ← ワールド・プレイヤー管理
  UI/
    VrexUI.cs
```

### ビルド設定

- Platform: Android
- XR Plugin: OpenXR または Meta XR Plugin
- Minimum API Level: Android 10
- Target: ARM64 / IL2CPP

---

## ボイスチャット

`voice_signal` イベントで WebRTC シグナリングを中継済み。
クライアント側は Meta Voice SDK (Vivox) または Agora SDK を使う。
