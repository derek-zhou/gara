defmodule GaraWeb.Chat do
  use Surface.Component
  import GaraWeb.Gettext

  prop tz_offset, :integer, default: 0
  prop messages, :list, default: []
  prop nick, :string, required: true

  defp date_string(date, tz_offset) do
    date
    |> NaiveDateTime.add(0 - tz_offset * 60)
    |> NaiveDateTime.truncate(:second)
    |> NaiveDateTime.to_time()
    |> Time.to_string()
  end
end
