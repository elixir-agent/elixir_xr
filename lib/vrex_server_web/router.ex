defmodule VrexServerWeb.Router do
  use VrexServerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {VrexServerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug CORSPlug
  end

  pipeline :auth do
    plug VrexServerWeb.AuthPlug
  end

  pipeline :admin_layout do
    plug :put_root_layout, html: {VrexServerWeb.Layouts, :admin}
  end

  pipeline :admin_auth do
    plug VrexServerWeb.AdminAuthPlug
  end

  # ─── 一般 ────────────────────────────────────────────────────

  scope "/", VrexServerWeb do
    pipe_through :browser
    get "/", PageController, :home
  end

  # ─── 管理画面: ログイン（認証不要） ─────────────────────────

  scope "/admin", VrexServerWeb do
    pipe_through :browser

    get  "/login",  AdminSessionController, :new
    post "/login",  AdminSessionController, :create
    delete "/logout", AdminSessionController, :delete
  end

  # ─── 管理画面: 認証必要 (LiveView) ───────────────────────────

  scope "/admin", VrexServerWeb do
    pipe_through [:browser, :admin_layout, :admin_auth]

    live "/",       Admin.DashboardLive, :index
    live "/users",  Admin.UsersLive,     :index
    live "/worlds", Admin.WorldsLive,    :index
    live "/items",  Admin.ItemsLive,     :index
    live "/rooms",  Admin.RoomsLive,     :index
  end

  # ─── REST API: 認証不要 ───────────────────────────────────────

  scope "/api/v1", VrexServerWeb do
    pipe_through :api

    post "/auth/register", AuthController, :register
    post "/auth/login",    AuthController, :login

    get "/worlds",     WorldController, :index
    get "/worlds/:id", WorldController, :show
    get "/rooms",      RoomController,  :index
  end

  # ─── REST API: 認証必要 ───────────────────────────────────────

  scope "/api/v1", VrexServerWeb do
    pipe_through [:api, :auth]

    get    "/auth/me",     AuthController, :me
    delete "/auth/logout", AuthController, :logout

    # Worlds
    get    "/worlds/mine",           WorldController, :my_worlds
    post   "/worlds",                WorldController, :create
    put    "/worlds/:id",            WorldController, :update
    delete "/worlds/:id",            WorldController, :delete
    post   "/worlds/:world_id/items", WorldController, :create_item
    put    "/items/:id",             WorldController, :update_item

    # Avatars
    get "/avatars",             AvatarController, :index
    get "/avatars/mine",        AvatarController, :my_avatars
    get "/avatars/:id",         AvatarController, :show
    post "/avatars",            AvatarController, :create
    put  "/avatars/:id",        AvatarController, :update
    put  "/avatars/:id/activate", AvatarController, :set_active

    # Rooms
    get    "/rooms/:id", RoomController, :show
    post   "/rooms",     RoomController, :create
    delete "/rooms/:id", RoomController, :delete
  end

  if Application.compile_env(:vrex_server, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: VrexServerWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
