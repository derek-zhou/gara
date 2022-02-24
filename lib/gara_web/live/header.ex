defmodule GaraWeb.Header do
  use Surface.Component
  import GaraWeb.Gettext
  alias Surface.Components.{Form, Link}
  alias Surface.Components.Form.{Field, Label, TextInput, FileInput, TextArea}
  alias GaraWeb.Endpoint
  alias GaraWeb.Router.Helpers, as: Routes

  prop tz_offset, :integer, default: 0
  prop name, :string, required: true
  prop stat, :map, required: true
  prop room_status, :atom, default: :unknown
  prop mode, :atom, default: :text
  prop show_info, :boolean, default: false
  prop uploading, :boolean, default: false
  prop attachment, :tuple, default: nil
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

  defp attached(nil), do: false
  defp attached(_), do: true

  defp attachment_type({_, nil, _, _}), do: :image
  defp attachment_type(_), do: :file

  defp attachment_name({_, name, _, _}), do: name

  defp percentage({size, _, offset, _}) when size > 0, do: floor(offset / size * 100)
  defp percentage(_), do: 100

  defp is_url(str) do
    case URI.parse(str) do
      %URI{scheme: "https"} -> true
      %URI{scheme: "http"} -> true
      _ -> false
    end
  end

  defp abbrev(url) do
    case URI.parse(url) do
      %URI{host: host, path: nil} -> host
      %URI{host: host, path: ""} -> host
      %URI{host: host, path: "/"} -> host
      %URI{host: _host, path: path} -> path
    end
  end
end
