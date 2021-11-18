defmodule GaraWeb.PageController do
  use GaraWeb, :controller

  alias Gara.Room
  alias Gara.Defaults
  alias Gara.RoomSupervisor
  alias Gara.Rooms

  plug :no_layout

  def index(conn, _params) do
    %{specs: occupied} = DynamicSupervisor.count_children(RoomSupervisor)
    rooms = Defaults.default(:max_rooms)

    conn
    |> assign(:rooms, rooms)
    |> assign(:occupied, occupied)
    |> render("welcome.html")
  end

  def create(conn, %{"create" => %{"topic" => topic}}) do
    case Room.new_room(topic) do
      nil -> redirect(conn, to: Routes.page_path(conn, :index))
      name -> redirect(conn, to: Routes.room_path(conn, :chat, name))
    end
  end

  def room(conn, %{"name" => name}) do
    room = {:via, Registry, {Rooms, name}}

    case Room.stat(room) do
      nil ->
        conn
        |> assign(:open, false)
        |> assign(:stat, %{})
        |> render("room.html")

      stat ->
        conn
        |> assign(:open, true)
        |> assign(:stat, stat)
        |> render("room.html")
    end
  end

  defp no_layout(conn, _opts), do: put_layout(conn, false)
end
