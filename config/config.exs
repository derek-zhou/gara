# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Configures the endpoint
config :gara, GaraWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  render_errors: [view: GaraWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: Gara.PubSub,
  live_view: [signing_salt: "Oz0jNWLw"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# for guardian
config :gara, GaraWeb.Guardian,
  issuer: "gara",
  secret_key: "Ub5Nfc6dAgJWZUyLoSWiVsCB8tr7z0x6w5eYmpE+A2WzQvFYhDQPDQJfExElOzIC",
  token_ttl: %{
    "access" => {8, :hours}
  }

# output directly to priv
config :surface, :compiler,
  hooks_output_dir: "priv/static/js/_hooks",
  css_output_file: "priv/static/css/_components.css"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
