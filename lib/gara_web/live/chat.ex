defmodule GaraWeb.Chat do
  use Surface.Component

  slot default, required: true
  prop messages, :map, default: %{}

  defp alert_class("error"), do: "alert-danger"
  defp alert_class("warning"), do: "alert-warning"
  defp alert_class("info"), do: "alert-info"
end
