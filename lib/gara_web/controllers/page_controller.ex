defmodule GaraWeb.PageController do
  use GaraWeb, :controller

  def index(conn, _params) do
    conn
    |> put_layout(false)
    |> assign(:rooms, 16)
    |> assign(:occupied, 0)
    |> render("index.html")
  end
end
