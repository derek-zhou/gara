defmodule GaraWeb.Countdown do
  use Surface.Component
  import GaraWeb.Gettext

  alias GaraWeb.Router.Helpers, as: Routes
  alias GaraWeb.Endpoint

  prop minutes, :integer, required: true
end
