defmodule GaraWeb.Header do
  use Surface.Component
  import GaraWeb.Gettext
  alias Surface.Components.Form
  alias Surface.Components.Form.{Field, Label, TextInput, TextArea}

  prop tz_offset, :integer, default: 0
  prop stat, :map, required: true
  prop joined, :boolean, default: false
  prop show_roster, :boolean, default: false
  prop show_info, :boolean, default: false
  prop participants, :list, default: []
  prop nick, :string, required: true
  prop idle_percentage, :integer, default: 0
  prop leave, :event, required: true
  prop rename, :event, required: true
  prop message, :event, required: true
  prop click_topic, :event, required: true
  prop click_nick, :event, required: true

  defp date_string(date, tz_offset) do
    date
    |> NaiveDateTime.add(0 - tz_offset * 60)
    |> NaiveDateTime.to_time()
    |> Time.to_string()
  end
end
