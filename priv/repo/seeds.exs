alias VrexServer.{Repo, Accounts, Worlds, Avatars, Rooms}
alias VrexServer.Worlds.{World, Item}
alias VrexServer.Rooms.Room

IO.puts("=== Vrex サンプルデータ投入 ===")

# ── admin ユーザー（既存なら skip） ─────────────────────────
admin =
  case Accounts.get_user_by_email("admin@example.com") do
    nil ->
      {:ok, u} = Accounts.register_user(%{
        username: "admin", email: "admin@example.com",
        password: "password123", display_name: "管理者"
      })
      Repo.update!(Ecto.Changeset.change(u, is_admin: true))
    u -> u
  end
IO.puts("  admin: #{admin.email}")

# ── 一般ユーザー ────────────────────────────────────────────
alice =
  case Accounts.get_user_by_email("alice@example.com") do
    nil ->
      {:ok, u} = Accounts.register_user(%{
        username: "alice", email: "alice@example.com",
        password: "password123", display_name: "Alice"
      })
      u
    u -> u
  end

bob =
  case Accounts.get_user_by_email("bob@example.com") do
    nil ->
      {:ok, u} = Accounts.register_user(%{
        username: "bob", email: "bob@example.com",
        password: "password123", display_name: "Bob"
      })
      u
    u -> u
  end
IO.puts("  users: alice, bob")

# ── ワールド 1: ロビー ──────────────────────────────────────
lobby =
  case Repo.get_by(World, name: "メインロビー") do
    nil ->
      {:ok, w} = Worlds.create_world(%{
        name:             "メインロビー",
        description:      "Vrex へようこそ！最初に集まるロビーワールドです。",
        asset_bundle_url: "https://example.com/bundles/lobby.assetbundle",
        thumbnail_url:    "https://example.com/thumbs/lobby.jpg",
        capacity:         32,
        is_public:        true,
        script_enabled:   true,
        created_by:       admin.id,
        media: %{
          "bgm"           => %{"url" => "https://example.com/music/lobby_bgm.mp3", "volume" => 0.6, "loop" => true},
          "skybox"        => %{"url" => "https://example.com/sky/lobby_sky.jpg", "type" => "panorama"},
          "loading_image" => %{"url" => "https://example.com/loading/lobby.jpg"},
          "ambient"       => %{"url" => "https://example.com/ambient/crowd.mp3", "volume" => 0.2}
        },
        script: """
defmodule LobbyScript do
  use VrexServer.Scripting.WorldScript

  def on_player_join(ctx) do
    broadcast(ctx.room_id, "welcome", %{
      message: "ようこそ Vrex へ！\\n/help でコマンド一覧が確認できます"
    })
  end

  def on_player_leave(ctx) do
    broadcast(ctx.room_id, "notice", %{
      message: "プレイヤーが退出しました"
    })
  end
end
"""
      })
      w
    w -> w
  end
IO.puts("  world: #{lobby.name}")

# ── ワールド 1 のアイテム ───────────────────────────────────
items_lobby = [
  %{
    name:          "インフォメーションボード",
    asset_url:     "https://example.com/items/info_board.glb",
    thumbnail_url: "https://example.com/thumbs/info_board.jpg",
    position:      %{"x" => 0.0,  "y" => 1.5, "z" => -3.0},
    rotation:      %{"x" => 0.0,  "y" => 0.0, "z" => 0.0, "w" => 1.0},
    scale:         %{"x" => 1.0,  "y" => 1.0, "z" => 1.0},
    script_enabled: true,
    script: """
defmodule InfoBoard do
  use VrexServer.Scripting.ItemScript
  def on_interact(_ctx) do
    %{message: "Vrex へようこそ！\\nこのボードに触れると説明が表示されます。", type: "info"}
  end
end
""",
    properties:    %{"type" => "sign", "color" => "#7c6af7"},
    media:         %{
      "image" => %{"url" => "https://example.com/images/welcome_board.png", "display_mode" => "billboard"}
    }
  },
  %{
    name:          "テレポートゲート: 日本庭園",
    asset_url:     "https://example.com/items/teleport_gate.glb",
    thumbnail_url: "https://example.com/thumbs/gate.jpg",
    position:      %{"x" => 5.0,  "y" => 0.0, "z" => 0.0},
    rotation:      %{"x" => 0.0,  "y" => 0.0, "z" => 0.0, "w" => 1.0},
    scale:         %{"x" => 1.5,  "y" => 2.0, "z" => 1.0},
    script_enabled: true,
    script: """
defmodule GardenGate do
  use VrexServer.Scripting.ItemScript
  def on_interact(_ctx) do
    %{action: "teleport", world_name: "日本庭園", message: "日本庭園へ移動します..."}
  end
end
""",
    properties:    %{"type" => "portal", "destination" => "japanese_garden"},
    media:         %{
      "sound" => %{"url" => "https://example.com/sounds/portal_warp.mp3", "trigger" => "interact", "volume" => 1.0, "loop" => false}
    }
  },
  %{
    name:          "BGM プレイヤー",
    asset_url:     "https://example.com/items/music_player.glb",
    thumbnail_url: "https://example.com/thumbs/music.jpg",
    position:      %{"x" => -4.0, "y" => 0.5, "z" => 2.0},
    rotation:      %{"x" => 0.0,  "y" => 45.0,"z" => 0.0, "w" => 1.0},
    scale:         %{"x" => 0.8,  "y" => 0.8, "z" => 0.8},
    script_enabled: true,
    script: """
defmodule MusicPlayer do
  use VrexServer.Scripting.ItemScript
  def on_interact(_ctx) do
    %{action: "play_sound", sound: "lobby_bgm", volume: 0.6}
  end
end
""",
    properties:    %{"type" => "audio", "loop" => true},
    media:         %{
      "sound" => %{"url" => "https://example.com/music/lobby_bgm.mp3", "trigger" => "interact", "volume" => 0.6, "loop" => true}
    }
  }
]

for attrs <- items_lobby do
  unless Repo.get_by(Item, name: attrs.name, world_id: lobby.id) do
    Worlds.create_item(Map.put(attrs, :world_id, lobby.id))
  end
end
IO.puts("  items: #{length(items_lobby)} 件 (#{lobby.name})")

# ── ワールド 2: 日本庭園 ────────────────────────────────────
garden =
  case Repo.get_by(World, name: "日本庭園") do
    nil ->
      {:ok, w} = Worlds.create_world(%{
        name:             "日本庭園",
        description:      "静かな日本庭園。桜と池が美しいリラックスワールドです。",
        asset_bundle_url: "https://example.com/bundles/japanese_garden.assetbundle",
        thumbnail_url:    "https://example.com/thumbs/garden.jpg",
        capacity:         16,
        is_public:        true,
        script_enabled:   false,
        created_by:       alice.id,
        media: %{
          "bgm"           => %{"url" => "https://example.com/music/zen_koto.mp3", "volume" => 0.5, "loop" => true},
          "skybox"        => %{"url" => "https://example.com/sky/cherry_blossom.jpg", "type" => "panorama"},
          "loading_image" => %{"url" => "https://example.com/loading/garden.jpg"},
          "ambient"       => %{"url" => "https://example.com/ambient/birds_water.mp3", "volume" => 0.4}
        },
        script: nil
      })
      w
    w -> w
  end
IO.puts("  world: #{garden.name}")

items_garden = [
  %{
    name:          "桜の木",
    asset_url:     "https://example.com/items/sakura_tree.glb",
    thumbnail_url: "https://example.com/thumbs/sakura.jpg",
    position:      %{"x" => 3.0,  "y" => 0.0, "z" => 5.0},
    rotation:      %{"x" => 0.0,  "y" => 0.0, "z" => 0.0, "w" => 1.0},
    scale:         %{"x" => 2.0,  "y" => 3.0, "z" => 2.0},
    script_enabled: false,
    script:        nil,
    properties:    %{"type" => "decoration", "season" => "spring"},
    media:         %{}
  },
  %{
    name:          "石灯篭",
    asset_url:     "https://example.com/items/stone_lantern.glb",
    thumbnail_url: "https://example.com/thumbs/lantern.jpg",
    position:      %{"x" => -2.0, "y" => 0.0, "z" => 3.0},
    rotation:      %{"x" => 0.0,  "y" => 0.0, "z" => 0.0, "w" => 1.0},
    scale:         %{"x" => 1.0,  "y" => 1.0, "z" => 1.0},
    script_enabled: true,
    script: """
defmodule Lantern do
  use VrexServer.Scripting.ItemScript
  def on_interact(_ctx) do
    %{action: "toggle_light", message: "石灯篭に火が灯りました"}
  end
end
""",
    properties:    %{"type" => "light", "default_on" => false},
    media:         %{
      "sound" => %{"url" => "https://example.com/sounds/lantern_ignite.mp3", "trigger" => "interact", "volume" => 0.8, "loop" => false}
    }
  },
  %{
    name:          "縁側",
    asset_url:     "https://example.com/items/engawa.glb",
    thumbnail_url: "https://example.com/thumbs/engawa.jpg",
    position:      %{"x" => 0.0,  "y" => 0.3, "z" => 8.0},
    rotation:      %{"x" => 0.0,  "y" => 0.0, "z" => 0.0, "w" => 1.0},
    scale:         %{"x" => 3.0,  "y" => 0.3, "z" => 1.5},
    script_enabled: false,
    script:        nil,
    properties:    %{"type" => "seat", "capacity" => 4},
    media:         %{}
  }
]

for attrs <- items_garden do
  unless Repo.get_by(Item, name: attrs.name, world_id: garden.id) do
    Worlds.create_item(Map.put(attrs, :world_id, garden.id))
  end
end
IO.puts("  items: #{length(items_garden)} 件 (#{garden.name})")

# ── ワールド 3: ゲームアリーナ ──────────────────────────────
arena =
  case Repo.get_by(World, name: "ゲームアリーナ") do
    nil ->
      {:ok, w} = Worlds.create_world(%{
        name:             "ゲームアリーナ",
        description:      "みんなでゲームを楽しむアリーナ。スコアボードとミニゲームが盛りだくさん！",
        asset_bundle_url: "https://example.com/bundles/arena.assetbundle",
        thumbnail_url:    "https://example.com/thumbs/arena.jpg",
        capacity:         24,
        is_public:        true,
        script_enabled:   true,
        created_by:       bob.id,
        media: %{
          "bgm"           => %{"url" => "https://example.com/music/arena_battle.mp3", "volume" => 0.8, "loop" => true},
          "skybox"        => %{"url" => "https://example.com/sky/arena_night.jpg", "type" => "panorama"},
          "loading_image" => %{"url" => "https://example.com/loading/arena.jpg"},
          "ambient"       => %{"url" => "https://example.com/ambient/crowd_cheer.mp3", "volume" => 0.3}
        },
        script: """
defmodule ArenaScript do
  use VrexServer.Scripting.WorldScript

  def on_player_join(ctx) do
    broadcast(ctx.room_id, "arena_event", %{
      type: "player_count_update",
      message: "新しいプレイヤーが参戦！ゲームを楽しんでください"
    })
  end
end
"""
      })
      w
    w -> w
  end
IO.puts("  world: #{arena.name}")

items_arena = [
  %{
    name:          "スコアボード",
    asset_url:     "https://example.com/items/scoreboard.glb",
    thumbnail_url: "https://example.com/thumbs/scoreboard.jpg",
    position:      %{"x" => 0.0,  "y" => 3.0, "z" => -10.0},
    rotation:      %{"x" => 0.0,  "y" => 0.0, "z" => 0.0, "w" => 1.0},
    scale:         %{"x" => 4.0,  "y" => 3.0, "z" => 0.1},
    script_enabled: true,
    script: """
defmodule Scoreboard do
  use VrexServer.Scripting.ItemScript
  def on_interact(_ctx) do
    %{type: "scoreboard", scores: []}
  end
end
""",
    properties:    %{"type" => "display", "display_type" => "scoreboard"},
    media:         %{
      "image" => %{"url" => "https://example.com/images/scoreboard_bg.png", "display_mode" => "flat"}
    }
  },
  %{
    name:          "スタートボタン",
    asset_url:     "https://example.com/items/start_button.glb",
    thumbnail_url: "https://example.com/thumbs/button.jpg",
    position:      %{"x" => 0.0,  "y" => 1.0, "z" => -5.0},
    rotation:      %{"x" => 0.0,  "y" => 0.0, "z" => 0.0, "w" => 1.0},
    scale:         %{"x" => 0.5,  "y" => 0.5, "z" => 0.5},
    script_enabled: true,
    script: """
defmodule StartButton do
  use VrexServer.Scripting.ItemScript
  def on_interact(ctx) do
    %{action: "start_game", room_id: ctx.room_id, message: "ゲームスタート！"}
  end
end
""",
    properties:    %{"type" => "button", "color" => "#22c55e"},
    media:         %{
      "sound" => %{"url" => "https://example.com/sounds/game_start.mp3", "trigger" => "interact", "volume" => 1.0, "loop" => false}
    }
  },
  %{
    name:          "アイテムボックス",
    asset_url:     "https://example.com/items/item_box.glb",
    thumbnail_url: "https://example.com/thumbs/box.jpg",
    position:      %{"x" => 4.0,  "y" => 0.5, "z" => 0.0},
    rotation:      %{"x" => 0.0,  "y" => 0.0, "z" => 0.0, "w" => 1.0},
    scale:         %{"x" => 0.7,  "y" => 0.7, "z" => 0.7},
    script_enabled: true,
    script: """
defmodule ItemBox do
  use VrexServer.Scripting.ItemScript
  def on_interact(_ctx) do
    items = ["スピードアップ", "シールド", "ジャンプブースト"]
    %{action: "give_item", item: Enum.random(items), message: "アイテムをゲット！"}
  end
end
""",
    properties:    %{"type" => "loot", "respawn_seconds" => 30},
    media:         %{
      "sound" => %{"url" => "https://example.com/sounds/item_pickup.mp3", "trigger" => "interact", "volume" => 1.0, "loop" => false}
    }
  },
  %{
    name:          "ゴールゲート",
    asset_url:     "https://example.com/items/goal_gate.glb",
    thumbnail_url: "https://example.com/thumbs/goal.jpg",
    position:      %{"x" => 0.0,  "y" => 0.0, "z" => 15.0},
    rotation:      %{"x" => 0.0,  "y" => 180.0,"z" => 0.0, "w" => 0.0},
    scale:         %{"x" => 3.0,  "y" => 4.0, "z" => 0.5},
    script_enabled: true,
    script: """
defmodule GoalGate do
  use VrexServer.Scripting.ItemScript
  def on_interact(ctx) do
    %{action: "goal", user_id: ctx.user_id, message: "ゴール！おめでとう！", sound: "fanfare"}
  end
end
""",
    properties:    %{"type" => "trigger", "trigger_event" => "goal"},
    media:         %{
      "sound" => %{"url" => "https://example.com/sounds/fanfare.mp3", "trigger" => "interact", "volume" => 1.0, "loop" => false}
    }
  }
]

for attrs <- items_arena do
  unless Repo.get_by(Item, name: attrs.name, world_id: arena.id) do
    Worlds.create_item(Map.put(attrs, :world_id, arena.id))
  end
end
IO.puts("  items: #{length(items_arena)} 件 (#{arena.name})")

# ── サンプルルーム ───────────────────────────────────────────
unless Repo.get_by(Room, world_id: lobby.id, owner_id: admin.id) do
  Rooms.create_room(%{world_id: lobby.id, owner_id: admin.id, name: "ロビー #1", max_players: 32})
end

# ═══════════════════════════════════════════════════════════════
# Quest 3 向け 楽しいワールド 3 つ
# ═══════════════════════════════════════════════════════════════

# ── ワールド 4: 宇宙ステーション ──────────────────────────────
space =
  case Repo.get_by(World, name: "宇宙ステーション") do
    nil ->
      {:ok, w} = Worlds.create_world(%{
        name:             "宇宙ステーション",
        description:      "地球周回軌道上の宇宙ステーション。窓の外に地球が見える無重力空間。",
        asset_bundle_url: "https://example.com/bundles/space_station.assetbundle",
        thumbnail_url:    "https://example.com/thumbs/space.jpg",
        capacity:         20,
        is_public:        true,
        script_enabled:   true,
        created_by:       admin.id,
        media: %{
          "bgm"           => %{"url" => "https://example.com/music/space_ambient.mp3", "volume" => 0.5, "loop" => true},
          "skybox"        => %{"url" => "https://example.com/sky/starfield_360.jpg", "type" => "panorama"},
          "loading_image" => %{"url" => "https://example.com/loading/space.jpg"},
          "ambient"       => %{"url" => "https://example.com/ambient/space_hum.mp3", "volume" => 0.3}
        },
        script: """
defmodule SpaceStationScript do
  use VrexServer.Scripting.WorldScript

  def on_player_join(ctx) do
    broadcast(ctx.room_id, "welcome", %{
      message: "宇宙ステーションへようこそ！\\n無重力を楽しんでください。地球まで400km！"
    })
  end
end
"""
      })
      w
    w -> w
  end
IO.puts("  world: #{space.name}")

items_space = [
  %{
    name:           "地球観測窓",
    asset_url:      "https://example.com/items/earth_window.glb",
    asset_format:   "glb",
    collider_enabled: true,
    thumbnail_url:  "https://example.com/thumbs/earth_window.jpg",
    position:       %{"x" => 0.0,  "y" => 1.5, "z" => 5.0},
    rotation:       %{"x" => 0.0,  "y" => 0.0, "z" => 0.0, "w" => 1.0},
    scale:          %{"x" => 3.0,  "y" => 2.0, "z" => 0.2},
    script_enabled: true,
    script: """
defmodule EarthWindow do
  use VrexServer.Scripting.ItemScript
  def on_interact(_ctx) do
    %{message: "地球が見えます。あそこに人類が住んでいる…\\n現在高度: 408km", type: "info"}
  end
end
""",
    properties: %{"type" => "display"},
    media: %{
      "image" => %{"url" => "https://example.com/images/earth_from_iss.jpg", "display_mode" => "flat"},
      "sound" => %{"url" => "https://example.com/sounds/space_awe.mp3", "trigger" => "interact", "volume" => 0.8, "loop" => false}
    }
  },
  %{
    name:           "宇宙服ラック",
    asset_url:      "https://example.com/items/spacesuit_rack.fbx",
    asset_format:   "fbx",
    collider_enabled: true,
    thumbnail_url:  "https://example.com/thumbs/spacesuit.jpg",
    position:       %{"x" => -3.0, "y" => 0.0, "z" => 0.0},
    rotation:       %{"x" => 0.0,  "y" => 90.0,"z" => 0.0, "w" => 0.0},
    scale:          %{"x" => 1.0,  "y" => 1.0, "z" => 1.0},
    script_enabled: true,
    script: """
defmodule SuitsRack do
  use VrexServer.Scripting.ItemScript
  def on_interact(ctx) do
    %{action: "equip_suit", user_id: ctx.user_id, message: "宇宙服を着ました！船外活動が可能になります"}
  end
end
""",
    properties: %{"type" => "equipment"},
    media: %{
      "sound" => %{"url" => "https://example.com/sounds/suit_equip.mp3", "trigger" => "interact", "volume" => 1.0, "loop" => false}
    }
  },
  %{
    name:           "操縦コンソール",
    asset_url:      "https://example.com/items/control_console.obj",
    asset_format:   "obj",
    collider_enabled: true,
    thumbnail_url:  "https://example.com/thumbs/console.jpg",
    position:       %{"x" => 0.0,  "y" => 0.8, "z" => -4.0},
    rotation:       %{"x" => 0.0,  "y" => 0.0, "z" => 0.0, "w" => 1.0},
    scale:          %{"x" => 1.5,  "y" => 1.0, "z" => 0.8},
    script_enabled: true,
    script: """
defmodule ControlConsole do
  use VrexServer.Scripting.ItemScript
  def on_interact(ctx) do
    %{action: "start_minigame", game: "orbital_control",
      room_id: ctx.room_id, message: "軌道制御ミニゲームを開始！"}
  end
end
""",
    properties: %{"type" => "button", "color" => "#3b82f6"},
    media: %{
      "image" => %{"url" => "https://example.com/images/console_screen.png", "display_mode" => "flat"},
      "sound" => %{"url" => "https://example.com/sounds/console_beep.mp3", "trigger" => "interact", "volume" => 0.9, "loop" => false},
      "video" => %{"url" => "https://example.com/video/earth_orbit.mp4", "autoplay" => true, "loop" => true}
    }
  }
]

for attrs <- items_space do
  unless Repo.get_by(Item, name: attrs.name, world_id: space.id) do
    Worlds.create_item(Map.put(attrs, :world_id, space.id))
  end
end
IO.puts("  items: #{length(items_space)} 件 (#{space.name})")

# ── ワールド 5: 海底遺跡 ────────────────────────────────────
ocean =
  case Repo.get_by(World, name: "海底遺跡") do
    nil ->
      {:ok, w} = Worlds.create_world(%{
        name:             "海底遺跡",
        description:      "深海に眠る古代文明の遺跡。謎の光を放つ遺物が散らばっている。",
        asset_bundle_url: "https://example.com/bundles/ocean_ruins.assetbundle",
        thumbnail_url:    "https://example.com/thumbs/ocean.jpg",
        capacity:         12,
        is_public:        true,
        script_enabled:   true,
        created_by:       alice.id,
        media: %{
          "bgm"           => %{"url" => "https://example.com/music/underwater_mystery.mp3", "volume" => 0.6, "loop" => true},
          "skybox"        => %{"url" => "https://example.com/sky/deep_ocean.jpg", "type" => "panorama"},
          "loading_image" => %{"url" => "https://example.com/loading/ocean.jpg"},
          "ambient"       => %{"url" => "https://example.com/ambient/ocean_bubbles.mp3", "volume" => 0.5}
        },
        script: """
defmodule OceanRuinsScript do
  use VrexServer.Scripting.WorldScript

  def on_player_join(ctx) do
    broadcast(ctx.room_id, "welcome", %{
      message: "海底遺跡へようこそ。\\n古代文明の謎を解き明かしてください…"
    })
  end
end
"""
      })
      w
    w -> w
  end
IO.puts("  world: #{ocean.name}")

items_ocean = [
  %{
    name:           "古代の壁画パネル",
    asset_url:      "https://example.com/items/ancient_mural.obj",
    asset_format:   "obj",
    collider_enabled: true,
    thumbnail_url:  "https://example.com/thumbs/mural.jpg",
    position:       %{"x" => 0.0,  "y" => 2.0, "z" => -6.0},
    rotation:       %{"x" => 0.0,  "y" => 0.0, "z" => 0.0, "w" => 1.0},
    scale:          %{"x" => 4.0,  "y" => 3.0, "z" => 0.1},
    script_enabled: true,
    script: """
defmodule AncientMural do
  use VrexServer.Scripting.ItemScript
  def on_interact(_ctx) do
    %{message: "壁画には星と海の神が描かれている。\\n古代人はここで何を祈ったのか…", type: "lore"}
  end
end
""",
    properties: %{"type" => "display"},
    media: %{
      "image" => %{"url" => "https://example.com/images/ancient_mural.png", "display_mode" => "flat"},
      "sound" => %{"url" => "https://example.com/sounds/mystical_chime.mp3", "trigger" => "interact", "volume" => 0.7, "loop" => false}
    }
  },
  %{
    name:           "発光するオーブ",
    asset_url:      "https://example.com/items/glowing_orb.fbx",
    asset_format:   "fbx",
    collider_enabled: true,
    thumbnail_url:  "https://example.com/thumbs/orb.jpg",
    position:       %{"x" => 3.0,  "y" => 1.2, "z" => -2.0},
    rotation:       %{"x" => 0.0,  "y" => 0.0, "z" => 0.0, "w" => 1.0},
    scale:          %{"x" => 0.5,  "y" => 0.5, "z" => 0.5},
    script_enabled: true,
    script: """
defmodule GlowingOrb do
  use VrexServer.Scripting.ItemScript
  def on_interact(ctx) do
    %{action: "collect_artifact", user_id: ctx.user_id,
      artifact: "発光するオーブ", message: "遺物を手に入れた！謎が一つ解けた…"}
  end
end
""",
    properties: %{"type" => "collectible", "glow_color" => "#7ee8fa"},
    media: %{
      "sound" => %{"url" => "https://example.com/sounds/orb_collect.mp3", "trigger" => "interact", "volume" => 1.0, "loop" => false}
    }
  },
  %{
    name:           "古代の祭壇",
    asset_url:      "https://example.com/items/ancient_altar.glb",
    asset_format:   "glb",
    collider_enabled: true,
    thumbnail_url:  "https://example.com/thumbs/altar.jpg",
    position:       %{"x" => 0.0,  "y" => 0.0, "z" => 0.0},
    rotation:       %{"x" => 0.0,  "y" => 0.0, "z" => 0.0, "w" => 1.0},
    scale:          %{"x" => 2.0,  "y" => 1.5, "z" => 2.0},
    script_enabled: true,
    script: """
defmodule AncientAltar do
  use VrexServer.Scripting.ItemScript
  def on_interact(ctx) do
    %{action: "altar_ritual", room_id: ctx.room_id,
      message: "祭壇に触れると部屋全体が光り輝いた！全員に加護が与えられた。"}
  end
end
""",
    properties: %{"type" => "trigger", "effect" => "room_glow"},
    media: %{
      "sound" => %{"url" => "https://example.com/sounds/altar_activate.mp3", "trigger" => "interact", "volume" => 1.0, "loop" => false},
      "video" => %{"url" => "https://example.com/video/altar_ritual.mp4", "autoplay" => false, "loop" => false}
    }
  }
]

for attrs <- items_ocean do
  unless Repo.get_by(Item, name: attrs.name, world_id: ocean.id) do
    Worlds.create_item(Map.put(attrs, :world_id, ocean.id))
  end
end
IO.puts("  items: #{length(items_ocean)} 件 (#{ocean.name})")

# ── ワールド 6: 忍者の里 ────────────────────────────────────
ninja =
  case Repo.get_by(World, name: "忍者の里") do
    nil ->
      {:ok, w} = Worlds.create_world(%{
        name:             "忍者の里",
        description:      "霧に包まれた山奥の忍者の里。忍術の試練があなたを待つ。",
        asset_bundle_url: "https://example.com/bundles/ninja_village.assetbundle",
        thumbnail_url:    "https://example.com/thumbs/ninja.jpg",
        capacity:         16,
        is_public:        true,
        script_enabled:   true,
        created_by:       bob.id,
        media: %{
          "bgm"           => %{"url" => "https://example.com/music/ninja_drums.mp3", "volume" => 0.7, "loop" => true},
          "skybox"        => %{"url" => "https://example.com/sky/misty_mountains.jpg", "type" => "panorama"},
          "loading_image" => %{"url" => "https://example.com/loading/ninja.jpg"},
          "ambient"       => %{"url" => "https://example.com/ambient/forest_night.mp3", "volume" => 0.4}
        },
        script: """
defmodule NinjaVillageScript do
  use VrexServer.Scripting.WorldScript

  def on_player_join(ctx) do
    broadcast(ctx.room_id, "welcome", %{
      message: "忍者の里へようこそ。\\n試練を乗り越え、真の忍者になれ。"
    })
  end
end
"""
      })
      w
    w -> w
  end
IO.puts("  world: #{ninja.name}")

items_ninja = [
  %{
    name:           "巻物の棚",
    asset_url:      "https://example.com/items/scroll_shelf.fbx",
    asset_format:   "fbx",
    collider_enabled: true,
    thumbnail_url:  "https://example.com/thumbs/scroll.jpg",
    position:       %{"x" => -2.0, "y" => 1.0, "z" => -3.0},
    rotation:       %{"x" => 0.0,  "y" => 0.0, "z" => 0.0, "w" => 1.0},
    scale:          %{"x" => 1.2,  "y" => 1.8, "z" => 0.5},
    script_enabled: true,
    script: """
defmodule ScrollShelf do
  use VrexServer.Scripting.ItemScript
  def on_interact(_ctx) do
    techniques = ["影分身の術", "水遁の術", "火遁の術", "変化の術"]
    tech = Enum.random(techniques)
    %{message: "巻物を開いた。\\n秘伝「\#{tech}」を習得した！", technique: tech}
  end
end
""",
    properties: %{"type" => "loot"},
    media: %{
      "image" => %{"url" => "https://example.com/images/scroll_text.png", "display_mode" => "billboard"},
      "sound" => %{"url" => "https://example.com/sounds/scroll_open.mp3", "trigger" => "interact", "volume" => 0.8, "loop" => false}
    }
  },
  %{
    name:           "的（まと）",
    asset_url:      "https://example.com/items/target_board.obj",
    asset_format:   "obj",
    collider_enabled: true,
    thumbnail_url:  "https://example.com/thumbs/target.jpg",
    position:       %{"x" => 5.0,  "y" => 1.5, "z" => 0.0},
    rotation:       %{"x" => 0.0,  "y" => -90.0,"z" => 0.0, "w" => 0.0},
    scale:          %{"x" => 1.0,  "y" => 1.0, "z" => 0.1},
    script_enabled: true,
    script: """
defmodule NinjaTarget do
  use VrexServer.Scripting.ItemScript
  def on_interact(ctx) do
    score = :rand.uniform(100)
    %{action: "score_point", user_id: ctx.user_id,
      score: score, message: "命中！\#{score}点！"}
  end
end
""",
    properties: %{"type" => "button", "color" => "#ef4444"},
    media: %{
      "sound" => %{"url" => "https://example.com/sounds/arrow_hit.mp3", "trigger" => "interact", "volume" => 1.0, "loop" => false}
    }
  },
  %{
    name:           "修行用丸太",
    asset_url:      "https://example.com/items/training_log.glb",
    asset_format:   "glb",
    collider_enabled: true,
    thumbnail_url:  "https://example.com/thumbs/log.jpg",
    position:       %{"x" => 0.0,  "y" => 0.5, "z" => 3.0},
    rotation:       %{"x" => 0.0,  "y" => 45.0,"z" => 0.0, "w" => 0.0},
    scale:          %{"x" => 0.4,  "y" => 1.2, "z" => 0.4},
    script_enabled: true,
    script: """
defmodule TrainingLog do
  use VrexServer.Scripting.ItemScript
  def on_interact(ctx) do
    %{action: "train", user_id: ctx.user_id,
      message: "修行！体力+10、忍術適性アップ！"}
  end
end
""",
    properties: %{"type" => "equipment"},
    media: %{
      "sound" => %{"url" => "https://example.com/sounds/punch_wood.mp3", "trigger" => "interact", "volume" => 0.9, "loop" => false}
    }
  }
]

for attrs <- items_ninja do
  unless Repo.get_by(Item, name: attrs.name, world_id: ninja.id) do
    Worlds.create_item(Map.put(attrs, :world_id, ninja.id))
  end
end
IO.puts("  items: #{length(items_ninja)} 件 (#{ninja.name})")

# ═══════════════════════════════════════════════════════════════
# 追加ユーザー 3 名
# ═══════════════════════════════════════════════════════════════

charlie =
  case Accounts.get_user_by_email("charlie@example.com") do
    nil ->
      {:ok, u} = Accounts.register_user(%{
        username: "charlie", email: "charlie@example.com",
        password: "password123", display_name: "Charlie"
      })
      u
    u -> u
  end

diana =
  case Accounts.get_user_by_email("diana@example.com") do
    nil ->
      {:ok, u} = Accounts.register_user(%{
        username: "diana", email: "diana@example.com",
        password: "password123", display_name: "Diana"
      })
      u
    u -> u
  end

eve =
  case Accounts.get_user_by_email("eve@example.com") do
    nil ->
      {:ok, u} = Accounts.register_user(%{
        username: "eve", email: "eve@example.com",
        password: "password123", display_name: "Eve"
      })
      u
    u -> u
  end

IO.puts("  users: admin, charlie, diana, eve")

# ═══════════════════════════════════════════════════════════════
# 追加ワールド 3 つ（各 3 アイテム）
# ═══════════════════════════════════════════════════════════════

# ── ワールド 7: 砂漠のオアシス ──────────────────────────────
oasis =
  case Repo.get_by(World, name: "砂漠のオアシス") do
    nil ->
      {:ok, w} = Worlds.create_world(%{
        name:             "砂漠のオアシス",
        description:      "広大な砂漠の中に佇む神秘的なオアシス。星空が美しい夜の憩い場。",
        asset_bundle_url: "https://example.com/bundles/desert_oasis.assetbundle",
        thumbnail_url:    "https://example.com/thumbs/oasis.jpg",
        capacity:         20,
        is_public:        true,
        script_enabled:   true,
        created_by:       charlie.id,
        media: %{
          "bgm"           => %{"url" => "https://example.com/music/desert_wind.mp3", "volume" => 0.5, "loop" => true},
          "skybox"        => %{"url" => "https://example.com/sky/desert_stars.jpg", "type" => "panorama"},
          "loading_image" => %{"url" => "https://example.com/loading/oasis.jpg"},
          "ambient"       => %{"url" => "https://example.com/ambient/crickets.mp3", "volume" => 0.4}
        },
        script: nil
      })
      w
    w -> w
  end
IO.puts("  world: #{oasis.name}")

items_oasis = [
  %{
    name:           "古い井戸",
    asset_url:      "https://example.com/items/old_well.glb",
    thumbnail_url:  "https://example.com/thumbs/well.jpg",
    position:       %{"x" => 0.0,  "y" => 0.0, "z" => 0.0},
    rotation:       %{"x" => 0.0,  "y" => 0.0, "z" => 0.0, "w" => 1.0},
    scale:          %{"x" => 1.0,  "y" => 1.0, "z" => 1.0},
    script_enabled: true,
    script: """
defmodule OldWell do
  use VrexServer.Scripting.ItemScript
  def on_interact(_ctx) do
    %{message: "井戸から冷たい水が湧き出ている。砂漠の旅で疲れた体が癒される。", type: "info"}
  end
end
""",
    properties: %{"type" => "decoration"},
    media: %{
      "sound" => %{"url" => "https://example.com/sounds/water_splash.mp3", "trigger" => "interact", "volume" => 0.8, "loop" => false}
    }
  },
  %{
    name:           "ヤシの木",
    asset_url:      "https://example.com/items/palm_tree.glb",
    thumbnail_url:  "https://example.com/thumbs/palm.jpg",
    position:       %{"x" => 3.0,  "y" => 0.0, "z" => 2.0},
    rotation:       %{"x" => 0.0,  "y" => 0.0, "z" => 0.0, "w" => 1.0},
    scale:          %{"x" => 1.5,  "y" => 2.5, "z" => 1.5},
    script_enabled: false,
    script:         nil,
    properties: %{"type" => "decoration"},
    media: %{}
  },
  %{
    name:           "砂漠のキャンプファイヤー",
    asset_url:      "https://example.com/items/campfire.glb",
    thumbnail_url:  "https://example.com/thumbs/campfire.jpg",
    position:       %{"x" => -2.0, "y" => 0.0, "z" => 1.0},
    rotation:       %{"x" => 0.0,  "y" => 0.0, "z" => 0.0, "w" => 1.0},
    scale:          %{"x" => 0.8,  "y" => 0.8, "z" => 0.8},
    script_enabled: true,
    script: """
defmodule DesertCampfire do
  use VrexServer.Scripting.ItemScript
  def on_interact(ctx) do
    %{action: "gather", room_id: ctx.room_id, message: "焚き火を囲んで語り合おう！"}
  end
end
""",
    properties: %{"type" => "light", "default_on" => true},
    media: %{
      "sound" => %{"url" => "https://example.com/sounds/fire_crackle.mp3", "trigger" => "always", "volume" => 0.5, "loop" => true}
    }
  }
]

for attrs <- items_oasis do
  unless Repo.get_by(Item, name: attrs.name, world_id: oasis.id) do
    Worlds.create_item(Map.put(attrs, :world_id, oasis.id))
  end
end
IO.puts("  items: #{length(items_oasis)} 件 (#{oasis.name})")

# ── ワールド 8: 雪山の頂上 ──────────────────────────────────
snowpeak =
  case Repo.get_by(World, name: "雪山の頂上") do
    nil ->
      {:ok, w} = Worlds.create_world(%{
        name:             "雪山の頂上",
        description:      "雲の上に聳える雪山の頂上。360度の絶景パノラマが広がる。",
        asset_bundle_url: "https://example.com/bundles/snow_peak.assetbundle",
        thumbnail_url:    "https://example.com/thumbs/snowpeak.jpg",
        capacity:         16,
        is_public:        true,
        script_enabled:   false,
        created_by:       diana.id,
        media: %{
          "bgm"           => %{"url" => "https://example.com/music/mountain_breeze.mp3", "volume" => 0.6, "loop" => true},
          "skybox"        => %{"url" => "https://example.com/sky/mountain_top.jpg", "type" => "panorama"},
          "loading_image" => %{"url" => "https://example.com/loading/snowpeak.jpg"},
          "ambient"       => %{"url" => "https://example.com/ambient/wind_howl.mp3", "volume" => 0.6}
        },
        script: nil
      })
      w
    w -> w
  end
IO.puts("  world: #{snowpeak.name}")

items_snowpeak = [
  %{
    name:           "山頂の石碑",
    asset_url:      "https://example.com/items/summit_stone.glb",
    thumbnail_url:  "https://example.com/thumbs/stone.jpg",
    position:       %{"x" => 0.0,  "y" => 0.5, "z" => 0.0},
    rotation:       %{"x" => 0.0,  "y" => 0.0, "z" => 0.0, "w" => 1.0},
    scale:          %{"x" => 1.0,  "y" => 1.5, "z" => 0.2},
    script_enabled: true,
    script: """
defmodule SummitStone do
  use VrexServer.Scripting.ItemScript
  def on_interact(_ctx) do
    %{message: "標高4,000m 登頂記念。\\nここに立った者は真の登山家である。", type: "info"}
  end
end
""",
    properties: %{"type" => "sign"},
    media: %{}
  },
  %{
    name:           "展望デッキ",
    asset_url:      "https://example.com/items/observation_deck.glb",
    thumbnail_url:  "https://example.com/thumbs/deck.jpg",
    position:       %{"x" => 4.0,  "y" => 0.0, "z" => -2.0},
    rotation:       %{"x" => 0.0,  "y" => 0.0, "z" => 0.0, "w" => 1.0},
    scale:          %{"x" => 3.0,  "y" => 0.2, "z" => 2.0},
    script_enabled: false,
    script:         nil,
    properties: %{"type" => "seat", "capacity" => 8},
    media: %{}
  },
  %{
    name:           "雪だるま",
    asset_url:      "https://example.com/items/snowman.glb",
    thumbnail_url:  "https://example.com/thumbs/snowman.jpg",
    position:       %{"x" => -3.0, "y" => 0.0, "z" => 1.0},
    rotation:       %{"x" => 0.0,  "y" => 0.0, "z" => 0.0, "w" => 1.0},
    scale:          %{"x" => 0.8,  "y" => 1.0, "z" => 0.8},
    script_enabled: true,
    script: """
defmodule Snowman do
  use VrexServer.Scripting.ItemScript
  def on_interact(_ctx) do
    %{message: "雪だるまが喋った！\\n「寒いけど楽しいね！」", type: "chat"}
  end
end
""",
    properties: %{"type" => "decoration"},
    media: %{
      "sound" => %{"url" => "https://example.com/sounds/snowman_hello.mp3", "trigger" => "interact", "volume" => 0.9, "loop" => false}
    }
  }
]

for attrs <- items_snowpeak do
  unless Repo.get_by(Item, name: attrs.name, world_id: snowpeak.id) do
    Worlds.create_item(Map.put(attrs, :world_id, snowpeak.id))
  end
end
IO.puts("  items: #{length(items_snowpeak)} 件 (#{snowpeak.name})")

# ── ワールド 9: ファンタジー城 ──────────────────────────────
castle =
  case Repo.get_by(World, name: "ファンタジー城") do
    nil ->
      {:ok, w} = Worlds.create_world(%{
        name:             "ファンタジー城",
        description:      "魔法と剣の世界に聳え立つ壮大な城。英雄たちの冒険の拠点。",
        asset_bundle_url: "https://example.com/bundles/fantasy_castle.assetbundle",
        thumbnail_url:    "https://example.com/thumbs/castle.jpg",
        capacity:         24,
        is_public:        true,
        script_enabled:   true,
        created_by:       eve.id,
        media: %{
          "bgm"           => %{"url" => "https://example.com/music/fantasy_epic.mp3", "volume" => 0.7, "loop" => true},
          "skybox"        => %{"url" => "https://example.com/sky/fantasy_sky.jpg", "type" => "panorama"},
          "loading_image" => %{"url" => "https://example.com/loading/castle.jpg"},
          "ambient"       => %{"url" => "https://example.com/ambient/castle_ambience.mp3", "volume" => 0.3}
        },
        script: """
defmodule FantasyCastleScript do
  use VrexServer.Scripting.WorldScript

  def on_player_join(ctx) do
    broadcast(ctx.room_id, "welcome", %{
      message: "ファンタジー城へようこそ、勇者よ。\\n冒険があなたを待っている！"
    })
  end
end
"""
      })
      w
    w -> w
  end
IO.puts("  world: #{castle.name}")

items_castle = [
  %{
    name:           "魔法の鏡",
    asset_url:      "",
    asset_format:   "mirror",
    thumbnail_url:  "https://example.com/thumbs/mirror.jpg",
    position:       %{"x" => 0.0,  "y" => 1.5, "z" => -5.0},
    rotation:       %{"x" => 0.0,  "y" => 0.0, "z" => 0.0, "w" => 1.0},
    scale:          %{"x" => 1.2,  "y" => 2.0, "z" => 0.1},
    script_enabled: true,
    script: """
defmodule MagicMirror do
  use VrexServer.Scripting.ItemScript
  def on_interact(_ctx) do
    prophecies = [
      "今日、あなたは偉大な発見をするだろう",
      "東の風が幸運を運んでくる",
      "剣よりも言葉が強い"
    ]
    %{message: "鏡が語った：「\#{Enum.random(prophecies)}」", type: "prophecy"}
  end
end
""",
    properties: %{
      "type" => "display",
      "texture_scale" => 0.3,
      "clip_plane_offset" => 0.06,
      "frame_enabled" => true,
      "frame_thickness" => 0.07,
      "frame_depth" => 0.02,
      "frame_color" => %{"r" => 0.1, "g" => 0.1, "b" => 0.1, "a" => 1.0}
    },
    media: %{
      "sound" => %{"url" => "https://example.com/sounds/magic_shimmer.mp3", "trigger" => "interact", "volume" => 0.8, "loop" => false}
    }
  },
  %{
    name:           "王座",
    asset_url:      "https://example.com/items/throne.glb",
    thumbnail_url:  "https://example.com/thumbs/throne.jpg",
    position:       %{"x" => 0.0,  "y" => 0.5, "z" => -8.0},
    rotation:       %{"x" => 0.0,  "y" => 180.0, "z" => 0.0, "w" => 0.0},
    scale:          %{"x" => 1.5,  "y" => 2.0, "z" => 1.5},
    script_enabled: true,
    script: """
defmodule Throne do
  use VrexServer.Scripting.ItemScript
  def on_interact(ctx) do
    %{action: "sit", user_id: ctx.user_id, message: "王座に座った！今だけあなたが王だ！"}
  end
end
""",
    properties: %{"type" => "seat", "capacity" => 1},
    media: %{
      "sound" => %{"url" => "https://example.com/sounds/fanfare_short.mp3", "trigger" => "interact", "volume" => 1.0, "loop" => false}
    }
  },
  %{
    name:           "武器庫の棚",
    asset_url:      "https://example.com/items/weapon_rack.glb",
    thumbnail_url:  "https://example.com/thumbs/weapons.jpg",
    position:       %{"x" => -4.0, "y" => 1.0, "z" => -3.0},
    rotation:       %{"x" => 0.0,  "y" => 90.0, "z" => 0.0, "w" => 0.0},
    scale:          %{"x" => 2.0,  "y" => 1.8, "z" => 0.5},
    script_enabled: true,
    script: """
defmodule WeaponRack do
  use VrexServer.Scripting.ItemScript
  def on_interact(ctx) do
    weapons = ["聖剣エクスカリバー", "雷の弓", "炎の槍", "風の短剣"]
    %{action: "equip_weapon", user_id: ctx.user_id,
      weapon: Enum.random(weapons), message: "武器を手に入れた！"}
  end
end
""",
    properties: %{"type" => "loot"},
    media: %{
      "sound" => %{"url" => "https://example.com/sounds/sword_draw.mp3", "trigger" => "interact", "volume" => 1.0, "loop" => false}
    }
  }
]

for attrs <- items_castle do
  unless Repo.get_by(Item, name: attrs.name, world_id: castle.id) do
    Worlds.create_item(Map.put(attrs, :world_id, castle.id))
  end
end
IO.puts("  items: #{length(items_castle)} 件 (#{castle.name})")

IO.puts("\n=== 完了 ===")
IO.puts("  Worlds: 9  (メインロビー / 日本庭園 / ゲームアリーナ / 宇宙ステーション / 海底遺跡 / 忍者の里 / 砂漠のオアシス / 雪山の頂上 / ファンタジー城)")
IO.puts("  Items:  #{length(items_lobby) + length(items_garden) + length(items_arena) + length(items_space) + length(items_ocean) + length(items_ninja) + length(items_oasis) + length(items_snowpeak) + length(items_castle)}")
IO.puts("  Users:  admin / alice / bob / charlie / diana / eve")
