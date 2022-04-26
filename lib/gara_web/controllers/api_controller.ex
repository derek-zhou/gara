defmodule GaraWeb.ApiController do
  use GaraWeb, :controller

  alias Gara.{Room, Rooms, RoomsByPublicTopic}

  def stat(conn, %{"name" => name}), do: stat_by_name(conn, name)

  def stat(conn, %{"url" => url}) do
    case Registry.lookup(RoomsByPublicTopic, url) do
      [] -> json(conn, %{error: "Rome by url #{url} not found"})
      [{_pid, name}] -> stat_by_name(conn, name)
    end
  end

  def stat(conn, _) do
    json(conn, %{error: "no rome name or url specified"})
  end

  defp stat_by_name(conn, name) do
    case Registry.lookup(Rooms, name) do
      [] ->
        json(conn, %{error: "Rome by name #{name} not found"})

      [{pid, _}] ->
        case Room.stat(pid) do
          nil -> json(conn, %{error: "Rome by name #{name} closed"})
          stat -> json(conn, stat)
        end
    end
  end
end
