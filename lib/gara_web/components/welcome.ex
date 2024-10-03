defmodule GaraWeb.Welcome do
  use Surface.Component
  import GaraWeb.Gettext

  use Phoenix.VerifiedRoutes,
    router: GaraWeb.Router,
    endpoint: GaraWeb.Endpoint,
    statics: ~w(css images js)

  prop rooms, :integer, required: true
  prop occupied, :integer, default: 0
end
