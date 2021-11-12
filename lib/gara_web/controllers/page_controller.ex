defmodule GaraWeb.PageController do
  use GaraWeb, :controller

  alias Gara.Room
  alias Gara.Defaults
  alias Gara.RoomSupervisor
  alias Gara.Rooms

  def index(conn, _params) do
    %{specs: rooms} = DynamicSupervisor.count_children(RoomSupervisor)
    occupied = Defaults.default(:max_rooms)

    conn
    |> put_layout(false)
    |> assign(:rooms, rooms)
    |> assign(:occupied, occupied)
    |> render("welcome.html")
  end

  def create(conn, %{"create" => %{"topic" => topic}}) do
    case Room.new_room(topic) do
      nil -> redirect(conn, to: Routes.page_path(conn, :index))
      name -> redirect(conn, to: Routes.page_path(conn, :room, name))
    end
  end

  def room(conn, %{"name" => name}) do
    room = {:via, Registry, {Rooms, name}}

    case Room.stat(room) do
      nil ->
        conn
        |> assign(:opened, false)
        |> render("room.html")

      stat ->
        conn
        |> assign(:open, true)
        |> assign(:stat, stat)
        |> render("room.html")
    end
  end
end
