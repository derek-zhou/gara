defmodule Gara.Message do
  @moduledoc """
  message parsing and handling. A message is a string parsed into html string
  """

  alias Gara.Parser

  require Logger

  @doc """
  parse user input into a {message, recipients} tuple
  """
  def parse(str) do
    {_, res} = Parser.parse(str)
    str = XmlBuilder.generate(res.ast, format: :none)
    recipients = res.ast |> find_recipients() |> List.flatten()
    {str, recipients}
  end

  @doc """
  show a simgle image
  """
  def flaunt(path) do
    """
    <img class="flaunt" alt="image" src="#{path}">
    """
  end

  @doc """
  show an attahment to be downloaded
  """
  def attach(name, path) do
    """
    <a class="attachment" target="_blank" download="#{name}" href="#{path}">#{name}</a>
    """
  end

  @doc """
  fetch a preview in html, and send back as a message
  """
  def fetch_preview(url, mid) do
    pid = self()

    spawn(fn ->
      case get_preview(url) do
        nil ->
          :ok

        {:error, reason} ->
          Logger.error(reason)

        {title, site, description, thumbnail} ->
          preview = preview_meta(url, title, site, description, thumbnail)
          send(pid, {:update, mid, preview})
      end
    end)
  end

  defp get_preview(url) do
    case body_from_url(url, 2) do
      {:error, reason} -> {:error, reason}
      body -> parse_html(body)
    end
  end

  defp body_from_url(_url, -1) do
    {:error, "Too much redirect"}
  end

  defp body_from_url(url, redirect_count) do
    # I have to disable ssl verification. otherwise a lot will be rejected
    case CookieJar.HTTPoison.get(
           Gara.CookieJar,
           url,
           [
             {"Accept", "text/html, application/xhtml+xml"},
             {"Accept-Encoding", "gzip, compress"}
           ],
           follow_redirect: false,
           max_body_length: 1_000_000,
           timeout: 8000,
           recv_timeout: 5000
         ) do
      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}

      {:ok, %HTTPoison.Response{status_code: 200, body: body, headers: headers}} ->
        case response_encoding(headers) do
          "gzip" -> body |> :zlib.gunzip()
          "compress" -> body |> :zlib.uncompress()
          _ -> body
        end

      {:ok, %HTTPoison.Response{status_code: code, headers: headers}}
      when code > 300 and code < 400 ->
        case location(headers) do
          nil ->
            {:error, "HTTP error code: " <> to_string(code)}

          new_url ->
            Logger.warn("#{url} redirect to #{new_url} at iteration #{redirect_count}")
            # make sure new url is not relative
            new_url = url |> URI.merge(new_url) |> to_string()
            body_from_url(new_url, redirect_count - 1)
        end

      {:ok, %HTTPoison.Response{status_code: code}} ->
        {:error, "HTTP error code: " <> to_string(code)}
    end
  end

  defp location(headers) do
    Enum.find_value(headers, fn {key, value} ->
      if String.downcase(key) == "location", do: value
    end)
  end

  defp response_encoding(headers) do
    Enum.find_value(headers, fn {key, value} ->
      if String.downcase(key) == "content-encoding", do: String.downcase(value)
    end)
  end

  defp parse_html(text) do
    case Floki.parse_document(text) do
      {:error, reason} ->
        {:error, reason}

      {:ok, tree} ->
        case parse_html_meta(tree) do
          {nil, nil, nil, _} ->
            nil

          {title, site, description, nil} ->
            {title, site, description, nil}

          {title, site, description, thumbnail} ->
            case URI.parse(thumbnail) do
              %URI{scheme: "https", port: 443, userinfo: nil} ->
                {title, site, description, thumbnail}

              _ ->
                {title, site, description, nil}
            end
        end
    end
  end

  defp parse_html_meta(tree) do
    {
      get_param(tree, "meta", "content", property: "og:title") ||
        get_text(tree, "title"),
      get_param(tree, "meta", "content", property: "og:site_name"),
      get_param(tree, "meta", "content", property: "og:description") ||
        get_param(tree, "meta", "content", name: "description"),
      get_param(tree, "meta", "content", property: "og:image")
    }
  end

  defp get_text(tree, tag) do
    case Floki.find(tree, tag) do
      [{^tag, _, children} | _] ->
        children |> Floki.text() |> String.trim()

      _ ->
        nil
    end
  end

  defp get_param(tree, tag, key, attrs) do
    query =
      Enum.reduce(attrs, tag, fn {attr, value}, selector ->
        selector <> "[#{attr}=\"#{value}\"]"
      end)

    node = Floki.find(tree, query)

    case Floki.attribute(node, key) do
      [head | _] ->
        case String.trim(head) do
          "" -> nil
          str -> str
        end

      _ ->
        nil
    end
  end

  defp preview_meta(url, title, site, description, thumbnail) do
    EEx.eval_string(
      """
      <div class="card">
      <%= if thumbnail do %>
      <div class="thumbnail">
      <a href="<%= url %>"><img alt="thumbnail" src="<%= thumbnail %>"></a>
      </div>
      <% end %>
      <div class="headline">
      <span class="title"><%= title %></span>
      <%= if site do %>
      <span class="site"> | <%= site %></span>
      <% end %>
      </div>
      <%= if description do %>
      <div class="description"><%= description %></div>
      <% end %>
      <a class="url" href="<%= url %>"><%= url %></a>
      </div>
      """,
      url: url,
      title: title,
      site: site,
      description: description,
      thumbnail: thumbnail
    )
  end

  defp find_recipients(ast) when is_list(ast), do: Enum.map(ast, &find_recipients/1)
  defp find_recipients({:span, %{"data-mention": name}, _}), do: name
  defp find_recipients({_, _, contents}), do: find_recipients(contents)
  defp find_recipients(_), do: []
end
