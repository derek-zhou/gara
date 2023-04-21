defmodule GaraWeb.Countdown do
  use Surface.Component
  import GaraWeb.Gettext

  use Phoenix.VerifiedRoutes,
    router: GaraWeb.Router,
    endpoint: GaraWeb.Endpoint,
    statics: ~w(css images js)

  prop minutes, :integer, required: true
end
