defmodule GaraWeb.PageController do
  use GaraWeb, :controller

  alias Gara.{Room, Defaults, RoomSupervisor, Rooms, RoomsByPublicTopic}

  plug :no_layout

  def index(conn, _params) do
    case get_req_header(conn, "referer") do
      [url | _] -> referrer_index(conn, url)
      _ -> local_index(conn)
    end
  end

  defp referrer_index(conn, url) do
    cond do
      url == "" ->
        local_index(conn)

      String.starts_with?(url, "/") ->
        local_index(conn)

      String.starts_with?(url, Routes.page_url(conn, :index)) ->
        local_index(conn)

      true ->
        case Room.new_room(url) do
          nil ->
            local_index(conn)

          :ignore ->
            case Registry.lookup(RoomsByPublicTopic, url) do
              [] -> local_index(conn)
              [{_pid, name}] -> redirect(conn, to: Routes.room_path(conn, :chat, name))
            end

          name ->
            redirect(conn, to: Routes.room_path(conn, :chat, name))
        end
    end
  end

  defp local_index(conn) do
    %{specs: occupied} = DynamicSupervisor.count_children(RoomSupervisor)
    rooms = Defaults.default(:max_rooms)

    conn
    |> assign(:rooms, rooms)
    |> assign(:occupied, occupied)
    |> assign(:page_title, gettext("The Lobby"))
    |> assign(:page_url, Routes.page_url(conn, :index))
    |> render("welcome.html")
  end

  def create(conn, %{"create" => %{"topic" => topic}}) do
    trimmed = String.trim(topic)

    case Registry.lookup(Rooms, trimmed) do
      [] ->
        case Room.new_room(trimmed) do
          nil ->
            redirect(conn, to: Routes.page_path(conn, :index))

          :ignore ->
            case Registry.lookup(RoomsByPublicTopic, trimmed) do
              [] -> redirect(conn, to: Routes.page_path(conn, :index))
              [{_pid, name}] -> redirect(conn, to: Routes.room_path(conn, :chat, name))
            end

          name ->
            redirect(conn, to: Routes.room_path(conn, :chat, name))
        end

      _ ->
        redirect(conn, to: Routes.room_path(conn, :chat, trimmed))
    end
  end

  defp no_layout(conn, _opts), do: put_layout(conn, false)
end
