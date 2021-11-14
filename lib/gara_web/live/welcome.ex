defmodule GaraWeb.Welcome do
  use Surface.Component

  alias Surface.Components.Form
  alias Surface.Components.Form.{Field, Label, TextInput}
  alias GaraWeb.Router.Helpers, as: Routes
  alias GaraWeb.Endpoint

  prop rooms, :integer, required: true
  prop occupied, :integer, default: 0
end
