defmodule GaraWeb.Header do
  use Surface.Component
  import GaraWeb.Gettext
  alias Surface.Components.{Form, Link}
  alias Surface.Components.Form.{Field, Label, TextInput, FileInput, TextArea}
  alias GaraWeb.Endpoint
  alias GaraWeb.Router.Helpers, as: Routes

  prop tz_offset, :integer, default: 0
  prop stat, :map, required: true
  prop room_status, :atom, default: :unknown
  prop mode, :atom, default: :text
  prop show_info, :boolean, default: false
  prop uploading, :boolean, default: false
  prop attached, :boolean, default: false
  prop participants, :list, default: []
  prop nick, :string, required: true
  prop preview_url, :string, default: ""
  prop idle_percentage, :integer, default: 0
  prop leave, :event, required: true
  prop rename, :event, required: true
  prop message, :event, required: true
  prop send_image, :event, required: true
  prop click_nick, :event, required: true
  prop click_else, :event, required: true
  prop click_toggle, :event, required: true

  defp date_string(date, tz_offset) do
    date
    |> NaiveDateTime.add(0 - tz_offset * 60)
    |> NaiveDateTime.truncate(:second)
    |> NaiveDateTime.to_time()
    |> Time.to_string()
  end
end
