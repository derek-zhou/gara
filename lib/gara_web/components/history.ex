defmodule GaraWeb.History do
  use Surface.Component
  import GaraWeb.Gettext

  prop messages, :list, default: []

  defp date_string(date) do
    date
    |> NaiveDateTime.truncate(:second)
    |> NaiveDateTime.to_string()
  end
end
