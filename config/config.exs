# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :vrex_server,
  ecto_repos: [VrexServer.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :vrex_server, VrexServerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: VrexServerWeb.ErrorHTML, json: VrexServerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: VrexServer.PubSub,
  live_view: [signing_salt: "gwhJ87ON"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :vrex_server, VrexServer.Mailer, adapter: Swoosh.Adapters.Local

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# GLB / GLTF の正しい MIME タイプを登録
config :mime, :types, %{
  "model/gltf-binary" => ["glb"],
  "model/gltf+json"   => ["gltf"]
}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
