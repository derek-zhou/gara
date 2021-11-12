defmodule GaraWeb.PageView do
  use GaraWeb, :view
  import Surface

  alias GaraWeb.Welcome
  alias GaraWeb.Room

  def render("welcome.html", assigns) do
    ~F'<Welcome rooms={@rooms} occupied={@occupied} />'
  end

  def render("room.html", assigns) do
    ~F'<Room open={@open} stat={@stat} />'
  end
end
